import Foundation

/// Coarse cadence for a recurring `WorkItem`. Deliberately small for v1 — just
/// the buckets Smart Capture's lightweight path can detect deterministically.
/// `custom` is the only open-ended case and is kept lightweight: "every N days".
enum RecurrenceFrequency: String, Codable, CaseIterable {
    case none
    case daily
    case weekdays   // Monday–Friday
    case weekly     // every week (optionally pinned to a weekday)
    case monthly
    case custom     // every N days (interval carries N)
}

/// A first-class, structured recurrence rule stored on a `WorkItem`. Value type
/// so it round-trips cleanly through SwiftData's flat columns and is trivial to
/// unit-test. There is intentionally no exception/skip handling yet.
struct RecurrenceRule: Equatable, Codable {
    var frequency: RecurrenceFrequency
    /// Every N units. 1 for simple cadences; >1 only for `.custom` ("every 2
    /// days") or interval weekly/monthly.
    var interval: Int
    /// 1 = Sunday … 7 = Saturday. Set only for `.weekly` pinned to a specific
    /// day (e.g. "every Friday").
    var weekday: Int?

    static let none = RecurrenceRule(frequency: .none, interval: 1, weekday: nil)

    init(frequency: RecurrenceFrequency, interval: Int = 1, weekday: Int? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekday = weekday
    }

    var isRecurring: Bool { frequency != .none }

    /// Short, human-readable cadence label for badges and detail rows.
    var displayLabel: String {
        switch frequency {
        case .none:
            return ""
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekly:
            if let weekday, let name = Self.weekdayName(weekday) {
                return "Every \(name)"
            }
            return interval > 1 ? "Every \(interval) weeks" : "Weekly"
        case .monthly:
            return interval > 1 ? "Every \(interval) months" : "Monthly"
        case .custom:
            return interval > 1 ? "Every \(interval) days" : "Daily"
        }
    }

    /// The next occurrence strictly after `reference`. Used to give a recurring
    /// item a concrete next due date so it appears once on the Timeline — never
    /// expanded into infinite instances.
    func nextOccurrence(after reference: Date, calendar: Calendar = .current) -> Date? {
        guard isRecurring else { return nil }
        let startOfRef = calendar.startOfDay(for: reference)
        switch frequency {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: startOfRef)
        case .custom:
            return calendar.date(byAdding: .day, value: max(1, interval), to: startOfRef)
        case .weekly:
            if let weekday {
                return calendar.nextDate(
                    after: reference,
                    matching: DateComponents(weekday: weekday),
                    matchingPolicy: .nextTimePreservingSmallerComponents
                ).map { calendar.startOfDay(for: $0) }
            }
            return calendar.date(byAdding: .day, value: 7 * max(1, interval), to: startOfRef)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: startOfRef) ?? startOfRef
            // Skip Saturday (7) and Sunday (1).
            while [1, 7].contains(calendar.component(.weekday, from: candidate)) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        case .monthly:
            return calendar.date(byAdding: .month, value: max(1, interval), to: startOfRef)
        }
    }

    /// Full weekday name for a 1=Sunday…7=Saturday index, locale-independent
    /// enough for our labels (uses the Gregorian symbols).
    static func weekdayName(_ weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        // Pin a fixed English locale so the label is deterministic ("Friday",
        // not a locale-abbreviated form) regardless of device region — matching
        // the hard-coded English "Every …" prefix it is composed with.
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.weekdaySymbols[weekday - 1]
    }
}
