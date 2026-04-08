import Foundation

struct ListMapping: Codable, Equatable {
    let reminders: String
    let omnifocus: String
}

struct Config: Codable, Equatable {
    let mappings: [ListMapping]
    let pollIntervalSeconds: Int
    let logLevel: String

    static let defaultPath = "\(NSHomeDirectory())/.config/reminders-sync/config.json"

    enum CodingKeys: String, CodingKey {
        case mappings, pollIntervalSeconds, logLevel
    }

    init(mappings: [ListMapping], pollIntervalSeconds: Int = 10, logLevel: String = "info") {
        self.mappings = mappings
        self.pollIntervalSeconds = pollIntervalSeconds
        self.logLevel = logLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mappings = try container.decode([ListMapping].self, forKey: .mappings)
        self.pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 10
        self.logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
    }

    static func parse(from data: Data) throws -> Config {
        let config = try JSONDecoder().decode(Config.self, from: data)
        guard !config.mappings.isEmpty else {
            throw ConfigError.emptyMappings
        }
        return config
    }

    static func load(from path: String) throws -> Config {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parse(from: data)
    }
}

enum ConfigError: Error, LocalizedError {
    case emptyMappings

    var errorDescription: String? {
        switch self {
        case .emptyMappings: return "Config must have at least one mapping."
        }
    }
}
