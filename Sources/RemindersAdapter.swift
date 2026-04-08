import EventKit
import Foundation

class RemindersAdapter {
    let store = EKEventStore()

    func requestAccess() async throws {
        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            throw RemindersError.accessDenied
        }
    }

    func findList(named name: String) -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == name }
    }

    func fetchReminders(inList list: EKCalendar) async throws -> [TaskSnapshot] {
        let predicate = store.predicateForReminders(in: [list])
        let reminders = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }
        return reminders.map { r in
            TaskSnapshot(
                id: r.calendarItemIdentifier,
                title: r.title ?? "",
                notes: r.notes,
                dueDate: r.dueDateComponents.flatMap { Self.isoString(from: $0) },
                completed: r.isCompleted,
                modified: (r.lastModifiedDate ?? r.creationDate ?? Date()).iso8601
            )
        }
    }

    func createReminder(from snapshot: TaskSnapshot, inList list: EKCalendar) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = snapshot.title
        reminder.notes = snapshot.notes
        reminder.calendar = list
        if let dueDateStr = snapshot.dueDate {
            reminder.dueDateComponents = Self.dateComponents(from: dueDateStr)
        }
        reminder.isCompleted = snapshot.completed
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func updateReminder(id: String, from snapshot: TaskSnapshot) throws {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.notFound(id)
        }
        item.title = snapshot.title
        item.notes = snapshot.notes
        item.dueDateComponents = snapshot.dueDate.flatMap { Self.dateComponents(from: $0) }
        item.isCompleted = snapshot.completed
        try store.save(item, commit: true)
    }

    func deleteReminder(id: String) throws {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(item, commit: true)
    }

    func registerChangeObserver(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { _ in handler() }
    }

    // MARK: - Date Helpers

    static func isoString(from components: DateComponents) -> String? {
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func dateComponents(from iso: String) -> DateComponents {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        var dc = DateComponents()
        if parts.count >= 3 {
            dc.year = parts[0]; dc.month = parts[1]; dc.day = parts[2]
        }
        return dc
    }
}

enum RemindersError: Error {
    case accessDenied
    case notFound(String)
}

extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
