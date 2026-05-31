import Foundation

/// Deterministic recurrence detection. Maps a raw capture string to a
/// structured `RecurrenceRule` so a recurring habit becomes a first-class
/// `WorkItem` field — not text buried in the title or notes, and not something
/// only the LLM "knows".
///
/// Conservative by design: a cadence is only inferred from explicit markers
/// ("every", "each", "daily", "weekdays", "on Fridays"). A bare weekday like
/// "submit report Friday" is a one-off deadline, NOT a weekly recurrence, so it
/// returns `.none`. Under-detection is the safe direction — a missed cadence is
/// just a normal task; a false positive would silently make a task repeat.
enum RecurrenceParser {

    static func parse(_ rawText: String) -> RecurrenceRule {
        let lower = rawText.lowercased()

        // 1. Weekdays (Mon–Fri). Checked before single-weekday so "every
        //    weekday" / "on weekdays" doesn't read as a specific day.
        if lower.contains("weekday")
            || lower.contains("week days")
            || lower.contains("monday to friday")
            || lower.contains("monday through friday")
            || lower.contains("mon-fri")
            || lower.contains("mon to fri") {
            return RecurrenceRule(frequency: .weekdays)
        }

        // 2. A specific weekday → weekly pinned to that day ("every Friday").
        if let weekday = weeklyWeekday(in: lower) {
            return RecurrenceRule(frequency: .weekly, weekday: weekday)
        }

        // 3. Custom interval in days ("every other day", "every 3 days").
        if lower.contains("every other day") {
            return RecurrenceRule(frequency: .custom, interval: 2)
        }
        if let n = everyNDays(in: lower) {
            return RecurrenceRule(frequency: .custom, interval: n)
        }

        // 4. Daily — includes time-of-day habits ("every night", "each morning").
        let dailyMarkers = [
            "every day", "everyday", "each day", "daily",
            "every morning", "each morning", "every evening", "each evening",
            "every night", "each night", "nightly"
        ]
        if dailyMarkers.contains(where: { lower.contains($0) }) {
            return RecurrenceRule(frequency: .daily)
        }

        // 5. Weekly (generic, no specific day).
        if lower.contains("every week") || lower.contains("each week") || lower.contains("weekly") {
            return RecurrenceRule(frequency: .weekly)
        }

        // 6. Monthly.
        if lower.contains("every month") || lower.contains("each month") || lower.contains("monthly") {
            return RecurrenceRule(frequency: .monthly)
        }

        return .none
    }

    // MARK: - Helpers

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`'s weekday numbering.
    private static let dayMap: [(name: String, weekday: Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7)
    ]

    /// Detects a recurring single weekday. Requires an explicit recurrence
    /// trigger ("every"/"each" + day, or the plural "on Fridays") so one-off
    /// deadlines like "ship it Friday" are not treated as recurring.
    private static func weeklyWeekday(in lower: String) -> Int? {
        for (name, weekday) in dayMap {
            if lower.contains("every \(name)")
                || lower.contains("each \(name)")
                || lower.contains("on \(name)s")
                || lower.contains("\(name)s ") && lower.contains("every") {
                return weekday
            }
        }
        return nil
    }

    /// Extracts N from "every N days". Returns nil when absent.
    private static func everyNDays(in lower: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"every\s+(\d+)\s+days?"#) else {
            return nil
        }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              match.numberOfRanges >= 2,
              let numRange = Range(match.range(at: 1), in: lower),
              let n = Int(lower[numRange]), n >= 1
        else { return nil }
        return n
    }
}
