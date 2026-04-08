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
