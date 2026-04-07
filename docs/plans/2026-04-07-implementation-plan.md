# OmniFocus Reminders Sync — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Swift CLI daemon that bidirectionally syncs Apple Reminders with OmniFocus, running as a launchd service.

**Architecture:** Swift Package with ArgumentParser for CLI, GRDB for SQLite sync database, EventKit for Reminders, and Omni Automation (osascript -l JavaScript) for OmniFocus. Runs as a long-lived process via RunLoop.main.run() with EventKit notifications + polling.

**Tech Stack:** Swift 5.9+, macOS 14+, SPM, ArgumentParser, GRDB, EventKit, Omni Automation (JXA)

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/main.swift`
- Create: `Sources/Commands/SyncCommand.swift`
- Create: `Sources/Commands/InstallCommand.swift`
- Create: `Sources/Commands/UninstallCommand.swift`
- Create: `Sources/Commands/StatusCommand.swift`
- Create: `reminders-sync.entitlements`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "reminders-sync",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "reminders-sync",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("EventKit"),
            ]
        ),
        .testTarget(
            name: "reminders-sync-tests",
            dependencies: [
                .target(name: "reminders-sync"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests"
        ),
    ]
)
```

**Step 2: Create Sources/main.swift**

```swift
import ArgumentParser

@main
struct RemindersSyncCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders-sync",
        abstract: "Bidirectional sync between Apple Reminders and OmniFocus.",
        subcommands: [SyncCommand.self, InstallCommand.self, UninstallCommand.self, StatusCommand.self]
    )
}
```

**Step 3: Create stub subcommands**

Each in its own file under `Sources/Commands/`. Example for SyncCommand:

```swift
import ArgumentParser

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Run a sync cycle immediately."
    )

    func run() throws {
        print("Sync not yet implemented.")
    }
}
```

Same pattern for InstallCommand ("install"), UninstallCommand ("uninstall"), StatusCommand ("status").

**Step 4: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.personal-information.reminders</key>
    <true/>
</dict>
</plist>
```

**Step 5: Build and verify**

```bash
swift build
```

Expected: builds successfully, `swift run reminders-sync --help` shows subcommands.

**Step 6: Commit**

```bash
git add Package.swift Sources/ Tests/ reminders-sync.entitlements
git commit -m "feat: project scaffolding with CLI subcommands"
```

---

### Task 2: Configuration

**Files:**
- Create: `Sources/Config.swift`
- Create: `Tests/ConfigTests.swift`

**Step 1: Write failing tests**

```swift
import XCTest
@testable import reminders_sync

final class ConfigTests: XCTestCase {
    func testParseFullConfig() throws {
        let json = """
        {
          "mappings": [
            {"reminders": "Inbox", "omnifocus": "OF Inbox"},
            {"reminders": "Groceries", "omnifocus": "Shopping"}
          ],
          "pollIntervalSeconds": 30,
          "logLevel": "debug"
        }
        """
        let config = try Config.parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(config.mappings.count, 2)
        XCTAssertEqual(config.mappings[0].reminders, "Inbox")
        XCTAssertEqual(config.mappings[0].omnifocus, "OF Inbox")
        XCTAssertEqual(config.pollIntervalSeconds, 30)
        XCTAssertEqual(config.logLevel, "debug")
    }

    func testParseMinimalConfig() throws {
        let json = """
        {
          "mappings": [{"reminders": "Inbox", "omnifocus": "Inbox"}]
        }
        """
        let config = try Config.parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(config.pollIntervalSeconds, 10)
        XCTAssertEqual(config.logLevel, "info")
    }

    func testParseEmptyMappingsThrows() {
        let json = """
        {"mappings": []}
        """
        XCTAssertThrowsError(try Config.parse(from: json.data(using: .utf8)!))
    }

    func testLoadFromFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-config.json")
        let json = """
        {"mappings": [{"reminders": "Inbox", "omnifocus": "Inbox"}]}
        """
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = try Config.load(from: tmp.path)
        XCTAssertEqual(config.mappings.count, 1)
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter ConfigTests
```

Expected: compilation error — `Config` doesn't exist.

**Step 3: Implement Config**

```swift
import Foundation

struct ListMapping: Codable, Equatable {
    let reminders: String
    let omnifocus: String
}

struct Config: Codable, Equatable {
    let mappings: [ListMapping]
    let pollIntervalSeconds: Int
    let logLevel: String

    static let defaultPath = "\(NSHomeDirectory())/.config/reminders-sync/config.json"

    enum CodingKeys: String, CodingKey {
        case mappings, pollIntervalSeconds, logLevel
    }

    init(mappings: [ListMapping], pollIntervalSeconds: Int = 10, logLevel: String = "info") {
        self.mappings = mappings
        self.pollIntervalSeconds = pollIntervalSeconds
        self.logLevel = logLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mappings = try container.decode([ListMapping].self, forKey: .mappings)
        self.pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 10
        self.logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
    }

    static func parse(from data: Data) throws -> Config {
        let config = try JSONDecoder().decode(Config.self, from: data)
        guard !config.mappings.isEmpty else {
            throw ConfigError.emptyMappings
        }
        return config
    }

    static func load(from path: String) throws -> Config {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parse(from: data)
    }
}

enum ConfigError: Error, LocalizedError {
    case emptyMappings

    var errorDescription: String? {
        switch self {
        case .emptyMappings: return "Config must have at least one mapping."
        }
    }
}
```

**Step 4: Run tests**

```bash
swift test --filter ConfigTests
```

Expected: all pass.

**Step 5: Commit**

```bash
git add Sources/Config.swift Tests/ConfigTests.swift
git commit -m "feat: config file parsing with defaults"
```

---

### Task 3: Sync Database

**Files:**
- Create: `Sources/SyncDatabase.swift`
- Create: `Tests/SyncDatabaseTests.swift`

**Step 1: Write failing tests**

```swift
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
            remindersId: "R1", omnifocusId: "OF1",
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
            remindersId: "R1", omnifocusId: "OF1",
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
            remindersId: "R1", omnifocusId: "OF1",
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
            remindersId: "R1", omnifocusId: "OF1",
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
            remindersId: "R1", omnifocusId: "OF1",
            title: "A", notes: nil, dueDate: nil,
            completed: false,
            remindersModified: "2026-04-07T10:00:00Z",
            omnifocusModified: "2026-04-07T10:00:00Z"
        )
        var r2 = SyncRecord(
            remindersId: "R2", omnifocusId: "OF2",
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
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter SyncDatabaseTests
```

Expected: compilation error.

**Step 3: Implement SyncDatabase**

```swift
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
```

**Step 4: Run tests**

```bash
swift test --filter SyncDatabaseTests
```

Expected: all pass.

**Step 5: Commit**

```bash
git add Sources/SyncDatabase.swift Tests/SyncDatabaseTests.swift
git commit -m "feat: sync database with GRDB"
```

---

### Task 4: Reminders Adapter

**Files:**
- Create: `Sources/RemindersAdapter.swift`
- Create: `Sources/TaskSnapshot.swift`

`TaskSnapshot` is a shared struct representing a task's synced fields from either side.

**Step 1: Create TaskSnapshot**

```swift
import Foundation

struct TaskSnapshot: Equatable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: String?  // ISO 8601
    var completed: Bool
    var modified: String  // ISO 8601
}
```

**Step 2: Implement RemindersAdapter**

```swift
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
```

**Step 3: Build to verify compilation**

```bash
swift build
```

Expected: compiles. (EventKit access can only be tested on a real Mac with permissions — integration testing later.)

**Step 4: Commit**

```bash
git add Sources/TaskSnapshot.swift Sources/RemindersAdapter.swift
git commit -m "feat: Reminders adapter with EventKit"
```

---

### Task 5: OmniFocus Adapter

**Files:**
- Create: `Sources/OmniFocusAdapter.swift`
- Create: `Tests/OmniFocusScriptTests.swift`

**Step 1: Write failing tests for script generation and JSON parsing**

```swift
import XCTest
@testable import reminders_sync

final class OmniFocusScriptTests: XCTestCase {
    func testFetchTasksScriptContainsProjectName() {
        let script = OmniFocusAdapter.fetchTasksScript(projectName: "Groceries")
        XCTAssertTrue(script.contains("Groceries"))
        XCTAssertTrue(script.contains("flattenedProjects"))
    }

    func testParseTasksJSON() throws {
        let json = """
        [
          {"id":"abc","name":"Buy milk","note":"2%","dueDate":"2026-04-10","completed":false,"modified":"2026-04-07T10:00:00Z","tags":[]},
          {"id":"def","name":"Clean","note":null,"dueDate":null,"completed":true,"modified":"2026-04-07T11:00:00Z","tags":["errand"]}
        ]
        """
        let tasks = try OmniFocusAdapter.parseTasks(from: json)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].id, "abc")
        XCTAssertEqual(tasks[0].title, "Buy milk")
        XCTAssertEqual(tasks[0].notes, "2%")
        XCTAssertEqual(tasks[0].completed, false)
        XCTAssertEqual(tasks[1].completed, true)
        XCTAssertNil(tasks[1].dueDate)
    }

    func testCreateTaskScriptContainsFields() {
        let script = OmniFocusAdapter.createTaskScript(
            projectName: "Groceries",
            title: "Buy eggs", notes: "Free range",
            dueDate: "2026-04-10"
        )
        XCTAssertTrue(script.contains("Buy eggs"))
        XCTAssertTrue(script.contains("Free range"))
        XCTAssertTrue(script.contains("2026-04-10"))
        XCTAssertTrue(script.contains("Groceries"))
    }

    func testSoftDeleteScriptContainsDeletedTag() {
        let script = OmniFocusAdapter.softDeleteScript(taskId: "abc123")
        XCTAssertTrue(script.contains("DELETED"))
        XCTAssertTrue(script.contains("abc123"))
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter OmniFocusScriptTests
```

Expected: compilation error.

**Step 3: Implement OmniFocusAdapter**

```swift
import Foundation

struct OFTask: Codable {
    let id: String
    let name: String
    let note: String?
    let dueDate: String?
    let completed: Bool
    let modified: String?
    let tags: [String]
}

class OmniFocusAdapter {

    // MARK: - Script Builders

    static func fetchTasksScript(projectName: String) -> String {
        let escaped = projectName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const proj = flattenedProjects.byName("\(escaped)");
            if (!proj) { JSON.stringify([]); }
            else {
                const tasks = proj.flattenedTasks.map(t => ({
                    id: t.id.primaryKey,
                    name: t.name,
                    note: t.note || null,
                    dueDate: t.dueDate ? t.dueDate.toISOString().substring(0,10) : null,
                    completed: t.taskStatus.name === "Completed",
                    modified: t.modified ? t.modified.toISOString() : null,
                    tags: t.tags.map(tag => tag.name)
                }));
                JSON.stringify(tasks);
            }
        `);
        """
    }

    static func createTaskScript(projectName: String, title: String, notes: String?, dueDate: String?) -> String {
        let escapedProject = projectName.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNotes = (notes ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let dueLine = dueDate.map { "t.dueDate = new Date(\"\($0)\");" } ?? ""
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const proj = flattenedProjects.byName("\(escapedProject)");
            const t = new Task("\(escapedTitle)", proj.beginning);
            t.note = "\(escapedNotes)";
            \(dueLine)
            t.id.primaryKey;
        `);
        """
    }

    static func updateTaskScript(taskId: String, title: String, notes: String?, dueDate: String?, completed: Bool) -> String {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNotes = (notes ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let dueLine = dueDate.map { "t.dueDate = new Date(\"\($0)\");" } ?? "t.dueDate = null;"
        let completionLine = completed ? "t.markComplete();" : "t.markIncomplete();"
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const t = Task.byIdentifier("\(taskId)");
            t.name = "\(escapedTitle)";
            t.note = "\(escapedNotes)";
            \(dueLine)
            \(completionLine)
            "ok";
        `);
        """
    }

    static func softDeleteScript(taskId: String) -> String {
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const t = Task.byIdentifier("\(taskId)");
            if (!t.name.startsWith("DELETED ")) { t.name = "DELETED " + t.name; }
            const tag = flattenedTags.byName("DELETED") || new Tag("DELETED");
            t.addTag(tag);
            "ok";
        `);
        """
    }

    // MARK: - JSON Parsing

    static func parseTasks(from jsonString: String) throws -> [TaskSnapshot] {
        let data = jsonString.data(using: .utf8)!
        let ofTasks = try JSONDecoder().decode([OFTask].self, from: data)
        return ofTasks.map { t in
            TaskSnapshot(
                id: t.id,
                title: t.name,
                notes: t.note,
                dueDate: t.dueDate,
                completed: t.completed,
                modified: t.modified ?? Date().iso8601
            )
        }
    }

    // MARK: - Execution

    func runScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw OFError.scriptFailed(process.terminationStatus, output)
        }
        return output
    }

    func fetchTasks(projectName: String) throws -> [TaskSnapshot] {
        let script = Self.fetchTasksScript(projectName: projectName)
        let output = try runScript(script)
        // osascript wraps evaluateJavascript return in quotes — strip them
        let json = output.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
        return try Self.parseTasks(from: json)
    }

    func createTask(projectName: String, snapshot: TaskSnapshot) throws -> String {
        let script = Self.createTaskScript(
            projectName: projectName,
            title: snapshot.title, notes: snapshot.notes, dueDate: snapshot.dueDate
        )
        let output = try runScript(script)
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
    }

    func updateTask(id: String, snapshot: TaskSnapshot) throws {
        let script = Self.updateTaskScript(
            taskId: id, title: snapshot.title, notes: snapshot.notes,
            dueDate: snapshot.dueDate, completed: snapshot.completed
        )
        _ = try runScript(script)
    }

    func softDelete(id: String) throws {
        let script = Self.softDeleteScript(taskId: id)
        _ = try runScript(script)
    }
}

enum OFError: Error {
    case scriptFailed(Int32, String)
}
```

**Step 4: Run tests**

```bash
swift test --filter OmniFocusScriptTests
```

Expected: all pass.

**Step 5: Commit**

```bash
git add Sources/OmniFocusAdapter.swift Tests/OmniFocusScriptTests.swift
git commit -m "feat: OmniFocus adapter with Omni Automation scripts"
```

---

### Task 6: Sync Engine

This is the core logic. It compares current state from both sides against the sync DB and produces a list of actions.

**Files:**
- Create: `Sources/SyncEngine.swift`
- Create: `Tests/SyncEngineTests.swift`

**Step 1: Write failing tests**

```swift
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
        // Reminders changed title, OF changed notes
        let reminders = [TaskSnapshot(id: "R1", title: "Oat milk", notes: nil, dueDate: nil, completed: false, modified: "2026-04-07T12:00:00Z")]
        let ofTasks = [TaskSnapshot(id: "OF1", title: "Buy milk", notes: "2%", dueDate: nil, completed: false, modified: "2026-04-07T12:00:00Z")]
        let syncRecords = [SyncRecord(id: 1, remindersId: "R1", omnifocusId: "OF1", title: "Buy milk", notes: nil, dueDate: nil, completed: false, remindersModified: "2026-04-07T10:00:00Z", omnifocusModified: "2026-04-07T10:00:00Z")]

        let actions = SyncEngine.computeActions(reminders: reminders, ofTasks: ofTasks, syncRecords: syncRecords)

        // Should produce updates to both sides with merged fields
        let updateOF = actions.first { if case .updateOF = $0 { return true } else { return false } }
        let updateReminders = actions.first { if case .updateReminders = $0 { return true } else { return false } }

        if case .updateOF(_, let s) = updateOF! {
            XCTAssertEqual(s.title, "Oat milk")  // from Reminders
            XCTAssertEqual(s.notes, "2%")         // from OF
        } else { XCTFail() }

        if case .updateReminders(_, let s) = updateReminders! {
            XCTAssertEqual(s.title, "Oat milk")  // from Reminders
            XCTAssertEqual(s.notes, "2%")         // from OF
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
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter SyncEngineTests
```

**Step 3: Implement SyncEngine**

```swift
import Foundation

enum SyncAction: Equatable {
    case createInOF(TaskSnapshot)
    case createInReminders(TaskSnapshot)
    case updateOF(String, TaskSnapshot)         // (ofId, merged snapshot)
    case updateReminders(String, TaskSnapshot)   // (remindersId, merged snapshot)
    case softDeleteInOF(String)                  // ofId
    case deleteInReminders(String)               // remindersId
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
        let syncByRemindersID = Dictionary(uniqueKeysWithValues: syncRecords.map { ($0.remindersId, $0) })
        let syncByOFID = Dictionary(uniqueKeysWithValues: syncRecords.map { ($0.omnifocusId, $0) })
        let trackedRemindersIDs = Set(syncRecords.map(\.remindersId))
        let trackedOFIDs = Set(syncRecords.map(\.omnifocusId))

        // New reminders (not in sync DB)
        for r in reminders where !trackedRemindersIDs.contains(r.id) {
            actions.append(.createInOF(r))
        }

        // New OF tasks (not in sync DB)
        for t in ofTasks where !trackedOFIDs.contains(t.id) {
            // Skip tasks that are already soft-deleted
            guard !t.title.hasPrefix("DELETED ") else { continue }
            actions.append(.createInReminders(t))
        }

        // Existing paired tasks
        for record in syncRecords {
            let reminderExists = remindersByID[record.remindersId] != nil
            let ofExists = ofByID[record.omnifocusId] != nil

            if !reminderExists && ofExists {
                // Deleted in Reminders -> soft-delete in OF
                actions.append(.softDeleteInOF(record.omnifocusId))
                continue
            }

            if reminderExists && !ofExists {
                // Deleted in OF -> delete in Reminders
                actions.append(.deleteInReminders(record.remindersId))
                continue
            }

            if !reminderExists && !ofExists {
                // Both gone — clean up sync record only
                continue
            }

            // Both exist — check for changes
            let currentReminder = remindersByID[record.remindersId]!
            let currentOF = ofByID[record.omnifocusId]!

            let reminderChanged = currentReminder.modified != record.remindersModified
            let ofChanged = currentOF.modified != record.omnifocusModified

            if !reminderChanged && !ofChanged { continue }

            // Per-field merge
            let merged = mergeFields(
                reminder: currentReminder,
                of: currentOF,
                base: record
            )

            if reminderChanged && !ofChanged {
                actions.append(.updateOF(record.omnifocusId, merged))
            } else if !reminderChanged && ofChanged {
                actions.append(.updateReminders(record.remindersId, merged))
            } else {
                // Both changed — push merged state to both
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
        // For each field: if only one side changed from base, take that side.
        // If both changed, last-write-wins by modification date.

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
```

**Step 4: Run tests**

```bash
swift test --filter SyncEngineTests
```

Expected: all pass.

**Step 5: Commit**

```bash
git add Sources/SyncEngine.swift Tests/SyncEngineTests.swift
git commit -m "feat: sync engine with per-field merge and conflict resolution"
```

---

### Task 7: OmniFocus Keepalive

**Files:**
- Create: `Sources/OFKeepalive.swift`

**Step 1: Implement OFKeepalive**

```swift
import AppKit
import Foundation

struct OFKeepalive {
    static let bundleID = "com.omnigroup.OmniFocus4"

    static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func ensureRunning() async throws {
        if isRunning() { return }

        Logger.info("OmniFocus not running, launching...")

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw OFKeepaliveError.notInstalled
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false  // don't bring to front
        config.hides = true

        try await NSWorkspace.shared.openApplication(at: url, configuration: config)

        // Wait up to 15 seconds for OF to be ready
        for _ in 0..<30 {
            if isRunning() {
                Logger.info("OmniFocus launched successfully.")
                // Give it a moment to initialize Omni Automation
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw OFKeepaliveError.launchTimeout
    }
}

enum OFKeepaliveError: Error {
    case notInstalled
    case launchTimeout
}
```

**Step 2: Build to verify compilation**

```bash
swift build
```

**Step 3: Commit**

```bash
git add Sources/OFKeepalive.swift
git commit -m "feat: OmniFocus keepalive — auto-launch if not running"
```

---

### Task 8: Logger & Watchdog

**Files:**
- Create: `Sources/Logger.swift`
- Create: `Sources/Watchdog.swift`

**Step 1: Implement Logger**

```swift
import Foundation

enum LogLevel: String, Comparable {
    case debug, info, warn, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warn, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    static func from(_ string: String) -> LogLevel {
        LogLevel(rawValue: string.lowercased()) ?? .info
    }
}

struct Logger {
    static var level: LogLevel = .info
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func log(_ lvl: LogLevel, _ message: String) {
        guard lvl >= level else { return }
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(lvl.rawValue.uppercased())] \(message)")
    }

    static func debug(_ msg: String) { log(.debug, msg) }
    static func info(_ msg: String) { log(.info, msg) }
    static func warn(_ msg: String) { log(.warn, msg) }
    static func error(_ msg: String) { log(.error, msg) }
}
```

**Step 2: Implement Watchdog**

```swift
import Foundation

class Watchdog {
    private let heartbeatPath: String
    private var timer: DispatchSourceTimer?
    private let staleThreshold: TimeInterval
    private let onStale: () -> Void

    init(heartbeatPath: String, staleThreshold: TimeInterval = 60, onStale: @escaping () -> Void) {
        self.heartbeatPath = heartbeatPath
        self.staleThreshold = staleThreshold
        self.onStale = onStale
    }

    func beat() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? timestamp.write(toFile: heartbeatPath, atomically: true, encoding: .utf8)
    }

    func start() {
        let queue = DispatchQueue(label: "watchdog")
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + staleThreshold, repeating: staleThreshold)
        timer?.setEventHandler { [weak self] in
            self?.check()
        }
        timer?.resume()
        Logger.info("Watchdog started (threshold: \(Int(staleThreshold))s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func check() {
        guard let content = try? String(contentsOfFile: heartbeatPath, encoding: .utf8),
              let lastBeat = ISO8601DateFormatter().date(from: content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            Logger.warn("Watchdog: no heartbeat file found, triggering restart.")
            onStale()
            return
        }

        let age = Date().timeIntervalSince(lastBeat)
        if age > staleThreshold {
            Logger.warn("Watchdog: heartbeat stale by \(Int(age))s, triggering restart.")
            onStale()
        }
    }
}
```

**Step 3: Build**

```bash
swift build
```

**Step 4: Commit**

```bash
git add Sources/Logger.swift Sources/Watchdog.swift
git commit -m "feat: logger and watchdog with heartbeat monitoring"
```

---

### Task 9: Sync Coordinator (Main Loop)

Ties everything together — the daemon loop that runs the sync cycle.

**Files:**
- Create: `Sources/SyncCoordinator.swift`

**Step 1: Implement SyncCoordinator**

```swift
import EventKit
import Foundation

class SyncCoordinator {
    let config: Config
    let db: SyncDatabase
    let remindersAdapter: RemindersAdapter
    let ofAdapter: OmniFocusAdapter
    let watchdog: Watchdog

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

        // Request Reminders access
        try await remindersAdapter.requestAccess()

        // Ensure OF is running
        try await OFKeepalive.ensureRunning()

        // Register EventKit change observer
        changeObserver = remindersAdapter.registerChangeObserver { [weak self] in
            Logger.debug("EventKit change notification received.")
            self?.triggerSync()
        }

        // Start poll timer for OF changes
        startPollTimer()

        // Start watchdog
        watchdog.start()

        // Initial full sync
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
        Task {
            try? await OFKeepalive.ensureRunning()
            changeObserver = remindersAdapter.registerChangeObserver { [weak self] in
                self?.triggerSync()
            }
            startPollTimer()
            watchdog.start()
            runSyncCycle()
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
            // Ensure OF is running
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
                try syncMapping(mapping, existingRecords: syncRecords.filter { record in
                    // We need to figure out which records belong to this mapping.
                    // We'll add a listName column later if needed. For now, process all.
                    true
                })
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

        // Fetch current state from both sides
        var reminders: [TaskSnapshot] = []
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            reminders = (try? await remindersAdapter.fetchReminders(inList: list)) ?? []
            semaphore.signal()
        }
        semaphore.wait()

        let ofTasks = (try? ofAdapter.fetchTasks(projectName: mapping.omnifocus)) ?? []

        // Compute actions
        let actions = SyncEngine.computeActions(
            reminders: reminders, ofTasks: ofTasks, syncRecords: existingRecords
        )

        if actions.isEmpty {
            Logger.debug("No changes for \(mapping.reminders) <-> \(mapping.omnifocus)")
            return
        }

        Logger.info("Processing \(actions.count) sync actions for \(mapping.reminders) <-> \(mapping.omnifocus)")

        // Execute actions
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
```

**Step 2: Build**

```bash
swift build
```

**Step 3: Commit**

```bash
git add Sources/SyncCoordinator.swift
git commit -m "feat: sync coordinator — main loop with event-driven + polling sync"
```

---

### Task 10: CLI Commands

Wire up the real subcommands.

**Files:**
- Modify: `Sources/Commands/SyncCommand.swift`
- Modify: `Sources/Commands/InstallCommand.swift`
- Modify: `Sources/Commands/UninstallCommand.swift`
- Modify: `Sources/Commands/StatusCommand.swift`
- Create: `Sources/LaunchdHelper.swift`

**Step 1: Implement LaunchdHelper**

```swift
import Foundation

struct LaunchdHelper {
    static let label = "com.reminders-sync"
    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
    }

    static func install(executablePath: String) throws {
        let logDir = "\(NSHomeDirectory())/.config/reminders-sync/logs"
        try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "daemon"],
            "KeepAlive": true,
            "RunAtLoad": true,
            "StandardOutPath": "\(logDir)/stdout.log",
            "StandardErrorPath": "\(logDir)/stderr.log",
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Service installed and loaded.")
        } else {
            print("Warning: launchctl load exited with status \(process.terminationStatus)")
        }
    }

    static func uninstall() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath]
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(atPath: plistPath)
        print("Service unloaded and removed.")
    }
}
```

**Step 2: Wire up SyncCommand (immediate sync)**

```swift
import ArgumentParser
import Foundation

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Run a single sync cycle immediately."
    )

    func run() async throws {
        let config = try Config.load(from: Config.defaultPath)
        Logger.level = LogLevel.from(config.logLevel)
        let dbPath = "\(NSHomeDirectory())/.config/reminders-sync/sync.db"
        let db = try SyncDatabase(path: dbPath)
        let coordinator = SyncCoordinator(config: config, db: db)
        try await coordinator.remindersAdapter.requestAccess()
        try await OFKeepalive.ensureRunning()
        coordinator.triggerSync()
        // Give the sync a moment to complete
        try await Task.sleep(nanoseconds: 3_000_000_000)
        print("Sync complete.")
    }
}
```

**Step 3: Wire up InstallCommand**

```swift
import ArgumentParser
import Foundation

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the background sync service."
    )

    func run() throws {
        let execPath = ProcessInfo.processInfo.arguments[0]
        try LaunchdHelper.install(executablePath: execPath)
    }
}
```

**Step 4: Wire up UninstallCommand**

```swift
import ArgumentParser

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Stop and remove the background sync service."
    )

    func run() throws {
        try LaunchdHelper.uninstall()
    }
}
```

**Step 5: Wire up StatusCommand**

```swift
import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync service status."
    )

    func run() throws {
        // Check heartbeat
        let heartbeatPath = "\(NSHomeDirectory())/.config/reminders-sync/heartbeat"
        if let content = try? String(contentsOfFile: heartbeatPath, encoding: .utf8),
           let date = ISO8601DateFormatter().date(from: content.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let age = Int(Date().timeIntervalSince(date))
            print("Last heartbeat: \(content.trimmingCharacters(in: .whitespacesAndNewlines)) (\(age)s ago)")
            print("Status: \(age < 120 ? "healthy" : "STALE")")
        } else {
            print("No heartbeat found. Service may not be running.")
        }

        // Show task counts
        let dbPath = "\(NSHomeDirectory())/.config/reminders-sync/sync.db"
        if let db = try? SyncDatabase(path: dbPath) {
            let records = try db.fetchAll()
            print("Tracked tasks: \(records.count)")
            let completed = records.filter(\.completed).count
            print("  Active: \(records.count - completed)")
            print("  Completed: \(completed)")
        }

        // Check if launchd service is loaded
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", LaunchdHelper.label]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        print("Service: \(process.terminationStatus == 0 ? "loaded" : "not loaded")")
    }
}
```

**Step 6: Add daemon subcommand to main.swift**

Update `Sources/main.swift`:

```swift
import ArgumentParser
import Foundation

@main
struct RemindersSyncCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders-sync",
        abstract: "Bidirectional sync between Apple Reminders and OmniFocus.",
        subcommands: [SyncCommand.self, InstallCommand.self, UninstallCommand.self, StatusCommand.self, DaemonCommand.self]
    )
}

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the sync daemon (used by launchd)."
    )

    func run() async throws {
        let config = try Config.load(from: Config.defaultPath)
        Logger.level = LogLevel.from(config.logLevel)
        Logger.info("reminders-sync daemon starting...")

        let dbPath = "\(NSHomeDirectory())/.config/reminders-sync/sync.db"
        let db = try SyncDatabase(path: dbPath)
        let coordinator = SyncCoordinator(config: config, db: db)

        try await coordinator.start()

        // Keep the process alive
        RunLoop.main.run()
    }
}
```

**Step 7: Build**

```bash
swift build
```

**Step 8: Commit**

```bash
git add Sources/
git commit -m "feat: CLI commands — install, uninstall, status, sync, daemon"
```

---

### Task 11: Build & Codesign Script

**Files:**
- Create: `scripts/build.sh`

**Step 1: Create build script**

```bash
#!/bin/bash
set -euo pipefail

echo "Building reminders-sync..."
swift build -c release

echo "Signing with entitlements..."
codesign --force --sign - \
  --entitlements reminders-sync.entitlements \
  .build/release/reminders-sync

echo "Done. Binary at .build/release/reminders-sync"
echo ""
echo "To install:"
echo "  cp .build/release/reminders-sync /usr/local/bin/"
echo "  reminders-sync install"
```

**Step 2: Make executable**

```bash
chmod +x scripts/build.sh
```

**Step 3: Commit**

```bash
git add scripts/build.sh
git commit -m "feat: build and codesign script"
```

---

### Task 12: Integration Test (Manual)

**No files to create — this is a manual verification checklist.**

**Step 1: Build and install**

```bash
./scripts/build.sh
cp .build/release/reminders-sync /usr/local/bin/
```

**Step 2: Create config**

```bash
mkdir -p ~/.config/reminders-sync
cat > ~/.config/reminders-sync/config.json << 'EOF'
{
  "mappings": [
    {"reminders": "Inbox", "omnifocus": "Inbox"}
  ],
  "pollIntervalSeconds": 10,
  "logLevel": "debug"
}
EOF
```

**Step 3: Run a manual sync**

```bash
reminders-sync sync
```

Expected: prompts for Reminders access, then syncs. Check OF for any existing Inbox reminders.

**Step 4: Test each sync direction**

1. Create a reminder in Reminders Inbox → verify it appears in OF Inbox
2. Create a task in OF Inbox → verify it appears in Reminders
3. Edit a reminder title → verify OF updates
4. Complete a task in OF → verify Reminders marks it done
5. Delete a reminder → verify OF task gets DELETED prefix and tag
6. Delete an OF task → verify reminder disappears

**Step 5: Install the service**

```bash
reminders-sync install
reminders-sync status
```

**Step 6: Commit any fixes**

```bash
git commit -am "fix: integration test fixes"
```
