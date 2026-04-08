import XCTest
@testable import reminders_sync

final class SyncEngineTests: XCTestCase {
    func testNewReminderCreatesInOF() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let ofTasks: [TaskSnapshot] = []
        let syncRecords: [SyncRecord] = []

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        XCTAssertEqual(actions.count, 1)
        if case .createInOF(let snapshot) = actions[0] {
            XCTAssertEqual(snapshot.title, "Buy milk")
        } else { XCTFail("Expected createInOF") }
    }

    func testNewOFTaskCreatesInReminders() throws {
        let reminders: [TaskSnapshot] = []
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Fix door", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let syncRecords: [SyncRecord] = []

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        XCTAssertEqual(actions.count, 1)
        if case .createInReminders(let snapshot) = actions[0] {
            XCTAssertEqual(snapshot.title, "Fix door")
        } else { XCTFail("Expected createInReminders") }
    }

    func testUpdatedReminderPushesToOF() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Buy oat milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T12:00:00Z")]
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        XCTAssertEqual(actions.count, 1)
        if case .updateOF(let id, let snapshot) = actions[0] {
            XCTAssertEqual(id, "OF1")
            XCTAssertEqual(snapshot.title, "Buy oat milk")
        } else { XCTFail("Expected updateOF") }
    }

    func testUpdatedOFPushesToReminders() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: "From store", dueDate: nil, completed: false, modified: "2026-04-07T12:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        XCTAssertEqual(actions.count, 1)
        if case .updateReminders(let id, let snapshot) = actions[0] {
            XCTAssertEqual(id, "R1")
            XCTAssertEqual(snapshot.notes, "From store")
        } else { XCTFail("Expected updateReminders") }
    }

    func testBothSidesDifferentFieldsMerges() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Oat milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T12:00:00Z")]
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: "2%", dueDate: nil, completed: false, modified: "2026-04-07T12:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        let updateOF = actions.first { if case .updateOF = $0 { return true } else { return false } }
        let updateReminders = actions.first { if case .updateReminders = $0 { return true } else { return false } }

        if case .updateOF(_, let s) = updateOF! {
            XCTAssertEqual(s.title, "Oat milk")
            XCTAssertEqual(s.notes, "2%")
        } else { XCTFail() }

        if case .updateReminders(_, let s) = updateReminders! {
            XCTAssertEqual(s.title, "Oat milk")
            XCTAssertEqual(s.notes, "2%")
        } else { XCTFail() }
    }

    func testDeletedInRemindersSoftDeletesInOF() throws {
        let reminders: [TaskSnapshot] = []
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        XCTAssertEqual(actions.count, 1)
        if case .softDeleteInOF(let id) = actions[0] {
            XCTAssertEqual(id, "OF1")
        } else { XCTFail("Expected softDeleteInOF") }
    }

    func testDeletedInOFDeletesInReminders() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let ofTasks: [TaskSnapshot] = []
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        XCTAssertEqual(actions.count, 1)
        if case .deleteInReminders(let id) = actions[0] {
            XCTAssertEqual(id, "R1")
        } else { XCTFail("Expected deleteInReminders") }
    }

    func testCompletedInRemindersPushesToOF() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Buy milk", notes: nil, dueDate: nil, completed: true, modified: "2026-04-07T12:00:00Z")]
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        if case .updateOF(_, let s) = actions[0] {
            XCTAssertTrue(s.completed)
        } else { XCTFail("Expected updateOF with completed=true") }
    }

    func testNoChangesNoActions() throws {
        let reminders = [TaskSnapshot(id: "R1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T10:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)
        XCTAssertTrue(actions.isEmpty)
    }
}
