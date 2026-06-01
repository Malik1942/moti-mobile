//
// RecurrenceParserTests.swift
//
// Covers the deterministic recurrence layer that makes recurring habits
// first-class WorkItem data instead of LLM notes:
//   - `RecurrenceParser.parse` (raw text → structured RecurrenceRule)
//   - `PlanningClassifier` routing of recurring captures to the lightweight,
//     no-subtask path
//   - `RecurrenceRule.nextOccurrence` (single next date, never infinite)
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class RecurrenceParserTests: XCTestCase {

    // MARK: - Parser: the required cases

    func test_scanLinkedInEveryDay_isDaily() {
        let rule = RecurrenceParser.parse("Scanning new roles on LinkedIn every day")
        XCTAssertEqual(rule.frequency, .daily)
        XCTAssertTrue(rule.isRecurring)
        XCTAssertNil(rule.weekday)
    }

    func test_practicePianoEveryNight_isDaily() {
        let rule = RecurrenceParser.parse("Practice piano every night")
        XCTAssertEqual(rule.frequency, .daily)
        XCTAssertTrue(rule.isRecurring)
    }

    func test_reviewPortfolioEveryFriday_isWeeklyOnFriday() {
        let rule = RecurrenceParser.parse("Review portfolio every Friday")
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.weekday, 6) // 1=Sun … 6=Fri
        XCTAssertEqual(rule.displayLabel, "Every Friday")
    }

    func test_checkJobsOnWeekdays_isWeekdays() {
        let rule = RecurrenceParser.parse("Check jobs on weekdays")
        XCTAssertEqual(rule.frequency, .weekdays)
        XCTAssertTrue(rule.isRecurring)
    }

    func test_atomicTask_isNotRecurring() {
        let rule = RecurrenceParser.parse("Email Andre my portfolio link tonight")
        XCTAssertEqual(rule.frequency, .none)
        XCTAssertFalse(rule.isRecurring)
    }

    // MARK: - Parser: guards against false positives

    func test_bareWeekdayDeadline_isNotRecurring() {
        // A one-off deadline must NOT become a weekly recurrence.
        let rule = RecurrenceParser.parse("Submit the final PDF by Friday")
        XCTAssertEqual(rule.frequency, .none)
    }

    func test_everyOtherDay_isCustomIntervalTwo() {
        let rule = RecurrenceParser.parse("Water the plants every other day")
        XCTAssertEqual(rule.frequency, .custom)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.displayLabel, "Every 2 days")
    }

    func test_everyThreeDays_isCustomIntervalThree() {
        let rule = RecurrenceParser.parse("Back up the database every 3 days")
        XCTAssertEqual(rule.frequency, .custom)
        XCTAssertEqual(rule.interval, 3)
    }

    func test_weeklyAndMonthlyGenerics() {
        XCTAssertEqual(RecurrenceParser.parse("Team sync weekly").frequency, .weekly)
        XCTAssertEqual(RecurrenceParser.parse("Pay rent every month").frequency, .monthly)
    }

    // MARK: - Classifier routing: recurring → lightweight, never subtasks

    func test_classifier_routesEveryDayToLightweightRecurring() {
        let d = PlanningClassifier.classify(rawInput: "Scanning new roles on LinkedIn every day")
        XCTAssertEqual(d.inputType, .recurringTask)
        XCTAssertEqual(d.planningDepth, .lightweight)
        XCTAssertFalse(d.shouldGeneratePlan)
        XCTAssertFalse(d.shouldCreateSubtasks)
    }

    func test_classifier_routesWeekdaysToLightweightRecurring() {
        let d = PlanningClassifier.classify(rawInput: "Check jobs on weekdays")
        XCTAssertEqual(d.inputType, .recurringTask)
        XCTAssertEqual(d.planningDepth, .lightweight)
        XCTAssertFalse(d.shouldCreateSubtasks)
    }

    func test_classifier_atomicTaskStaysDepthNone() {
        let d = PlanningClassifier.classify(rawInput: "Email Andre my portfolio link tonight")
        XCTAssertEqual(d.planningDepth, .none)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    // MARK: - nextOccurrence: one date, never infinite

    func test_nextOccurrence_dailyAdvancesOneDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2026-05-30 is a Saturday.
        let reference = cal.date(from: DateComponents(year: 2026, month: 5, day: 30))!
        let rule = RecurrenceRule(frequency: .daily)
        let next = rule.nextOccurrence(after: reference, calendar: cal)
        XCTAssertEqual(next, cal.date(from: DateComponents(year: 2026, month: 5, day: 31)))
    }

    func test_nextOccurrence_weekdaysSkipsWeekend() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Friday 2026-05-29 → next weekday is Monday 2026-06-01.
        let friday = cal.date(from: DateComponents(year: 2026, month: 5, day: 29))!
        let rule = RecurrenceRule(frequency: .weekdays)
        let next = rule.nextOccurrence(after: friday, calendar: cal)
        XCTAssertEqual(next, cal.date(from: DateComponents(year: 2026, month: 6, day: 1)))
    }

    func test_nextOccurrence_weeklyOnFriday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Saturday 2026-05-30 → next Friday is 2026-06-05.
        let saturday = cal.date(from: DateComponents(year: 2026, month: 5, day: 30))!
        let rule = RecurrenceRule(frequency: .weekly, weekday: 6)
        let next = rule.nextOccurrence(after: saturday, calendar: cal)
        XCTAssertEqual(next, cal.date(from: DateComponents(year: 2026, month: 6, day: 5)))
    }

    func test_nextOccurrence_noneReturnsNil() {
        XCTAssertNil(RecurrenceRule.none.nextOccurrence(after: .now))
    }
}
