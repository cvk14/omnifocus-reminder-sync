import ArgumentParser

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the launchd agent for automatic syncing."
    )

    func run() throws {
        print("Install not yet implemented.")
    }
}
