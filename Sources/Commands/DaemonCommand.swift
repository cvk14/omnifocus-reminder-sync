import ArgumentParser
import Foundation

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

        // Keep the process alive; dispatchMain() never returns.
        dispatchMain()
    }
}
