import Foundation

enum DeterministicPreClassifier {

    // Internal pairing of a resolution with its position in the input text.
    // Used to detect and remove overlapping matches.
    struct Candidate {
        let resolution: TemporalResolution
        let nsRange: NSRange
    }

    // Returns ALL non-overlapping temporal expressions found in the input, in order.
    // Multiple expressions ("5.15 at 7pm") each produce their own TemporalResolution.
    // Returns [] when no temporal signal is present.
    static func classify(
        input: String,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [TemporalResolution] {
        let text = input.lowercased()
        var pool: [Candidate] = []

        // Collect every match from every pattern (may overlap).
        // Clock time is collected before dot/slash so that "5.15pm" — where the am/pm check
        // in dot-notation discards the dot candidate — still gets a clock-time result.
        pool += isoDateCandidates(in: text, calendar: calendar, now: now)
        pool += relativeDurationCandidates(in: text, now: now)
        pool += clockTimeCandidates(in: text)
        pool += slashNotationCandidates(in: text, calendar: calendar, now: now)
        pool += dotNotationCandidates(in: text, calendar: calendar, now: now)
        pool += weekdayNameCandidates(in: text, calendar: calendar, now: now)
        pool += dayKeywordCandidates(in: text, calendar: calendar, now: now)
        pool += weekReferenceCandidates(in: text, calendar: calendar, now: now)

        // Sort by start position; earlier-starting match wins on overlap.
        let sorted = pool.sorted { $0.nsRange.location < $1.nsRange.location }
        return nonOverlapping(sorted).map(\.resolution)
    }

    // MARK: - Non-overlapping filter

    private static func nonOverlapping(_ sorted: [Candidate]) -> [Candidate] {
        var result: [Candidate] = []
        var lastEnd = 0
        for c in sorted {
            if c.nsRange.location >= lastEnd {
                result.append(c)
                lastEnd = NSMaxRange(c.nsRange)
            }
        }
        return result
    }

    // MARK: - Pattern: ISO date (2026-05-15)

    private static func isoDateCandidates(in text: String, calendar: Calendar, now: Date) -> [Candidate] {
        let pattern = #"\b(\d{4})-(\d{2})-(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let yr = intCapture(match, at: 1, in: text),
                  let mo = intCapture(match, at: 2, in: text),
                  let dy = intCapture(match, at: 3, in: text),
                  let date = calendar.date(from: DateComponents(year: yr, month: mo, day: dy))
            else { return nil }
            let r = TemporalResolution(originalText: substring(match, in: text),
                                       interpretation: .calendarDate, confidence: 0.95,
                                       resolvedDate: date, resolvedDuration: nil,
                                       resolvedClockTime: nil, formatAssumption: nil,
                                       alternativeCandidates: [], resolverPath: .deterministic)
            return Candidate(resolution: r, nsRange: match.range)
        }
    }

    // MARK: - Pattern: relative duration ("in 5 days", "after 3 hours")

    private static func relativeDurationCandidates(in text: String, now: Date) -> [Candidate] {
        // Requires an explicit time-unit word — prevents "in 5.15" from matching here.
        let pattern = #"\b(in|after)\s+(\d+)\s+(days?|weeks?|hours?|minutes?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let amount = intCapture(match, at: 2, in: text),
                  let unitRange = Range(match.range(at: 3), in: text)
            else { return nil }
            let unit = String(text[unitRange]).lowercased()
            let seconds: TimeInterval
            let label: String
            if unit.hasPrefix("minute") {
                seconds = TimeInterval(amount) * 60
                label = amount == 1 ? "in 1 minute" : "in \(amount) minutes"
            } else if unit.hasPrefix("hour") {
                seconds = TimeInterval(amount) * 3600
                label = amount == 1 ? "in 1 hour" : "in \(amount) hours"
            } else if unit.hasPrefix("week") {
                seconds = TimeInterval(amount) * 7 * 86_400
                label = amount == 1 ? "in 1 week" : "in \(amount) weeks"
            } else {
                seconds = TimeInterval(amount) * 86_400
                label = amount == 1 ? "in 1 day" : "in \(amount) days"
            }
            let r = TemporalResolution(originalText: substring(match, in: text),
                                       interpretation: .relativeDuration, confidence: 0.95,
                                       resolvedDate: Date(timeInterval: seconds, since: now),
                                       resolvedDuration: seconds,
                                       resolvedClockTime: nil, formatAssumption: nil,
                                       alternativeCandidates: [], resolverPath: .deterministic)
            return Candidate(resolution: r, nsRange: match.range)
        }
    }

    // MARK: - Pattern: clock time (7pm, 14:30)

    private static func clockTimeCandidates(in text: String) -> [Candidate] {
        let pattern = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let hour = intCapture(match, at: 1, in: text),
                  let meridiemRange = Range(match.range(at: 3), in: text)
            else { return nil }

            var h = hour
            let meridiem = String(text[meridiemRange]).lowercased()
            if meridiem == "pm", h < 12 { h += 12 }
            if meridiem == "am", h == 12 { h = 0 }
            // Validate 12-hour input (1-12 before meridiem conversion)
            guard (0...23).contains(h) else { return nil }

            let minute: Int
            if match.range(at: 2).location != NSNotFound, let m = intCapture(match, at: 2, in: text) {
                guard (0...59).contains(m) else { return nil }
                minute = m
            } else {
                minute = 0
            }

            var comps = DateComponents()
            comps.hour = h; comps.minute = minute
            let r = TemporalResolution(originalText: substring(match, in: text),
                                       interpretation: .clockTime, confidence: 0.90,
                                       resolvedDate: nil, resolvedDuration: nil,
                                       resolvedClockTime: comps, formatAssumption: nil,
                                       alternativeCandidates: [], resolverPath: .deterministic)
            return Candidate(resolution: r, nsRange: match.range)
        }
    }

    // MARK: - Pattern: slash notation (5/15, 5/15/26)

    private static func slashNotationCandidates(in text: String, calendar: Calendar, now: Date) -> [Candidate] {
        let pattern = #"\b(\d{1,2})/(\d{1,2})(?:/\d{2,4})?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let n = intCapture(match, at: 1, in: text),
                  let m = intCapture(match, at: 2, in: text)
            else { return nil }
            let matched = substring(match, in: text)
            let r = numericDateResolution(n: n, m: m, matched: matched,
                                          text: text, matchRange: match.range,
                                          calendar: calendar, now: now)
            return r.map { Candidate(resolution: $0, nsRange: match.range) }
        }
    }

    // MARK: - Pattern: dot notation (5.15, 10.3)

    private static func dotNotationCandidates(in text: String, calendar: Calendar, now: Date) -> [Candidate] {
        let pattern = #"\b(\d{1,2})\.(\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let n = intCapture(match, at: 1, in: text),
                  let m = intCapture(match, at: 2, in: text)
            else { return nil }

            // Skip if immediately followed by "am" or "pm" — it's a time like "5.15pm"
            let matchEnd = NSMaxRange(match.range)
            if let afterRange = Range(NSRange(location: matchEnd, length: 0), in: text) {
                let suffix = String(text[afterRange.lowerBound...].prefix(2)).lowercased()
                if suffix.hasPrefix("am") || suffix.hasPrefix("pm") { return nil }
            }

            let matched = substring(match, in: text)
            let r = numericDateResolution(n: n, m: m, matched: matched,
                                          text: text, matchRange: match.range,
                                          calendar: calendar, now: now)
            return r.map { Candidate(resolution: $0, nsRange: match.range) }
        }
    }

    // Shared resolution logic for N.M and N/M patterns.
    private static func numericDateResolution(
        n: Int, m: Int,
        matched: String,
        text: String,
        matchRange: NSRange,
        calendar: Calendar,
        now: Date
    ) -> TemporalResolution? {
        // Guard 1: must be valid US month.day values
        guard (1...12).contains(n), (1...31).contains(m) else {
            return TemporalResolution(originalText: matched, interpretation: .unknown,
                                      confidence: 0.1, resolvedDate: nil, resolvedDuration: nil,
                                      resolvedClockTime: nil, formatAssumption: nil,
                                      alternativeCandidates: [], resolverPath: .deterministic)
        }

        // Guard 2: currency, quantity, or version signals anywhere in the input
        if hasCurrencySignal(in: text) || hasQuantitySignal(in: text) || hasVersionSignal(in: text) {
            return TemporalResolution(originalText: matched, interpretation: .unknown,
                                      confidence: 0.1, resolvedDate: nil, resolvedDuration: nil,
                                      resolvedClockTime: nil, formatAssumption: nil,
                                      alternativeCandidates: [], resolverPath: .deterministic)
        }

        guard let date = futureDate(month: n, day: m, calendar: calendar, now: now) else { return nil }

        // Confidence depends on preceding preposition and surrounding context.
        let wordCount = text.split(separator: " ").count
        let preceding = precedingWord(beforeRange: matchRange, in: text)
        let baseConfidence: Double
        if wordCount <= 2 {
            // Almost no context — keep below Step-3 threshold so LLM runs
            baseConfidence = 0.60
        } else if let p = preceding, ["in", "after"].contains(p) {
            // Duration prepositions create ambiguity with relative duration interpretation.
            // Drop below 0.85 so SemanticContextResolver can weigh in.
            baseConfidence = 0.70
        } else if let p = preceding, p == "at" {
            // "at N.M" — could be time or date
            baseConfidence = 0.75
        } else {
            // "on 5.15", "by 5.15", no preposition — unambiguous date context
            baseConfidence = 0.85
        }

        return TemporalResolution(originalText: matched, interpretation: .calendarDate,
                                  confidence: baseConfidence, resolvedDate: date,
                                  resolvedDuration: nil, resolvedClockTime: nil,
                                  formatAssumption: "month.day (US format)",
                                  alternativeCandidates: [], resolverPath: .deterministic)
    }

    // MARK: - Pattern: named weekday

    private static func weekdayNameCandidates(in text: String, calendar: Calendar, now: Date) -> [Candidate] {
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        let pattern = #"\b(next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let dayRange = Range(match.range(at: 2), in: text) else { return nil }
            let dayName = String(text[dayRange])
            let hasNext = match.range(at: 1).location != NSNotFound
                && Range(match.range(at: 1), in: text) != nil
            guard let idx = days.firstIndex(of: dayName).map({ $0 + 2 }) else { return nil }
            let date = hasNext
                ? nextWeekdayStrictlyNext(idx, from: now, calendar: calendar)
                : nextWeekday(idx, from: now, calendar: calendar)
            let r = TemporalResolution(originalText: substring(match, in: text),
                                       interpretation: .calendarDate, confidence: 0.90,
                                       resolvedDate: date, resolvedDuration: nil,
                                       resolvedClockTime: nil, formatAssumption: nil,
                                       alternativeCandidates: [], resolverPath: .deterministic)
            return Candidate(resolution: r, nsRange: match.range)
        }
    }

    // MARK: - Pattern: today / tonight / tomorrow

    private static func dayKeywordCandidates(in text: String, calendar: Calendar, now: Date) -> [Candidate] {
        let pattern = #"\b(tonight|tomorrow|today)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let kwRange = Range(match.range(at: 1), in: text) else { return nil }
            let kw = String(text[kwRange])
            let date: Date
            switch kw {
            case "tonight":
                date = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now
            case "tomorrow":
                guard let t = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
                date = endOfDay(t, calendar: calendar)
            default: // "today"
                date = endOfDay(now, calendar: calendar)
            }
            let r = TemporalResolution(originalText: kw, interpretation: .calendarDate,
                                       confidence: 0.95, resolvedDate: date,
                                       resolvedDuration: nil, resolvedClockTime: nil,
                                       formatAssumption: nil, alternativeCandidates: [],
                                       resolverPath: .deterministic)
            return Candidate(resolution: r, nsRange: match.range)
        }
    }

    // MARK: - Pattern: this week / next week

    private static func weekReferenceCandidates(in text: String, calendar: Calendar, now: Date) -> [Candidate] {
        let pattern = #"\b(next|this)\s+week\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: fullRange(text)).compactMap { match in
            guard let kwRange = Range(match.range(at: 1), in: text) else { return nil }
            let kw = String(text[kwRange])
            let date: Date
            if kw == "next" {
                let monday = nextWeekday(2, from: now, calendar: calendar)
                guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: monday)?.start else { return nil }
                date = calendar.date(byAdding: .day, value: 6, to: weekStart)
                    .map { endOfDay($0, calendar: calendar) } ?? monday
            } else {
                date = nextWeekday(6, from: now, calendar: calendar) // Friday
            }
            let r = TemporalResolution(originalText: substring(match, in: text),
                                       interpretation: .calendarDate, confidence: 0.90,
                                       resolvedDate: date, resolvedDuration: nil,
                                       resolvedClockTime: nil, formatAssumption: nil,
                                       alternativeCandidates: [], resolverPath: .deterministic)
            return Candidate(resolution: r, nsRange: match.range)
        }
    }

    // MARK: - Guards

    private static func hasCurrencySignal(in text: String) -> Bool {
        SemanticBias.currencySignals.contains { text.contains($0) }
    }

    private static func hasQuantitySignal(in text: String) -> Bool {
        SemanticBias.quantitySignals.contains { text.contains($0) }
    }

    private static func hasVersionSignal(in text: String) -> Bool {
        SemanticBias.versionSignals.contains { text.contains($0) }
    }

    // MARK: - Preceding-word helper

    private static func precedingWord(beforeRange range: NSRange, in text: String) -> String? {
        guard range.location > 0,
              let endIdx = Range(NSRange(location: 0, length: range.location), in: text)?.upperBound
        else { return nil }
        let prefix = String(text[..<endIdx]).trimmingCharacters(in: .whitespaces)
        return prefix.components(separatedBy: .whitespaces).last.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Date helpers

    private static func futureDate(month: Int, day: Int, calendar: Calendar, now: Date) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: now)
        var comps = DateComponents(year: year, month: month, day: day)
        guard var date = calendar.date(from: comps) else { return nil }
        if calendar.startOfDay(for: date) < calendar.startOfDay(for: now) {
            comps.year = year + 1
            date = calendar.date(from: comps) ?? date
        }
        return endOfDay(date, calendar: calendar)
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
    }

    private static func nextWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: now)
        let days = (weekday - current + 7) % 7
        let offset = days == 0 ? 7 : days
        return endOfDay(calendar.date(byAdding: .day, value: offset, to: now) ?? now, calendar: calendar)
    }

    private static func nextWeekdayStrictlyNext(_ weekday: Int, from now: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: now)
        let days = (weekday - current + 7) % 7
        let offset = days == 0 ? 7 : days + 7
        return endOfDay(calendar.date(byAdding: .day, value: offset, to: now) ?? now, calendar: calendar)
    }

    // MARK: - Regex helpers

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..., in: text)
    }

    private static func intCapture(_ match: NSTextCheckingResult, at group: Int, in text: String) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static func substring(_ match: NSTextCheckingResult, in text: String) -> String {
        guard let range = Range(match.range, in: text) else { return "" }
        return String(text[range])
    }
}
