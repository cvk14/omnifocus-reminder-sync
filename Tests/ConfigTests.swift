import XCTest
@testable import reminders_sync

final class ConfigTests: XCTestCase {
    func testParseFullConfig() throws {
        let json = """
        {
          "mappings": [
            {"reminders": "Inbox", "omnifocus": "OF Inbox"},
            {"reminders": "Groceries", "omnifocus": "Shopping"}
          ],
          "pollIntervalSeconds": 30,
          "logLevel": "debug"
        }
        """
        let config = try Config.parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(config.mappings.count, 2)
        XCTAssertEqual(config.mappings[0].reminders, "Inbox")
        XCTAssertEqual(config.mappings[0].omnifocus, "OF Inbox")
        XCTAssertEqual(config.pollIntervalSeconds, 30)
        XCTAssertEqual(config.logLevel, "debug")
    }

    func testParseMinimalConfig() throws {
        let json = """
        {
          "mappings": [{"reminders": "Inbox", "omnifocus": "Inbox"}]
        }
        """
        let config = try Config.parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(config.pollIntervalSeconds, 10)
        XCTAssertEqual(config.logLevel, "info")
    }

    func testParseEmptyMappingsThrows() {
        let json = """
        {"mappings": []}
        """
        XCTAssertThrowsError(try Config.parse(from: json.data(using: .utf8)!))
    }

    func testLoadFromFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-config.json")
        let json = """
        {"mappings": [{"reminders": "Inbox", "omnifocus": "Inbox"}]}
        """
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = try Config.load(from: tmp.path)
        XCTAssertEqual(config.mappings.count, 1)
    }
}
