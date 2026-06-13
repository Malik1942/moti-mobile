import Foundation

enum ResolverPath: String, Codable, Equatable {
    case deterministic
    case semantic
    case llmTiebreaker
    case noSignal
}
