import Foundation

struct TaskSnapshot: Equatable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: String?  // ISO 8601
    var completed: Bool
    var modified: String  // ISO 8601
}
