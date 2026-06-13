//
// PlanningIntentTests.swift
//
// Covers the semantic planning-intent layer that replaced brittle keyword
// equality: PlanningIntentDetector (none/mild/explicit) and the classifier
// depth it drives. The goal is reliable planning-intent detection that still
// preserves the anti-overplanning default for plain captures.
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class PlanningIntentTests: XCTestCase {

    // MARK: - Detector: the three levels

    func test_plainTask_isNone() {
        XCTAssertEqual(PlanningIntentDetector.detect("buy milk tomorrow"), .none)
    }

    func test_deadlinePressure_isMild() {
        XCTAssertEqual(PlanningIntentDetector.detect("I need to finish this before Friday"), .mild)
    }

    func test_explicitAsk_isExplicit() {
        XCTAssertEqual(PlanningIntentDetector.detect("help me plan this out"), .explicit)
    }

    // MARK: - Detector: the previously-missed inputs (the regression)

    func test_regressedInputs_allDetectExplicit() {
        let inputs = [
            "help me planning out the timeline",
            "plan this out",
            "organize this before July 1",
            "help me structure this",
            "make a timeline for this",
            "break this down into steps",
            "break it down",
            "plan for me",
            "I need to finish MOTI v2.1 in 15 days, help me plan it out",
            "I need to finish MOTI v2.1 before June 25, help me planning it out",
            "map out my week",
            "come up with a plan for the launch",
            "build a roadmap for this"
        ]
        for input in inputs {
            XCTAssertEqual(PlanningIntentDetector.detect(input), .explicit, "Expected explicit for: \(input)")
        }
    }

    // MARK: - Detector: must NOT false-positive on look-alike words

    func test_lookAlikeWords_areNotPlanning() {
        // Token matching, not substring: "plant"/"plane"/"organic" must not fire,
        // and "timeline" without a planning verb is the app's tab, not an ask.
        let nonPlanning = [
            "water the plant tomorrow",
            "buy a plane ticket",
            "pick up organic groceries",
            "add this to my timeline",
            "scan LinkedIn every day"
        ]
        for input in nonPlanning {
            XCTAssertNotEqual(PlanningIntentDetector.detect(input), .explicit, "Should not be explicit: \(input)")
        }
    }

    // MARK: - Classifier: explicit intent unlocks structured planning

    func test_classifier_helpMePlanThisOut_isStructured() {
        let d = PlanningClassifier.classify(rawInput: "help me plan this out")
        XCTAssertEqual(d.inputType, .complexPlanning)
        XCTAssertEqual(d.planningDepth, .structured)
        XCTAssertTrue(d.shouldUseLLM)
        XCTAssertTrue(d.shouldGeneratePlan)
        XCTAssertTrue(d.shouldCreateSubtasks)
    }

    func test_classifier_makeATimeline_isStructured() {
        let d = PlanningClassifier.classify(rawInput: "make a timeline for this")
        XCTAssertEqual(d.planningDepth, .structured)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    func test_classifier_organizeBeforeDate_isStructured() {
        let d = PlanningClassifier.classify(rawInput: "organize this before July 1")
        XCTAssertEqual(d.planningDepth, .structured)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    func test_classifier_explicitPlanRequest_generatesAPlan() {
        // Explicit ask → a real plan with subtasks (structured here; deep when
        // the scope is also project-scale like "ship beta version by June").
        let d = PlanningClassifier.classify(rawInput: "help me plan out job hunting before July 1")
        XCTAssertTrue(d.shouldGeneratePlan)
        XCTAssertTrue(d.shouldCreateSubtasks)
        XCTAssertTrue(d.planningDepth == .structured || d.planningDepth == .deep)
    }

    func test_classifier_projectWithRelativeDeadlineAndPlanAsk_generatesPlan() {
        let d = PlanningClassifier.classify(rawInput: "I need to finish MOTI v2.1 in 15 days, help me plan it out")
        XCTAssertEqual(d.inputType, .complexPlanning)
        XCTAssertTrue(d.shouldUseLLM)
        XCTAssertTrue(d.shouldGeneratePlan)
        XCTAssertTrue(d.shouldCreateSubtasks)
    }

    func test_classifier_projectWithNamedDateAndPlanAsk_generatesPlan() {
        let d = PlanningClassifier.classify(rawInput: "I need to finish MOTI v2.1 before June 25, help me plan it out")
        XCTAssertEqual(d.inputType, .complexPlanning)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    func test_classifier_projectScalePlanRequest_isDeep() {
        let d = PlanningClassifier.classify(rawInput: "help me plan the beta version launch")
        XCTAssertEqual(d.planningDepth, .deep)
        XCTAssertTrue(d.shouldGeneratePlan)
    }

    // MARK: - Classifier: anti-overplanning preserved

    func test_classifier_plainTask_staysAtomic() {
        let d = PlanningClassifier.classify(rawInput: "buy milk tomorrow")
        XCTAssertEqual(d.planningDepth, .none)
        XCTAssertFalse(d.shouldGeneratePlan)
        XCTAssertFalse(d.shouldUseLLM)
    }

    func test_classifier_mildDeadline_staysSingleTask() {
        // Time pressure alone must NOT trigger a plan.
        let d = PlanningClassifier.classify(rawInput: "I need to finish the report before Friday")
        XCTAssertEqual(d.planningDepth, .none)
        XCTAssertFalse(d.shouldGeneratePlan)
    }

    func test_classifier_recurringHabit_staysLightweight() {
        let d = PlanningClassifier.classify(rawInput: "scan LinkedIn every day")
        XCTAssertEqual(d.inputType, .recurringTask)
        XCTAssertEqual(d.planningDepth, .lightweight)
        XCTAssertFalse(d.shouldCreateSubtasks)
    }
}
