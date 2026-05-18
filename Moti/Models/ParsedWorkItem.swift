import Foundation

struct ParsedWorkItem: Equatable {
    var rawInput: String
    var title: String
    var projectGuess: String?
    var temporalIntent: WorkItemTemporalIntent
    var dueDate: Date?
    var workingStartDate: Date?
    var workingEndDate: Date?
    var suggestedSessions: [SuggestedSession]
    var estimatedEffort: Int?
    var parserConfidence: Double
    var needsReview: Bool
    var reviewReason: String?
    var parserExplanation: String
}

enum WorkItemTemporalIntent: String, Codable, Equatable {
    case deadline
    case workingPeriod
    case event
    case periodWithDeadline
    case openEndedAfter
    case noTime
    case unknown
}

struct SuggestedSession: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var startTime: Date?
    var endTime: Date?
    var reason: String
    var source: String

    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date? = nil,
        endTime: Date? = nil,
        reason: String,
        source: String = "parser"
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.reason = reason
        self.source = source
    }
}

// MARK: - Deduplication

extension ParsedWorkItem {
    /// Compact key used to detect duplicate parses.
    ///
    /// Two parses with the same signature describe the same work item and
    /// should not both be inserted. Dates are rounded to the nearest minute so
    /// two parses of the same capture (one with microsecond-level drift) still
    /// collide.
    var dedupSignature: String {
        let normalizedTitle = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let project = (projectGuess ?? "").lowercased()
        let dueKey   = ParsedWorkItem.minuteKey(dueDate)
        let startKey = ParsedWorkItem.minuteKey(workingStartDate)
        let endKey   = ParsedWorkItem.minuteKey(workingEndDate)
        return "\(normalizedTitle)|\(project)|\(dueKey)|\(startKey)|\(endKey)|\(temporalIntent.rawValue)"
    }

    private static func minuteKey(_ date: Date?) -> String {
        guard let date else { return "-" }
        return String(Int(date.timeIntervalSinceReferenceDate / 60))
    }
}

extension Array where Element == ParsedWorkItem {
    /// Drops content-duplicate items while preserving the original order. Used
    /// as a final guard before inserting work items into SwiftData so that any
    /// upstream parser glitch (FM returning the same item twice, user typing a
    /// duplicate line, segmenter over-splitting) never produces duplicate work.
    func deduplicatedByContent() -> [ParsedWorkItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.dedupSignature).inserted }
    }
}
