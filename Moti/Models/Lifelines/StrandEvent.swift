import Foundation

/// A single behavioral act the user took on a strand, reduced to its essence:
/// *what kind* of act and *when*. This is the only input the presence
/// computation reads — it deliberately knows nothing about `WorkItem`,
/// `Project`, or SwiftData. The adapter (`StrandTimelineBuilder`) is responsible
/// for deriving these from the live model layer; the computer just counts them.
///
/// The four kinds mirror the PRD's behavioral vocabulary
/// (created / completed / deferred / touched). Every kind is a *past* act — a
/// plan for the future (a due date, a working window) is **not** an event, since
/// presence measures what the user has actually done, not what they intend.
enum StrandEventKind: String, Codable, CaseIterable, Equatable {
    /// The user brought something into this strand (captured a task, added work).
    case created
    /// The user finished something in this strand (marked done, completed an
    /// occurrence of a habit).
    case completed
    /// The user deliberately set something down (deferred / skipped).
    case deferred
    /// Any other contact with the strand — an edit, a check-in, a session pulse.
    case touched
}

/// One behavioral event: a kind plus the moment it happened.
struct StrandEvent: Equatable {
    let kind: StrandEventKind
    let date: Date

    init(kind: StrandEventKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}
