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
    var calendarEventIdentifier: String?
    var calendarProvider: String?
    var lastCalendarSyncAt: Date?
    var suggestedProjectName: String?

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
        self.calendarEventIdentifier = nil
        self.calendarProvider = nil
        self.lastCalendarSyncAt = nil
        self.suggestedProjectName = nil
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
        projectName?.isEmpty == false ? projectName! : ProjectCatalog.unassignedLabel
    }

    /// True when the item has a usable working period or due date.
    var hasUsableTiming: Bool {
        let hasValidPeriod = workingStartDate.flatMap { start in
            workingEndDate.map { start <= $0 }
        } ?? false
        return dueDate != nil || hasValidPeriod
    }

    /// True when the item can appear on Timeline but has no assigned project.
    /// These items show in Review as a light (non-blocking) reminder.
    var needsProjectAssignment: Bool {
        hasUsableTiming && !needsReview && projectName == nil && status != .archived
    }

    /// Human-readable reason shown in the light-review row.
    var lightReviewReason: String {
        if let suggested = suggestedProjectName, !suggested.isEmpty {
            return "Suggested project: \(suggested)"
        }
        return "Assign a project"
    }
}
