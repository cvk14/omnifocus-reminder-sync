import Foundation

struct LaunchdHelper {
    static let label = "com.reminders-sync"
    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
    }

    static func install(executablePath: String) throws {
        let logDir = "\(NSHomeDirectory())/.config/reminders-sync/logs"
        try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "daemon"],
            "KeepAlive": true,
            "RunAtLoad": true,
            "StandardOutPath": "\(logDir)/stdout.log",
            "StandardErrorPath": "\(logDir)/stderr.log",
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Service installed and loaded.")
        } else {
            print("Warning: launchctl load exited with status \(process.terminationStatus)")
        }
    }

    static func uninstall() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath]
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(atPath: plistPath)
        print("Service unloaded and removed.")
    }
}
