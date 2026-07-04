import Foundation

// Horizon Timeline v2 — T4. The fold predicate (PRD §6.4). Injectable so the
// Phase-2 divergence read can swap in without rows or the snapshot ever learning
// which implementation is live. Pure, Foundation-only.

/// Decides whether a strand is *quiet* — calm enough to fold away — so that
/// visual density equals problem density (PRD §5, §6.4). Rows and the snapshot
/// hold a `QuietnessProvider` and see only the `Bool`; they never branch on the
/// concrete provider. This protocol IS the Phase-2 seam.
///
/// ⚠️ Naming hazard: here "quiet" means **calm / not worth surfacing** (it folds
/// away). This is the OPPOSITE polarity from the engine's `PresenceState.quiet`
/// and `TrajectoryOutcome.quiet`, which mean "weakening / thinning" — a strand
/// that is engine-`quiet` is *drifting* and would be surfaced, not folded. When
/// writing `DivergenceQuietnessProvider`, do NOT wire `isQuiet` to
/// `PresenceState.quiet`; read `TrajectoryOutcome.needsAttention` (loud =
/// needsAttention) instead.
protocol QuietnessProvider {
    /// `true` when `strand` should fold into the "on course" summary rather than
    /// occupy its own row. `placement` is the strand's already-computed bucket
    /// placement (T2), passed so the predicate need not recompute overdue /
    /// feed-approaching state.
    func isQuiet(_ strand: HorizonStrand, placement: BucketPlacement) -> Bool
}

/// Phase-1 fold predicate (PRD §6.4, simplified per the implementation
/// breakdown): a strand is quiet unless it is **overdue** or **feed-approaching**
/// (elapsed ≥ 0.8 × typicalGap). Phase 1 has no divergence signal, so every
/// on-track achievement and every not-yet-approaching maintenance strand folds.
///
/// Phase 2 replaces this with a `DivergenceQuietnessProvider` that additionally
/// keeps a strand loud when `strand.divergence?.exceedsThreshold == true`.
struct CalmQuietnessProvider: QuietnessProvider {
    func isQuiet(_ strand: HorizonStrand, placement: BucketPlacement) -> Bool {
        switch placement {
        case .overdue, .feedOverdue:
            return false // overdue signals always surface (and pin)
        case let .feedBy(_, rhythm):
            return !rhythm.isApproaching // approaching the feed-by → surface
        case .dueIn, .achievementNoDueDate, .maintenanceNoRhythm:
            return true // on-track / no-signal → fold
        }
    }
}
