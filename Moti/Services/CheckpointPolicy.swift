import Foundation

/// The single source of truth for *which* timeline checkpoints exist.
///
/// Product philosophy: Moti should feel calm and supportive, not constantly
/// monitoring. Checkpoints represent **meaningful pacing moments**, not granular
/// machine progress sampling — so the default is sparse (quarter / half / three-
/// quarter / done) and gets sparser for short tasks and recurring habits.
///
/// Centralizing the decision here (rather than scattering `[0.25, 0.5, …]`
/// literals across the schedulers and the session model) is deliberate
/// future-facing architecture: the percentages can later evolve into *adaptive*
/// pacing checkpoints — derived from how the user is actually tracking — without
/// touching any caller. Every checkpoint producer asks `CheckpointPolicy`.
enum CheckpointPolicy {

    /// Tasks shorter than this get the reduced (half / done) cadence — frequent
    /// check-ins on a sub-90-minute task are just noise.
    static let shortTaskThreshold: TimeInterval = 90 * 60

    /// Default meaningful pacing moments: quarter, half, three-quarter, done.
    static let standard: [Double] = [0.25, 0.5, 0.75, 1.0]

    /// Short tasks: just the midpoint and completion.
    static let short: [Double] = [0.5, 1.0]

    /// Recurring habits: completion only — an ongoing habit shouldn't be
    /// interrupted partway through.
    static let recurring: [Double] = [1.0]

    /// Superset of every fraction any policy can emit (plus the legacy `0.9`).
    /// Used only to build notification identifiers for *cancellation*, so a
    /// reschedule reliably clears whatever was previously scheduled regardless
    /// of which policy produced it.
    static let allCancellableFractions: [Double] = [0.25, 0.5, 0.75, 0.9, 1.0]

    /// The checkpoints for a task/session of the given planned duration.
    ///
    /// - Parameters:
    ///   - duration: planned working span in seconds. `<= 0` falls back to the
    ///     standard cadence.
    ///   - isRecurring: whether the underlying work item is a recurring habit.
    static func checkpoints(duration: TimeInterval, isRecurring: Bool) -> [Double] {
        if isRecurring { return recurring }
        guard duration > 0 else { return standard }
        return duration < shortTaskThreshold ? short : standard
    }
}
