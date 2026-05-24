import Foundation

/// Where a work item sits in its lifecycle, derived from its persistent
/// `status` plus its dates relative to "now".
///
/// Critical rule: **a passed due date never hides a task** — it simply becomes
/// `.overdue` and stays visible and actionable. Nothing here filters items out;
/// it only classifies them so views can group rather than drop.
enum WorkItemTimeState: String, CaseIterable {
    case upcoming      // scheduled for the future
    case active        // current / relevant now (in its working window, or due today, or untimed)
    case overdue       // due date (or planned window) passed, not completed
    case completed     // marked done
    case skipped       // user intentionally decided not to do it
    case archived      // hidden from active planning, preserved in history
    case needsReview   // captured but lacks usable timing — needs the user

    var label: String {
        switch self {
        case .upcoming:    "Upcoming"
        case .active:      "Active"
        case .overdue:     "Overdue"
        case .completed:   "Completed"
        case .skipped:     "Skipped"
        case .archived:    "Archived"
        case .needsReview: "Needs Review"
        }
    }

    /// True for states that still demand the user's attention / action.
    var isActionable: Bool {
        switch self {
        case .upcoming, .active, .overdue, .needsReview: true
        case .completed, .skipped, .archived:            false
        }
    }
}

extension WorkItem {
    /// Derived lifecycle position. Combines persistent status with dates so the
    /// UI can group tasks across past / present / future without ever losing a
    /// task to a passed deadline.
    func timeState(now: Date = .now, calendar: Calendar = .current) -> WorkItemTimeState {
        // Persistent statuses win outright.
        switch status {
        case .archived:    return .archived
        case .done:        return .completed
        case .skipped:     return .skipped
        case .needsReview: return .needsReview
        case .planned, .active, .deferred:
            break
        }
        if needsReview { return .needsReview }

        // A due date that has passed → overdue (even on the same day, once the
        // moment is behind us). Due today but still ahead → active focus.
        if let due = dueDate {
            if due < now { return .overdue }
            if calendar.isDateInToday(due) { return .active }
        } else if let end = workingEndDate, end < now {
            // No deadline, but the planned working window ended unfinished.
            return .overdue
        }

        // Currently inside its working window.
        if let start = workingStartDate, let end = workingEndDate, start <= now, now <= end {
            return .active
        }

        // Scheduled for later.
        if let start = workingStartDate, start > now { return .upcoming }
        if let due = dueDate, due > now { return .upcoming }

        // Untimed but live — a current concern.
        return .active
    }
}

// MARK: - Project task grouping

/// Single source of truth for splitting a project's work items into time-state
/// buckets. Used by the project overview UI and by the AI planning context so
/// the two never drift apart. Pass a project's items in; get ordered groups out.
struct ProjectTaskBuckets {
    let currentFocus: [WorkItem]    // .active
    let needsAttention: [WorkItem]  // .overdue + .needsReview (overdue first)
    let upcoming: [WorkItem]        // .upcoming
    let completed: [WorkItem]       // .completed (most recent first)
    let skipped: [WorkItem]         // .skipped
    let archived: [WorkItem]        // .archived

    init(items: [WorkItem], now: Date = .now) {
        var focus: [WorkItem] = []
        var overdue: [WorkItem] = []
        var review: [WorkItem] = []
        var up: [WorkItem] = []
        var done: [WorkItem] = []
        var skip: [WorkItem] = []
        var arch: [WorkItem] = []

        for item in items {
            switch item.timeState(now: now) {
            case .active:      focus.append(item)
            case .overdue:     overdue.append(item)
            case .needsReview: review.append(item)
            case .upcoming:    up.append(item)
            case .completed:   done.append(item)
            case .skipped:     skip.append(item)
            case .archived:    arch.append(item)
            }
        }

        // Soonest-anchored ordering for live work; most-recent first for history.
        func anchor(_ item: WorkItem) -> Date {
            item.dueDate ?? item.workingEndDate ?? item.workingStartDate ?? item.createdAt
        }
        self.currentFocus = focus.sorted { anchor($0) < anchor($1) }
        // Most overdue first (oldest due date), then needs-review by recency.
        self.needsAttention = overdue.sorted { anchor($0) < anchor($1) }
            + review.sorted { $0.createdAt > $1.createdAt }
        self.upcoming = up.sorted { anchor($0) < anchor($1) }
        self.completed = done.sorted { $0.updatedAt > $1.updatedAt }
        self.skipped = skip.sorted { $0.updatedAt > $1.updatedAt }
        self.archived = arch.sorted { $0.updatedAt > $1.updatedAt }
    }

    var overdueCount: Int { needsAttention.filter { $0.timeState() == .overdue }.count }
}

// MARK: - Project Pulse

/// Compact at-a-glance health summary for a project, computed from its buckets.
struct ProjectPulse {
    let total: Int
    let completed: Int
    let active: Int
    let overdue: Int
    let upcoming: Int
    let nextDeadline: Date?
    let lastActivity: Date?

    init(items: [WorkItem], buckets: ProjectTaskBuckets, now: Date = .now) {
        self.total = items.count
        self.completed = buckets.completed.count
        self.active = buckets.currentFocus.count
        self.overdue = buckets.overdueCount
        self.upcoming = buckets.upcoming.count
        self.nextDeadline = (buckets.currentFocus + buckets.upcoming)
            .compactMap(\.dueDate)
            .filter { $0 >= now }
            .min()
        self.lastActivity = items.map(\.updatedAt).max()
    }

    /// Human-readable project status, prioritizing attention then progress.
    var statusLabel: String {
        if total == 0 { return "Empty" }
        if overdue > 0 { return "Needs attention" }
        if completed == total { return "Complete" }
        if active > 0 { return "In progress" }
        if upcoming > 0 { return "Scheduled" }
        return "Planned"
    }
}
