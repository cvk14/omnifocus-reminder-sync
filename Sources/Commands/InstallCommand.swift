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
