//
// FallbackHonestyTests.swift
//
// Step 4 (fallback honesty): when Smart Capture can't use the full intelligence
// path and degrades to a weaker tier, the result must carry an honest
// `intelligenceSource` marker instead of silently posing as full AI. Also
// covers the deterministic fallback preserving multi-deadline structure, and
// proves normal deterministic task creation is unchanged.
//

import XCTest
@testable import Moti

/// A URLSession protocol stub that fails every request — simulates a Gemini /
/// proxy network outage deterministically, with no real network.
private final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// A fallback service that returns a fixed, pre-stamped decision so a test can
/// prove the upper tier passed it through without overwriting its marker.
private struct StubAgent: ContextualCaptureAgentService {
    let decision: ContextualCaptureDecision
    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision { decision }
}

final class FallbackHonestyTests: XCTestCase {

    private func context(
        _ raw: String,
        clarification: ClarificationState? = nil,
        signals: [SmartCaptureTimeSignal] = [],
        depth: PlanningDepth = .structured
    ) -> SmartCaptureContext {
        SmartCaptureContext(
            rawInput: raw,
            currentDate: Date(timeIntervalSince1970: 1_801_267_200),
            timezone: TimeZone(identifier: "America/Los_Angeles")!,
            currentScreen: "QuickCapture",
            clarificationState: clarification,
            timeSignals: signals,
            planningDepth: depth
        )
    }

    private func failingGeminiSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Gemini / proxy failure → honest fallback marker

    func test_geminiFailure_passesFallbackMarkerThrough_neverClaimsFullLLM() async throws {
        // The fallback returns an on-device-stamped decision; Gemini must pass it
        // through unchanged on failure, NOT relabel it `.fullLLM`.
        let onDeviceDecision = ContextualCaptureDecision(
            inputCompleteness: .actionableTask, intentType: .createTask,
            confidence: 0.8, isActionable: true, needsClarification: false,
            proposedTask: ProposedTask(title: "Email Caleb", projectId: nil, timeExpression: "tomorrow", rationale: ""),
            intelligenceSource: .onDevice
        )
        let gemini = GeminiContextualCaptureService(
            transport: .direct(apiKey: "test-key"),
            fallback: StubAgent(decision: onDeviceDecision),
            session: failingGeminiSession()
        )
        let result = try await gemini.analyze(context("email Caleb tomorrow"))
        XCTAssertEqual(result.intelligenceSource, .onDevice,
                       "a remote failure must not be relabeled as full-LLM success")
    }

    func test_geminiFailure_fallsBackToRuleBased_marksDeterministic() async throws {
        // The realistic silent-degradation case: Gemini down, real rule-based
        // fallback produces a confident-looking result — which must read
        // `.deterministic`, not pose as AI.
        let gemini = GeminiContextualCaptureService(
            transport: .direct(apiKey: "test-key"),
            fallback: RuleBasedContextualCaptureService(),
            session: failingGeminiSession()
        )
        let result = try await gemini.analyze(context("email Caleb tomorrow", depth: .none))
        XCTAssertEqual(result.intelligenceSource, .deterministic)
        XCTAssertFalse(result.intelligenceSource.isModelBacked)
    }

    // MARK: - Stamping semantics

    func test_stampedHelper_confidentResultKeepsProvenance() {
        let confident = ContextualCaptureDecision(
            inputCompleteness: .actionableTask, intentType: .createTask,
            confidence: 0.9, isActionable: true, needsClarification: false,
            proposedTask: ProposedTask(title: "x", projectId: nil, timeExpression: nil, rationale: "")
        )
        XCTAssertEqual(confident.stamped(provenance: .fullLLM).intelligenceSource, .fullLLM)
        XCTAssertEqual(confident.stamped(provenance: .onDevice).intelligenceSource, .onDevice)
    }

    func test_stampedHelper_clarificationOverridesProvenance() {
        let asking = ContextualCaptureDecision(
            inputCompleteness: .vagueTask, intentType: .unknown,
            confidence: 0.4, isActionable: false, needsClarification: true,
            clarificationQuestion: ClarificationQuestion(question: "?", choices: [], allowsFreeformAnswer: true)
        )
        // Even when the full LLM produced it, an asking-for-clarification result
        // is honestly marked as such — it isn't a finished plan.
        XCTAssertEqual(asking.stamped(provenance: .fullLLM).intelligenceSource, .clarificationNeeded)
        XCTAssertEqual(asking.stamped(provenance: .deterministic).intelligenceSource, .clarificationNeeded)
    }

    func test_decisionDefault_neverOverclaimsAI() {
        let bare = ContextualCaptureDecision(
            inputCompleteness: .actionableTask, intentType: .createTask,
            confidence: 0.9, isActionable: true, needsClarification: false
        )
        XCTAssertEqual(bare.intelligenceSource, .deterministic,
                       "an unstamped decision must default to the lowest, non-AI provenance")
    }

    // MARK: - Rule-based service stamps itself honestly

    func test_ruleBased_confidentTask_marksDeterministic() async throws {
        let service = RuleBasedContextualCaptureService()
        let result = try await service.analyze(context("finish the report by Friday", depth: .none))
        XCTAssertFalse(result.needsClarification)
        XCTAssertEqual(result.intelligenceSource, .deterministic)
    }

    func test_ruleBased_vagueInput_marksClarificationNeeded() async throws {
        let service = RuleBasedContextualCaptureService()
        let result = try await service.analyze(context("portfolio", depth: .none))
        XCTAssertTrue(result.needsClarification)
        XCTAssertEqual(result.intelligenceSource, .clarificationNeeded)
    }

    // MARK: - Deterministic fallback preserves extracted structure

    func test_fallbackWorkspace_preservesEveryDeadline() async throws {
        // Reached via the clarification-continuation planning path with a
        // multi-deadline capture. The deterministic plan must keep one target
        // per deliverable, each with its own deadline — not collapse to one.
        let raw = "finish my portfolio by June 25, apply to 5 jobs by June 18, and prepare slides by June 20"
        let clar = ClarificationState(
            previousInput: raw,
            previousQuestion: ClarificationQuestion(question: "Goal?", choices: [], allowsFreeformAnswer: true),
            userAnswer: "plan it out"
        )
        let service = RuleBasedContextualCaptureService()
        let result = try await service.analyze(context(raw, clarification: clar))

        let workspace = try XCTUnwrap(result.proposedWorkspace)
        XCTAssertEqual(workspace.targets.count, 3, "every deliverable is preserved as its own target")
        let expressions = workspace.targets.compactMap(\.dueTimeExpression)
        XCTAssertEqual(expressions.count, 3, "each target keeps its own deadline")
        XCTAssertEqual(Set(expressions).count, 3, "deadlines are distinct, not merged")
        XCTAssertEqual(result.intelligenceSource, .deterministic,
                       "the richer plan is still honestly marked as the quick path")
    }

    func test_fallbackWorkspace_singleDeliverable_keepsLightweightShape() async throws {
        let raw = "I need to finish MOTI v2.1 in 15 days, help me plan it out"
        let clar = ClarificationState(
            previousInput: raw,
            previousQuestion: ClarificationQuestion(question: "Goal?", choices: [], allowsFreeformAnswer: true),
            userAnswer: "A review-ready v2.1 build"
        )
        let service = RuleBasedContextualCaptureService()
        let result = try await service.analyze(context(raw, clarification: clar))
        let workspace = try XCTUnwrap(result.proposedWorkspace)
        XCTAssertEqual(workspace.targets.count, 1, "a single deliverable stays one target (unchanged shape)")
        XCTAssertFalse(result.needsClarification)
        XCTAssertEqual(result.intelligenceSource, .deterministic)
    }

    // MARK: - Normal deterministic task creation is unaffected

    func test_normalDeterministicTask_stillCreatesCleanly() async throws {
        let parser = RuleBasedTaskUnderstandingService()
        let item = try await parser.parse("Buy coffee beans tomorrow")
        XCTAssertFalse(item.needsReview, "a clear dated task is not pushed to review")
        XCTAssertNotNil(item.dueDate)
        XCTAssertEqual(item.title, "Buy coffee beans")
    }

    func test_intelligenceSource_labelsAreCalm() {
        // No label should read as an error / failure to the user.
        for source in [IntelligenceSource.fullLLM, .onDevice, .deterministic, .clarificationNeeded] {
            XCTAssertFalse(source.displayLabel.isEmpty)
            XCTAssertFalse(source.displayLabel.localizedCaseInsensitiveContains("fail"))
            XCTAssertFalse(source.displayLabel.localizedCaseInsensitiveContains("error"))
        }
    }
}
