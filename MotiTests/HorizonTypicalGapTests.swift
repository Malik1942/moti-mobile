//
// HorizonTypicalGapTests.swift
//
// Horizon Timeline v2 — T3. typical_gap derivation (PRD §11): median of the
// last 5 inter-event gaps, requiring >=3 events, else nil. Non-positive gaps
// (identical timestamps / clock skew) are dropped.
//

import XCTest
@testable import Moti

final class HorizonTypicalGapTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400
    /// An event `d` days after the base instant.
    private func at(_ d: Double) -> Date { base.addingTimeInterval(d * day) }
    private func days(_ n: Double) -> TimeInterval { n * day }

    // MARK: - Minimum-evidence gate

    func test_fewerThanThreeEvents_returnsNil() {
        XCTAssertNil(HorizonRhythm.typicalGap(events: []))
        XCTAssertNil(HorizonRhythm.typicalGap(events: [at(0)]))
        XCTAssertNil(HorizonRhythm.typicalGap(events: [at(0), at(7)]),
                     "two events (one gap) is below the >=3-event bar")
    }

    func test_exactlyThreeEvenlySpacedEvents_returnsThatGap() {
        // 3 events, 7 days apart → gaps [7, 7] → median 7d.
        let gap = HorizonRhythm.typicalGap(events: [at(0), at(7), at(14)])
        XCTAssertEqual(gap, days(7))
    }

    // MARK: - Median behaviour

    func test_irregularGaps_returnsMedian_oddCount() {
        // events → gaps [5, 7, 8, 1, 19]; sorted [1,5,7,8,19] → median 7d.
        let events = [at(0), at(5), at(12), at(20), at(21), at(40)]
        XCTAssertEqual(HorizonRhythm.typicalGap(events: events), days(7))
    }

    func test_median_evenCount_averagesTwoMiddleGaps() {
        // 5 events → gaps [2, 4, 6, 8] → median (4+6)/2 = 5d.
        let events = [at(0), at(2), at(6), at(12), at(20)]
        XCTAssertEqual(HorizonRhythm.typicalGap(events: events), days(5))
    }

    func test_onlyLastFiveGapsCount() {
        // 8 events. Early gaps are huge (100d each); the recent five are small.
        // gaps: [100,100, 3,4,5,6,7]; suffix(5) = [3,4,5,6,7] → median 5d.
        let events = [at(0), at(100), at(200), at(203), at(207), at(212), at(218), at(225)]
        XCTAssertEqual(HorizonRhythm.typicalGap(events: events), days(5),
                       "the ancient 100-day gaps must not drag the recent cadence")
    }

    // MARK: - Degenerate timestamps

    func test_allIdenticalTimestamps_returnsNil() {
        let t = at(3)
        XCTAssertNil(HorizonRhythm.typicalGap(events: [t, t, t, t]),
                     "no positive interval → no derivable cadence")
    }

    func test_duplicateInTheMiddle_dropsZeroGap() {
        // events at 0, 7, 7, 14 → raw gaps [7, 0, 7]; drop the 0 → [7,7] → 7d.
        let events = [at(0), at(7), at(7), at(14)]
        XCTAssertEqual(HorizonRhythm.typicalGap(events: events), days(7))
    }

    // MARK: - Ordering & clock skew

    func test_unsortedInput_isSortedFirst() {
        let events = [at(14), at(0), at(7)] // out of order
        XCTAssertEqual(HorizonRhythm.typicalGap(events: events), days(7))
    }

    func test_clockSkew_futureEvent_stillYieldsPositiveGap() {
        // A far-future event (skew) sorts last; its gap is still a real positive
        // interval — the result is never negative or nil for otherwise-valid data.
        let events = [at(0), at(7), at(14), at(1000)]
        let gap = HorizonRhythm.typicalGap(events: events)
        XCTAssertNotNil(gap)
        XCTAssertGreaterThan(gap!, 0)
    }

    // MARK: - median() helper

    func test_median_helper_oddAndEven() {
        XCTAssertEqual(HorizonRhythm.median([3, 1, 2]), 2)
        XCTAssertEqual(HorizonRhythm.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(HorizonRhythm.median([42]), 42)
    }
}
