import Foundation

/// Centralized, view-specific work-item scopes.
///
/// Moti is a **temporal memory system, not just a future task scheduler** — past
/// work stays visible because it's project context and material for reflection.
/// So no scope here filters by "is the due date still ahead of now": a passed
/// deadline becomes `.overdue` (via `WorkItem.timeState`) and remains visible.
/// The only things hidden by default are archived items (and deleted items,
/// which are already gone from the store).
///
/// Each scope is named for the surface that consumes it so the intent is
/// explicit and the predicates can't silently drift back toward upcoming-only.
enum WorkItemScope {

    /// **Timeline** — past + present + future. Hides only archived items.
    /// This is the base set for the Timeline screen; cards below narrow it.
    static func timeline(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items.filter { $0.timeState(now: now) != .archived }
    }

    /// **Due Soon** — dated work still needing action: upcoming or overdue
    /// (due-today counts as active and is included). Most-urgent first.
    static func dueSoon(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items
            .filter { $0.dueDate != nil }
            .filter {
                switch $0.timeState(now: now) {
                case .upcoming, .overdue, .active: return true
                case .completed, .skipped, .archived, .needsReview: return false
                }
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// **Overdue** — past-due work that was never completed (the "missed" set).
    static func overdue(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items
            .filter { $0.timeState(now: now) == .overdue }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    /// **Active Queue** — work that is live right now (in its window, due today,
    /// or untimed-but-open). Excludes overdue and upcoming.
    static func activeQueue(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items.filter { $0.timeState(now: now) == .active }
    }

    /// **Upcoming** — scheduled work that hasn't started yet, soonest first
    /// (by working-window start, falling back to due date).
    static func upcoming(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items
            .filter { $0.timeState(now: now) == .upcoming }
            .sorted {
                ($0.workingStartDate ?? $0.dueDate ?? .distantFuture)
                    < ($1.workingStartDate ?? $1.dueDate ?? .distantFuture)
            }
    }

    /// **Recently Completed** — finished work, most recent first. The Timeline's
    /// short-term memory of what just got done.
    static func recentlyCompleted(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items
            .filter { $0.timeState(now: now) == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// **Project History** — everything finished or in the past: completed,
    /// skipped, archived, and overdue (past-dated) work. Most recent first.
    static func projectHistory(_ items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items
            .filter {
                switch $0.timeState(now: now) {
                case .completed, .skipped, .archived, .overdue: return true
                case .upcoming, .active, .needsReview: return false
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
