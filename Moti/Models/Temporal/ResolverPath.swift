import Foundation

enum ResolverPath: String, Codable {
    case deterministic
    case semantic
    case llmTiebreaker
    case noSignal
}
