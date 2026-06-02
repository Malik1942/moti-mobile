//
// TimelineNarratorTests.swift
//
// Covers the phrasing layer: the top synthesized sentence and the single
// "What matters now" focus. These tests pin the product's *voice* (calm,
// behavioral, non-shaming) and the separation of concerns — the narrator only
// reads computed presence, it never decides state.
//

import XCTest
@testable import Moti

final class TimelineNarratorTests: XCTestCase {

    private func strand(
        _ name: String, _ state: PresenceState,
        days: Int? = nil, paused: Bool = false,
        baseline: Double? = 7, source: BaselineSource = .recurrence
    ) -> Strand {
        Strand(
            id: name, name: name, colorToken: "blue", kind: .maintenance,
            presence: StrandPresence(
                state: state, reach: 0.5, lastActivity: nil,
                daysSinceLastActivity: days, baselineCadenceDays: baseline, baselineSource: source
            ),
            isPaused: paused, recurrenceCadenceDays: baseline, openCount: 1, deferredCount: 0,
            deadline: nil, forwardNodes: [], lastTraces: [], coOccurringStrandNames: []
        )
    }

    // MARK: - Headline

    func test_headline_namesActiveAndDrifted() {
        let h = TimelineNarrator.headline(for: [
            strand("Work", .active), strand("Move", .active), strand("Fitness", .drifted, days: 21)
        ])
        XCTAssertEqual(h, "This week Work and Move stayed active. Fitness drifted before now.")
    }

    func test_headline_calmWhenOnlyActive() {
        let h = TimelineNarrator.headline(for: [strand("Work", .active)])
        XCTAssertEqual(h, "This week Work stayed active. Everything's still in reach.")
    }

    func test_headline_sereneWhenOnlyQuiet() {
        let h = TimelineNarrator.headline(for: [strand("Reading", .quiet), strand("Spanish", .quiet)])
        XCTAssertEqual(h, "A calm week — everything's still in reach.")
    }

    func test_headline_pausedStrandsAreNotNarrated() {
        let h = TimelineNarrator.headline(for: [
            strand("Work", .active), strand("Reading", .drifted, days: 30, paused: true)
        ])
        // The paused strand must not appear as drifted noise.
        XCTAssertFalse(h.contains("Reading"))
        XCTAssertTrue(h.contains("Work"))
    }

    func test_headline_emptyState() {
        XCTAssertEqual(TimelineNarrator.headline(for: []),
                       "Your futures will appear here as you use Moti.")
    }

    // MARK: - Focus

    func test_focus_picksLongestSilentDrifted() {
        let focus = TimelineNarrator.focus(for: [
            strand("Fitness", .drifted, days: 18),
            strand("Parents", .drifted, days: 34),
            strand("Work", .active)
        ])
        guard case let .attention(id, title, _) = focus else { return XCTFail("expected attention") }
        XCTAssertEqual(id, "Parents")
        XCTAssertEqual(title, "Parents has gone quiet")
    }

    func test_focus_calmWhenNothingDrifted() {
        let focus = TimelineNarrator.focus(for: [strand("Work", .active), strand("Reading", .quiet)])
        XCTAssertEqual(focus, .calm("Everything's still in reach."))
    }

    func test_focus_excludesPausedAndParked() {
        let focus = TimelineNarrator.focus(
            for: [strand("Reading", .drifted, days: 40, paused: true),
                  strand("Fitness", .drifted, days: 20)],
            parkedIDs: ["Fitness"]
        )
        // Paused and parked are peaceful, first-class choices — never resurfaced.
        XCTAssertEqual(focus, .calm("Everything's still in reach."))
    }

    func test_driftDetail_isBehavioralAndNonShaming() {
        let detail = TimelineNarrator.driftDetail(for: strand("Fitness", .drifted, days: 22, baseline: 7))
        XCTAssertEqual(detail, "Quiet for 22 days · usually weekly")
    }

    // MARK: - Helpers

    func test_cadenceWord_buckets() {
        XCTAssertEqual(TimelineNarrator.cadenceWord(1), "daily")
        XCTAssertEqual(TimelineNarrator.cadenceWord(7), "weekly")
        XCTAssertEqual(TimelineNarrator.cadenceWord(14), "every couple weeks")
        XCTAssertEqual(TimelineNarrator.cadenceWord(30), "monthly")
    }

    func test_joined_oxford() {
        XCTAssertEqual(TimelineNarrator.joined(["A"]), "A")
        XCTAssertEqual(TimelineNarrator.joined(["A", "B"]), "A and B")
        XCTAssertEqual(TimelineNarrator.joined(["A", "B", "C"]), "A, B, and C")
    }
}
