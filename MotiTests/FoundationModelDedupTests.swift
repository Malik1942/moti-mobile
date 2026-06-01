//
// FoundationModelDedupTests.swift
//
// Covers the deterministic duplicate/normalization layer that Foundation Model
// mode routes its output through. FM occasionally splits one capture into a
// bare task plus a temporal twin (e.g. "finish video filming" + "finish video
// filming before 3:45") or returns the same item twice; this layer collapses
// those into one richer task.
//
// Product rule under test: a temporal phrase enriches ONE task — it must never
// create a second.
//
// These exercise `[ParsedWorkItem].deduplicatedMergingVariants()` and the
// title normalization (`DateResolver.removingDatePhrases` /
// `RuleBasedTaskUnderstandingService.normalizedTitle`) directly, with fixtures
// that mirror what the model returns — so the behavior is verified without an
// on-device model.
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class FoundationModelDedupTests: XCTestCase {

    private let cal = Calendar.current
    // A single reference instant for the whole test case so a date built for a
    // fixture (e.g. `days(3)`) is exactly equal to the same expression used in an
    // assertion. Calling `.now` at each site drifts by sub-seconds and makes the
    // `dueDate` equality checks flaky even though the dedup logic is correct.
    private let now = Date()
    private func today(_ h: Int, _ m: Int) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: now)!
    }
    private func days(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: now)!
    }

    private func parsed(
        _ title: String,
        project: String? = nil,
        due: Date? = nil,
        start: Date? = nil,
        end: Date? = nil,
        intent: WorkItemTemporalIntent = .deadline,
        needsReview: Bool = false,
        confidence: Double = 0.8
    ) -> ParsedWorkItem {
        ParsedWorkItem(
            rawInput: title,
            title: title,
            projectGuess: project,
            temporalIntent: intent,
            dueDate: due,
            workingStartDate: start,
            workingEndDate: end,
            suggestedSessions: [],
            estimatedEffort: nil,
            parserConfidence: confidence,
            needsReview: needsReview,
            reviewReason: needsReview ? "Missing time information" : nil,
            parserExplanation: ""
        )
    }

    // MARK: - The headline bug

    func test_videoFilming_temporalTwin_collapsesToOneRichTask() {
        // What FM returns for "finish video filming before 3:45 today":
        let bare = parsed("Finish video filming", due: nil, intent: .noTime, needsReview: true)
        let rich = parsed("Finish video filming before 3:45", due: today(15, 45), intent: .deadline)

        let result = [bare, rich].deduplicatedMergingVariants()

        XCTAssertEqual(result.count, 1, "A temporal phrase must enrich one task, not create a second.")
        XCTAssertEqual(result[0].title, "Finish video filming", "Surviving title is the clean core, no temporal residue.")
        XCTAssertEqual(result[0].dueDate, today(15, 45), "Keeps the extracted due time.")
        XCTAssertFalse(result[0].needsReview, "A placeable twin rescues the bare one from review.")
    }

    func test_videoFilming_orderIndependent() {
        let bare = parsed("Finish video filming", due: nil, intent: .noTime, needsReview: true)
        let rich = parsed("Finish video filming before 3:45", due: today(15, 45))
        // Rich first, bare second — still one rich task.
        let result = [rich, bare].deduplicatedMergingVariants()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Finish video filming")
        XCTAssertEqual(result[0].dueDate, today(15, 45))
    }

    // MARK: - The required input set

    func test_submitPortfolioByFriday_twinCollapses() {
        let bare = parsed("Submit portfolio", project: "Portfolio", due: nil, intent: .noTime, needsReview: true)
        let rich = parsed("Submit portfolio before Friday", project: "Portfolio", due: days(3))
        let result = [bare, rich].deduplicatedMergingVariants()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Submit portfolio")
        XCTAssertEqual(result[0].dueDate, days(3))
    }

    func test_reviewResumeTomorrowAtFive_twinCollapses() {
        let bare = parsed("Review resume", project: "Job Search", due: nil, intent: .noTime, needsReview: true)
        let rich = parsed("Review resume at 5", project: "Job Search", due: days(1))
        let result = [bare, rich].deduplicatedMergingVariants()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Review resume")
        XCTAssertEqual(result[0].dueDate, days(1))
    }

    func test_identicalModelOutputs_collapseToOne() {
        let a = parsed("Finish video filming", due: today(15, 45))
        let b = parsed("Finish video filming", due: today(15, 45))
        XCTAssertEqual([a, b].deduplicatedMergingVariants().count, 1)
    }

    func test_sameTaskWithAndWithoutTemporalPhrase_collapseToOne() {
        let withPhrase = parsed("Submit portfolio before Friday", project: "Portfolio", due: days(3))
        let without    = parsed("Submit portfolio", project: "Portfolio", due: nil, intent: .noTime, needsReview: true)
        let result = [withPhrase, without].deduplicatedMergingVariants()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].dueDate, days(3))
    }

    // MARK: - Must NOT over-merge distinct tasks

    func test_sameTitleDifferentConcreteDates_staySeparate() {
        // "call mom today" + "call mom tomorrow" are two real tasks.
        let todayTask    = parsed("Call mom", project: "Personal", due: today(18, 0))
        let tomorrowTask = parsed("Call mom", project: "Personal", due: days(1))
        let result = [todayTask, tomorrowTask].deduplicatedMergingVariants()
        XCTAssertEqual(result.count, 2, "Conflicting concrete due dates are distinct tasks, not variants.")
    }

    func test_differentTasks_staySeparate() {
        let email = parsed("Email Alice", project: "Job Search", due: days(1))
        let call  = parsed("Call Bob", project: "Job Search", due: days(1))
        XCTAssertEqual([email, call].deduplicatedMergingVariants().count, 2)
    }

    // MARK: - Title normalization strips colon/hour times (the root cause)

    func test_removingDatePhrases_stripsColonAndHourTimes() {
        // Case is preserved — only the temporal phrase is removed.
        XCTAssertEqual(DateResolver.removingDatePhrases(from: "Finish video filming before 3:45 today"), "Finish video filming")
        XCTAssertEqual(DateResolver.removingDatePhrases(from: "Review resume tomorrow at 5"), "Review resume")
        XCTAssertEqual(DateResolver.removingDatePhrases(from: "Submit portfolio by Friday"), "Submit portfolio")
    }

    func test_removingDatePhrases_leavesPlainNumbersAlone() {
        // No temporal lead-in → the number is part of the task, not a time.
        XCTAssertEqual(DateResolver.removingDatePhrases(from: "Apply to 3 roles"), "Apply to 3 roles")
        XCTAssertEqual(DateResolver.removingDatePhrases(from: "Finish 5 job applications"), "Finish 5 job applications")
    }

    func test_normalizedTitle_producesCleanCoreTitles() {
        XCTAssertEqual(RuleBasedTaskUnderstandingService.normalizedTitle(from: "finish video filming before 3:45 today"), "Finish video filming")
        XCTAssertEqual(RuleBasedTaskUnderstandingService.normalizedTitle(from: "review resume tomorrow at 5"), "Review resume")
    }
}
