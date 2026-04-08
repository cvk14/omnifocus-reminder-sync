import XCTest
import GRDB
@testable import reminders_sync

final class SyncDatabaseTests: XCTestCase {
    var db: SyncDatabase!

    override func setUp() async throws {
        db = try SyncDatabase(path: ":memory:")
    }

    func testInsertAndFetchRecord() throws {
        var record = SyncRecord(
            mappingKey: "test", remindersId: "R1", omnifocusId: "OF1",
            title: "Buy milk", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        try db.insert(&record)
        XCTAssertNotNil(record.id)

        let fetched = try db.fetchByRemindersId("R1")
        XCTAssertEqual(fetched?.title, "Buy milk")
    }

    func testFetchByOmnifocusId() throws {
        var record = SyncRecord(
            mappingKey: "test", remindersId: "R1", omnifocusId: "OF1",
            title: "Test", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        try db.insert(&record)

        let fetched = try db.fetchByOmnifocusId("OF1")
        XCTAssertEqual(fetched?.remindersId, "R1")
    }

    func testUpdateRecord() throws {
        var record = SyncRecord(
            mappingKey: "test", remindersId: "R1", omnifocusId: "OF1",
            title: "Buy milk", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        try db.insert(&record)

        record.title = "Buy oat milk"
        record.completed = true
        try db.update(record)

        let fetched = try db.fetchByRemindersId("R1")
        XCTAssertEqual(fetched?.title, "Buy oat milk")
        XCTAssertEqual(fetched?.completed, true)
    }

    func testDeleteRecord() throws {
        var record = SyncRecord(
            mappingKey: "test", remindersId: "R1", omnifocusId: "OF1",
            title: "Test", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        try db.insert(&record)
        try db.delete(record)

        let fetched = try db.fetchByRemindersId("R1")
        XCTAssertNil(fetched)
    }

    func testFetchAllForMapping() throws {
        var r1 = SyncRecord(
            mappingKey: "test", remindersId: "R1", omnifocusId: "OF1",
            title: "A", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        var r2 = SyncRecord(
            mappingKey: "test", remindersId: "R2", omnifocusId: "OF2",
            title: "B", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        try db.insert(&r1)
        try db.insert(&r2)

        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 2)
    }
}
