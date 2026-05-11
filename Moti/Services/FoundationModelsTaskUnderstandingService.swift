import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsTaskUnderstandingService: TaskUnderstandingService {
    var fallback: any TaskUnderstandingService

    func parse(_ input: String) async throws -> ParsedWorkItem {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                return try await FoundationModelParser().parse(input)
            } catch {
                #if DEBUG
                print("FoundationModelsTaskUnderstandingService fallback:", error.localizedDescription)
                #endif
                return try await fallback.parse(input)
            }
        }
        #endif

        #if DEBUG
        print("FoundationModelsTaskUnderstandingService fallback: FoundationModels requires iOS 26 or newer.")
        #endif
        return try await fallback.parse(input)
    }
}

struct FoundationModelAvailabilityStatus: Equatable {
    var isAvailable: Bool
    var summary: String
    var fallbackSummary: String?
}

enum FoundationModelRuntime {
    static var status: FoundationModelAvailabilityStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return FoundationModelAvailabilityStatus(
                    isAvailable: true,
                    summary: "Available",
                    fallbackSummary: nil
                )
            case .unavailable(let reason):
                return FoundationModelAvailabilityStatus(
                    isAvailable: false,
                    summary: "Unavailable: \(reason.userFacingDescription)",
                    fallbackSummary: "Using Rule-based fallback"
                )
            }
        }
        #endif

        return FoundationModelAvailabilityStatus(
            isAvailable: false,
            summary: "Unavailable: requires iOS 26 and Apple Intelligence",
            fallbackSummary: "Using Rule-based fallback"
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private struct FoundationModelParser {
    func parse(_ input: String) async throws -> ParsedWorkItem {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw TaskUnderstandingError.foundationModelUnavailable(model.availability.userFacingDescription)
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(for: input),
            generating: FoundationModelWorkItemDraft.self
        )
        return map(response.content, rawInput: input)
    }

    private func map(_ draft: FoundationModelWorkItemDraft, rawInput input: String) -> ParsedWorkItem {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = Date.now
        let rawTemporal = DateResolver.resolveTemporal(in: trimmed, now: createdAt)
        let temporalIntent = normalizedTemporalIntent(draft.temporalIntent, rawInput: trimmed)
        let rawHasPeriodSyntax = DateResolver.containsWorkingPeriodSyntax(trimmed)

        var workingStartDate = draft.workingStartDateText
            .flatMap { DateResolver.resolveStartDate(in: $0, now: createdAt) }
            ?? rawTemporal.workingStartDate

        var workingEndDate = draft.workingEndDateText
            .flatMap { DateResolver.resolveEndDate(in: $0, now: createdAt) }
            ?? rawTemporal.workingEndDate

        if rawHasPeriodSyntax {
            workingStartDate = rawTemporal.workingStartDate ?? workingStartDate
            workingEndDate = rawTemporal.workingEndDate ?? workingEndDate
        }

        let shouldPreferPeriodEndAsDue = temporalIntent == .workingPeriod || (rawHasPeriodSyntax && temporalIntent != .periodWithDeadline)
        var dueDate: Date?
        if shouldPreferPeriodEndAsDue {
            dueDate = workingEndDate ?? rawTemporal.dueDate
        } else {
            dueDate = draft.dueDateText
                .flatMap { DateResolver.resolve(in: $0, now: createdAt)?.date }
                ?? rawTemporal.dueDate
        }

        if dueDate == nil, let workingEndDate, hasImplicitPeriodDeadline(in: trimmed) || rawHasPeriodSyntax {
            dueDate = workingEndDate
        }

        if let dueDate, workingStartDate == nil, workingEndDate == nil {
            workingStartDate = createdAt
            workingEndDate = dueDate
        }

        let modelTitle = RuleBasedTaskUnderstandingService.normalizedTitle(from: draft.title)
        let fallbackTitle = RuleBasedTaskUnderstandingService.normalizedTitle(from: trimmed)
        let title = modelTitle.isEmpty || modelTitle.caseInsensitiveCompare(trimmed) == .orderedSame ? fallbackTitle : modelTitle
        let project = normalizedProject(draft.projectName) ?? ProjectInferrer.infer(from: trimmed)
        let hasUsableTimeInfo = draft.hasUsableTimeInfo || dueDate != nil || workingStartDate != nil || workingEndDate != nil
        let explicitlyNoDeadline = DateResolver.explicitlyHasNoDeadline(trimmed)
        let actionable = CapturedClassifier.hasActionVerb(trimmed) || CapturedClassifier.hasActionVerb(title)

        let needsReview = explicitlyNoDeadline || !hasUsableTimeInfo || !actionable || title.isEmpty
        let reviewReason: String?
        if needsReview {
            if explicitlyNoDeadline || !hasUsableTimeInfo {
                reviewReason = "Missing time information"
            } else if !actionable || title.isEmpty {
                reviewReason = "Needs a clearer work description"
            } else {
                reviewReason = "Needs review before it can be placed on the timeline"
            }
        } else {
            reviewReason = nil
        }

        #if DEBUG
        print(
            """
            Foundation Model parsed:
            rawInput=\(trimmed)
            modelTitle=\(draft.title)
            title=\(title)
            project=\(project ?? "Uncategorized")
            temporalIntent=\(temporalIntent.rawValue)
            dueDateText=\(draft.dueDateText ?? "nil")
            workingStartDateText=\(draft.workingStartDateText ?? "nil")
            workingEndDateText=\(draft.workingEndDateText ?? "nil")
            dueDate=\(dueDate?.description ?? "nil")
            workingStartDate=\(workingStartDate?.description ?? "nil")
            workingEndDate=\(workingEndDate?.description ?? "nil")
            hasUsableTimeInfo=\(hasUsableTimeInfo)
            needsReview=\(needsReview)
            parserConfidence=\(draft.parserConfidence)
            """
        )
        #endif

        return ParsedWorkItem(
            rawInput: trimmed,
            title: title.isEmpty ? fallbackTitle : title,
            projectGuess: project,
            temporalIntent: temporalIntent,
            dueDate: dueDate,
            workingStartDate: workingStartDate,
            workingEndDate: workingEndDate,
            suggestedSessions: [],
            estimatedEffort: effortMinutes(from: draft.estimatedEffort),
            parserConfidence: min(max(draft.parserConfidence, 0.0), 1.0),
            needsReview: needsReview,
            reviewReason: reviewReason,
            parserExplanation: draft.reason
        )
    }

    private static var instructions: String {
        """
        You are the natural language understanding layer for Moti, an AI-native project timeline manager.

        Your job is to convert short user captures into structured work items.

        Moti is not a todo app. Moti places work on a project timeline.

        Core behavior:
        - Be helpful and infer reasonable defaults.
        - Do not be overly conservative.
        - If there is usable time information, create a timeline item.
        - Review is only for items that cannot be placed on the timeline.
        - Summarize the input into a clean short title.
        - Do not use the raw sentence as the title.
        - Infer the project proactively.
        - If project is unclear but time exists, use Uncategorized and still place it on Timeline.
        - If the user gives a date but no exact time, treat it as a valid deadline at 23:59.
        - If the user says "before X" or "by X," treat X as a deadline.
        - If dueDate exists but working period is missing, working period should be from createdAt to dueDate.
        - Do not assume the first date is the due date.
        - If the user says "between X and Y", X is workingStartDateText and Y is workingEndDateText.
        - If the user says "from X to Y", X is workingStartDateText and Y is workingEndDateText.
        - If the user gives both a working period and a deadline, preserve both separately.
        - For period-only work, use temporalIntent working_period and use the period end as dueDateText only if a deadline marker is useful.

        Title rules:
        Remove filler phrases: I need to, I have to, I want to, remind me to, please, can you.
        Remove time phrases from the title: before 5.15, by Friday, next Thursday 10AM, tomorrow, tonight, this weekend, between 5.20 and 6.5, from Monday to Wednesday.
        Normalize obvious grammar, such as "5 job application" to "5 job applications".
        Normalize "apply 3 roles" to "Apply to 3 roles".

        Temporal intent rules:
        - "between X and Y" -> working_period.
        - "from X to Y" -> working_period.
        - "from X to Y and submit by Z" -> period_with_deadline.
        - "before X", "by X", "due X", or "submit by X" -> deadline.
        - "meeting/interview/call at X" -> event.
        - "no deadline yet" -> no_time.

        Examples:
        Raw: I want to apply 3 big tech roles between 5.20 and 6.5
        Output: title Apply to 3 big tech roles, projectName Job Search, temporalIntent working_period, workingStartDateText 5.20, workingEndDateText 6.5, dueDateText 6.5, needsReview false.
        Raw: Work on portfolio from Monday to Wednesday and submit by Friday
        Output: title Work on portfolio, projectName Portfolio, temporalIntent period_with_deadline, workingStartDateText Monday, workingEndDateText Wednesday, dueDateText Friday, needsReview false.
        Raw: I need to finish 5 job applications before 5.15
        Output: title Finish 5 job applications, projectName Job Search, temporalIntent deadline, dueDateText 5.15, workingStartDateText null, workingEndDateText null, needsReview false.
        Raw: I need to have an interview with Matt next Thursday 10AM
        Output: title Interview with Matt, projectName Job Search, temporalIntent event, dueDateText next Thursday 10AM, workingStartDateText null, workingEndDateText null, needsReview false.

        Project inference:
        Job Search: job application, job applications, application, resume, recruiter, interview, referral, LinkedIn, cover letter, hiring, company, internship, full-time.
        School: assignment, DIS, class, course, paper, reading, research proposal, homework.
        Portfolio: portfolio, case study, website, personal brand, project page.
        Moti: Moti, app, SwiftUI, Xcode, parser, timeline, Codex.
        Personal: cycling, gym, grocery, errand, personal.

        Return structured output only.
        """
    }

    private static func prompt(for input: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let currentDate = formatter.string(from: .now)
        let timezone = TimeZone.current.identifier

        return """
        Current date: \(currentDate)
        Timezone: \(timezone)

        Convert this capture into a structured Moti work item:
        \(input)
        """
    }

    private func normalizedProject(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "Uncategorized" else { return nil }
        if ProjectCatalog.defaultProjects.contains(value) {
            return value
        }
        return nil
    }

    private func normalizedTemporalIntent(_ value: String, rawInput: String) -> WorkItemTemporalIntent {
        switch value.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "deadline":
            return .deadline
        case "working_period":
            return .workingPeriod
        case "event":
            return .event
        case "period_with_deadline":
            return .periodWithDeadline
        case "no_time":
            return .noTime
        default:
            let text = rawInput.lowercased()
            if DateResolver.explicitlyHasNoDeadline(rawInput) { return .noTime }
            if DateResolver.containsWorkingPeriodSyntax(rawInput) {
                if text.contains(" by ") || text.contains("before ") || text.contains("submit by") {
                    return .periodWithDeadline
                }
                return .workingPeriod
            }
            if text.contains("interview") || text.contains("meeting") || text.contains("call ") {
                return .event
            }
            return .unknown
        }
    }

    private func effortMinutes(from value: String) -> Int {
        switch value.lowercased() {
        case "low": 30
        case "high": 180
        default: 60
        }
    }

    private func hasImplicitPeriodDeadline(in input: String) -> Bool {
        let text = input.lowercased()
        return text.contains("over the weekend") || text.contains("this weekend")
    }
}

@available(iOS 26.0, *)
@Generable
private struct FoundationModelWorkItemDraft {
    @Guide(description: "A clean short title, not the raw user sentence.")
    var title: String

    @Guide(description: "One of Job Search, School, Portfolio, Moti, Personal, or Uncategorized.")
    var projectName: String

    @Guide(description: "One of deadline, working_period, event, period_with_deadline, or no_time.")
    var temporalIntent: String

    @Guide(description: "Deadline text, such as before 5.15, by Friday, next Thursday 10AM, or null.")
    var dueDateText: String?

    @Guide(description: "Working period start text, such as Monday, this Saturday, next Monday, or null.")
    var workingStartDateText: String?

    @Guide(description: "Working period end text, such as Wednesday, this Sunday, next Sunday, or null.")
    var workingEndDateText: String?

    @Guide(description: "True when there is any usable date, deadline, working period, or time range.")
    var hasUsableTimeInfo: Bool

    @Guide(description: "True only if the item cannot be placed on the timeline.")
    var needsReview: Bool

    @Guide(description: "One of low, medium, or high.")
    var estimatedEffort: String

    @Guide(description: "Parser confidence between 0.0 and 1.0.")
    var parserConfidence: Double

    @Guide(description: "Short explanation of the parse decision.")
    var reason: String
}

@available(iOS 26.0, *)
private extension SystemLanguageModel.Availability {
    var userFacingDescription: String {
        switch self {
        case .available:
            "Available"
        case .unavailable(let reason):
            reason.userFacingDescription
        }
    }
}

@available(iOS 26.0, *)
private extension SystemLanguageModel.Availability.UnavailableReason {
    var userFacingDescription: String {
        switch self {
        case .deviceNotEligible:
            "device not eligible"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence not enabled"
        case .modelNotReady:
            "model not ready"
        @unknown default:
            "unknown reason"
        }
    }
}
#endif
