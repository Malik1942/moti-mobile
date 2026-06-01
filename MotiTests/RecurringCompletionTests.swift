//
// RecurringCompletionTests.swift
//
// Covers the "living habit" completion rule: completing a recurring WorkItem
// rolls its due date forward to the next occurrence and keeps it active, rather
// than marking it permanently done. Non-recurring items still complete once.
//
// Exercises `WorkItem.completeRecurringOccurrence` directly (pure model logic,
// no ModelContext) so the date math is verified without SwiftData.
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class RecurringCompletionTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Minimal recurring WorkItem for completion tests.
    private func makeItem(recurrence: RecurrenceRule, dueDate: Date?) -> WorkItem {
        let item = WorkItem(
            rawInput: "habit",
            title: "habit",
            projectName: nil,
            dueDate: dueDate,
            workingStartDate: nil,
            workingEndDate: nil,
            suggestedSessions: [],
            estimatedEffort: nil,
            parserConfidence: 1,
            needsReview: false,
            reviewReason: nil,
            status: .active,
            parserExplanation: ""
        )
        item.recurrence = recurrence
        return item
    }

    // MARK: - Required cases

    func test_dailyTask_advancesToTomorrow_andStaysActive() {
        let cal = utcCalendar()
        let today = date(2026, 5, 30, cal)
        let item = makeItem(recurrence: RecurrenceRule(frequency: .daily), dueDate: today)

        let completed = item.completeRecurringOccurrence(now: today, calendar: cal)

        XCTAssertEqual(completed, today)
        XCTAssertEqual(item.dueDate, date(2026, 5, 31, cal))
        XCTAssertEqual(item.status, .active)        // not permanently done
        XCTAssertTrue(item.isRecurring)             // recurrence preserved
        XCTAssertEqual(item.recurrence.frequency, .daily)
    }

    func test_weekdayTask_advancesFromFridayToMonday() {
        let cal = utcCalendar()
        let friday = date(2026, 5, 29, cal) // 2026-05-29 is a Friday
        let item = makeItem(recurrence: RecurrenceRule(frequency: .weekdays), dueDate: friday)

        item.completeRecurringOccurrence(now: friday, calendar: cal)

        XCTAssertEqual(item.dueDate, date(2026, 6, 1, cal)) // Monday
        XCTAssertEqual(item.status, .active)
    }

    func test_weeklyFridayTask_advancesToNextFriday() {
        let cal = utcCalendar()
        let friday = date(2026, 5, 29, cal)
        let item = makeItem(recurrence: RecurrenceRule(frequency: .weekly, weekday: 6), dueDate: friday)

        item.completeRecurringOccurrence(now: friday, calendar: cal)

        XCTAssertEqual(item.dueDate, date(2026, 6, 5, cal)) // next Friday
        XCTAssertEqual(item.status, .active)
        XCTAssertEqual(item.recurrence.weekday, 6)          // pinned weekday preserved
    }

    func test_nonRecurringTask_completesNormally() {
        let cal = utcCalendar()
        let due = date(2026, 5, 30, cal)
        let item = makeItem(recurrence: .none, dueDate: due)

        // Non-recurring items return nil (caller falls back to `.done`) and the
        // due date is untouched by the recurrence roll-forward.
        let completed = item.completeRecurringOccurrence(now: due, calendar: cal)

        XCTAssertNil(completed)
        XCTAssertEqual(item.dueDate, due)
        XCTAssertFalse(item.isRecurring)
    }

    // MARK: - No infinite duplication

    func test_repeatedCompletions_keepSingleItemRollingForward() {
        let cal = utcCalendar()
        var anchor = date(2026, 5, 30, cal)
        let item = makeItem(recurrence: RecurrenceRule(frequency: .daily), dueDate: anchor)

        for _ in 0..<5 {
            item.completeRecurringOccurrence(now: anchor, calendar: cal)
            anchor = item.dueDate!
        }

        // Five completions advanced the same single item five days — no new
        // WorkItems were created.
        XCTAssertEqual(item.dueDate, date(2026, 6, 4, cal))
        XCTAssertEqual(item.status, .active)
    }
}
