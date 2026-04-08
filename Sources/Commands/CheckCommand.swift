import ArgumentParser
import EventKit
import Foundation

struct CheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Verify config against actual Reminders lists and OmniFocus projects."
    )

    func run() async throws {
        // Load config
        let config: Config
        do {
            config = try Config.load(from: Config.defaultPath)
            print("Config loaded from \(Config.defaultPath)")
        } catch {
            print("ERROR: Could not load config: \(error)")
            print("  Expected at: \(Config.defaultPath)")
            return
        }

        // Get Reminders lists
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            print("ERROR: Reminders access denied. Grant access in System Settings > Privacy > Reminders.")
            return
        }

        let reminderLists = store.calendars(for: .reminder).map(\.title)

        print("\n--- Reminders Lists ---")
        for name in reminderLists.sorted() {
            print("  \(name)")
        }

        // Get OmniFocus projects
        print("\n--- OmniFocus Projects ---")
        let ofAdapter = OmniFocusAdapter()
        let ofProjects: [String]
        do {
            let script = """
            const app = Application("OmniFocus");
            app.evaluateJavascript(`
                JSON.stringify(flattenedProjects.map(p => p.name));
            `);
            """
            let output = try ofAdapter.runScript(script)
            let json = output.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .replacingOccurrences(of: "\\\"", with: "\"")
            if let data = json.data(using: .utf8) {
                ofProjects = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            } else {
                ofProjects = []
            }
        } catch {
            print("  ERROR: Could not query OmniFocus: \(error)")
            print("  Is OmniFocus running?")
            ofProjects = []
        }

        for name in ofProjects.sorted() {
            print("  \(name)")
        }
        print("  Inbox (built-in)")

        // Validate mappings
        print("\n--- Config Validation ---")
        var allGood = true

        for mapping in config.mappings {
            let rOk = reminderLists.contains(mapping.reminders)
            let oOk = mapping.omnifocus == OmniFocusAdapter.inboxSentinel || ofProjects.contains(mapping.omnifocus)

            let rStatus = rOk ? "OK" : "NOT FOUND"
            let oStatus = oOk ? "OK" : "NOT FOUND"

            let line = "  \(mapping.reminders) [\(rStatus)] -> \(mapping.omnifocus) [\(oStatus)]"
            print(line)

            if !rOk || !oOk { allGood = false }
        }

        if allGood {
            print("\nAll mappings valid. Ready to sync.")
        } else {
            print("\nSome mappings have issues. Fix the list/project names in:")
            print("  \(Config.defaultPath)")
        }
    }
}
