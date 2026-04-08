import Foundation

enum LogLevel: String, Comparable {
    case debug, info, warn, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warn, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    static func from(_ string: String) -> LogLevel {
        LogLevel(rawValue: string.lowercased()) ?? .info
    }
}

struct Logger {
    static var level: LogLevel = .info
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func log(_ lvl: LogLevel, _ message: String) {
        guard lvl >= level else { return }
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(lvl.rawValue.uppercased())] \(message)")
    }

    static func debug(_ msg: String) { log(.debug, msg) }
    static func info(_ msg: String) { log(.info, msg) }
    static func warn(_ msg: String) { log(.warn, msg) }
    static func error(_ msg: String) { log(.error, msg) }
}
