import Foundation

enum SyncAction: Equatable {
    case createInOF(TaskSnapshot)
    case createInReminders(TaskSnapshot)
    case updateOF(String, TaskSnapshot)
    case updateReminders(String, TaskSnapshot)
    case softDeleteInOF(String)
    case deleteInReminders(String)
    case updateSyncRecord(SyncRecord)
    case insertSyncRecord(SyncRecord)
    case deleteSyncRecord(SyncRecord)
}

struct SyncEngine {

    static func computeActions(
        reminders: [TaskSnapshot],
        ofTasks: [TaskSnapshot],
        syncRecords: [SyncRecord]
    ) -> [SyncAction] {
        var actions: [SyncAction] = []
        let remindersByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        let ofByID = Dictionary(uniqueKeysWithValues: ofTasks.map { ($0.id, $0) })
        let trackedRemindersIDs = Set(syncRecords.map(\.remindersId))
        let trackedOFIDs = Set(syncRecords.map(\.omnifocusId))

        // New reminders (not in sync DB)
        for r in reminders where !trackedRemindersIDs.contains(r.id) {
            actions.append(.createInOF(r))
        }

        // New OF tasks (not in sync DB)
        for t in ofTasks where !trackedOFIDs.contains(t.id) {
            guard !t.title.hasPrefix("DELETED ") else { continue }
            actions.append(.createInReminders(t))
        }

        // Existing paired tasks
        for record in syncRecords {
            let reminderExists = remindersByID[record.remindersId] != nil
            let ofExists = ofByID[record.omnifocusId] != nil

            if !reminderExists && ofExists {
                actions.append(.softDeleteInOF(record.omnifocusId))
                continue
            }

            if reminderExists && !ofExists {
                actions.append(.deleteInReminders(record.remindersId))
                continue
            }

            if !reminderExists && !ofExists {
                actions.append(.deleteSyncRecord(record))
                continue
            }

            let currentReminder = remindersByID[record.remindersId]!
            let currentOF = ofByID[record.omnifocusId]!

            let reminderChanged = currentReminder.modified != record.remindersModified
            let ofChanged = currentOF.modified != record.omnifocusModified

            if !reminderChanged && !ofChanged { continue }

            let merged = mergeFields(reminder: currentReminder, of: currentOF, base: record)

            if reminderChanged && !ofChanged {
                actions.append(.updateOF(record.omnifocusId, merged))
            } else if !reminderChanged && ofChanged {
                actions.append(.updateReminders(record.remindersId, merged))
            } else {
                actions.append(.updateOF(record.omnifocusId, merged))
                actions.append(.updateReminders(record.remindersId, merged))
            }
        }

        return actions
    }

    static func mergeFields(
        reminder: TaskSnapshot,
        of: TaskSnapshot,
        base: SyncRecord
    ) -> TaskSnapshot {
        let reminderNewer = reminder.modified >= of.modified

        let title: String = {
            let rChanged = reminder.title != base.title
            let oChanged = of.title != base.title
            if rChanged && !oChanged { return reminder.title }
            if !rChanged && oChanged { return of.title }
            if rChanged && oChanged { return reminderNewer ? reminder.title : of.title }
            return base.title
        }()

        let notes: String? = {
            let rChanged = reminder.notes != base.notes
            let oChanged = of.notes != base.notes
            if rChanged && !oChanged { return reminder.notes }
            if !rChanged && oChanged { return of.notes }
            if rChanged && oChanged { return reminderNewer ? reminder.notes : of.notes }
            return base.notes
        }()

        let dueDate: String? = {
            let rChanged = reminder.dueDate != base.dueDate
            let oChanged = of.dueDate != base.dueDate
            if rChanged && !oChanged { return reminder.dueDate }
            if !rChanged && oChanged { return of.dueDate }
            if rChanged && oChanged { return reminderNewer ? reminder.dueDate : of.dueDate }
            return base.dueDate
        }()

        let completed: Bool = {
            let rChanged = reminder.completed != base.completed
            let oChanged = of.completed != base.completed
            if rChanged && !oChanged { return reminder.completed }
            if !rChanged && oChanged { return of.completed }
            if rChanged && oChanged { return reminderNewer ? reminder.completed : of.completed }
            return base.completed
        }()

        return TaskSnapshot(
            id: reminder.id,
            title: title, notes: notes, dueDate: dueDate,
            completed: completed,
            modified: max(reminder.modified, of.modified)
        )
    }
}
