//
// GeminiSchemaTests.swift
//
// Guards the Gemini structured-output fix: the live `responseSchema` must stay
// flat enough for Gemini to accept (no deeply-nested object arrays, no
// `maxItems`), and the local flat→nested reconstruction must rebuild the
// PlanningWorkspace correctly. Deterministic — no network — so it runs in CI
// and prevents the HTTP 400 "too many states" regression from silently
// returning.
//

import XCTest
@testable import Moti

final class GeminiSchemaTests: XCTestCase {

    // MARK: - Schema-shape acceptance guard

    /// Deepest chain of array-of-object nesting in a JSON-schema node. The 2026
    /// HTTP 400 ("schema produces a constraint that has too many states") was
    /// caused by depth 3 (targets → phases → tasks). Gemini accepts the flat
    /// schema at depth 1.
    private func objectArrayDepth(_ node: Any) -> Int {
        guard let dict = node as? [String: Any] else { return 0 }
        let type = (dict["type"] as? String)?.uppercased()
        if type == "ARRAY", let items = dict["items"] as? [String: Any] {
            // An array of objects adds one level; recurse into the item object.
            let itemIsObject = (items["type"] as? String)?.uppercased() == "OBJECT"
            let inner = objectArrayDepth(items)
            return (itemIsObject ? 1 : 0) + inner
        }
        if type == "OBJECT", let props = dict["properties"] as? [String: Any] {
            return props.values.map { objectArrayDepth($0) }.max() ?? 0
        }
        return 0
    }

    private func containsKeyAnywhere(_ node: Any, key: String) -> Bool {
        if let dict = node as? [String: Any] {
            if dict[key] != nil { return true }
            return dict.values.contains { containsKeyAnywhere($0, key: key) }
        }
        if let arr = node as? [Any] {
            return arr.contains { containsKeyAnywhere($0, key: key) }
        }
        return false
    }

    func test_responseSchema_staysFlatEnoughForGemini() {
        let schema = GeminiContextualCaptureService.responseSchema
        XCTAssertLessThanOrEqual(
            objectArrayDepth(schema), 1,
            "Gemini rejects deeply-nested object arrays ('too many states'). Keep the workspace flat (planTargets + planTasks), not targets→phases→tasks."
        )
        XCTAssertFalse(
            containsKeyAnywhere(schema, key: "maxItems"),
            "`maxItems` on (especially nested) arrays inflates the constraint state count Gemini rejects — bound counts via the prompt instead."
        )
    }

    func test_responseSchema_isValidJSONAndHasFlatPlanArrays() throws {
        let schema = GeminiContextualCaptureService.responseSchema
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema), "schema must serialize for the request body")
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(props["planTargets"], "flat target metadata array")
        XCTAssertNotNil(props["planTasks"], "flat task array linked by targetTitle")
        XCTAssertNil(props["proposedWorkspace"], "the old nested workspace must be gone")
    }

    // MARK: - Flat → nested reconstruction

    private func draft(_ json: [String: Any]) throws -> GeminiCaptureDraft {
        var base: [String: Any] = [
            "inputCompleteness": "projectSeed", "intentType": "createProjectPlan",
            "confidence": 0.9, "isActionable": true, "needsClarification": false,
            "allowsFreeformAnswer": true
        ]
        base.merge(json) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: base)
        return try JSONDecoder().decode(GeminiCaptureDraft.self, from: data)
    }

    private func ctx() -> SmartCaptureContext {
        SmartCaptureContext(rawInput: "x", currentDate: Date(timeIntervalSince1970: 1_801_267_200),
                            timezone: .current, currentScreen: "QC")
    }

    func test_reconstruct_groupsFlatTasksIntoTargetsAndPhases() throws {
        let d = try draft([
            "workspaceTitle": "Launch",
            "planTargets": [
                ["title": "Prototype", "dueTimeExpression": "by Wednesday"],
                ["title": "Testing", "dueTimeExpression": "by Friday"]
            ],
            "planTasks": [
                ["targetTitle": "Prototype", "phaseTitle": "Build", "phasePurpose": "make it", "title": "Sketch UI"],
                ["targetTitle": "Prototype", "phaseTitle": "Build", "title": "Wire screens"],
                ["targetTitle": "Testing", "phaseTitle": "QA", "title": "Write test cases"]
            ]
        ])
        let ws = try XCTUnwrap(GeminiContextualCaptureService.reconstructWorkspace(from: d, context: ctx()))
        XCTAssertEqual(ws.targets.map(\.title), ["Prototype", "Testing"], "targets preserved in order")
        XCTAssertEqual(ws.targets[0].dueTimeExpression, "by Wednesday")
        XCTAssertEqual(ws.targets[1].dueTimeExpression, "by Friday")
        // Prototype: one "Build" phase with two tasks; Testing: one "QA" phase.
        XCTAssertEqual(ws.targets[0].phases.map(\.title), ["Build"])
        XCTAssertEqual(ws.targets[0].phases[0].tasks.map(\.title), ["Sketch UI", "Wire screens"])
        XCTAssertEqual(ws.targets[0].phases[0].purpose, "make it")
        XCTAssertEqual(ws.targets[1].phases[0].tasks.map(\.title), ["Write test cases"])
    }

    func test_reconstruct_synthesizesTargetForOrphanTask() throws {
        // A task naming a target with no planTargets entry must not be dropped.
        let d = try draft([
            "planTargets": [["title": "Known"]],
            "planTasks": [
                ["targetTitle": "Known", "title": "Do known thing"],
                ["targetTitle": "Surprise", "title": "Do surprise thing"]
            ]
        ])
        let ws = try XCTUnwrap(GeminiContextualCaptureService.reconstructWorkspace(from: d, context: ctx()))
        XCTAssertEqual(Set(ws.targets.map(\.title)), ["Known", "Surprise"])
        let surprise = try XCTUnwrap(ws.targets.first { $0.title == "Surprise" })
        XCTAssertEqual(surprise.phases.flatMap(\.tasks).map(\.title), ["Do surprise thing"])
    }

    func test_reconstruct_nilWhenNoPlanPresent() throws {
        let d = try draft(["proposedTaskTitle": "Email Caleb"])
        XCTAssertNil(GeminiContextualCaptureService.reconstructWorkspace(from: d, context: ctx()),
                     "a single-task / no-plan response must not fabricate a workspace")
    }

    func test_mapDecision_endToEnd_flatDraftBecomesNestedWorkspace() throws {
        let d = try draft([
            "workspaceTitle": "App Launch Plan",
            "extractedPlanningTargets": [["title": "App Launch", "dueTimeExpression": "before next Friday"]],
            "planTargets": [["title": "App Launch", "dueTimeExpression": "before next Friday"]],
            "planTasks": [
                ["targetTitle": "App Launch", "phaseTitle": "Prep", "title": "Finalize build"],
                ["targetTitle": "App Launch", "phaseTitle": "Prep", "title": "Prepare store assets"]
            ]
        ])
        let decision = GeminiContextualCaptureService.mapDecision(d, context: ctx())
        let ws = try XCTUnwrap(decision.proposedWorkspace)
        XCTAssertEqual(ws.title, "App Launch Plan")
        XCTAssertEqual(ws.targets.count, 1)
        XCTAssertEqual(ws.targets[0].phases[0].tasks.count, 2)
        // The dropped-target validation still works against the reconstruction.
        XCTAssertTrue(decision.missingExtractedTargets().isEmpty, "extracted target is represented in the workspace")
    }
}
