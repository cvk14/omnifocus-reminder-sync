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
