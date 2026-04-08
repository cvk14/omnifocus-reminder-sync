import ArgumentParser

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync status and configuration."
    )

    func run() throws {
        print("Status not yet implemented.")
    }
}
