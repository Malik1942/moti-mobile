import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsTaskUnderstandingService: TaskUnderstandingService {
    var fallback: any TaskUnderstandingService

    func parse(_ input: String) async throws -> ParsedWorkItem {
        let items = try await parseMany(input)
        if let first = items.first {
            return first
        }
        return try await fallback.parse(input)
    }

    func parseMany(_ input: String) async throws -> [ParsedWorkItem] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let items = try await FoundationModelParser().parseMany(input)
                if items.isEmpty {
                    return try await fallback.parseMany(input)
                }
                return items
            } catch {
                #if DEBUG
                print("FoundationModelsTaskUnderstandingService fallback:", error.localizedDescription)
                #endif
                return try await fallback.parseMany(input)
            }
        }
        #endif

        #if DEBUG
        print("FoundationModelsTaskUnderstandingService fallback: FoundationModels requires iOS 26 or newer.")
        #endif
        return try await fallback.parseMany(input)
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
        let items = try await parseMany(input)
        guard let first = items.first else {
            throw TaskUnderstandingError.foundationModelUnavailable("no structured work items returned")
        }
        return first
    }

    func parseMany(_ input: String) async throws -> [ParsedWorkItem] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw TaskUnderstandingError.foundationModelUnavailable(model.availability.userFacingDescription)
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(for: input),
            generating: FoundationModelWorkItemsDraft.self
        )

        let localSegments = CaptureSegmenter.segments(from: input)
        let drafts = response.content.items
        let mapped = drafts.enumerated().map { index, draft in
            let source = draft.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackSource = localSegments.count == drafts.count ? localSegments[index] : input
            return map(draft, rawInput: source?.isEmpty == false ? source! : fallbackSource)
        }

        // Defense in depth: the model occasionally splits one capture into a
        // bare task plus a temporal twin (e.g. "finish video filming" +
        // "finish video filming before 3:45"), or returns the same item twice.
        // Collapse exact duplicates AND temporal variants into one richer task
        // before deciding whether to fall back to the line-based splitter below.
        let deduplicated = mapped.deduplicatedMergingVariants()

        #if DEBUG
        if deduplicated.count != mapped.count {
            print(
                "Foundation Model dedup: model returned \(mapped.count) drafts, \(deduplicated.count) unique."
            )
        }
        #endif

        if deduplicated.count <= 1, localSegments.count > 1 {
            #if DEBUG
            print("Foundation Model returned one item for a multi-segment capture; using line-based fallback split.")
            #endif
            return try await RuleBasedTaskUnderstandingService().parseMany(input)
        }

        return deduplicated
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
        if temporalIntent == .openEndedAfter {
            dueDate = nil
            workingStartDate = draft.workingStartDateText
                .flatMap { DateResolver.resolveStartDate(in: $0, now: createdAt) }
                ?? rawTemporal.dueDate
                .flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) }
            workingEndDate = nil
        } else if shouldPreferPeriodEndAsDue {
            dueDate = workingEndDate ?? rawTemporal.dueDate
        } else {
            dueDate = draft.dueDateText
                .flatMap { DateResolver.resolve(in: $0, now: createdAt)?.date }
                ?? rawTemporal.dueDate
        }

        if dueDate == nil, let workingEndDate, hasImplicitPeriodDeadline(in: trimmed) || rawHasPeriodSyntax {
            dueDate = workingEndDate
        }

        if temporalIntent == .event, let dueDate {
            // Point-in-time: one-day bar on the event date, not createdAt → eventDate.
            let cal = Calendar.current
            workingStartDate = cal.startOfDay(for: dueDate)
            workingEndDate = cal.date(bySettingHour: 23, minute: 59, second: 0, of: dueDate) ?? dueDate
        } else if let dueDate, workingStartDate == nil, workingEndDate == nil {
            workingStartDate = createdAt
            workingEndDate = dueDate
        }

        let modelTitle = RuleBasedTaskUnderstandingService.normalizedTitle(from: draft.title)
        let fallbackTitle = RuleBasedTaskUnderstandingService.normalizedTitle(from: trimmed)
        let title = modelTitle.isEmpty || modelTitle.caseInsensitiveCompare(trimmed) == .orderedSame ? fallbackTitle : modelTitle
        let project = normalizedProject(draft.projectName) ?? ProjectInferrer.infer(from: trimmed)
        let hasUsableTimeInfo = draft.hasUsableTimeInfo || dueDate != nil || workingStartDate != nil || workingEndDate != nil
        let explicitlyNoDeadline = DateResolver.explicitlyHasNoDeadline(trimmed)
        let actionable = CapturedClassifier.hasActionVerb(trimmed)
            || CapturedClassifier.hasActionVerb(title)
            || (!title.isEmpty && hasUsableTimeInfo && !CapturedClassifier.isVeryVague(title))
        let missingEndDate = temporalIntent == .openEndedAfter || (workingStartDate != nil && workingEndDate == nil && dueDate == nil)
        // An ambiguous same-day time whose AM and PM readings have both passed is
        // an impossible deadline — route to review rather than create it past-due.
        let timeAlreadyPassed = DateResolver.ambiguousClockTimeAlreadyPassed(in: trimmed, now: createdAt)

        let needsReview = explicitlyNoDeadline || !hasUsableTimeInfo || !actionable || title.isEmpty || missingEndDate || timeAlreadyPassed
        let reviewReason: String?
        if needsReview {
            if missingEndDate {
                reviewReason = "Missing end date"
            } else if explicitlyNoDeadline || !hasUsableTimeInfo {
                reviewReason = "Missing time information"
            } else if timeAlreadyPassed {
                reviewReason = "That time has already passed today"
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
            sourceText=\(draft.sourceText ?? "nil")
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
        - If temporalIntent is deadline and dueDate exists but working period is missing, set working period from createdAt to dueDate.
        - If temporalIntent is event, do NOT add a working period. Set workingStartDateText and workingEndDateText to null. The Swift layer creates a one-day working period from the event date.
        - Do not assume the first date is the due date.
        - If the user says "between X and Y", X is workingStartDateText and Y is workingEndDateText.
        - If the user says "from X to Y", X is workingStartDateText and Y is workingEndDateText.
        - If the user gives both a working period and a deadline, preserve both separately.
        - For period-only work, use temporalIntent working_period and use the period end as dueDateText only if a deadline marker is useful.
        - A single capture can contain multiple independent work items. Return one item per independent work intention.
        - Split on line breaks, bullet points, numbered lists, semicolons, equals-sign structures, and separate clauses with different time expressions when they describe distinct deliverables or phases.
        - Split phase language such as "now to X", "after X", and "by X" when each phrase describes a separate work phase.
        - Do not split one coherent item just because it has both a working period and a deadline.
        - "now to X = work" means temporalIntent working_period, workingStartDateText now, workingEndDateText X.
        - "after X = work" means temporalIntent open_ended_after, workingStartDateText after X, workingEndDateText null, dueDateText null, needsReview true, reason Missing end date.

        Uniqueness:
        - Each returned item must be unique. Never return the same item twice.
        - Two items are duplicates if they share the same title, project, and timing. If the user expressed the same intention twice, return only one item.
        - Before returning, mentally verify that each item has a distinct combination of (title, dates). Do not pad the list with near-duplicates.

        When NOT to split (one coherent item):
        - Multiple verbs on the same thing: "research and write the paper this weekend" → 1 item.
        - Sequential micro-actions on one target: "review and approve the PR" → 1 item.
        - Setup steps listed inline as detail: "set up dev environment: clone repo, install deps, run tests" → 1 item.
        - Working period plus deadline for the same deliverable: "work on portfolio from Monday to Wednesday and submit by Friday" → 1 item, period_with_deadline.
        - A list of small details under one heading or task name: "groceries: eggs, milk, bread" → 1 item.

        When to split (independent items):
        - Different targets or people, parallel actions: "email Alice and call Bob tomorrow" → 2 items.
        - Semicolon-separated unrelated tasks: "buy groceries; finish report by Friday" → 2 items.
        - Dated rows mapping each day to its own work: "Monday: design review, Tuesday: code review, Wednesday: deploy" → 3 items, each event/working_period for its date.
        - Numbered or bulleted list of independent work: "1. Submit application by Friday. 2. Prep interview for next week." → 2 items.
        - Multiple time expressions, each anchoring its own task: "send invoice today, review contract tomorrow" → 2 items.

        When in doubt, prefer not to split. One slightly broad task is a better outcome than two duplicate or fragmented tasks.

        Title rules:
        Remove filler phrases: I need to, I have to, I want to, remind me to, please, can you.
        Remove time phrases from the title: before 5.15, by Friday, next Thursday 10AM, tomorrow, tonight, this weekend, between 5.20 and 6.5, from Monday to Wednesday.
        Normalize obvious grammar, such as "5 job application" to "5 job applications".
        Normalize "apply 3 roles" to "Apply to 3 roles".

        Temporal intent rules:
        - "on [date]" or "at [time]" for a point-in-time item (interview, meeting, call, demo, exam, presentation, submission event) -> event.
        - "between X and Y" -> working_period.
        - "from X to Y" -> working_period.
        - "from X to Y and submit by Z" -> period_with_deadline.
        - "before X", "by X", "due X", or "submit by X" -> deadline.
        - "now to X" -> working_period.
        - "after X" with no end date -> open_ended_after.
        - "meeting/interview/call/demo at X" -> event.
        - "no deadline yet" -> no_time.
        For events: workingStartDateText = null, workingEndDateText = null. Only dueDateText is set.

        Examples:
        Raw: I want to apply 3 big tech roles between 5.20 and 6.5
        Output: title Apply to 3 big tech roles, projectName Job Search, temporalIntent working_period, workingStartDateText 5.20, workingEndDateText 6.5, dueDateText 6.5, needsReview false.
        Raw: Work on portfolio from Monday to Wednesday and submit by Friday
        Output: title Work on portfolio, projectName Portfolio, temporalIntent period_with_deadline, workingStartDateText Monday, workingEndDateText Wednesday, dueDateText Friday, needsReview false.
        Raw: I need to finish 5 job applications before 5.15
        Output: title Finish 5 job applications, projectName Job Search, temporalIntent deadline, dueDateText 5.15, workingStartDateText null, workingEndDateText null, needsReview false.
        Raw: Submit portfolio by Friday
        Output: title Submit portfolio, projectName Portfolio, temporalIntent deadline, dueDateText Friday, workingStartDateText null, workingEndDateText null, needsReview false.
        Raw: I need to have an interview with Matt next Thursday 10AM
        Output: title Interview with Matt, projectName Job Search, temporalIntent event, dueDateText next Thursday 10AM, workingStartDateText null, workingEndDateText null, needsReview false.
        Raw: Interview with Matt on Friday
        Output: title Interview with Matt, projectName Job Search, temporalIntent event, dueDateText Friday, workingStartDateText null, workingEndDateText null, needsReview false.
        Raw: Call recruiter on 5.20
        Output: title Call recruiter, projectName Job Search, temporalIntent event, dueDateText 5.20, workingStartDateText null, workingEndDateText null, needsReview false.
        Raw:
        Now to May 15 = preparation and casual job hunting
        After May 15 = serious job hunting and outreach rhythm
        By May 22 = story library ready for interviews and coffee chats
        Output: three items:
        1. sourceText Now to May 15 = preparation and casual job hunting, title Preparation and casual job hunting, projectName Job Search, temporalIntent working_period, workingStartDateText now, workingEndDateText May 15, dueDateText May 15, needsReview false.
        2. sourceText After May 15 = serious job hunting and outreach rhythm, title Serious job hunting and outreach rhythm, projectName Job Search, temporalIntent open_ended_after, workingStartDateText after May 15, workingEndDateText null, dueDateText null, needsReview true.
        3. sourceText By May 22 = story library ready for interviews and coffee chats, title Build story library for interviews and coffee chats, projectName Job Search, temporalIntent deadline, dueDateText May 22, workingStartDateText null, workingEndDateText null, needsReview false.

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

        Convert this capture into structured Moti work items.
        Return an array. If the capture is one coherent work intention, return exactly one item.
        If it contains multiple lines or independent dated phases, return multiple items.

        \(input)
        """
    }

    private func normalizedProject(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "Uncategorized" else { return nil }
        return ProjectCatalog.normalizedTemplateName(value)
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
        case "open_ended_after":
            return .openEndedAfter
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
private struct FoundationModelWorkItemsDraft {
    @Guide(description: "All parsed work items from the capture. Use one item for one coherent work intention; use multiple items for independent lines, bullets, phases, or deliverables.")
    var items: [FoundationModelWorkItemDraft]
}

@available(iOS 26.0, *)
@Generable
private struct FoundationModelWorkItemDraft {
    @Guide(description: "The original line or fragment this item came from.")
    var sourceText: String?

    @Guide(description: "A clean short title, not the raw user sentence.")
    var title: String

    @Guide(description: "One of Job Search, School, Portfolio, Moti, Personal, or Uncategorized.")
    var projectName: String

    @Guide(description: "One of deadline, working_period, event, period_with_deadline, open_ended_after, or no_time.")
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
