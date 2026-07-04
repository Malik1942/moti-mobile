import Foundation

// Horizon Timeline v2 — T2. Bucket assignment (PRD §6.2). Pure, Foundation-only.
// Output is DATA ONLY (enum + payload) — zero strings, zero formatting. The row
// layer (Workstream 3) turns these into copy; the domain never phrases anything.

/// The minimal, type-resolved view of a strand that bucket assignment needs.
///
/// Built from a `Strand` at the adapter boundary (Workstream-1 → app seam). The
/// trajectory *engine* types (`TrajectoryProjection`, `TrajectoryOutcome`) never
/// cross into the domain — that is the Phase-2 seam: divergence swaps in behind
/// `QuietnessProvider` and the row second-line, and neither bucketing nor
/// folding ever learns which provider is live.
struct HorizonItem: Equatable {
    enum Kind: Equatable {
        /// Achievement: a landing. `due == nil` means no deadline set.
        case achievement(due: Date?)
        /// Maintenance: a rhythm. `typicalGap == nil` (or no `lastFed`) means the
        /// cadence is not derivable (PRD §11) → no feed-by placement.
        case maintenance(lastFed: Date?, typicalGap: TimeInterval?)
    }

    /// Stable strand identity (the `Strand.id`).
    let id: String
    let kind: Kind
}

/// Raw runway data for an achievement row (PRD §6.3). No strings.
struct CountdownPayload: Equatable {
    /// Whole calendar days from the start of today to the due date's day.
    /// `0` = due today, `>0` = ahead, `<0` = overdue (see `overdueDays`).
    let daysRemaining: Int
    let dueDate: Date
    /// **Phase 2 seam.** The engine's "time actually required at current pace" —
    /// the second duration ("needs Xd") that lands on the row's second line.
    /// **Always `nil` in Phase 1.**
    let requiredDuration: TimeInterval?

    init(daysRemaining: Int, dueDate: Date, requiredDuration: TimeInterval? = nil) {
        self.daysRemaining = daysRemaining
        self.dueDate = dueDate
        self.requiredDuration = requiredDuration
    }
}

/// Raw rhythm data for a maintenance row (PRD §6.3). No strings.
struct MaintenanceRhythm: Equatable {
    let lastFed: Date
    /// The derived typical gap (seconds) — from `HorizonRhythm.typicalGap` or a
    /// declared cadence.
    let typicalGap: TimeInterval
    /// `lastFed + typicalGap`.
    let nextFeedBy: Date
    /// Whole calendar days since the last feed (clamped at 0).
    let daysSinceLastFed: Int
    /// Whole calendar days from today to the feed-by day (`<0` when overdue).
    let daysUntilFeedBy: Int
    /// Rhythm baseline is "approaching": elapsed >= 0.8 × typicalGap (PRD §6.3).
    /// Always true once overdue.
    let isApproaching: Bool
}

/// Where a strand lands and the raw data its row needs. One case per PRD §6.2
/// rule. The `bucket`/`isPinnedToTodayTop` derivations keep the placement
/// self-describing so callers never re-encode the policy.
enum BucketPlacement: Equatable {
    /// Achievement due today or later → the due date's bucket.
    case dueIn(bucket: TimeBucket, countdown: CountdownPayload)
    /// Achievement whose due day is already past → pinned to the top of Today
    /// with the elapsed overdue days (PRD §6.2: does not migrate to Past until
    /// completed/abandoned).
    case overdue(overdueDays: Int, countdown: CountdownPayload)
    /// Achievement with no due date → Later, countdown suppressed (PRD §6.2).
    case achievementNoDueDate
    /// Maintenance whose next feed-by is today or later → that bucket.
    case feedBy(bucket: TimeBucket, rhythm: MaintenanceRhythm)
    /// Maintenance past its feed-by → pinned to the top of Today with elapsed
    /// rhythm data ("14d since last · usually 7d").
    case feedOverdue(rhythm: MaintenanceRhythm)
    /// Maintenance with no derivable cadence → Later, no feed-by copy (PRD §11).
    case maintenanceNoRhythm

    /// The bucket this placement renders in.
    var bucket: TimeBucket {
        switch self {
        case let .dueIn(bucket, _): return bucket
        case let .feedBy(bucket, _): return bucket
        case .overdue, .feedOverdue: return .today
        case .achievementNoDueDate, .maintenanceNoRhythm: return .later
        }
    }

    /// True when this placement pins to the top of Today (the overdue signals).
    var isPinnedToTodayTop: Bool {
        switch self {
        case .overdue, .feedOverdue: return true
        default: return false
        }
    }
}

enum BucketAssigner {

    /// Assign a strand to its bucket with the raw data its row needs (PRD §6.2).
    ///
    /// `windows` come from `HorizonBuckets.windows(now:calendar:)` (T1); `now`
    /// and `calendar` drive the countdown/overdue math. Position encodes *intent*
    /// (due/feed-by date); divergence is annotation, never relocation.
    static func assign(_ item: HorizonItem,
                       windows: [BucketWindow],
                       now: Date,
                       calendar: Calendar = .current) -> BucketPlacement {
        switch item.kind {
        case let .achievement(due):
            return assignAchievement(due: due, windows: windows, now: now, calendar: calendar)
        case let .maintenance(lastFed, typicalGap):
            return assignMaintenance(lastFed: lastFed, typicalGap: typicalGap,
                                     windows: windows, now: now, calendar: calendar)
        }
    }

    // MARK: - Achievement

    private static func assignAchievement(due: Date?,
                                          windows: [BucketWindow],
                                          now: Date,
                                          calendar cal: Calendar) -> BucketPlacement {
        guard let due else { return .achievementNoDueDate }

        let daysRemaining = calendarDayDelta(from: now, to: due, cal)
        let countdown = CountdownPayload(daysRemaining: daysRemaining, dueDate: due)

        if cal.startOfDay(for: due) < cal.startOfDay(for: now) {
            // Overdue = the due *day* is strictly before today (a same-day-past
            // deadline still reads as "due today", 0d left, in the Today bucket).
            return .overdue(overdueDays: -daysRemaining, countdown: countdown)
        }
        let bucket = HorizonBuckets.bucket(for: due, in: windows) ?? .later
        return .dueIn(bucket: bucket, countdown: countdown)
    }

    // MARK: - Maintenance

    private static func assignMaintenance(lastFed: Date?,
                                          typicalGap: TimeInterval?,
                                          windows: [BucketWindow],
                                          now: Date,
                                          calendar cal: Calendar) -> BucketPlacement {
        guard let lastFed, let typicalGap, typicalGap > 0 else { return .maintenanceNoRhythm }

        let nextFeedBy = lastFed.addingTimeInterval(typicalGap)
        let elapsed = now.timeIntervalSince(lastFed)
        let rhythm = MaintenanceRhythm(
            lastFed: lastFed,
            typicalGap: typicalGap,
            nextFeedBy: nextFeedBy,
            daysSinceLastFed: max(0, calendarDayDelta(from: lastFed, to: now, cal)),
            daysUntilFeedBy: calendarDayDelta(from: now, to: nextFeedBy, cal),
            isApproaching: elapsed >= 0.8 * typicalGap
        )

        if now > nextFeedBy {
            return .feedOverdue(rhythm: rhythm)
        }
        let bucket = HorizonBuckets.bucket(for: nextFeedBy, in: windows) ?? .later
        return .feedBy(bucket: bucket, rhythm: rhythm)
    }

    // MARK: - Day math

    /// Whole calendar days between two instants' *days* (midnight-to-midnight),
    /// so "due in N days" counts day boundaries crossed, not 24h blocks — this is
    /// what makes the countdown agree with the calendar-aligned buckets.
    private static func calendarDayDelta(from a: Date, to b: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }
}
