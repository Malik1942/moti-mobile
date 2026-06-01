//
// WorkItemScopeTests.swift
//
// Covers the view-specific work-item scopes that keep past work visible:
// Timeline (past+present+future, archived hidden), Due Soon (upcoming+overdue),
// Active Queue (active only), Recently Completed, and Project History.
//
// The product rule under test: a passed due date must NEVER hide a task —
// Moti is a temporal memory system, not an upcoming-only scheduler.
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class WorkItemScopeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000) // fixed "now"

    private func makeItem(
        title: String,
        dueOffset: TimeInterval? = nil,
        status: WorkItemStatus = .active
    ) -> WorkItem {
        WorkItem(
            rawInput: title,
            title: title,
            projectName: "P",
            dueDate: dueOffset.map { now.addingTimeInterval($0) },
            workingStartDate: nil,
            workingEndDate: nil,
            suggestedSessions: [],
            estimatedEffort: nil,
            parserConfidence: 1,
            needsReview: false,
            reviewReason: nil,
            status: status,
            parserExplanation: ""
        )
    }

    private lazy var upcoming   = makeItem(title: "upcoming",  dueOffset: +86_400)        // tomorrow
    private lazy var overdue    = makeItem(title: "overdue",   dueOffset: -86_400)        // yesterday, still active
    private lazy var completed  = makeItem(title: "completed", dueOffset: -172_800, status: .done)
    private lazy var archived   = makeItem(title: "archived",  dueOffset: -86_400, status: .archived)
    private lazy var skipped    = makeItem(title: "skipped",   dueOffset: -86_400, status: .skipped)

    private lazy var all = [upcoming, overdue, completed, archived, skipped]

    // MARK: - Timeline: past + present + future, only archived hidden

    func test_timeline_keepsPastPresentFuture_hidesArchivedOnly() {
        let scope = WorkItemScope.timeline(all, now: now)
        XCTAssertTrue(scope.contains(upcoming))
        XCTAssertTrue(scope.contains(overdue))    // overdue stays visible
        XCTAssertTrue(scope.contains(completed))  // completed stays visible
        XCTAssertTrue(scope.contains(skipped))
        XCTAssertFalse(scope.contains(archived))  // only archived hidden
    }

    // MARK: - Due Soon: upcoming + overdue

    func test_dueSoon_includesUpcomingAndOverdue_notCompleted() {
        let scope = WorkItemScope.dueSoon(all, now: now)
        XCTAssertTrue(scope.contains(upcoming))
        XCTAssertTrue(scope.contains(overdue))
        XCTAssertFalse(scope.contains(completed))
        XCTAssertFalse(scope.contains(archived))
    }

    func test_dueSoon_sortsMostUrgentFirst() {
        let scope = WorkItemScope.dueSoon(all, now: now)
        XCTAssertEqual(scope.first, overdue) // yesterday sorts before tomorrow
    }

    // MARK: - Overdue (missed)

    func test_overdue_onlyPastDueStillActive() {
        let scope = WorkItemScope.overdue(all, now: now)
        XCTAssertEqual(scope.map(\.title), ["overdue"])
    }

    // MARK: - Active Queue: active only

    func test_activeQueue_excludesOverdueUpcomingAndHistory() {
        // None of the dated fixtures are "active now" (upcoming is future,
        // overdue is past); an untimed open item is.
        let untimed = makeItem(title: "untimed")
        let scope = WorkItemScope.activeQueue(all + [untimed], now: now)
        XCTAssertEqual(scope.map(\.title), ["untimed"])
    }

    // MARK: - Recently Completed

    func test_recentlyCompleted_onlyDone() {
        let scope = WorkItemScope.recentlyCompleted(all, now: now)
        XCTAssertEqual(scope.map(\.title), ["completed"])
    }

    // MARK: - Project History: completed + overdue + skipped + archived

    func test_projectHistory_includesAllPastAndFinished() {
        let scope = WorkItemScope.projectHistory(all, now: now)
        let titles = Set(scope.map(\.title))
        XCTAssertEqual(titles, ["overdue", "completed", "skipped", "archived"])
        XCTAssertFalse(titles.contains("upcoming")) // future work isn't history
    }
}
