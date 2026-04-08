import XCTest
@testable import reminders_sync

final class OmniFocusScriptTests: XCTestCase {
    func testFetchTasksScriptContainsProjectName() {
        let script = OmniFocusAdapter.fetchTasksScript(projectName: "Groceries")
        XCTAssertTrue(script.contains("Groceries"))
        XCTAssertTrue(script.contains("flattenedProjects"))
    }

    func testParseTasksJSON() throws {
        let json = """
        [
          {"id":"abc","name":"Buy milk","note":"2%","dueDate":"2026-04-10","completed":false,"modified":"2026-04-07T10:00:00Z","tags":[]},
          {"id":"def","name":"Clean","note":null,"dueDate":null,"completed":true,"modified":"2026-04-07T11:00:00Z","tags":["errand"]}
        ]
        """
        let tasks = try OmniFocusAdapter.parseTasks(from: json)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].id, "abc")
        XCTAssertEqual(tasks[0].title, "Buy milk")
        XCTAssertEqual(tasks[0].notes, "2%")
        XCTAssertEqual(tasks[0].completed, false)
        XCTAssertEqual(tasks[1].completed, true)
        XCTAssertNil(tasks[1].dueDate)
    }

    func testCreateTaskScriptContainsFields() {
        let script = OmniFocusAdapter.createTaskScript(
            projectName: "Groceries",
            title: "Buy eggs", notes: "Free range",
            dueDate: "2026-04-10"
        )
        XCTAssertTrue(script.contains("Buy eggs"))
        XCTAssertTrue(script.contains("Free range"))
        XCTAssertTrue(script.contains("2026-04-10"))
        XCTAssertTrue(script.contains("Groceries"))
    }

    func testSoftDeleteScriptContainsDeletedTag() {
        let script = OmniFocusAdapter.softDeleteScript(taskId: "abc123")
        XCTAssertTrue(script.contains("DELETED"))
        XCTAssertTrue(script.contains("abc123"))
    }
}
