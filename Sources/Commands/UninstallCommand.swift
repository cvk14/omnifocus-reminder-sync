import ArgumentParser

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall the launchd agent."
    )

    func run() throws {
        print("Uninstall not yet implemented.")
    }
}
