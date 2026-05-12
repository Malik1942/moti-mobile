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
