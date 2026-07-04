import Foundation

// Horizon Timeline v2 — the surface's voice (PRD §7.3). Pure String factory so
// the wording is unit-testable in isolation. All copy is DESCRIPTIVE, never
// evaluative. Banned on this surface: behind, late, failing, overdue (as an
// adjective), streak. The domain layer produced only data; formatting lives here.

enum HorizonCopy {

    // MARK: - Achievement countdown (trailing)

    /// Runway for an on-track achievement: "4d left", or "today" when it lands
    /// today (the row already sits in Today, so we don't repeat the number).
    static func daysLeft(_ daysRemaining: Int) -> String {
        daysRemaining <= 0 ? "today" : "\(daysRemaining)d left"
    }

    /// Elapsed time past an achievement's due date: "2d over" (statement, not blame).
    static func daysOver(_ overdueDays: Int) -> String {
        "\(max(1, overdueDays))d over"
    }

    // MARK: - Maintenance feed-by (trailing) + rhythm (second line)

    /// When the next feed is due, phrased relatively: "feed by today",
    /// "feed by tomorrow", "feed by Sun" (this week), or "feed by Jul 3".
    static func feedBy(_ nextFeedBy: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: nextFeedBy)).day ?? 0
        switch days {
        case ..<0, 0: return "feed by today"
        case 1: return "feed by tomorrow"
        case 2...6:
            let idx = calendar.component(.weekday, from: nextFeedBy) - 1
            let symbols = calendar.shortWeekdaySymbols
            let name = symbols.indices.contains(idx) ? symbols[idx] : ""
            return "feed by \(name)"
        default:
            let f = DateFormatter()
            f.calendar = calendar
            f.locale = calendar.locale ?? .current
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return "feed by \(f.string(from: nextFeedBy))"
        }
    }

    /// Rhythm baseline for a maintenance row (PRD §6.3):
    /// "last fed 5d ago · usually every 7d".
    static func rhythm(daysSinceLastFed: Int, typicalGap: TimeInterval) -> String {
        "last fed \(max(0, daysSinceLastFed))d ago · usually every \(gapDays(typicalGap))d"
    }

    /// Trailing for a maintenance strand past its feed-by: "9d since last".
    static func daysSinceLast(_ daysSinceLastFed: Int) -> String {
        "\(max(0, daysSinceLastFed))d since last"
    }

    /// Second line for a past-feed-by maintenance strand: "usually every 7d"
    /// (the honest, non-judgmental rhythm baseline — PRD §11 open question).
    static func usualRhythm(typicalGap: TimeInterval) -> String {
        "usually every \(gapDays(typicalGap))d"
    }

    // MARK: - Folds

    /// The near-bucket on-course fold (PRD §6.4): "3 more on course".
    static func onCourse(_ count: Int) -> String {
        "\(count) more on course"
    }

    /// The far-bucket collapsed count row: "5 futures" / "1 future" (Moti voice).
    static func collapsedCount(_ count: Int) -> String {
        "\(count) future\(count == 1 ? "" : "s")"
    }

    // MARK: - Bucket headers (PRD §6.1)

    static func bucketTitle(_ bucket: TimeBucket) -> String {
        switch bucket {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .restOfThisWeek: return "Rest of this week"
        case .nextWeek: return "Next week"
        case .restOfThisMonth: return "Rest of this month"
        case .later: return "Later"
        }
    }

    /// Empty-Today voice moment (PRD §7.3).
    static let nothingToday = "Nothing needs you today."

    // MARK: - Past region (PRD §6.5)

    /// Per-strand origin line: "began Mar 2 · 118 days".
    static func origin(began: Date, until: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale ?? .current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let days = max(0, calendar.dateComponents([.day],
                                                  from: calendar.startOfDay(for: began),
                                                  to: calendar.startOfDay(for: until)).day ?? 0)
        return "began \(f.string(from: began)) · \(days) day\(days == 1 ? "" : "s")"
    }

    /// Past region header: "Arrived in 2026 · 3 futures" (quiet record, not archive).
    static func pastHeader(year: Int, count: Int) -> String {
        "Arrived in \(year) · \(count) future\(count == 1 ? "" : "s")"
    }

    // MARK: - Helpers

    /// Whole days for a gap interval, rounded, floored at 1.
    static func gapDays(_ interval: TimeInterval) -> Int {
        max(1, Int((interval / 86_400).rounded()))
    }
}
