import Foundation

enum DateResolver {
    struct TemporalParse {
        var dueDate: Date?
        var dueLabel: String?
        var workingStartDate: Date?
        var workingEndDate: Date?
        var isVague: Bool
        var hasTimeInformation: Bool
    }

    static func resolveTemporal(in input: String, calendar: Calendar = .current, now: Date = .now) -> TemporalParse {
        let text = input.lowercased()
        var due: (date: Date, label: String, rangeLike: Bool)?
        var workStart: Date?
        var workEnd: Date?
        var vague = false

        if text.contains("no deadline") || text.contains("whenever") {
            return TemporalParse(dueDate: nil, dueLabel: nil, workingStartDate: nil, workingEndDate: nil, isVague: true, hasTimeInformation: false)
        }

        if let range = resolveWorkingRange(in: text, calendar: calendar, now: now) {
            workStart = range.start
            workEnd = range.end
            vague = range.vague
        }

        if workStart != nil || workEnd != nil {
            due = resolveExplicitDeadline(in: text, calendar: calendar, now: now)
            if due == nil, let workEnd {
                due = (workEnd, "working period end", true)
            }
        } else {
            due = resolve(in: input, calendar: calendar, now: now)
        }

        if due == nil, text.contains("this weekend") || text.contains("over the weekend") {
            let weekend = upcomingWeekend(from: now, calendar: calendar)
            workStart = workStart ?? weekend.start
            workEnd = workEnd ?? weekend.end
            due = (weekend.end, text.contains("this weekend") ? "this weekend" : "over the weekend", true)
            vague = true
        }

        if due == nil, text.contains("next week") {
            let range = nextWeekRange(from: now, calendar: calendar)
            workStart = workStart ?? range.start
            workEnd = workEnd ?? range.end
            vague = true
        }

        if let dueDate = due?.date, workStart == nil, workEnd == nil {
            workStart = now
            workEnd = dueDate
        }

        return TemporalParse(
            dueDate: due?.date,
            dueLabel: due?.label,
            workingStartDate: workStart,
            workingEndDate: workEnd,
            isVague: vague || due?.rangeLike == true,
            hasTimeInformation: due != nil || workStart != nil || workEnd != nil
        )
    }

    static func resolve(in input: String, calendar: Calendar = .current, now: Date = .now) -> (date: Date, label: String, rangeLike: Bool)? {
        let text = input.lowercased()
        if let match = resolveBeforeAfter(in: text, calendar: calendar, now: now) {
            return match
        }
        // "in N days/weeks/months" — relative duration, checked before numeric-date scan
        // so "in 5 days" is NOT confused with the calendar-date pattern M.DD
        if let match = resolveRelativeDuration(in: text, calendar: calendar, now: now) {
            return match
        }
        if !containsWorkingPeriodSyntax(text), let baseDate = resolveDateFragment(text, calendar: calendar, now: now) {
            return (date(on: baseDate, matchingTimeIn: text, calendar: calendar, now: now), dateLabel(in: text) ?? "date", false)
        }
        if let match = resolveStandaloneDate(in: text, calendar: calendar, now: now) {
            return match
        }
        if let match = resolveByOrAt(in: text, calendar: calendar, now: now) {
            return match
        }
        if text.contains("tonight") {
            return (calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now, "tonight", false)
        }
        if text.contains("today") {
            return (date(on: now, matchingTimeIn: text, calendar: calendar, now: now), "today", false)
        }
        if text.contains("tomorrow"), let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            return (date(on: tomorrow, matchingTimeIn: text, calendar: calendar, now: now), "tomorrow", false)
        }
        if text.contains("this week") {
            return (upcomingFriday(from: now, calendar: calendar), "this week", false)
        }
        for (weekday, index) in weekdayIndexes where text.contains(weekday) {
            return (nextWeekday(index, from: now, calendar: calendar), weekday.capitalized, false)
        }
        // A bare clock time with no day word ("submit by 7", "at 5") implies
        // today; resolve it to the nearest reasonable future time.
        if let bare = bareClockTime(in: text) {
            return (inferAmbiguousTime(hour: bare.hour, minute: bare.minute, on: now, now: now, calendar: calendar), "today", false)
        }
        return nil
    }

    static func removingDatePhrases(from input: String) -> String {
        var title = input
        let phrases = [
            "by next week", "before next week", "after next week", "sometime next week", "next week",
            "during next week", "this week", "this weekend", "over the weekend", "no deadline yet", "no deadline",
            "whenever", "tonight", "today", "tomorrow", "morning", "afternoon", "evening", "night"
        ]
        for phrase in phrases {
            title = title.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive])
        }
        let dateToken = #"(?:next\s+)?(?:sunday|monday|tuesday|wednesday|thursday|friday|saturday)|\d{1,2}[./-]\d{1,2}|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|sept|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?"#
        title = title.replacingOccurrences(
            of: #"\bbetween\s+(\#(dateToken))\s+and\s+(\#(dateToken))\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: #"\bfrom\s+(\#(dateToken))\s+to\s+(\#(dateToken))\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: #"\bfrom\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+to\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: #"\bin\s+\d+\s+(?:days?|weeks?|months?)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: #"\b(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: #"\b(?:before|by|due|on|submit on|in|at)?\s*(?:\d{1,2}[./-]\d{1,2}|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|sept|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Colon clock times, with or without a lead-in: "before 3:45",
        // "at 3:45pm", or a bare "3:45". The dot/slash date forms above already
        // ran, so "5.15" is gone before we get here.
        title = title.replacingOccurrences(
            of: #"\b(?:before|by|due|at|after|around|til|till|until)?\s*\d{1,2}:\d{2}\s*(?:am|pm)?\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Hour-only times that REQUIRE an explicit lead-in, so plain numbers in
        // a title ("5 job applications", "Apply to 3 roles") are left intact:
        // "at 5", "before 3", "by 9pm".
        title = title.replacingOccurrences(
            of: #"\b(?:before|by|due|at|around|til|till|until)\s+\d{1,2}\s*(?:am|pm)?\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        for weekday in weekdayIndexes.map(\.0) {
            title = title.replacingOccurrences(of: "by \(weekday)", with: "", options: [.caseInsensitive])
            title = title.replacingOccurrences(of: "before \(weekday)", with: "", options: [.caseInsensitive])
            title = title.replacingOccurrences(of: "after \(weekday)", with: "", options: [.caseInsensitive])
            title = title.replacingOccurrences(of: "next \(weekday)", with: "", options: [.caseInsensitive])
            title = title.replacingOccurrences(of: weekday, with: "", options: [.caseInsensitive])
        }
        let cleaned = title.split(separator: " ").joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-")))
    }

    static func explicitlyHasNoDeadline(_ input: String) -> Bool {
        let text = input.lowercased()
        return text.contains("no deadline") || text.contains("whenever")
    }

    static func resolveStartDate(in input: String, calendar: Calendar = .current, now: Date = .now) -> Date? {
        let text = input.lowercased()
        if text.contains("now") {
            return now
        }
        if text.contains("after "),
           let baseDate = resolve(in: input, calendar: calendar, now: now)?.date {
            let start = calendar.startOfDay(for: baseDate)
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return resolve(in: input, calendar: calendar, now: now)
            .map { calendar.startOfDay(for: $0.date) }
    }

    static func resolveEndDate(in input: String, calendar: Calendar = .current, now: Date = .now) -> Date? {
        resolve(in: input, calendar: calendar, now: now)?.date
    }

    private static let weekdayIndexes = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7)
    ]

    static func containsWorkingPeriodSyntax(_ input: String) -> Bool {
        let text = input.lowercased()
        return text.contains("between ") || text.contains("from ") || text.contains("over the weekend") || text.contains("this weekend") || text.contains("during next week")
    }

    private static func resolveExplicitDeadline(in text: String, calendar: Calendar, now: Date) -> (Date, String, Bool)? {
        if let match = resolveBeforeAfter(in: text, calendar: calendar, now: now) {
            return match
        }
        if let match = resolveStandaloneDate(in: text, calendar: calendar, now: now) {
            return match
        }
        return nil
    }

    private static func resolveRelativeDuration(in text: String, calendar: Calendar, now: Date) -> (Date, String, Bool)? {
        let pattern = #"\bin\s+(\d+)\s+(days?|weeks?|months?)\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let numberRange = Range(match.range(at: 1), in: text),
            let unitRange = Range(match.range(at: 2), in: text),
            let n = Int(text[numberRange])
        else { return nil }

        let unit = String(text[unitRange]).lowercased()
        let component: Calendar.Component
        let label: String
        if unit.hasPrefix("day") {
            component = .day
            label = n == 1 ? "in 1 day" : "in \(n) days"
        } else if unit.hasPrefix("week") {
            component = .weekOfYear
            label = n == 1 ? "in 1 week" : "in \(n) weeks"
        } else {
            component = .month
            label = n == 1 ? "in 1 month" : "in \(n) months"
        }
        guard let date = calendar.date(byAdding: component, value: n, to: now) else { return nil }
        return (date, label, false)
    }

    private static func resolveBeforeAfter(in text: String, calendar: Calendar, now: Date) -> (Date, String, Bool)? {
        for prefix in ["before", "after", "by"] {
            guard let range = text.range(of: "\(prefix) ") else { continue }
            let fragment = String(text[range.upperBound...])
            if let baseDate = resolveDateFragment(fragment, calendar: calendar, now: now) {
                return (date(on: baseDate, matchingTimeIn: fragment, calendar: calendar, now: now), "\(prefix) \(dateLabel(in: fragment) ?? "date")", false)
            }
            if fragment.contains("next week") {
                return (nextMonday(after: now, calendar: calendar), "\(prefix) next week", prefix == "after")
            }
            for (weekday, index) in weekdayIndexes where fragment.contains(weekday) {
                let day = nextWeekday(index, from: now, calendar: calendar)
                return (date(on: day, matchingTimeIn: fragment, calendar: calendar, now: now), "\(prefix) \(weekday)", prefix == "after")
            }
            if fragment.contains("tomorrow"), let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return (date(on: tomorrow, matchingTimeIn: fragment, calendar: calendar, now: now), "\(prefix) tomorrow", prefix == "after")
            }
        }
        return nil
    }

    private static func resolveStandaloneDate(in text: String, calendar: Calendar, now: Date) -> (Date, String, Bool)? {
        let cues = ["due ", "by ", "before ", "submit on ", " on "]
        let hasCue = cues.contains(where: { text.contains($0) }) || text.hasPrefix("on ") || text.hasPrefix("due ")
        guard hasCue else { return nil }
        guard let baseDate = resolveDateFragment(text, calendar: calendar, now: now) else { return nil }
        return (date(on: baseDate, matchingTimeIn: text, calendar: calendar, now: now), dateLabel(in: text) ?? "date", false)
    }

    private static func resolveByOrAt(in text: String, calendar: Calendar, now: Date) -> (Date, String, Bool)? {
        for (weekday, index) in weekdayIndexes where text.contains("next \(weekday)") {
            let day = nextWeekday(index, from: now, calendar: calendar)
            return (date(on: day, matchingTimeIn: text, calendar: calendar, now: now), "next \(weekday)", false)
        }
        for (weekday, index) in weekdayIndexes where text.contains(weekday) {
            let day = nextWeekday(index, from: now, calendar: calendar)
            return (date(on: day, matchingTimeIn: text, calendar: calendar, now: now), weekday, false)
        }
        return nil
    }

    private static func resolveDateFragment(_ text: String, calendar: Calendar, now: Date) -> Date? {
        if let numeric = numericDate(in: text, calendar: calendar, now: now) {
            return numeric
        }
        if let named = namedMonthDate(in: text, calendar: calendar, now: now) {
            return named
        }
        return nil
    }

    private static func dateLabel(in text: String) -> String? {
        if let range = text.range(
            of: #"\b\d{1,2}[./-]\d{1,2}\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(text[range])
        }
        if let range = text.range(
            of: #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|sept|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(text[range])
        }
        return nil
    }

    private static func numericDate(in text: String, calendar: Calendar, now: Date) -> Date? {
        let pattern = #"\b(\d{1,2})[./-](\d{1,2})\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let monthRange = Range(match.range(at: 1), in: text),
            let dayRange = Range(match.range(at: 2), in: text),
            let month = Int(text[monthRange]),
            let day = Int(text[dayRange])
        else { return nil }
        return futureDate(month: month, day: day, calendar: calendar, now: now)
    }

    private static func namedMonthDate(in text: String, calendar: Calendar, now: Date) -> Date? {
        let pattern = #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|sept|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let monthRange = Range(match.range(at: 1), in: text),
            let dayRange = Range(match.range(at: 2), in: text),
            let month = monthNumber(String(text[monthRange])),
            let day = Int(text[dayRange])
        else { return nil }
        return futureDate(month: month, day: day, calendar: calendar, now: now)
    }

    private static func futureDate(month: Int, day: Int, calendar: Calendar, now: Date) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: now)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard var date = calendar.date(from: components) else { return nil }
        if calendar.startOfDay(for: date) < calendar.startOfDay(for: now) {
            components.year = year + 1
            guard let nextYearDate = calendar.date(from: components) else { return nil }
            date = nextYearDate
        }
        return date
    }

    private static func monthNumber(_ value: String) -> Int? {
        switch value.lowercased() {
        case "jan", "january": 1
        case "feb", "february": 2
        case "mar", "march": 3
        case "apr", "april": 4
        case "may": 5
        case "jun", "june": 6
        case "jul", "july": 7
        case "aug", "august": 8
        case "sep", "sept", "september": 9
        case "oct", "october": 10
        case "nov", "november": 11
        case "dec", "december": 12
        default: nil
        }
    }

    private static func resolveWorkingRange(in text: String, calendar: Calendar, now: Date) -> (start: Date, end: Date, vague: Bool)? {
        if text.contains("this weekend") || text.contains("over the weekend") {
            let weekend = upcomingWeekend(from: now, calendar: calendar)
            return (weekend.start, weekend.end, true)
        }
        if text.contains("during next week") {
            let range = nextWeekRange(from: now, calendar: calendar)
            return (range.start, range.end, true)
        }
        if let range = resolveNowToRange(in: text, calendar: calendar, now: now) {
            return range
        }
        if let range = resolveRangeExpression(in: text, startMarker: "between ", separator: " and ", calendar: calendar, now: now) {
            return range
        }
        if let range = resolveRangeExpression(in: text, startMarker: "from ", separator: " to ", calendar: calendar, now: now) {
            return range
        }
        return nil
    }

    private static func resolveNowToRange(in text: String, calendar: Calendar, now: Date) -> (start: Date, end: Date, vague: Bool)? {
        let markers = ["now to ", "now until ", "now through "]
        guard let marker = markers.first(where: { text.contains($0) }),
              let range = text.range(of: marker)
        else { return nil }

        let fragment = String(text[range.upperBound...])
        guard let end = resolveRangeEndpoint(in: fragment, isStart: false, calendar: calendar, now: now) else {
            return nil
        }
        return (now, max(now, end), false)
    }

    private static func resolveRangeExpression(in text: String, startMarker: String, separator: String, calendar: Calendar, now: Date) -> (start: Date, end: Date, vague: Bool)? {
        guard let markerRange = text.range(of: startMarker) else { return nil }
        let fragment = String(text[markerRange.upperBound...])
        guard let separatorRange = fragment.range(of: separator) else { return nil }
        let startFragment = String(fragment[..<separatorRange.lowerBound])
        let endFragment = String(fragment[separatorRange.upperBound...])
        guard
            let start = resolveRangeEndpoint(in: startFragment, isStart: true, calendar: calendar, now: now),
            let end = resolveRangeEndpoint(in: endFragment, isStart: false, calendar: calendar, now: now)
        else { return nil }
        return (start, max(start, end), false)
    }

    private static func resolveRangeEndpoint(in fragment: String, isStart: Bool, calendar: Calendar, now: Date) -> Date? {
        let text = fragment.lowercased()
        if text.contains("today") {
            return isStart ? calendar.startOfDay(for: now) : endOfDay(for: now, calendar: calendar)
        }
        if text.contains("tomorrow"), let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            return isStart ? calendar.startOfDay(for: tomorrow) : endOfDay(for: tomorrow, calendar: calendar)
        }
        if let baseDate = resolveDateFragment(text, calendar: calendar, now: now) {
            return isStart ? calendar.startOfDay(for: baseDate) : date(on: baseDate, matchingTimeIn: text, calendar: calendar, now: now)
        }
        for (weekday, index) in weekdayIndexes where text.contains("next \(weekday)") {
            let day = nextWeekday(index, from: now, calendar: calendar)
            return isStart ? calendar.startOfDay(for: day) : date(on: day, matchingTimeIn: text, calendar: calendar, now: now)
        }
        for (weekday, index) in weekdayIndexes where text.contains(weekday) {
            let day = upcomingWeekday(index, from: now, calendar: calendar)
            return isStart ? calendar.startOfDay(for: day) : date(on: day, matchingTimeIn: text, calendar: calendar, now: now)
        }
        return nil
    }

    private static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
    }

    private static func date(on day: Date, matchingTimeIn text: String, calendar: Calendar, now: Date = .now) -> Date {
        if let explicit = explicitTime(in: text) {
            return calendar.date(bySettingHour: explicit.hour, minute: explicit.minute, second: 0, of: day) ?? day
        }
        // Ambiguous bare clock time ("before 3:45", "at 5") with no AM/PM. Only
        // inferred for *today* — pick the nearest reasonable FUTURE occurrence
        // rather than defaulting to a passed morning time. Other days keep the
        // existing time-of-day handling below.
        if calendar.isDate(day, inSameDayAs: now), let bare = bareClockTime(in: text) {
            return inferAmbiguousTime(hour: bare.hour, minute: bare.minute, on: day, now: now, calendar: calendar)
        }
        if text.contains("morning") {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        if text.contains("afternoon") {
            return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
        }
        if text.contains("night") {
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day) ?? day
        }
        if text.contains("evening") {
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        }
        return endOfDay(for: day, calendar: calendar)
    }

    private static func explicitTime(in text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let hourRange = Range(match.range(at: 1), in: text),
            let meridiemRange = Range(match.range(at: 3), in: text)
        else { return nil }

        var hour = Int(text[hourRange]) ?? 0
        let minute: Int
        if
            match.range(at: 2).location != NSNotFound,
            let minuteRange = Range(match.range(at: 2), in: text)
        {
            minute = Int(text[minuteRange]) ?? 0
        } else {
            minute = 0
        }

        let meridiem = text[meridiemRange].lowercased()
        if meridiem == "pm", hour < 12 {
            hour += 12
        } else if meridiem == "am", hour == 12 {
            hour = 0
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    // MARK: - Ambiguous (no AM/PM) clock times

    /// Extracts a bare clock time that carries NO meridiem — either an explicit
    /// `HH:MM` ("3:45", "15:45") or a lead-in hour ("at 5", "by 7", "before 3").
    /// Plain numbers without a clock lead-in ("5 job applications", "Apply to 3
    /// roles") are deliberately NOT matched. Returns nil when an AM/PM time is
    /// present (that's `explicitTime`'s job).
    private static func bareClockTime(in text: String) -> (hour: Int, minute: Int)? {
        guard explicitTime(in: text) == nil else { return nil }

        if let g = regexGroups(#"\b(\d{1,2}):(\d{2})\b"#, in: text),
           let hour = Int(g[0]), let minute = Int(g[1]),
           (0...23).contains(hour), (0...59).contains(minute) {
            return (hour, minute)
        }
        // Lead-in hour, not followed by ":" or another digit (so we don't grab
        // the "5" of "5:45" or part of a longer number).
        if let g = regexGroups(#"\b(?:before|by|due|at|around|til|till|until)\s+(\d{1,2})(?![:\d])"#, in: text),
           let hour = Int(g[0]), (0...23).contains(hour) {
            return (hour, 0)
        }
        return nil
    }

    /// Resolves an ambiguous clock reading to the most likely time on `day`,
    /// preferring the next FUTURE occurrence relative to `now`:
    ///   - A 24-hour reading (>= 13) or midnight (0) is used as-is.
    ///   - For 1–12, try the AM reading first, then PM; pick the earliest that
    ///     is still ahead of `now`. If both have passed, prefer PM (the caller
    ///     flags the resulting past-due item for review).
    private static func inferAmbiguousTime(hour: Int, minute: Int, on day: Date, now: Date, calendar: Calendar) -> Date {
        if hour == 0 || hour >= 13 {
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let amHour = (hour == 12) ? 0 : hour
        let pmHour = (hour == 12) ? 12 : hour + 12
        let amDate = calendar.date(bySettingHour: amHour, minute: minute, second: 0, of: day) ?? day
        let pmDate = calendar.date(bySettingHour: pmHour, minute: minute, second: 0, of: day) ?? day
        if amDate > now { return amDate }
        if pmDate > now { return pmDate }
        return pmDate
    }

    /// True when the input names an ambiguous (no AM/PM) clock time for *today*
    /// whose AM and PM readings have BOTH already passed — an impossible same-day
    /// deadline. Callers route these to review instead of creating a past-due
    /// task silently.
    static func ambiguousClockTimeAlreadyPassed(in input: String, calendar: Calendar = .current, now: Date = .now) -> Bool {
        let text = input.lowercased()
        guard explicitTime(in: text) == nil, let bare = bareClockTime(in: text) else { return false }
        guard !mentionsNonTodayDate(text, now: now, calendar: calendar) else { return false }

        if bare.hour == 0 || bare.hour >= 13 {
            let exact = calendar.date(bySettingHour: bare.hour, minute: bare.minute, second: 0, of: now) ?? now
            return exact < now
        }
        let amHour = (bare.hour == 12) ? 0 : bare.hour
        let pmHour = (bare.hour == 12) ? 12 : bare.hour + 12
        guard
            let amDate = calendar.date(bySettingHour: amHour, minute: bare.minute, second: 0, of: now),
            let pmDate = calendar.date(bySettingHour: pmHour, minute: bare.minute, second: 0, of: now)
        else { return false }
        return amDate < now && pmDate < now
    }

    /// Whether the text references a day other than today (so an ambiguous clock
    /// time should not be treated as a same-day deadline).
    private static func mentionsNonTodayDate(_ text: String, now: Date, calendar: Calendar) -> Bool {
        if text.contains("tomorrow") || text.contains("next week") || text.contains("tonight") { return true }
        if weekdayIndexes.contains(where: { text.contains($0.0) }) { return true }
        if resolveDateFragment(text, calendar: calendar, now: now) != nil { return true }
        return false
    }

    /// Returns the capture groups (1…n) of the first match, or nil if no match.
    private static func regexGroups(_ pattern: String, in text: String) -> [String]? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1
        else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let r = Range(match.range(at: i), in: text) else { return nil }
            groups.append(String(text[r]))
        }
        return groups
    }

    private static func nextWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: now)
        let days = (weekday - current + 7) % 7
        let offset = days == 0 ? 7 : days
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return endOfDay(for: date, calendar: calendar)
    }

    private static func upcomingWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: now)
        let offset = (weekday - current + 7) % 7
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return endOfDay(for: date, calendar: calendar)
    }

    private static func nextMonday(after now: Date, calendar: Calendar) -> Date {
        nextWeekday(2, from: now, calendar: calendar)
    }

    private static func upcomingFriday(from now: Date, calendar: Calendar) -> Date {
        nextWeekday(6, from: now, calendar: calendar)
    }

    private static func upcomingWeekend(from now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let saturday = calendar.startOfDay(for: nextWeekday(7, from: now, calendar: calendar))
        let sundayBase = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
        return (saturday, endOfDay(for: sundayBase, calendar: calendar))
    }

    private static func nextWeekRange(from now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let monday = calendar.startOfDay(for: nextMonday(after: now, calendar: calendar))
        let sundayBase = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        return (monday, endOfDay(for: sundayBase, calendar: calendar))
    }
}
