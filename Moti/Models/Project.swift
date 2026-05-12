import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorToken: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorToken: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorToken = colorToken
        self.createdAt = createdAt
    }
}
