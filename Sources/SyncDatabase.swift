import Foundation
import GRDB

struct SyncRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var remindersId: String
    var omnifocusId: String
    var title: String
    var notes: String?
    var dueDate: String?
    var completed: Bool
    var remindersModified: String
    var omnifocusModified: String

    static let databaseTableName = "sync_records"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

class SyncDatabase {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        if path == ":memory:" {
            dbQueue = try DatabaseQueue()
        } else {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: path)
        }
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "sync_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("remindersId", .text).notNull().unique()
                t.column("omnifocusId", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("dueDate", .text)
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("remindersModified", .text).notNull()
                t.column("omnifocusModified", .text).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    func insert(_ record: inout SyncRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: SyncRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(_ record: SyncRecord) throws {
        try dbQueue.write { db in
            _ = try record.delete(db)
        }
    }

    func fetchByRemindersId(_ remindersId: String) throws -> SyncRecord? {
        try dbQueue.read { db in
            try SyncRecord.filter(Column("remindersId") == remindersId).fetchOne(db)
        }
    }

    func fetchByOmnifocusId(_ omnifocusId: String) throws -> SyncRecord? {
        try dbQueue.read { db in
            try SyncRecord.filter(Column("omnifocusId") == omnifocusId).fetchOne(db)
        }
    }

    func fetchAll() throws -> [SyncRecord] {
        try dbQueue.read { db in
            try SyncRecord.fetchAll(db)
        }
    }
}
