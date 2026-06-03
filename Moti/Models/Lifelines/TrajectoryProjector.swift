import Foundation

// MARK: - Trajectory outcome (the forward read — the hero)

/// Where a future's *current pace* lands it, read from the dashed projection
/// against its goal/deadline marker (PRD §5.2). Two outcomes per type:
/// achievement futures resolve On-time / Behind; maintenance futures resolve
/// Sustained / Fading. This is **directional only** in v1 — never a day-count
/// (precise slippage is gated to v2, §9.6).
enum TrajectoryOutcome: String, Equatable, CaseIterable {
    case onTime     // achievement: projection reaches completion at/before the deadline
    case behind     // achievement: projection completes past the deadline
    case sustained  // maintenance: projection continues at a steady rhythm
    case fading     // maintenance: projection thins and fades to nothing

    /// True when the outcome is the one that should raise its voice (§6.1 calm
    /// by default — only the slipping / fading future draws the eye).
    var needsAttention: Bool { self == .behind || self == .fading }
}

// MARK: - Projection result

/// The computed forward trajectory. Carries the directional outcome plus the
/// few quantities the view needs to *draw* the path — every visual property maps
/// to a computed quantity (§14), and none of these are rendered as numbers.
struct TrajectoryProjection: Equatable {
    let outcome: TrajectoryOutcome

    /// Achievement only: does this future have a deadline marker to land against?
    let hasGoal: Bool

    /// Achievement: completed actions / total actions, `0...1`. Drives the solid
    /// extent and the Peek's milestone-health texture. `nil` for maintenance.
    let progressFraction: Double?

    /// Achievement: progress-so-far vs. time-elapsed toward the deadline.
    /// `≥1` ⇒ keeping pace (on-time); `<1` ⇒ behind. Directional input to the
    /// outcome — **never displayed as a number**. `nil` for maintenance.
    let paceRatio: Double?

    /// Maintenance: recent feeding rate vs. the strand's own cadence, `0...~1+`.
    /// Higher ⇒ sustained; near-zero ⇒ fading. `nil` for achievement.
    let feedingRatio: Double?

    /// How far the path stays **solid** (certain) before becoming dashed/fading,
    /// `0...1` of the near-future band. Driven by recent-signal strength — a
    /// strongly-fed future is certain further out (§5 solid-vs-dashed).
    let solidFraction: Double
}

extension TrajectoryProjection {
    /// Terse directional value for previews and tests (no progress detail).
    static func directional(_ outcome: TrajectoryOutcome, solidFraction: Double = 0.35) -> TrajectoryProjection {
        TrajectoryProjection(
            outcome: outcome,
            hasGoal: outcome == .onTime || outcome == .behind,
            progressFraction: nil, paceRatio: nil, feedingRatio: nil,
            solidFraction: solidFraction
        )
    }
}

// MARK: - Policy

struct TrajectoryPolicy: Equatable {
    /// Achievement: pace at/above this reads on-time.
    var onTimePaceThreshold: Double
    /// Maintenance: presence reach at/above this reads sustained.
    var sustainedReachThreshold: Double
    var minSolidFraction: Double
    var maxSolidFraction: Double

    static let `default` = TrajectoryPolicy(
        onTimePaceThreshold: 1.0,
        sustainedReachThreshold: 0.4,
        minSolidFraction: 0.12,
        maxSolidFraction: 0.55
    )
}

// MARK: - Projector (pure)

/// Pure, deterministic forward projection. It **extrapolates actual behavior** —
/// completed events and feeding rate — and never assumes scheduled work will
/// happen (that assumption is the calendar's, the thing Moti exists to avoid;
/// §14). Presence/drift is an *input* here, not the organizing principle.
///
/// Genuinely new compute, not a rename of the presence computer: the presence
/// computer answers "is this still reaching Now?"; this answers "where does the
/// current pace land it?".
enum TrajectoryProjector {

    static func project(
        events: [StrandEvent],
        type: StrandType,
        presence: StrandPresence,
        deadline: Date?,
        completedCount: Int,
        totalCount: Int,
        recurrenceCadenceDays: Double? = nil,
        firstActivity: Date? = nil,
        now: Date,
        calendar: Calendar = .current,
        policy: TrajectoryPolicy = .default
    ) -> TrajectoryProjection {
        let solid = solidFraction(for: presence, policy: policy)
        let hasSignal = !events.contains { $0.date <= now } ? false : true

        // Achievement with a real deadline → land against the marker.
        if type == .achievement, let deadline {
            return achievementProjection(
                deadline: deadline, completedCount: completedCount, totalCount: totalCount,
                firstActivity: firstActivity ?? events.map(\.date).min(),
                hasSignal: hasSignal, solid: solid, now: now, policy: policy
            )
        }

        // Maintenance (or an achievement with no deadline to land against) →
        // sustained vs. fading from the feeding rate, with drift as the input.
        return maintenanceProjection(presence: presence, solid: solid, policy: policy)
    }

    // MARK: Achievement

    private static func achievementProjection(
        deadline: Date, completedCount: Int, totalCount: Int,
        firstActivity: Date?, hasSignal: Bool, solid: Double, now: Date,
        policy: TrajectoryPolicy
    ) -> TrajectoryProjection {
        let progress = totalCount > 0 ? min(1.0, Double(completedCount) / Double(totalCount)) : 0

        // Already complete → on-time regardless of clock.
        if totalCount > 0 && progress >= 1.0 {
            return .init(outcome: .onTime, hasGoal: true, progressFraction: 1,
                         paceRatio: .infinity, feedingRatio: nil, solidFraction: solid)
        }

        // No behavior yet → don't fabricate "behind"; read calm/on-time (§10).
        guard hasSignal, let start = firstActivity, start < deadline else {
            return .init(outcome: .onTime, hasGoal: true, progressFraction: progress,
                         paceRatio: nil, feedingRatio: nil, solidFraction: solid)
        }

        // Deadline already passed and not complete → behind.
        if now >= deadline {
            return .init(outcome: .behind, hasGoal: true, progressFraction: progress,
                         paceRatio: 0, feedingRatio: nil, solidFraction: solid)
        }

        let timeElapsed = (now.timeIntervalSince(start)) / (deadline.timeIntervalSince(start))
        let clampedElapsed = min(max(timeElapsed, 0.0001), 1.0)
        let pace = progress / clampedElapsed
        let outcome: TrajectoryOutcome = pace >= policy.onTimePaceThreshold ? .onTime : .behind

        return .init(outcome: outcome, hasGoal: true, progressFraction: progress,
                     paceRatio: pace, feedingRatio: nil, solidFraction: solid)
    }

    // MARK: Maintenance

    private static func maintenanceProjection(
        presence: StrandPresence, solid: Double, policy: TrajectoryPolicy
    ) -> TrajectoryProjection {
        // Drift is the input to the forecast: a drifted rhythm fades; a fed one
        // is sustained. Quiet is the borderline, decided by how close to its own
        // cadence the recent feeding is (presence.reach).
        let outcome: TrajectoryOutcome
        switch presence.state {
        case .drifted: outcome = .fading
        case .active:  outcome = .sustained
        case .quiet:   outcome = presence.reach >= policy.sustainedReachThreshold ? .sustained : .fading
        }
        return .init(outcome: outcome, hasGoal: false, progressFraction: nil,
                     paceRatio: nil, feedingRatio: presence.reach, solidFraction: solid)
    }

    // MARK: Solid extent

    /// A strongly-fed future stays certain further out; a drifting one dashes
    /// almost immediately. Mapped from presence reach into the policy band.
    private static func solidFraction(for presence: StrandPresence, policy: TrajectoryPolicy) -> Double {
        let reach = max(0, min(1, presence.reach))
        let raw = policy.minSolidFraction + reach * (policy.maxSolidFraction - policy.minSolidFraction)
        return min(max(raw, policy.minSolidFraction), policy.maxSolidFraction)
    }
}
