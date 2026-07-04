import Foundation

// Horizon Timeline v2 — Workstream 1 (Domain). Pure, Foundation-only, no UI.
// Time is encoded by *membership* (which bucket a strand sits in), not by spatial
// position (PRD §2). This file computes the bucket windows; assignment lives in
// BucketPlacement.swift.

/// The forward temporal buckets, top-to-bottom in render order (PRD §6.1).
///
/// Granularity is intentionally **log-time**: fine near Now, coarse far away.
/// The `Past` region (completed futures + origins) is a *separate* section kind
/// (T10), reconstructed from completions — no active strand is ever assigned to
/// it — so it is deliberately not a case here.
enum TimeBucket: String, CaseIterable, Equatable {
    /// Current calendar day. Always rendered, even when empty (PRD §6.1).
    case today
    /// Next calendar day.
    case tomorrow
    /// From the day after tomorrow through the end of the current week.
    case restOfThisWeek
    /// The whole of the following week.
    case nextWeek
    /// From the end of next week through the end of the current calendar month.
    case restOfThisMonth
    /// Everything beyond the current month.
    case later

    /// Distance from Now: `today` = 0 (nearest) … `later` = 5 (farthest). A
    /// smaller ordinal is nearer — used to detect strands that migrated toward
    /// Now between snapshots (T15).
    var ordinal: Int { TimeBucket.allCases.firstIndex(of: self) ?? 0 }
}

/// A half-open date window `[start, end)` owned by exactly one bucket.
///
/// Half-open so adjacent windows tile the timeline with no gaps and no overlaps:
/// a date belongs to the window where `start <= date < end`. An *empty* window
/// (`start == end`) owns nothing — that is how "Rest of this week" collapses to
/// nothing when today is the last day of the week.
struct BucketWindow: Equatable {
    let bucket: TimeBucket
    let start: Date
    /// Exclusive upper bound. `.later` uses `Date.distantFuture`.
    let end: Date

    /// A window that owns no instant (its bucket is empty this cycle).
    var isEmpty: Bool { start >= end }

    /// Half-open membership test: `start <= date < end`.
    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

enum HorizonBuckets {

    /// Calendar-aligned, half-open bucket windows anchored at `now` (PRD §6.1).
    ///
    /// Boundaries are **calendar-aligned**, not rolling windows — the
    /// Sunday-midnight bucket migration is a feature (Monday's open shows "what
    /// entered range this week"). The week boundary follows
    /// `calendar.firstWeekday`, so device locale decides where the week turns
    /// over. The PRD's "through Sunday" phrasing assumes a US (Sunday-first)
    /// locale; we respect the device's locale instead of hardcoding Sunday.
    ///
    /// The six windows are contiguous and monotonic: each starts exactly where
    /// the previous ended, beginning at the start of today and ending at
    /// `.distantFuture`. When a "natural" boundary would fall *before* the
    /// running boundary (e.g. tomorrow already spills into next week, or next
    /// week straddles the month end), the affected window collapses to empty and
    /// the nearer bucket keeps the days — nearer buckets always win.
    static func windows(now: Date, calendar: Calendar = .current) -> [BucketWindow] {
        let startOfToday = calendar.startOfDay(for: now)

        // Day boundaries via calendar arithmetic (DST-safe: adding a `.day`
        // component lands on the next wall-clock midnight, not now+86_400s).
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? startOfTomorrow

        // Week boundaries honour `calendar.firstWeekday`.
        let startOfNextWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? startOfDayAfterTomorrow
        let startOfWeekAfterNext = calendar.dateInterval(of: .weekOfYear, for: startOfNextWeek)?.end ?? startOfNextWeek

        // Month boundary.
        let startOfNextMonth = calendar.dateInterval(of: .month, for: now)?.end ?? startOfWeekAfterNext

        // The ordered "natural" end of each bucket, before monotonic clamping.
        let naturalEnds: [(TimeBucket, Date)] = [
            (.today, startOfTomorrow),
            (.tomorrow, startOfDayAfterTomorrow),
            (.restOfThisWeek, startOfNextWeek),
            (.nextWeek, startOfWeekAfterNext),
            (.restOfThisMonth, startOfNextMonth),
            (.later, .distantFuture),
        ]

        var boundary = startOfToday
        return naturalEnds.map { bucket, naturalEnd in
            let end = max(boundary, naturalEnd) // clamp: never run backwards
            let window = BucketWindow(bucket: bucket, start: boundary, end: end)
            boundary = end
            return window
        }
    }

    /// The bucket a forward-facing `date` falls into, or `nil` if it is before
    /// the start of today (i.e. in the Past region, handled separately).
    ///
    /// Overdue placement (a past deadline pinned into Today) is **not** derived
    /// here — bucket assignment owns that policy (see `BucketPlacement`).
    static func bucket(for date: Date, in windows: [BucketWindow]) -> TimeBucket? {
        windows.first { $0.contains(date) }?.bucket
    }
}
