//
// HorizonCompletionTimestampTests.swift
//
// Horizon Timeline v2 — audit P6. A non-recurring completion stamps
// WorkItem.completedAt once and never re-stamps it, so the Past region's
// arrival date doesn't drift when a completed item is edited later.
//

import SwiftData
import XCTest
@testable import Moti

final class HorizonCompletionTimestampTests: XCTestCase {

    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self, WorkItem.self, SessionCheckIn.self,
                 WorkSession.self, ProjectContext.self, ContextNote.self,
                 CompletionLog.self,
            configurations: config
        )
        ctx = ModelContext(container)
    }

    override func tearDownWithError() throws {
        ctx = nil
        container = nil
    }

    private func nonRecurringItem() -> WorkItem {
        WorkItem(rawInput: "ship it", title: "ship it", projectName: nil,
                 dueDate: nil, workingStartDate: nil, workingEndDate: nil,
                 suggestedSessions: [], estimatedEffort: nil, parserConfidence: 1,
                 needsReview: false, reviewReason: nil, status: .active, parserExplanation: "")
    }

    func test_completedAt_isSetOnce_andNeverRestamped() throws {
        let item = nonRecurringItem()
        ctx.insert(item)
        XCTAssertNil(item.completedAt)

        let firstDone = Date(timeIntervalSince1970: 1_000)
        _ = WorkItemCompletion.complete(item, in: ctx, now: firstDone)
        XCTAssertEqual(item.status, .done)
        XCTAssertEqual(item.completedAt, firstDone)

        // A later edit / re-completion moves updatedAt but NOT completedAt.
        let later = Date(timeIntervalSince1970: 9_999)
        _ = WorkItemCompletion.complete(item, in: ctx, now: later)
        XCTAssertEqual(item.completedAt, firstDone, "completedAt is immutable once set")
        XCTAssertEqual(item.updatedAt, later, "updatedAt still tracks the latest edit")
    }
}
