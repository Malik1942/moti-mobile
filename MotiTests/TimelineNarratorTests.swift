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
        baseline: Double? = 7, source: BaselineSource = .recurrence,
        outcome: TrajectoryOutcome? = nil
    ) -> Strand {
        Strand(
            id: name, name: name, colorToken: "blue",
            computedType: .maintenance, userOverrideType: nil, eventCount: 1,
            presence: StrandPresence(
                state: state, reach: 0.5, lastActivity: nil,
                daysSinceLastActivity: days, baselineCadenceDays: baseline, baselineSource: source
            ),
            trajectory: .directional(outcome ?? (state == .drifted ? .fading : .sustained)),
            isPaused: paused, recurrenceCadenceDays: baseline, openCount: 1, deferredCount: 0,
            completedActionCount: 0, totalActionCount: 0,
            deadline: nil, forwardNodes: [], lastTraces: [], coOccurringStrandNames: []
        )
    }

    // MARK: - Trajectory (forward-looking) copy

    func test_trajectoryHeadline_namesSlippingAndFading() {
        let h = TimelineNarrator.trajectoryHeadline(for: [
            strand("Launch", .active, outcome: .behind),
            strand("Fitness", .drifted, outcome: .fading),
            strand("Work", .active, outcome: .onTime)
        ])
        XCTAssertEqual(h, "On current pace: Launch is slipping and Fitness is fading.")
    }

    func test_trajectoryHeadline_calmWhenAllOnTrack() {
        let h = TimelineNarrator.trajectoryHeadline(for: [
            strand("Work", .active, outcome: .onTime),
            strand("Parents", .quiet, outcome: .sustained)
        ])
        XCTAssertEqual(h, "On current pace, everything's on track.")
    }

    func test_trajectoryFocus_behindOutranksFading() {
        let focus = TimelineNarrator.trajectoryFocus(for: [
            strand("Fitness", .drifted, outcome: .fading),
            strand("Launch", .active, outcome: .behind)
        ])
        guard case let .attention(id, title, _) = focus else { return XCTFail("expected attention") }
        XCTAssertEqual(id, "Launch")
        XCTAssertEqual(title, "Launch is slipping")
    }

    func test_trajectoryFocus_calmWhenNoneNeedAttention() {
        let focus = TimelineNarrator.trajectoryFocus(for: [strand("Work", .active, outcome: .onTime)])
        XCTAssertEqual(focus, .calm("Everything's on track."))
    }

    func test_trajectoryFocus_excludesPausedAndParked() {
        let focus = TimelineNarrator.trajectoryFocus(
            for: [strand("Launch", .active, paused: true, outcome: .behind),
                  strand("Fitness", .drifted, outcome: .fading)],
            parkedIDs: ["Fitness"]
        )
        XCTAssertEqual(focus, .calm("Everything's on track."))
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

    // MARK: - Peek copy

    private func achievement(
        done: Int, deferred: Int, hasDeadline: Bool
    ) -> Strand {
        let nodes = (0..<done).map {
            StrandForwardNode(id: UUID(), title: "Step \($0)", date: nil, isDeadline: false, isReached: true)
        }
        return Strand(
            id: "S", name: "Move", colorToken: "purple",
            computedType: .achievement, userOverrideType: nil, eventCount: max(done, 1),
            presence: StrandPresence(state: .active, reach: 0.9, lastActivity: nil,
                                     daysSinceLastActivity: 1, baselineCadenceDays: nil, baselineSource: .none),
            trajectory: .directional(.onTime),
            isPaused: false, recurrenceCadenceDays: nil, openCount: 3, deferredCount: deferred,
            completedActionCount: done, totalActionCount: max(done, 4),
            deadline: hasDeadline ? Date() : nil, forwardNodes: nodes, lastTraces: [], coOccurringStrandNames: []
        )
    }

    func test_achievementStatus_isBehavioral() {
        XCTAssertEqual(TimelineNarrator.achievementStatus(for: achievement(done: 4, deferred: 2, hasDeadline: true)),
                       "Moving toward deadline · 4 done, 2 deferred")
        XCTAssertEqual(TimelineNarrator.achievementStatus(for: achievement(done: 0, deferred: 0, hasDeadline: false)),
                       "In progress")
    }

    func test_maintenanceRhythm_showsQuietDuration() {
        let s = strand("Fitness", .drifted, days: 18, baseline: 7)
        XCTAssertEqual(TimelineNarrator.maintenanceRhythm(for: s), "Usually weekly · quiet for 18 days")
    }

    func test_whyQuiet_isCoOccurrenceNotCausation() {
        var s = strand("Fitness", .drifted, days: 18)
        s.coOccurringStrandNames = ["Work", "Move"]
        let why = TimelineNarrator.whyQuiet(for: s)
        XCTAssertEqual(why, "It faded as Work and Move rose during the same weeks.")
        XCTAssertFalse(why!.lowercased().contains("crowded out")) // never blame
    }

    func test_whyQuiet_nilWhenActiveOrNoRisers() {
        XCTAssertNil(TimelineNarrator.whyQuiet(for: strand("Work", .active)))
        XCTAssertNil(TimelineNarrator.whyQuiet(for: strand("Fitness", .drifted, days: 18)))
    }

    func test_whyQuietOrFallback_nonCausalWhenNoCoOccurrence() {
        // Drifted with no computable riser → a non-causal fallback, never a cause.
        let line = TimelineNarrator.whyQuietOrFallback(for: strand("Fitness", .drifted, days: 18))
        XCTAssertEqual(line, "It's been quiet a while.")
        XCTAssertFalse(line!.lowercased().contains("crowded"))
        XCTAssertNil(TimelineNarrator.whyQuietOrFallback(for: strand("Work", .active)))
    }

    func test_milestoneHealth_isDirectionalAndNonShaming() {
        XCTAssertEqual(TimelineNarrator.milestoneHealth(for: strand("Move", .active, outcome: .onTime)),
                       "On track for the pace you set.")
        XCTAssertEqual(TimelineNarrator.milestoneHealth(for: strand("Launch", .quiet, outcome: .behind)),
                       "Behind the pace you set — but the deadline's still in view.")
        // No day-counts anywhere in the milestone-health copy (§9.6).
        for o in TrajectoryOutcome.allCases {
            let line = TimelineNarrator.milestoneHealth(for: strand("S", .active, outcome: o))
            XCTAssertFalse(line.contains("week"))
            XCTAssertFalse(line.contains("day"))
        }
    }
}
