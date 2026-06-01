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
    var calendarIdentifier: String?
    var calendarProvider: String?
    var lastCalendarSyncAt: Date?
    var suggestedProjectName: String?

    // Structured recurrence. Stored as flat columns (with defaults so existing
    // stores migrate lightweightly) and surfaced through the `recurrence`
    // computed property. A recurring item is a single WorkItem whose `dueDate`
    // is its next occurrence — it is never expanded into infinite instances.
    var recurrenceFrequencyRawValue: String = RecurrenceFrequency.none.rawValue
    var recurrenceInterval: Int = 1
    var recurrenceWeekday: Int?

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
        self.calendarIdentifier = nil
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

    /// Structured recurrence rule, assembled from the flat stored columns.
    var recurrence: RecurrenceRule {
        get {
            RecurrenceRule(
                frequency: RecurrenceFrequency(rawValue: recurrenceFrequencyRawValue) ?? .none,
                interval: max(1, recurrenceInterval),
                weekday: recurrenceWeekday
            )
        }
        set {
            recurrenceFrequencyRawValue = newValue.frequency.rawValue
            recurrenceInterval = max(1, newValue.interval)
            recurrenceWeekday = newValue.weekday
        }
    }

    var isRecurring: Bool { recurrence.isRecurring }

    /// Completes one occurrence of a recurring item: rolls `dueDate` forward to
    /// the next occurrence and leaves the item **active** so the habit keeps
    /// living. Storing a single rolled-forward item — rather than spawning a new
    /// one — is what prevents infinite future duplication.
    ///
    /// Returns the occurrence date that was just completed (for logging), or
    /// `nil` for non-recurring items, signalling the caller to fall back to
    /// normal `.done` completion.
    @discardableResult
    func completeRecurringOccurrence(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard isRecurring else { return nil }
        // Advance from the current due date when present (the occurrence the user
        // just finished), otherwise from now. Recurrence fields are untouched.
        let completedOccurrence = dueDate ?? now
        dueDate = recurrence.nextOccurrence(after: completedOccurrence, calendar: calendar)
        updatedAt = now
        return completedOccurrence
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

    func elapsedTime(asOf date: Date = .now, calendar: Calendar = .current) -> WorkItemElapsedTime? {
        guard let start = workingStartDate, let end = workingEndDate else { return nil }

        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        guard startDay < endDay else {
            return WorkItemElapsedTime(elapsedDays: 0, totalDays: 0, percentage: 0, isEvent: true)
        }

        let totalDays = max(1, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 1)
        let currentDay = calendar.startOfDay(for: date)
        let rawElapsedDays = calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0
        let elapsedDays = min(max(rawElapsedDays, 0), totalDays)
        let percentage = Int((Double(elapsedDays) / Double(totalDays) * 100).rounded())

        return WorkItemElapsedTime(
            elapsedDays: elapsedDays,
            totalDays: totalDays,
            percentage: min(max(percentage, 0), 100),
            isEvent: false
        )
    }
}

struct WorkItemElapsedTime: Equatable {
    let elapsedDays: Int
    let totalDays: Int
    let percentage: Int
    let isEvent: Bool

    var compactLabel: String {
        isEvent ? "Event" : "\(elapsedDays)/\(totalDays)d · \(percentage)%"
    }

    var detailLabel: String {
        isEvent ? "Event" : "\(elapsedDays) of \(totalDays) days · \(percentage)%"
    }
}
