//
// PlanningClassifierTests.swift
//
// Covers Stage 1 of the two-stage intelligence flow — the deterministic
// `PlanningClassifier` that decides whether deep LLM planning runs at all.
//
// NOTE: the Moti project has no active unit-test target yet (see the other
// files in MotiTests/). This file is therefore not compiled by xcodebuild
// today; it documents the expected classification behavior as runnable XCTest
// methods that will work as-is once a test target is added with
// `@testable import Moti`.
//

import XCTest
@testable import Moti

final class PlanningClassifierTests: XCTestCase {

    // MARK: Atomic / simple — must NOT plan or decompose

    func test_atomicTaskWithDueDate_createsDirectly() {
        let d = PlanningClassifier.classify(rawInput: "Email Andre my portfolio link tonight")
        XCTAssertEqual(d.inputType, .atomicTask)
        XCTAssertFalse(d.shouldUseLLM)
        XCTAssertFalse(d.shouldGeneratePlan)
        XCTAssertFalse(d.shouldCreateSubtasks)
    }

    func test_submitByFriday_isAtomic_notMultiDeadline() {
        let d = PlanningClassifier.classify(rawInput: "Submit the final PDF by Friday")
        // "by Friday" is ONE deadline anchor — must not be read as multi-deadline.
        XCTAssertEqual(d.inputType, .atomicTask)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    func test_simpleTaskNoDate_createsDirectly() {
        let d = PlanningClassifier.classify(rawInput: "Upload screenshots to App Store Connect")
        XCTAssertEqual(d.inputType, .simpleTask)
        XCTAssertFalse(d.shouldUseLLM)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    // MARK: Reminder / status / note

    func test_reminder() {
        let d = PlanningClassifier.classify(rawInput: "Remind me to renew my visa")
        XCTAssertEqual(d.inputType, .reminder)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    func test_statusUpdate() {
        let d = PlanningClassifier.classify(rawInput: "Finished the research section already")
        XCTAssertEqual(d.inputType, .statusUpdate)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    func test_projectNote_doesNotBecomeAPlan() {
        let d = PlanningClassifier.classify(rawInput: "Aura should focus on anticipation, not symptom relief")
        XCTAssertEqual(d.inputType, .projectNote)
        XCTAssertTrue(d.shouldUseLLM)        // LLM extracts context
        XCTAssertFalse(d.shouldGeneratePlan) // but does not plan
    }

    // MARK: Planning paths

    func test_explicitPlanRequest_generatesPlan() {
        let d = PlanningClassifier.classify(rawInput: "Plan my Moti launch next week")
        XCTAssertEqual(d.inputType, .complexPlanning)
        XCTAssertTrue(d.shouldUseLLM)
        XCTAssertTrue(d.shouldGeneratePlan)
        XCTAssertTrue(d.shouldCreateSubtasks)
    }

    func test_twoDeadlines_isMultiDeadlinePlanning() {
        let d = PlanningClassifier.classify(
            rawInput: "Research proposal due Friday and presentation due next Tuesday"
        )
        XCTAssertEqual(d.inputType, .multiDeadlinePlanning)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    func test_threeDeadlines_isMultiDeadlinePlanning() {
        let d = PlanningClassifier.classify(rawInput: "Report Friday, slides Monday, demo next Wednesday")
        XCTAssertEqual(d.inputType, .multiDeadlinePlanning)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    func test_refinement_revisesNotRestarts() {
        let d = PlanningClassifier.classify(rawInput: "make it fit into 3 days", isRefinement: true)
        XCTAssertEqual(d.inputType, .refinementRequest)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    func test_vagueInput_asksClarification() {
        let d = PlanningClassifier.classify(rawInput: "portfolio")
        XCTAssertEqual(d.inputType, .unclear)
        XCTAssertTrue(d.shouldAskForClarification)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    // MARK: - Integration cases to verify manually (context builder, not classifier)
    //
    // These exercise SmartCaptureContext / SmartCapturePromptBuilder rather than
    // the classifier, so they're documented here as manual checks:
    //
    // 1. Overdue project tasks appear in the prompt under "Overdue work
    //    (reschedule rather than recreate)" — ask for a plan with an overdue
    //    item present and confirm the LLM reschedules instead of duplicating.
    // 2. Completed tasks appear under "Recently completed (do not re-plan)" and
    //    are NOT reintroduced into a new plan.
    // 3. Skipped tasks appear under "Intentionally skipped" and are not
    //    reintroduced.
    // 4. A project note routes to context extraction (ProjectContextPreviewCard),
    //    never a task plan.
}
