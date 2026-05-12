import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorToken: String
    var createdAt: Date
    var calendarIdentifier: String?
    var sortIndex: Int?

    init(
        id: UUID = UUID(),
        name: String,
        colorToken: String,
        createdAt: Date = .now,
        calendarIdentifier: String? = nil,
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.colorToken = colorToken
        self.createdAt = createdAt
        self.calendarIdentifier = calendarIdentifier
        self.sortIndex = sortIndex
    }
}

extension Array where Element == Project {
    var motiOrdered: [Project] {
        sorted { lhs, rhs in
            let lhsIndex = lhs.sortIndex ?? Int.max
            let rhsIndex = rhs.sortIndex ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var nextSortIndex: Int {
        (compactMap(\.sortIndex).max() ?? (count - 1)) + 1
    }
}
