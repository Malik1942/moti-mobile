import Foundation

// MARK: - Presence state (the computed truth)

/// The one primary signal of the Timeline: does this strand still reach the
/// fixed `Now` axis, or has it quietly drifted out of the present?
///
/// This is **what is true**, computed deterministically from event counting. It
/// is never decided by the model layer (which only narrates it). `Paused` is
/// deliberately *not* here: pausing is a user choice, layered on top by the view
/// — it is not something the event stream can infer. The computation answers a
/// single question with three honest outcomes.
enum PresenceState: String, Equatable, CaseIterable {
    /// Fed within its own rhythm — solid, full-color, reaches Now with a node.
    case active
    /// Present but low activity — approaches/just reaches Now, faded.
    case quiet
    /// Silently falling out of the present — fades and stops short of Now,
    /// leaving an empty slot on the axis. The one that catches the eye.
    case drifted

    /// Whether the strand's line should arrive at the Now axis at all. Drift is
    /// the *only* state that does not reach — that gap is the loudest element on
    /// screen and the whole point of the view.
    var reachesNow: Bool { self != .drifted }
}

/// Where a strand's baseline cadence came from. Surfaced so the UI / copy can be
/// honest about how much it actually knows (and so it never fabricates urgency
/// from thin air — see `PRD §8`, §10).
enum BaselineSource: String, Equatable {
    /// Declared by the strand's own recurrence rule ("Every Friday"). Strongest.
    case recurrence
    /// Learned from the median spacing of the strand's own past events.
    case history
    /// Only one event exists — degrade to a single gentle one-time cadence.
    case inferredOneTime
    /// No events at all — there is no baseline. Never drifts; stays calm.
    case none
}

// MARK: - Result

/// The full computed presence of a strand: the headline state plus the
/// quantities the renderer needs (so every visual property maps to a number, per
/// PRD §14 "lines must not become decoration").
struct StrandPresence: Equatable {
    /// The headline signal.
    let state: PresenceState

    /// How far the line reaches toward `Now`, in `0...1`.
    /// `1` = touches the Now node; `0` = breaks off at the start of the window
    /// (a fully drifted strand leaves an empty slot). The active/quiet boundary
    /// sits at exactly `0.5`, so position alone separates them with no label.
    let reach: Double

    /// Most recent behavioral event, if any.
    let lastActivity: Date?

    /// Whole days since `lastActivity` (floored). `nil` when there is no history.
    let daysSinceLastActivity: Int?

    /// The strand's own characteristic interval, in days. `nil` when unknown.
    let baselineCadenceDays: Double?

    /// Provenance of the baseline — drives how confidently copy can speak.
    let baselineSource: BaselineSource

    /// Convenience: did the strand reach the Now axis?
    var reachesNow: Bool { state.reachesNow }
}

// MARK: - Policy

/// Tunable thresholds for the presence computation. Defaults are deliberately
/// gentle: a strand has to fall to *twice* its own cadence before it reads as
/// drifted, and a strand with no history never drifts at all.
struct PresencePolicy: Equatable {
    /// A strand is `drifted` once it has been silent for `baseline * this`.
    /// The active/quiet split is the midpoint of this horizon.
    var driftMultiplier: Double

    /// Baseline used when exactly one event exists and no recurrence is declared.
    /// A single one-off capture with no follow-up gently ages out over ~2× this.
    var inferredOneTimeCadenceDays: Double

    /// Lower clamp on baseline, to avoid div-by-zero and day-to-day jitter.
    var minBaselineDays: Double

    /// Upper clamp on baseline. A genuinely seasonal strand should still be
    /// allowed a long rhythm, but we cap it so nothing becomes immortal.
    var maxBaselineDays: Double

    static let `default` = PresencePolicy(
        driftMultiplier: 2.0,
        inferredOneTimeCadenceDays: 14,
        minBaselineDays: 1,
        maxBaselineDays: 365
    )
}

// MARK: - Computer (pure)

/// Pure, deterministic presence computation. No SwiftData, no `Date.now`, no
/// hidden state — every output is a function of the inputs, which is what makes
/// the drift signal trustworthy (PRD §8: "structure is computed").
///
/// The model layer never calls into here to *decide* anything; it only reads the
/// result to phrase it.
enum StrandPresenceComputer {

    /// Compute a strand's presence from its behavioral events.
    ///
    /// - Parameters:
    ///   - events: every past act on the strand (any order). Future-dated entries
    ///     are ignored — presence is about behavior, not plans.
    ///   - recurrenceCadenceDays: the strand's *declared* rhythm in days, if it
    ///     has a recurring habit (e.g. weekly → 7). Passed in by the adapter so
    ///     this function stays ignorant of `WorkItem`. `nil` when none is declared.
    ///   - now: the fixed Now axis.
    ///   - policy: thresholds (defaults are gentle and calm).
    static func presence(
        events: [StrandEvent],
        recurrenceCadenceDays: Double? = nil,
        now: Date,
        policy: PresencePolicy = .default
    ) -> StrandPresence {
        // Only past behavior counts. Sort ascending for spacing math.
        let past = events
            .filter { $0.date <= now }
            .sorted { $0.date < $1.date }

        let lastActivity = past.last?.date

        // --- Derive the strand's own baseline cadence -----------------------
        let (rawBaseline, source) = baseline(
            for: past,
            recurrenceCadenceDays: recurrenceCadenceDays,
            policy: policy
        )

        // No history at all → there is nothing to drift away from. Stay calm and
        // neutral; never fabricate urgency (PRD §10).
        guard let baselineDays = rawBaseline, let last = lastActivity else {
            return StrandPresence(
                state: .quiet,
                reach: 0.5,
                lastActivity: lastActivity,
                daysSinceLastActivity: nil,
                baselineCadenceDays: rawBaseline,
                baselineSource: source
            )
        }

        // --- Recency vs. the strand's OWN cadence ---------------------------
        let daysSince = wholeDaysBetween(last, and: now)
        let driftHorizon = baselineDays * policy.driftMultiplier

        if Double(daysSince) >= driftHorizon {
            // Gap before Now → drifted. Line breaks off; its slot is empty.
            return StrandPresence(
                state: .drifted,
                reach: 0,
                lastActivity: last,
                daysSinceLastActivity: daysSince,
                baselineCadenceDays: baselineDays,
                baselineSource: source
            )
        }

        // Still reaching. Reach falls linearly from 1 (just acted) toward 0 (about
        // to drift). The active/quiet boundary is exactly one baseline interval of
        // silence, i.e. reach == 0.5.
        let reach = 1.0 - (Double(daysSince) / driftHorizon)
        let state: PresenceState = Double(daysSince) <= baselineDays ? .active : .quiet

        return StrandPresence(
            state: state,
            reach: reach,
            lastActivity: last,
            daysSinceLastActivity: daysSince,
            baselineCadenceDays: baselineDays,
            baselineSource: source
        )
    }

    // MARK: - Baseline derivation

    /// Returns the strand's own characteristic interval in days and where it came
    /// from. Order of preference: declared recurrence → learned history → a single
    /// gentle one-time cadence → nothing.
    private static func baseline(
        for sortedPastEvents: [StrandEvent],
        recurrenceCadenceDays: Double?,
        policy: PresencePolicy
    ) -> (Double?, BaselineSource) {
        // 1. Declared recurrence wins — it is the strand stating its own rhythm.
        if let declared = recurrenceCadenceDays, declared > 0 {
            return (clampBaseline(declared, policy: policy), .recurrence)
        }

        // 2. Learn from the strand's own spacing when there are ≥ 2 events.
        if sortedPastEvents.count >= 2 {
            var gaps: [Double] = []
            for i in 1..<sortedPastEvents.count {
                let days = sortedPastEvents[i].date
                    .timeIntervalSince(sortedPastEvents[i - 1].date) / 86_400
                if days > 0 { gaps.append(days) }
            }
            if let med = median(gaps) {
                return (clampBaseline(med, policy: policy), .history)
            }
        }

        // 3. Exactly one event, no declared rhythm → a single gentle cadence.
        if sortedPastEvents.count == 1 {
            return (clampBaseline(policy.inferredOneTimeCadenceDays, policy: policy), .inferredOneTime)
        }

        // 4. Nothing to go on.
        return (nil, .none)
    }

    private static func clampBaseline(_ value: Double, policy: PresencePolicy) -> Double {
        min(max(value, policy.minBaselineDays), policy.maxBaselineDays)
    }

    // MARK: - Small numeric helpers

    /// Whole days (floored, never negative) between two instants.
    static func wholeDaysBetween(_ earlier: Date, and later: Date) -> Int {
        let days = later.timeIntervalSince(earlier) / 86_400
        return max(0, Int(days.rounded(.down)))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
