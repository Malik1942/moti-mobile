import Foundation

// MARK: - Trajectory outcome (the forward read — the hero)

/// Where a future's *current pace* lands it (PRD v2.1 "Computed States"). The
/// state set is type-dependent:
///
/// - **Achievement** (has a finish line): On&nbsp;Track / Slipping / Stalled / Completed
/// - **Maintenance** (no finish line): Sustained / Quiet / Fading
///
/// (Paused is a deliberate user choice carried on `Strand.isPaused`, not an
/// outcome.) Directional only in v1 — never a day-count (precise slippage is
/// gated to v2). The computation decides this; the model only phrases it.
enum TrajectoryOutcome: String, Equatable, CaseIterable {
    // Achievement
    case onTrack      // progress keeping pace → reaches the deadline
    case slipping     // progressing, but pace lands it past the deadline
    case stalled      // momentum gone before the deadline (no recent feeding)
    case completed    // finish condition met
    // Maintenance
    case sustained    // fed at its own rhythm → continues
    case quiet        // slowing — present but thinning
    case fading       // losing support → projection fades toward nothing

    /// The one that should raise its voice (PRD: only slipping / stalled /
    /// fading draw the eye; on-track, sustained, completed, quiet stay calm).
    var needsAttention: Bool { self == .slipping || self == .stalled || self == .fading }

    /// Whether this is an achievement-shaped outcome.
    var isAchievement: Bool {
        switch self {
        case .onTrack, .slipping, .stalled, .completed: return true
        case .sustained, .quiet, .fading:               return false
        }
    }
}

// MARK: - Projection result

/// The computed forward trajectory. Carries the directional outcome plus the
/// quantities the view needs to *draw* the path — every visual property maps to
/// a computed quantity (PRD non-negotiable: "visual variation must always map to
/// real behavioral signals"), and none are rendered as numbers.
struct TrajectoryProjection: Equatable {
    let outcome: TrajectoryOutcome

    /// Achievement only: does this future have a deadline marker to land against?
    let hasGoal: Bool

    /// Achievement: completed actions / total actions, `0...1`. Drives the Peek's
    /// milestone-health texture. `nil` for maintenance.
    let progressFraction: Double?

    /// Achievement: progress-so-far vs. time-elapsed toward the deadline.
    /// `≥1` ⇒ keeping pace; `<1` ⇒ behind. Directional — never shown as a number.
    let paceRatio: Double?

    /// Maintenance: recent feeding rate vs. cadence (presence reach), `0...~1`.
    let feedingRatio: Double?

    /// How far the path stays **solid** (certain) before becoming dashed/fading.
    let solidFraction: Double

    /// **Behavior-derived feeding curve**, oldest→Now, normalised `~0.15...0.85`.
    /// This is the actual evidence region of the strand — its shape comes from the
    /// real event stream (rising on bursts, dipping when quiet), not a template.
    let actualSeries: [Double]

    /// The projected continuation, Now→future, normalised. Starts from the real
    /// recent level and is shaped *directionally* by the computed outcome.
    let projectedSeries: [Double]

    /// The date of the **first real behavioral event** — the start of available
    /// evidence. The actual curve is drawn from here to Now (date-accurate), so a
    /// young strand begins near Now with empty space before it, and an old one
    /// extends back into the pannable past. `nil` when there is no history.
    let actualStartDate: Date?
}

extension TrajectoryProjection {
    /// Terse value for previews and tests (flat series, no progress detail).
    static func directional(_ outcome: TrajectoryOutcome, solidFraction: Double = 0.35) -> TrajectoryProjection {
        TrajectoryProjection(
            outcome: outcome,
            hasGoal: outcome.isAchievement,
            progressFraction: nil, paceRatio: nil, feedingRatio: nil,
            solidFraction: solidFraction,
            actualSeries: Array(repeating: 0.5, count: 7),
            projectedSeries: Array(repeating: 0.5, count: 6),
            actualStartDate: nil
        )
    }
}

// MARK: - Policy

struct TrajectoryPolicy: Equatable {
    /// Achievement: pace at/above this reads on-track.
    var onTrackPaceThreshold: Double
    var minSolidFraction: Double
    var maxSolidFraction: Double
    /// Feeding-history lookback for the actual curve, in days.
    var curveLookbackDays: Double
    /// Number of buckets in the actual feeding curve.
    var curveBuckets: Int
    /// Number of points in the projected continuation.
    var projectionPoints: Int

    static let `default` = TrajectoryPolicy(
        onTrackPaceThreshold: 1.0,
        minSolidFraction: 0.12,
        maxSolidFraction: 0.55,
        curveLookbackDays: 84,
        curveBuckets: 12,
        projectionPoints: 6
    )
}

// MARK: - Projector (pure)

/// Pure, deterministic forward projection. It **extrapolates actual behavior** —
/// completed events and feeding rate — and never assumes scheduled work will
/// happen. Presence/drift is an *input* here, not the organizing principle.
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
        let hasSignal = events.contains { $0.date <= now }
        // Evidence starts at the first real event — never fabricated earlier.
        let evidenceStart = firstActivity ?? events.filter { $0.date <= now }.map(\.date).min()
        let actual = actualSeries(events: events, start: evidenceStart, now: now, policy: policy)

        let outcome: TrajectoryOutcome
        let progress: Double?
        let pace: Double?
        let feeding: Double?
        let hasGoal: Bool

        if type == .achievement, let deadline {
            let r = achievementOutcome(
                deadline: deadline, completedCount: completedCount, totalCount: totalCount,
                firstActivity: firstActivity ?? events.map(\.date).min(),
                presence: presence, hasSignal: hasSignal, now: now, policy: policy
            )
            outcome = r.outcome; progress = r.progress; pace = r.pace; feeding = nil; hasGoal = true
        } else {
            outcome = maintenanceOutcome(presence: presence)
            progress = nil; pace = nil; feeding = presence.reach; hasGoal = false
        }

        let projected = projectedSeries(from: actual.last ?? 0.4, outcome: outcome, policy: policy)

        return TrajectoryProjection(
            outcome: outcome, hasGoal: hasGoal,
            progressFraction: progress, paceRatio: pace, feedingRatio: feeding,
            solidFraction: solid, actualSeries: actual, projectedSeries: projected,
            actualStartDate: evidenceStart
        )
    }

    // MARK: Achievement

    private static func achievementOutcome(
        deadline: Date, completedCount: Int, totalCount: Int,
        firstActivity: Date?, presence: StrandPresence, hasSignal: Bool, now: Date,
        policy: TrajectoryPolicy
    ) -> (outcome: TrajectoryOutcome, progress: Double, pace: Double?) {
        let progress = totalCount > 0 ? min(1.0, Double(completedCount) / Double(totalCount)) : 0

        // Finish condition met.
        if totalCount > 0 && progress >= 1.0 { return (.completed, 1, .infinity) }

        // No behavior yet → don't fabricate alarm; read calm/on-track.
        guard hasSignal, let start = firstActivity, start < deadline else {
            return (.onTrack, progress, nil)
        }

        // Past the deadline, unfinished → slipping (geometric overshoot).
        if now >= deadline { return (.slipping, progress, 0) }

        // Before the deadline but momentum has gone quiet → stalled.
        if presence.state == .drifted { return (.stalled, progress, 0) }

        let elapsed = min(max(now.timeIntervalSince(start) / deadline.timeIntervalSince(start), 0.0001), 1)
        let pace = progress / elapsed
        return (pace >= policy.onTrackPaceThreshold ? .onTrack : .slipping, progress, pace)
    }

    // MARK: Maintenance

    /// Drift is the input: a fed rhythm is sustained, a slowing one is quiet, a
    /// silent one is fading. The three presence states map directly.
    private static func maintenanceOutcome(presence: StrandPresence) -> TrajectoryOutcome {
        switch presence.state {
        case .active:  return .sustained
        case .quiet:   return .quiet
        case .drifted: return .fading
        }
    }

    // MARK: Behavioral curves

    /// Normalised feeding intensity from the **start of evidence** (`start`, the
    /// first real event) to Now — never earlier, so no fabricated pre-history.
    /// The shape is the real evidence: busy buckets rise, quiet buckets dip.
    /// Capped to the policy lookback so a very old strand stays within the
    /// pannable range; empty history collapses to a flat calm line.
    static func actualSeries(events: [StrandEvent], start: Date?, now: Date, policy: TrajectoryPolicy) -> [Double] {
        let buckets = max(2, policy.curveBuckets)
        let lookbackStart = now.addingTimeInterval(-policy.curveLookbackDays * 86_400)
        // Span begins at the first event (clamped to the lookback window); if
        // there is no evidence, fall back to a short flat segment at Now.
        guard let evidence = start else { return [0.2, 0.2] }
        let spanStart = max(evidence, lookbackStart)
        let spanDays = max(1.0, now.timeIntervalSince(spanStart) / 86_400)
        let bucketDays = spanDays / Double(buckets)

        var counts = [Int](repeating: 0, count: buckets)
        for e in events where e.date >= spanStart && e.date <= now {
            let offset = e.date.timeIntervalSince(spanStart) / 86_400
            let idx = min(buckets - 1, max(0, Int(offset / bucketDays)))
            counts[idx] += 1
        }
        let maxCount = max(1, counts.max() ?? 1)
        // Normalise to a calm band so the strand reads as a silk thread, not a graph.
        return counts.map { 0.2 + (Double($0) / Double(maxCount)) * 0.6 }
    }

    /// Directional continuation from the real recent level, shaped by the outcome.
    static func projectedSeries(from start: Double, outcome: TrajectoryOutcome, policy: TrajectoryPolicy) -> [Double] {
        let n = max(2, policy.projectionPoints)
        let target: Double
        switch outcome {
        case .onTrack:   target = min(0.82, start + 0.16)
        case .slipping:  target = max(0.3, start - 0.1)
        case .stalled:   target = max(0.16, start * 0.5)
        case .completed: target = 0.85
        case .sustained: target = start
        case .quiet:     target = max(0.22, start - 0.12)
        case .fading:    target = 0.12
        }
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            return start + (target - start) * t
        }
    }

    // MARK: Solid extent

    private static func solidFraction(for presence: StrandPresence, policy: TrajectoryPolicy) -> Double {
        let reach = max(0, min(1, presence.reach))
        let raw = policy.minSolidFraction + reach * (policy.maxSolidFraction - policy.minSolidFraction)
        return min(max(raw, policy.minSolidFraction), policy.maxSolidFraction)
    }
}
