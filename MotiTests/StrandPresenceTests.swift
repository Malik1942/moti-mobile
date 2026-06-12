//
// StrandPresenceTests.swift
//
// Covers the pure, deterministic presence computation that powers the Lifelines
// Timeline: recency vs. each strand's OWN baseline cadence → {active|quiet|drifted}.
//
// The product rules under test (PRD §5.1, §8, §10):
//   • Reach-to-Now is the primary signal; drifted is the only non-reaching state.
//   • The active/quiet boundary is exactly one baseline interval of silence
//     (reach == 0.5), so position alone separates them — no labels needed.
//   • A strand drifts only after silence past TWICE its own cadence.
//   • No history → never drifts (calm by default; never fabricate urgency).
//   • Baseline prefers declared recurrence, then learned spacing, then a single
//     gentle one-time cadence.
//

import XCTest
@testable import Moti

final class StrandPresenceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference
    private let day: TimeInterval = 86_400

    private func daysAgo(_ n: Double) -> Date {
        now.addingTimeInterval(-n * day)
    }

    private func events(_ kindDates: [(StrandEventKind, Double)]) -> [StrandEvent] {
        kindDates.map { StrandEvent(kind: $0.0, date: daysAgo($0.1)) }
    }

    // MARK: - Active

    func test_freshActivityWithinCadence_isActive_andReachesNow() {
        // Weekly strand, touched yesterday → solidly active.
        let p = StrandPresenceComputer.presence(
            events: events([(.completed, 14), (.completed, 7), (.completed, 1)]),
            recurrenceCadenceDays: 7,
            now: now
        )
        XCTAssertEqual(p.state, .active)
        XCTAssertTrue(p.reachesNow)
        XCTAssertGreaterThan(p.reach, 0.5)
    }

    func test_activeAtExactlyOneBaseline_isBoundaryActive_reachHalf() {
        // Silent for exactly one cadence (7 of 14-day horizon) → reach == 0.5,
        // and the boundary is inclusive on the active side.
        let p = StrandPresenceComputer.presence(
            events: events([(.completed, 7)]),
            recurrenceCadenceDays: 7,
            now: now
        )
        XCTAssertEqual(p.state, .active)
        XCTAssertEqual(p.reach, 0.5, accuracy: 0.0001)
    }

    // MARK: - Quiet

    func test_silentBeyondOneBaselineButWithinDriftHorizon_isQuiet() {
        // 10 days of silence on a 7-day cadence (horizon 14) → present but quiet.
        let p = StrandPresenceComputer.presence(
            events: events([(.completed, 21), (.completed, 10)]),
            recurrenceCadenceDays: 7,
            now: now
        )
        XCTAssertEqual(p.state, .quiet)
        XCTAssertTrue(p.reachesNow)
        XCTAssertLessThan(p.reach, 0.5)
        XCTAssertGreaterThan(p.reach, 0)
    }

    // MARK: - Drifted

    func test_silentPastTwiceCadence_isDrifted_andDoesNotReach() {
        // 18 days silent on a weekly cadence (horizon 14) → drifted, empty slot.
        let p = StrandPresenceComputer.presence(
            events: events([(.completed, 40), (.completed, 18)]),
            recurrenceCadenceDays: 7,
            now: now
        )
        XCTAssertEqual(p.state, .drifted)
        XCTAssertFalse(p.reachesNow)
        XCTAssertEqual(p.reach, 0)
    }

    func test_driftBoundaryIsInclusive_atExactlyTwiceCadence() {
        // Exactly 14 days on a 7-day cadence → at the horizon → drifted.
        let p = StrandPresenceComputer.presence(
            events: events([(.completed, 14)]),
            recurrenceCadenceDays: 7,
            now: now
        )
        XCTAssertEqual(p.state, .drifted)
    }

    // MARK: - Baseline learned from the strand's own history

    func test_baselineLearnedFromMedianSpacing_whenNoRecurrence() {
        // Roughly-weekly touches with no declared recurrence: spacing ≈ 7 days,
        // last touch 3 days ago → active, baseline learned from history.
        let p = StrandPresenceComputer.presence(
            events: events([(.touched, 24), (.touched, 17), (.touched, 10), (.touched, 3)]),
            recurrenceCadenceDays: nil,
            now: now
        )
        XCTAssertEqual(p.baselineSource, .history)
        XCTAssertEqual(p.baselineCadenceDays ?? 0, 7, accuracy: 1.0)
        XCTAssertEqual(p.state, .active)
    }

    func test_recurrenceBaselineWins_overHistory() {
        // Even with dense recent history, a declared monthly rhythm sets the bar.
        let p = StrandPresenceComputer.presence(
            events: events([(.completed, 9), (.completed, 2)]),
            recurrenceCadenceDays: 30,
            now: now
        )
        XCTAssertEqual(p.baselineSource, .recurrence)
        XCTAssertEqual(p.baselineCadenceDays, 30)
        XCTAssertEqual(p.state, .active) // 2 days into a monthly rhythm
    }

    // MARK: - No-history fallbacks (never fabricate urgency)

    func test_noEvents_isCalmQuiet_neverDrifts() {
        let p = StrandPresenceComputer.presence(
            events: [],
            recurrenceCadenceDays: nil,
            now: now
        )
        XCTAssertEqual(p.state, .quiet)
        XCTAssertEqual(p.baselineSource, .none)
        XCTAssertNil(p.daysSinceLastActivity)
        XCTAssertEqual(p.reach, 0.5, accuracy: 0.0001)
    }

    func test_singleRecentEvent_usesInferredOneTimeCadence() {
        let p = StrandPresenceComputer.presence(
            events: events([(.created, 2)]),
            recurrenceCadenceDays: nil,
            now: now
        )
        XCTAssertEqual(p.baselineSource, .inferredOneTime)
        XCTAssertEqual(p.state, .active) // 2 days into a 14-day inferred cadence
    }

    func test_singleStaleEvent_canGentlyDrift() {
        // One capture 40 days ago, never followed up → past 2×14 → drifted.
        let p = StrandPresenceComputer.presence(
            events: events([(.created, 40)]),
            recurrenceCadenceDays: nil,
            now: now
        )
        XCTAssertEqual(p.baselineSource, .inferredOneTime)
        XCTAssertEqual(p.state, .drifted)
    }

    // MARK: - Hygiene

    func test_futureDatedEventsAreIgnored() {
        // A plan in the future is not behavior; it must not count as activity.
        let future = StrandEvent(kind: .created, date: now.addingTimeInterval(5 * day))
        let p = StrandPresenceComputer.presence(
            events: [future, StrandEvent(kind: .completed, date: daysAgo(30))],
            recurrenceCadenceDays: 7,
            now: now
        )
        XCTAssertEqual(p.lastActivity, daysAgo(30))
        XCTAssertEqual(p.state, .drifted)
    }

    func test_reachIsMonotonicWithSilence() {
        // More silence → less reach, on the same cadence.
        let recent = StrandPresenceComputer.presence(
            events: events([(.completed, 2)]), recurrenceCadenceDays: 7, now: now)
        let older = StrandPresenceComputer.presence(
            events: events([(.completed, 9)]), recurrenceCadenceDays: 7, now: now)
        XCTAssertGreaterThan(recent.reach, older.reach)
    }

    func test_wholeDaysBetween_floorsAndNeverNegative() {
        XCTAssertEqual(StrandPresenceComputer.wholeDaysBetween(daysAgo(3.9), and: now), 3)
        XCTAssertEqual(StrandPresenceComputer.wholeDaysBetween(now.addingTimeInterval(day), and: now), 0)
    }
}
