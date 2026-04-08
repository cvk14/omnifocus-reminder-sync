import AppKit
import Foundation

struct OFKeepalive {
    static let bundleID = "com.omnigroup.OmniFocus4"

    static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func ensureRunning() async throws {
        if isRunning() { return }

        Logger.info("OmniFocus not running, launching...")

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw OFKeepaliveError.notInstalled
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true

        try await NSWorkspace.shared.openApplication(at: url, configuration: config)

        for _ in 0..<30 {
            if isRunning() {
                Logger.info("OmniFocus launched successfully.")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw OFKeepaliveError.launchTimeout
    }
}

enum OFKeepaliveError: Error {
    case notInstalled
    case launchTimeout
}
