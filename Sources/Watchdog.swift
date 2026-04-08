import Foundation

class Watchdog {
    private let heartbeatPath: String
    private var timer: DispatchSourceTimer?
    private let staleThreshold: TimeInterval
    private let onStale: () -> Void

    init(heartbeatPath: String, staleThreshold: TimeInterval = 60, onStale: @escaping () -> Void) {
        self.heartbeatPath = heartbeatPath
        self.staleThreshold = staleThreshold
        self.onStale = onStale
    }

    func beat() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? timestamp.write(toFile: heartbeatPath, atomically: true, encoding: .utf8)
    }

    func start() {
        let queue = DispatchQueue(label: "watchdog")
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + staleThreshold, repeating: staleThreshold)
        timer?.setEventHandler { [weak self] in
            self?.check()
        }
        timer?.resume()
        Logger.info("Watchdog started (threshold: \(Int(staleThreshold))s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func check() {
        guard let content = try? String(contentsOfFile: heartbeatPath, encoding: .utf8),
              let lastBeat = ISO8601DateFormatter().date(from: content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            Logger.warn("Watchdog: no heartbeat file found, triggering restart.")
            onStale()
            return
        }

        let age = Date().timeIntervalSince(lastBeat)
        if age > staleThreshold {
            Logger.warn("Watchdog: heartbeat stale by \(Int(age))s, triggering restart.")
            onStale()
        }
    }
}
