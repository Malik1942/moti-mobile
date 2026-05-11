import Foundation
import SwiftData

@Model
final class WorkItem {
    @Attribute(.unique) var id: UUID
    var rawInput: String
    var title: String
    var projectName: String?
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
    var workingStartDate: Date?
    var workingEndDate: Date?
    var suggestedSessionsData: Data?
    var estimatedEffort: Int?
    @Attribute(originalName: "confidence") var parserConfidence: Double
    var needsReview: Bool
    var reviewReason: String?
    var statusRawValue: String
    var notes: String?
    var parserExplanation: String

    init(
        id: UUID = UUID(),
        rawInput: String,
        title: String,
        projectName: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        dueDate: Date?,
        workingStartDate: Date?,
        workingEndDate: Date?,
        suggestedSessions: [SuggestedSession],
        estimatedEffort: Int?,
        parserConfidence: Double,
        needsReview: Bool,
        reviewReason: String?,
        status: WorkItemStatus = .active,
        notes: String? = nil,
        parserExplanation: String
    ) {
        self.id = id
        self.rawInput = rawInput
        self.title = title
        self.projectName = projectName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.workingStartDate = workingStartDate
        self.workingEndDate = workingEndDate
        self.suggestedSessionsData = try? JSONEncoder().encode(suggestedSessions)
        self.estimatedEffort = estimatedEffort
        self.parserConfidence = parserConfidence
        self.needsReview = needsReview
        self.reviewReason = reviewReason
        self.statusRawValue = status.rawValue
        self.notes = notes
        self.parserExplanation = parserExplanation
    }

    convenience init(parsed: ParsedWorkItem) {
        self.init(
            rawInput: parsed.rawInput,
            title: parsed.title,
            projectName: parsed.projectGuess,
            dueDate: parsed.dueDate,
            workingStartDate: parsed.workingStartDate,
            workingEndDate: parsed.workingEndDate,
            suggestedSessions: parsed.suggestedSessions,
            estimatedEffort: parsed.estimatedEffort,
            parserConfidence: parsed.parserConfidence,
            needsReview: parsed.needsReview,
            reviewReason: parsed.reviewReason,
            status: parsed.needsReview ? .needsReview : .active,
            parserExplanation: parsed.parserExplanation
        )
    }

    var status: WorkItemStatus {
        get { WorkItemStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var suggestedSessions: [SuggestedSession] {
        get {
            guard let suggestedSessionsData else { return [] }
            return (try? JSONDecoder().decode([SuggestedSession].self, from: suggestedSessionsData)) ?? []
        }
        set {
            suggestedSessionsData = try? JSONEncoder().encode(newValue)
        }
    }

    var displayProject: String {
        projectName?.isEmpty == false ? projectName! : "Uncategorized"
    }
}
