//
// TrajectoryProjectorTests.swift
//
// Covers the forward trajectory projection (PRD §5.2, §8) — the hero of the
// redesign. Directional only (on-time / behind / fading / sustained); zero
// estimates; extrapolates ACTUAL behavior, never assumes scheduled work happens.
//
// Rules under test:
//   • achievement = progress-so-far vs time-elapsed → on-time / behind
//   • completed deadline passed & unfinished → behind; fully done → on-time
//   • no behavior yet → calm (on-time), never fabricate "behind"
//   • maintenance = drift/feeding as input → sustained / fading
//   • solid extent grows with recent-signal strength
//

import XCTest
@testable import Moti

final class TrajectoryProjectorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * day) }
    private func daysAhead(_ n: Double) -> Date { now.addingTimeInterval(n * day) }

    private func presence(_ state: PresenceState, reach: Double) -> StrandPresence {
        StrandPresence(state: state, reach: reach, lastActivity: nil,
                       daysSinceLastActivity: nil, baselineCadenceDays: 7, baselineSource: .recurrence)
    }

    private func someEvents(_ n: Int = 3) -> [StrandEvent] {
        (1...max(1, n)).map { StrandEvent(kind: .completed, date: daysAgo(Double($0) * 5)) }
    }

    // MARK: - Achievement

    func test_achievement_aheadOfPace_isOnTime() {
        // 60% done only 30% of the way through the time to deadline → on-time.
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .achievement, presence: presence(.active, reach: 0.9),
            deadline: daysAhead(70), completedCount: 6, totalCount: 10,
            firstActivity: daysAgo(30), now: now
        )
        XCTAssertEqual(p.outcome, .onTime)
        XCTAssertTrue(p.hasGoal)
        XCTAssertGreaterThanOrEqual(p.paceRatio ?? 0, 1.0)
    }

    func test_achievement_behindPace_isBehind() {
        // 20% done but 80% of the time gone → behind.
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .achievement, presence: presence(.quiet, reach: 0.3),
            deadline: daysAhead(10), completedCount: 2, totalCount: 10,
            firstActivity: daysAgo(40), now: now
        )
        XCTAssertEqual(p.outcome, .behind)
        XCTAssertLessThan(p.paceRatio ?? 1, 1.0)
    }

    func test_achievement_deadlinePassedUnfinished_isBehind() {
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .achievement, presence: presence(.quiet, reach: 0.3),
            deadline: daysAgo(2), completedCount: 5, totalCount: 10,
            firstActivity: daysAgo(40), now: now
        )
        XCTAssertEqual(p.outcome, .behind)
    }

    func test_achievement_fullyComplete_isOnTime() {
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .achievement, presence: presence(.active, reach: 0.9),
            deadline: daysAhead(5), completedCount: 10, totalCount: 10,
            firstActivity: daysAgo(20), now: now
        )
        XCTAssertEqual(p.outcome, .onTime)
        XCTAssertEqual(p.progressFraction, 1)
    }

    func test_achievement_noBehaviorYet_staysCalmOnTime_neverFabricatesBehind() {
        let p = TrajectoryProjector.project(
            events: [], type: .achievement, presence: presence(.quiet, reach: 0.5),
            deadline: daysAhead(20), completedCount: 0, totalCount: 5,
            firstActivity: nil, now: now
        )
        XCTAssertEqual(p.outcome, .onTime)
    }

    func test_achievementWithoutDeadline_fallsBackToMaintenanceRead() {
        // An override-forced achievement with no deadline can't land on a marker
        // → degrade to sustained/fading from feeding, not a crash or false behind.
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .achievement, presence: presence(.drifted, reach: 0),
            deadline: nil, completedCount: 1, totalCount: 4,
            firstActivity: daysAgo(20), now: now
        )
        XCTAssertEqual(p.outcome, .fading)
        XCTAssertFalse(p.hasGoal)
    }

    // MARK: - Maintenance

    func test_maintenance_activeRhythm_isSustained() {
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .maintenance, presence: presence(.active, reach: 0.9),
            deadline: nil, completedCount: 0, totalCount: 0,
            recurrenceCadenceDays: 7, firstActivity: daysAgo(20), now: now
        )
        XCTAssertEqual(p.outcome, .sustained)
        XCTAssertFalse(p.hasGoal)
    }

    func test_maintenance_drifted_isFading() {
        let p = TrajectoryProjector.project(
            events: someEvents(), type: .maintenance, presence: presence(.drifted, reach: 0),
            deadline: nil, completedCount: 0, totalCount: 0,
            recurrenceCadenceDays: 7, firstActivity: daysAgo(40), now: now
        )
        XCTAssertEqual(p.outcome, .fading)
    }

    func test_maintenance_quietBorderline_splitsOnReach() {
        let sustained = TrajectoryProjector.project(
            events: someEvents(), type: .maintenance, presence: presence(.quiet, reach: 0.5),
            deadline: nil, completedCount: 0, totalCount: 0, now: now)
        let fading = TrajectoryProjector.project(
            events: someEvents(), type: .maintenance, presence: presence(.quiet, reach: 0.2),
            deadline: nil, completedCount: 0, totalCount: 0, now: now)
        XCTAssertEqual(sustained.outcome, .sustained)
        XCTAssertEqual(fading.outcome, .fading)
    }

    // MARK: - Solid extent

    func test_solidFraction_growsWithRecentSignalStrength() {
        let strong = TrajectoryProjector.project(
            events: someEvents(), type: .maintenance, presence: presence(.active, reach: 0.95),
            deadline: nil, completedCount: 0, totalCount: 0, now: now)
        let weak = TrajectoryProjector.project(
            events: someEvents(), type: .maintenance, presence: presence(.drifted, reach: 0.0),
            deadline: nil, completedCount: 0, totalCount: 0, now: now)
        XCTAssertGreaterThan(strong.solidFraction, weak.solidFraction)
    }

    // MARK: - Attention

    func test_outcomeNeedsAttention_onlyForBehindAndFading() {
        XCTAssertTrue(TrajectoryOutcome.behind.needsAttention)
        XCTAssertTrue(TrajectoryOutcome.fading.needsAttention)
        XCTAssertFalse(TrajectoryOutcome.onTime.needsAttention)
        XCTAssertFalse(TrajectoryOutcome.sustained.needsAttention)
    }
}
