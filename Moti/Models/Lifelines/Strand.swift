import Foundation

/// What kind of future a strand is. Achievement and maintenance futures are not
/// the same kind of thing and must not share one generic checklist (PRD §6.2):
/// the peek sheet branches on this.
///
/// Inferred, not stored (per the v1 decision): a strand is `achievement` when it
/// carries a real one-time deadline; otherwise it is `maintenance`. Recurrence
/// biases toward maintenance — a weekly habit is a rhythm, not a deadline.
enum StrandKind: String, Equatable {
    case achievement
    case maintenance
}

/// A point an achievement strand passes through on its way to a deadline. Drawn
/// as a node on the line — **not** a checklist row (PRD §6.2).
struct StrandForwardNode: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// The step's own date, if dated. `nil` for an undated upcoming step.
    let date: Date?
    /// The final marker of the strand (e.g. "move day").
    let isDeadline: Bool
    /// Already passed through (done, or its date is behind Now).
    let isReached: Bool
}

/// A dated mark in a maintenance strand's history — the "last traces" that show
/// the *shape of absence* rather than a checkbox list (PRD §6.2).
struct StrandTrace: Identifiable, Equatable {
    let id: UUID
    /// Human label for the trace ("Evening walk", "Skipped", "Gym").
    let label: String
    let date: Date
    let kind: StrandEventKind
}

/// One future, ready to render. Identity (id, name, color) is stable across time
/// and screens; everything else is computed from behavior. This value type is
/// what the views consume — they never touch `WorkItem` directly, which keeps the
/// main axis honest (presence only; detail on tap; execution in Projects).
struct Strand: Identifiable, Equatable {
    /// Stable identity — the Project's UUID string, or `Strand.unassignedID`.
    let id: String
    let name: String
    /// Identity color token (stable per future). Never a status scale.
    let colorToken: String
    let kind: StrandKind

    /// The computed truth: does this line still reach Now?
    let presence: StrandPresence

    /// Deliberately set down by the user — drawn dashed + labeled, and held
    /// visually distinct from silent drift (PRD §5.1).
    let isPaused: Bool

    // MARK: Rhythm / context (behavioral counts only — zero estimates)

    /// The strand's declared cadence in days, if it has a recurring habit.
    let recurrenceCadenceDays: Double?
    /// Open (not done/archived) item count — context only, never shown on the axis.
    let openCount: Int
    /// How many things the user has set down in this strand.
    let deferredCount: Int

    // MARK: Achievement peek

    /// The furthest meaningful deadline, if any.
    let deadline: Date?
    /// Upcoming steps as points toward the deadline (not a checklist).
    let forwardNodes: [StrandForwardNode]

    // MARK: Maintenance peek

    /// Recent dated history, most recent first.
    let lastTraces: [StrandTrace]
    /// Names of strands that *rose while this one fell*, in the same recent
    /// window. Stated as co-occurrence — never causation, never "crowded out"
    /// (PRD §6.2). This is the computed truth; the model layer phrases it.
    let coOccurringStrandNames: [String]

    static let unassignedID = "strand.unassigned"

    /// Identifier used to scope per-strand UI preferences (paused, nudges).
    var preferenceKey: String { id }
}
