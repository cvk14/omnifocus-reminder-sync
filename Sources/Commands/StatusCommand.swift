import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync service status."
    )

    func run() throws {
        let heartbeatPath = "\(NSHomeDirectory())/.config/reminders-sync/heartbeat"
        if let content = try? String(contentsOfFile: heartbeatPath, encoding: .utf8),
           let date = ISO8601DateFormatter().date(from: content.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let age = Int(Date().timeIntervalSince(date))
            print("Last heartbeat: \(content.trimmingCharacters(in: .whitespacesAndNewlines)) (\(age)s ago)")
            print("Status: \(age < 120 ? "healthy" : "STALE")")
        } else {
            print("No heartbeat found. Service may not be running.")
        }

        let dbPath = "\(NSHomeDirectory())/.config/reminders-sync/sync.db"
        if let db = try? SyncDatabase(path: dbPath) {
            let records = try db.fetchAll()
            print("Tracked tasks: \(records.count)")
            let completed = records.filter(\.completed).count
            print("  Active: \(records.count - completed)")
            print("  Completed: \(completed)")
        }

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
