import Foundation

struct OFTask: Codable {
    let id: String
    let name: String
    let note: String?
    let dueDate: String?
    let completed: Bool
    let modified: String?
    let tags: [String]
}

class OmniFocusAdapter {

    // MARK: - Script Builders

    static func fetchTasksScript(projectName: String) -> String {
        let escaped = projectName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const proj = flattenedProjects.byName("\(escaped)");
            if (!proj) { JSON.stringify([]); }
            else {
                const tasks = proj.flattenedTasks.map(t => ({
                    id: t.id.primaryKey,
                    name: t.name,
                    note: t.note || null,
                    dueDate: t.dueDate ? t.dueDate.toISOString().substring(0,10) : null,
                    completed: t.taskStatus.name === "Completed",
                    modified: t.modified ? t.modified.toISOString() : null,
                    tags: t.tags.map(tag => tag.name)
                }));
                JSON.stringify(tasks);
            }
        `);
        """
    }

    static func createTaskScript(projectName: String, title: String, notes: String?, dueDate: String?) -> String {
        let escapedProject = projectName.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNotes = (notes ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let dueLine = dueDate.map { "t.dueDate = new Date(\"\($0)\");" } ?? ""
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const proj = flattenedProjects.byName("\(escapedProject)");
            const t = new Task("\(escapedTitle)", proj.beginning);
            t.note = "\(escapedNotes)";
            \(dueLine)
            t.id.primaryKey;
        `);
        """
    }

    static func updateTaskScript(taskId: String, title: String, notes: String?, dueDate: String?, completed: Bool) -> String {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNotes = (notes ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let dueLine = dueDate.map { "t.dueDate = new Date(\"\($0)\");" } ?? "t.dueDate = null;"
        let completionLine = completed ? "t.markComplete();" : "t.markIncomplete();"
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const t = Task.byIdentifier("\(taskId)");
            t.name = "\(escapedTitle)";
            t.note = "\(escapedNotes)";
            \(dueLine)
            \(completionLine)
            "ok";
        `);
        """
    }

    static func softDeleteScript(taskId: String) -> String {
        return """
        const app = Application("OmniFocus");
        app.evaluateJavascript(`
            const t = Task.byIdentifier("\(taskId)");
            if (!t.name.startsWith("DELETED ")) { t.name = "DELETED " + t.name; }
            const tag = flattenedTags.byName("DELETED") || new Tag("DELETED");
            t.addTag(tag);
            "ok";
        `);
        """
    }

    // MARK: - JSON Parsing

    static func parseTasks(from jsonString: String) throws -> [TaskSnapshot] {
        let data = jsonString.data(using: .utf8)!
        let ofTasks = try JSONDecoder().decode([OFTask].self, from: data)
        return ofTasks.map { t in
            TaskSnapshot(
                id: t.id,
                title: t.name,
                notes: t.note,
                dueDate: t.dueDate,
                completed: t.completed,
                modified: t.modified ?? Date().iso8601
            )
        }
    }

    // MARK: - Execution

    func runScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw OFError.scriptFailed(process.terminationStatus, output)
        }
        return output
    }

    func fetchTasks(projectName: String) throws -> [TaskSnapshot] {
        let script = Self.fetchTasksScript(projectName: projectName)
        let output = try runScript(script)
        let json = output.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
        return try Self.parseTasks(from: json)
    }

    func createTask(projectName: String, snapshot: TaskSnapshot) throws -> String {
        let script = Self.createTaskScript(
            projectName: projectName,
            title: snapshot.title, notes: snapshot.notes, dueDate: snapshot.dueDate
        )
        let output = try runScript(script)
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
    }

    func updateTask(id: String, snapshot: TaskSnapshot) throws {
        let script = Self.updateTaskScript(
            taskId: id, title: snapshot.title, notes: snapshot.notes,
            dueDate: snapshot.dueDate, completed: snapshot.completed
        )
        _ = try runScript(script)
    }

    func softDelete(id: String) throws {
        let script = Self.softDeleteScript(taskId: id)
        _ = try runScript(script)
    }
}

enum OFError: Error {
    case scriptFailed(Int32, String)
}
