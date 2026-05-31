//
// CheckpointPolicyTests.swift
//
// Covers the centralized checkpoint cadence that keeps Moti calm: sparse
// default pacing moments (25/50/75/100), reduced cadence for short tasks
// (50/100), and completion-only for recurring habits (100).
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class CheckpointPolicyTests: XCTestCase {

    private let twoHours: TimeInterval = 2 * 60 * 60
    private let oneHour: TimeInterval = 60 * 60

    // MARK: - Standard default

    func test_standardTask_usesQuarterHalfThreeQuarterDone() {
        let cps = CheckpointPolicy.checkpoints(duration: twoHours, isRecurring: false)
        XCTAssertEqual(cps, [0.25, 0.5, 0.75, 1.0])
    }

    func test_standardTask_endsAtCompletionNotNinety() {
        let cps = CheckpointPolicy.checkpoints(duration: twoHours, isRecurring: false)
        XCTAssertEqual(cps.last, 1.0)
        XCTAssertFalse(cps.contains(0.9)) // the old dense 90% sample is gone
    }

    // MARK: - Short tasks (< 90 minutes)

    func test_shortTask_usesHalfAndDoneOnly() {
        let cps = CheckpointPolicy.checkpoints(duration: oneHour, isRecurring: false)
        XCTAssertEqual(cps, [0.5, 1.0])
    }

    func test_exactlyNinetyMinutes_isStandard_notShort() {
        // The threshold is exclusive: 90 minutes still gets the full cadence.
        let cps = CheckpointPolicy.checkpoints(duration: CheckpointPolicy.shortTaskThreshold, isRecurring: false)
        XCTAssertEqual(cps, [0.25, 0.5, 0.75, 1.0])
    }

    func test_justUnderNinetyMinutes_isShort() {
        let cps = CheckpointPolicy.checkpoints(duration: CheckpointPolicy.shortTaskThreshold - 1, isRecurring: false)
        XCTAssertEqual(cps, [0.5, 1.0])
    }

    // MARK: - Recurring habits

    func test_recurringHabit_usesCompletionOnly() {
        let cps = CheckpointPolicy.checkpoints(duration: twoHours, isRecurring: true)
        XCTAssertEqual(cps, [1.0])
    }

    func test_recurringWins_evenForShortDuration() {
        let cps = CheckpointPolicy.checkpoints(duration: oneHour, isRecurring: true)
        XCTAssertEqual(cps, [1.0])
    }

    // MARK: - Degenerate input

    func test_zeroDuration_fallsBackToStandard() {
        let cps = CheckpointPolicy.checkpoints(duration: 0, isRecurring: false)
        XCTAssertEqual(cps, [0.25, 0.5, 0.75, 1.0])
    }

    // MARK: - WorkSession derives from the policy

    func test_workSession_standardLength_derivesStandardCheckpoints() {
        let start = Date()
        let session = WorkSession(
            workItemID: UUID(),
            startTime: start,
            expectedEndTime: start.addingTimeInterval(twoHours)
        )
        XCTAssertEqual(session.checkpointProgress, [0.25, 0.5, 0.75, 1.0])
    }

    func test_workSession_shortLength_derivesReducedCheckpoints() {
        let start = Date()
        let session = WorkSession(
            workItemID: UUID(),
            startTime: start,
            expectedEndTime: start.addingTimeInterval(oneHour)
        )
        XCTAssertEqual(session.checkpointProgress, [0.5, 1.0])
    }

    func test_workSession_recurring_derivesCompletionOnly() {
        let start = Date()
        let session = WorkSession(
            workItemID: UUID(),
            startTime: start,
            expectedEndTime: start.addingTimeInterval(twoHours),
            isRecurring: true
        )
        XCTAssertEqual(session.checkpointProgress, [1.0])
    }
}
