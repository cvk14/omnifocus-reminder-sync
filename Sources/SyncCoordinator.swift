import EventKit
import Foundation

class SyncCoordinator {
    let config: Config
    let db: SyncDatabase
    let remindersAdapter: RemindersAdapter
    let ofAdapter: OmniFocusAdapter
    private(set) var watchdog: Watchdog!

    private var changeObserver: NSObjectProtocol?
    private var pollTimer: DispatchSourceTimer?
    private var syncInProgress = false
    private let syncQueue = DispatchQueue(label: "sync")

    init(config: Config, db: SyncDatabase) {
        self.config = config
        self.db = db
        self.remindersAdapter = RemindersAdapter()
        self.ofAdapter = OmniFocusAdapter()

        let heartbeatPath = "\(NSHomeDirectory())/.config/reminders-sync/heartbeat"
        self.watchdog = Watchdog(heartbeatPath: heartbeatPath) { [weak self] in
            Logger.warn("Watchdog triggered restart.")
            self?.restart()
        }
    }

    func start() async throws {
        Logger.info("Starting sync coordinator...")

        try await remindersAdapter.requestAccess()
        try await OFKeepalive.ensureRunning()

        changeObserver = remindersAdapter.registerChangeObserver { [weak self] in
            Logger.debug("EventKit change notification received.")
            self?.triggerSync()
        }

        startPollTimer()
        watchdog.start()

        Logger.info("Running initial sync...")
        runSyncCycle()

        Logger.info("Sync coordinator running. Poll interval: \(config.pollIntervalSeconds)s")
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        watchdog.stop()
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        Logger.info("Sync coordinator stopped.")
    }

    func triggerSync() {
        syncQueue.async { [weak self] in
            self?.runSyncCycle()
        }
    }

    private func startPollTimer() {
        let queue = DispatchQueue(label: "poll")
        pollTimer = DispatchSource.makeTimerSource(queue: queue)
        let interval = Double(config.pollIntervalSeconds)
        pollTimer?.schedule(deadline: .now() + interval, repeating: interval)
        pollTimer?.setEventHandler { [weak self] in
            self?.triggerSync()
        }
        pollTimer?.resume()
    }

    private func restart() {
        Logger.info("Restarting sync loop...")
        stop()
        Task { [weak self] in
            guard let self else { return }
            try? await OFKeepalive.ensureRunning()
            self.changeObserver = self.remindersAdapter.registerChangeObserver { [weak self] in
                self?.triggerSync()
            }
            self.startPollTimer()
            self.watchdog.start()
            self.runSyncCycle()
        }
    }

    private func runSyncCycle() {
        guard !syncInProgress else {
            Logger.debug("Sync already in progress, skipping.")
            return
        }
        syncInProgress = true
        defer {
            syncInProgress = false
            watchdog.beat()
        }

        do {
            if !OFKeepalive.isRunning() {
                Logger.info("OmniFocus not running, launching...")
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    try await OFKeepalive.ensureRunning()
                    semaphore.signal()
                }
                semaphore.wait()
            }

            let syncRecords = try db.fetchAll()

            for mapping in config.mappings {
                try syncMapping(mapping, existingRecords: syncRecords)
            }

            Logger.debug("Sync cycle complete.")
        } catch {
            Logger.error("Sync cycle failed: \(error)")
        }
    }

    private func syncMapping(_ mapping: ListMapping, existingRecords: [SyncRecord]) throws {
        guard let list = remindersAdapter.findList(named: mapping.reminders) else {
            Logger.warn("Reminders list '\(mapping.reminders)' not found, skipping.")
            return
        }

        var reminders: [TaskSnapshot] = []
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            reminders = (try? await remindersAdapter.fetchReminders(inList: list)) ?? []
            semaphore.signal()
        }
        semaphore.wait()

        let ofTasks = (try? ofAdapter.fetchTasks(projectName: mapping.omnifocus)) ?? []

        let actions = SyncEngine.computeActions(
            reminders: reminders, ofTasks: ofTasks, syncRecords: existingRecords
        )

        if actions.isEmpty {
            Logger.debug("No changes for \(mapping.reminders) <-> \(mapping.omnifocus)")
            return
        }

        Logger.info("Processing \(actions.count) sync actions for \(mapping.reminders) <-> \(mapping.omnifocus)")

        for action in actions {
            do {
                try executeAction(action, mapping: mapping, list: list)
            } catch {
                Logger.error("Action failed: \(action) — \(error)")
            }
        }
    }

    private func executeAction(_ action: SyncAction, mapping: ListMapping, list: EKCalendar) throws {
        switch action {
        case .createInOF(let snapshot):
            let ofId = try ofAdapter.createTask(projectName: mapping.omnifocus, snapshot: snapshot)
            var record = SyncRecord(
                remindersId: snapshot.id, omnifocusId: ofId,
                title: snapshot.title, notes: snapshot.notes,
                dueDate: snapshot.dueDate, completed: snapshot.completed,
                remindersModified: snapshot.modified, omnifocusModified: snapshot.modified
            )
            try db.insert(&record)
            Logger.info("Created in OF: \(snapshot.title)")

        case .createInReminders(let snapshot):
            let rId = try remindersAdapter.createReminder(from: snapshot, inList: list)
            var record = SyncRecord(
                remindersId: rId, omnifocusId: snapshot.id,
                title: snapshot.title, notes: snapshot.notes,
                dueDate: snapshot.dueDate, completed: snapshot.completed,
                remindersModified: snapshot.modified, omnifocusModified: snapshot.modified
            )
            try db.insert(&record)
            Logger.info("Created in Reminders: \(snapshot.title)")

        case .updateOF(let ofId, let snapshot):
            try ofAdapter.updateTask(id: ofId, snapshot: snapshot)
            if var record = try db.fetchByOmnifocusId(ofId) {
                record.title = snapshot.title
                record.notes = snapshot.notes
                record.dueDate = snapshot.dueDate
                record.completed = snapshot.completed
                record.remindersModified = snapshot.modified
                record.omnifocusModified = snapshot.modified
                try db.update(record)
            }
            Logger.info("Updated OF: \(snapshot.title)")

        case .updateReminders(let rId, let snapshot):
            try remindersAdapter.updateReminder(id: rId, from: snapshot)
            if var record = try db.fetchByRemindersId(rId) {
                record.title = snapshot.title
                record.notes = snapshot.notes
                record.dueDate = snapshot.dueDate
                record.completed = snapshot.completed
                record.remindersModified = snapshot.modified
                record.omnifocusModified = snapshot.modified
                try db.update(record)
            }
            Logger.info("Updated Reminders: \(snapshot.title)")

        case .softDeleteInOF(let ofId):
            try ofAdapter.softDelete(id: ofId)
            if let record = try db.fetchByOmnifocusId(ofId) {
                try db.delete(record)
            }
            Logger.info("Soft-deleted in OF: \(ofId)")

        case .deleteInReminders(let rId):
            try remindersAdapter.deleteReminder(id: rId)
            if let record = try db.fetchByRemindersId(rId) {
                try db.delete(record)
            }
            Logger.info("Deleted in Reminders: \(rId)")

        case .updateSyncRecord(let record):
            try db.update(record)

        case .insertSyncRecord(var record):
            try db.insert(&record)

        case .deleteSyncRecord(let record):
            try db.delete(record)
        }
    }
}
