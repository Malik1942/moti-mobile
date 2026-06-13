//
// RefinementLoopTests.swift
//
// Step 5 (refinement-loop hardening): refining a generated plan must preserve
// the original intent, the previous plan's targets/deadlines/assumptions, and
// the intelligence source — instead of restarting understanding from scratch.
// Clarification rounds are capped so the agent can't interrogate forever.
//

import XCTest
@testable import Moti

final class RefinementLoopTests: XCTestCase {

    private func context(
        _ raw: String,
        clarification: ClarificationState? = nil,
        refinement: PlanRefinementRequest? = nil,
        round: Int = 0,
        depth: PlanningDepth = .structured
    ) -> SmartCaptureContext {
        SmartCaptureContext(
            rawInput: raw,
            currentDate: Date(timeIntervalSince1970: 1_801_267_200),
            timezone: TimeZone(identifier: "America/Los_Angeles")!,
            currentScreen: "QuickCapture",
            clarificationState: clarification,
            planRefinement: refinement,
            clarificationRound: round,
            planningDepth: depth
        )
    }

    private func clarification(_ original: String, answer: String) -> ClarificationState {
        ClarificationState(
            previousInput: original,
            previousQuestion: ClarificationQuestion(question: "What's the goal?", choices: [], allowsFreeformAnswer: true),
            userAnswer: answer
        )
    }

    private func sampleWorkspace() -> PlanningWorkspace {
        PlanningWorkspace(
            title: "App launch",
            summary: "Ship the v1 app.",
            targets: [
                PlanningTarget(
                    title: "TestFlight build",
                    dueTimeExpression: "next Friday",
                    sourceTextSpan: "TestFlight ready by next Friday",
                    phases: [TaskPhase(title: "Build", purpose: "Get a build out",
                                       tasks: [PlannedTask(title: "Archive and upload", timeExpression: "next Friday")])]
                )
            ],
            assumptions: ["Solo developer, evenings only"]
        )
    }

    // MARK: - Stable original-capture text (fixes the dead-code recovery)

    func test_refinementOriginalText_prefersStableSnapshotOverLiveField() {
        XCTAssertEqual(
            RefinementOriginalText.resolve(stored: "Plan my app launch", liveInput: "totally different edit"),
            "Plan my app launch",
            "the stable snapshot must win over a since-edited live field"
        )
    }

    func test_refinementOriginalText_fallsBackToLiveFieldWhenNoSnapshot() {
        XCTAssertEqual(
            RefinementOriginalText.resolve(stored: "   ", liveInput: "live text"),
            "live text"
        )
    }

    // MARK: - Refinement prompt preserves the previous plan

    func test_refinementPrompt_preservesOriginalTargetsDeadlinesAndHistory() {
        let workspace = sampleWorkspace()
        let refinement = PlanRefinementRequest(
            originalInput: "Help me plan my app launch. I need TestFlight ready by next Friday.",
            previousWorkspace: workspace,
            feedback: "make this less intense",
            history: [PlanRefinementHistoryItem(feedback: "add screenshots", summaryOfChange: "Added a screenshots target")]
        )
        let prompt = SmartCapturePromptBuilder.userPrompt(for: context("Help me plan my app launch.", refinement: refinement))

        XCTAssertTrue(prompt.contains("Help me plan my app launch"), "original input preserved")
        XCTAssertTrue(prompt.contains("TestFlight build"), "previous target preserved")
        XCTAssertTrue(prompt.contains("next Friday"), "previous deadline preserved")
        XCTAssertTrue(prompt.contains("Solo developer, evenings only"), "previous assumptions preserved")
        XCTAssertTrue(prompt.contains("add screenshots"), "earlier refinement history preserved")
        XCTAssertTrue(prompt.contains("make this less intense"), "current feedback present")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("Preserve all existing"),
                      "instructs modify-not-restart")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("not as a new raw task"),
                      "feedback treated as a command, not a fresh capture")
    }

    // MARK: - Clarification cap

    func test_belowCap_canStillAskClarification() async throws {
        let service = RuleBasedContextualCaptureService()
        // Round 1 (< cap) with a vague short input still asks.
        let result = try await service.analyze(context("portfolio", round: 1, depth: .none))
        XCTAssertTrue(result.needsClarification, "below the cap the agent may still ask")
    }

    func test_atCap_stopsAskingAndProceeds_planning() async throws {
        let service = RuleBasedContextualCaptureService()
        let clar = clarification("Plan my thesis defense", answer: "in two weeks")
        let result = try await service.analyze(
            context("Plan my thesis defense", clarification: clar, round: 2, depth: .structured)
        )
        XCTAssertFalse(result.needsClarification, "at the cap the agent must not ask again")
        XCTAssertNotNil(result.proposedWorkspace, "it proceeds with a plan instead")
    }

    func test_atCap_recordsAssumptionThatItProceeded() async throws {
        let service = RuleBasedContextualCaptureService()
        let clar = clarification("Plan my thesis defense", answer: "soon")
        let result = try await service.analyze(
            context("Plan my thesis defense", clarification: clar, round: 2, depth: .structured)
        )
        let workspace = try XCTUnwrap(result.proposedWorkspace)
        XCTAssertTrue(
            workspace.assumptions.contains { $0.localizedCaseInsensitiveContains("proceeded") },
            "post-cap assumptions are recorded in the existing assumptions model"
        )
    }

    func test_atCap_nonPlanning_proceedsWithTaskNotQuestion() async throws {
        let service = RuleBasedContextualCaptureService()
        let clar = clarification("email Caleb", answer: "tomorrow")
        let result = try await service.analyze(
            context("email Caleb tomorrow", clarification: clar, round: 2, depth: .none)
        )
        XCTAssertFalse(result.needsClarification)
        XCTAssertNotNil(result.proposedTask)
        XCTAssertNotNil(result.safetyNote, "records that it proceeded on assumptions")
    }

    func test_promptBuilder_capInstruction_tellsModelToStopAsking() {
        let clar = clarification("Plan my launch", answer: "next month")
        let prompt = SmartCapturePromptBuilder.userPrompt(
            for: context("Plan my launch", clarification: clar, round: 2)
        )
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("Do NOT ask another question"),
                      "the LLM is told to stop asking once the budget is spent")
    }

    func test_promptBuilder_belowCap_doesNotForceStop() {
        let clar = clarification("Plan my launch", answer: "next month")
        let prompt = SmartCapturePromptBuilder.userPrompt(
            for: context("Plan my launch", clarification: clar, round: 1)
        )
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("Do NOT ask another question"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("Never stop after recording the answer"))
    }

    func test_clarificationBudgetExhausted_flag() {
        XCTAssertFalse(context("x", round: 0).clarificationBudgetExhausted)
        XCTAssertFalse(context("x", round: 1).clarificationBudgetExhausted)
        XCTAssertTrue(context("x", round: 2).clarificationBudgetExhausted)
        XCTAssertTrue(context("x", round: 3).clarificationBudgetExhausted)
        XCTAssertEqual(SmartCaptureContext.maxClarificationRounds, 2)
    }

    // MARK: - Intelligence source preserved through refinement

    func test_deterministicRefinement_preservesPlanAndStampsHonestly() async throws {
        let service = RuleBasedContextualCaptureService()
        let refinement = PlanRefinementRequest(
            originalInput: "Plan my app launch",
            previousWorkspace: sampleWorkspace(),
            feedback: "make this less intense"
        )
        let result = try await service.analyze(context("Plan my app launch", refinement: refinement))

        // The deterministic path can't rewrite the plan, so it must PRESERVE it
        // (never restart from the short feedback) and stay honestly stamped.
        let workspace = try XCTUnwrap(result.proposedWorkspace)
        XCTAssertEqual(workspace.targets.map(\.title), ["TestFlight build"], "targets preserved")
        XCTAssertEqual(workspace.targets.first?.dueTimeExpression, "next Friday", "deadline preserved")
        XCTAssertTrue(workspace.assumptions.contains("Solo developer, evenings only"), "assumptions preserved")
        XCTAssertEqual(workspace.refinementHistory.last?.feedback, "make this less intense", "feedback recorded in history")
        XCTAssertFalse(result.needsClarification, "refinement is not treated as a fresh, under-specified capture")
        XCTAssertEqual(result.intelligenceSource, .deterministic, "honestly marked — not faked AI, not dropped")
        XCTAssertFalse(result.intelligenceSource.isModelBacked)
    }
}
