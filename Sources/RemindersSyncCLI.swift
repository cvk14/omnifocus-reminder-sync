import ArgumentParser

@main
struct RemindersSyncCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders-sync",
        abstract: "Bidirectional sync between Apple Reminders and OmniFocus.",
        subcommands: [SyncCommand.self, InstallCommand.self, UninstallCommand.self, StatusCommand.self, DaemonCommand.self]
    )
}
