import Foundation

struct RuleBasedTaskUnderstandingService: TaskUnderstandingService {
    func parseMany(_ input: String) async throws -> [ParsedWorkItem] {
        let segments = CaptureSegmenter.segments(from: input)
        guard segments.count > 1 else {
            return [try await parse(input)]
        }
        var parsedItems: [ParsedWorkItem] = []
        for segment in segments {
            parsedItems.append(try await parse(segment))
        }
        return parsedItems
    }

    func parse(_ input: String) async throws -> ParsedWorkItem {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let temporal = DateResolver.resolveTemporal(in: trimmed)
        let openEndedStart = Self.openEndedAfterStart(in: trimmed)
        let isOpenEndedAfter = openEndedStart != nil
        let project = ProjectInferrer.infer(from: trimmed)
        let hasVerb = CapturedClassifier.hasActionVerb(trimmed)
        let veryVague = CapturedClassifier.isVeryVague(trimmed)
        let hasNumericRange = trimmed.range(of: #"\b\d+\s+to\s+\d+\b"#, options: .regularExpression) != nil
        let title = Self.normalizedTitle(from: trimmed)
        let hasUsableSchedule = temporal.hasTimeInformation || isOpenEndedAfter
        let actionable = hasVerb || (!title.isEmpty && hasUsableSchedule && !veryVague)
        let clearTitle = actionable && !title.isEmpty

        let parserConfidence: Double
        if clearTitle && temporal.hasTimeInformation && !temporal.isVague && project != nil {
            parserConfidence = 0.92
        } else if clearTitle && temporal.hasTimeInformation {
            parserConfidence = temporal.isVague ? 0.68 : 0.82
        } else if clearTitle && project != nil {
            parserConfidence = 0.75
        } else if veryVague || !clearTitle {
            parserConfidence = project != nil ? 0.42 : 0.25
        } else {
            parserConfidence = 0.55
        }

        let needsReview = DateResolver.explicitlyHasNoDeadline(trimmed) || !hasUsableSchedule || !actionable || title.isEmpty || isOpenEndedAfter
        let reviewReason: String?
        if isOpenEndedAfter {
            reviewReason = "Missing end date"
        } else if DateResolver.explicitlyHasNoDeadline(trimmed) || !hasUsableSchedule {
            reviewReason = "Missing time information"
        } else if !actionable || title.isEmpty {
            reviewReason = "Needs a clearer work description"
        } else {
            reviewReason = nil
        }
        let intent = isOpenEndedAfter ? WorkItemTemporalIntent.openEndedAfter : Self.temporalIntent(for: trimmed, temporal: temporal)

        // Events are point-in-time: override the createdAt→dueDate fallback with a one-day bar.
        var dueDate = temporal.dueDate
        var workStart = temporal.workingStartDate
        var workEnd = temporal.workingEndDate
        if isOpenEndedAfter {
            dueDate = nil
            workStart = openEndedStart
            workEnd = nil
        } else if intent == .event, let due = temporal.dueDate {
            let cal = Calendar.current
            workStart = cal.startOfDay(for: due)
            workEnd = cal.date(bySettingHour: 23, minute: 59, second: 0, of: due) ?? due
        }

        let sessions = Self.suggestedSessions(
            start: workStart,
            end: workEnd,
            due: temporal.dueDate
        )

        return ParsedWorkItem(
            rawInput: trimmed,
            title: title.isEmpty ? trimmed : title,
            projectGuess: project,
            temporalIntent: intent,
            dueDate: dueDate,
            workingStartDate: workStart,
            workingEndDate: workEnd,
            suggestedSessions: needsReview ? [] : sessions,
            estimatedEffort: hasNumericRange ? 120 : 60,
            parserConfidence: parserConfidence,
            needsReview: needsReview,
            reviewReason: reviewReason,
            parserExplanation: reasoningSummary(clearTitle: clearTitle, hasTime: temporal.hasTimeInformation, project: project, vague: temporal.isVague)
        )
    }

    private static func suggestedSessions(start: Date?, end: Date?, due: Date?) -> [SuggestedSession] {
        guard let start, let end else { return [] }
        let calendar = Calendar.current
        let first = calendar.date(byAdding: .hour, value: 2, to: start) ?? start
        let midpoint = Date(timeInterval: end.timeIntervalSince(start) * 0.55, since: start)
        let final = due.flatMap { calendar.date(byAdding: .hour, value: -24, to: $0) }
        let candidates = [first, midpoint, final].compactMap { $0 }.filter { $0 <= end }
        return Array(candidates.prefix(3)).map {
            SuggestedSession(date: $0, startTime: $0, endTime: calendar.date(byAdding: .minute, value: 45, to: $0), reason: "Suggested before the deadline")
        }
    }

    static func normalizedTitle(from input: String) -> String {
        var source = input
        if let equalsRange = source.range(of: "=") {
            source = String(source[equalsRange.upperBound...])
        }

        var title = DateResolver.removingDatePhrases(from: source)
        for prefix in ["i need to ", "i have to ", "i want to ", "remind me to ", "please ", "can you ", "i need ", "need to ", "need "] {
            if title.lowercased().hasPrefix(prefix) {
                title.removeFirst(prefix.count)
                break
            }
        }
        title = title.replacingOccurrences(
            of: #"\b(\d+)\s+job application\b"#,
            with: "$1 job applications",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: #"(?i)^apply\s+(?!to\b)"#,
            with: "Apply to ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"(?i)^have an interview with\s+"#,
            with: "Interview with ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"(?i)\s+and\s+(submit|finish|send|turn in)$"#,
            with: "",
            options: .regularExpression
        )
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-")))
        title = title.split(separator: " ").joined(separator: " ")
        guard let first = title.first else { return "" }
        return first.uppercased() + String(title.dropFirst())
    }

    private static func temporalIntent(for input: String, temporal: DateResolver.TemporalParse) -> WorkItemTemporalIntent {
        let text = input.lowercased()
        if DateResolver.explicitlyHasNoDeadline(input) || !temporal.hasTimeInformation {
            return .noTime
        }
        let hasWorkingPeriod = temporal.workingStartDate != nil && temporal.workingEndDate != nil
        let hasPeriodSyntax = text.contains("between ") || text.contains("from ") || text.contains("over the weekend") || text.contains("this weekend") || text.contains("during next week")
        let hasDeadlineSyntax = text.contains(" by ") || text.contains("before ") || text.contains(" due ") || text.contains("submit by") || text.contains("finish before")
        if hasPeriodSyntax && hasDeadlineSyntax { return .periodWithDeadline }
        if hasPeriodSyntax || (hasWorkingPeriod && temporal.isVague) { return .workingPeriod }
        if text.contains("interview") || text.contains("meeting") || text.contains("meet ") || text.contains("call ") {
            return .event
        }
        return .deadline
    }

    private static func openEndedAfterStart(in input: String) -> Date? {
        let text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("after ") else { return nil }
        return DateResolver.resolveStartDate(in: text)
    }

    private func reasoningSummary(clearTitle: Bool, hasTime: Bool, project: String?, vague: Bool) -> String {
        if clearTitle && hasTime && !vague { return "Placed this on the timeline with a working period and deadline." }
        if clearTitle && hasTime { return "Added this with a softer time window, so the timeline can stay flexible." }
        if !hasTime { return "Needs review because there is no time information yet." }
        if project == nil { return "Added timing, but the project is not obvious yet." }
        return "Needs a clearer work description before scheduling."
    }
}
