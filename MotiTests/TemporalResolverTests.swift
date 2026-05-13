import XCTest
@testable import Moti

final class TemporalResolverTests: XCTestCase {

    // Fixed reference: 2026-05-12 noon, so "tomorrow" and "next week" are deterministic.
    private let now: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 12; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }()

    // Returns the primary (first non-noSignal) resolution, or noSignal if none.
    private func resolve(_ input: String) -> TemporalResolution {
        let results = TemporalResolver.resolve(input: input, now: now)
        return results.first(where: { $0.resolverPath != .noSignal })
            ?? results.first
            ?? .noSignal(for: input)
    }

    private func resolveAll(_ input: String) -> [TemporalResolution] {
        TemporalResolver.resolve(input: input, now: now)
    }

    // MARK: - Unambiguous calendarDate (Step 1 handles)

    func testBirthdayPartyDotNotation() {
        let r = resolve("Birthday party in 5.15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.85)
        assertDate(r.resolvedDate, month: 5, day: 15)
    }

    func testDinnerDotNotation() {
        let r = resolve("Dinner on 10.3")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.85)
        assertDate(r.resolvedDate, month: 10, day: 3)
    }

    func testRelativeDurationDays() {
        let r = resolve("Submit assignment in 5 days")
        XCTAssertEqual(r.interpretation, .relativeDuration)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.90)
        XCTAssertNotNil(r.resolvedDuration)
        XCTAssertEqual(r.resolvedDuration!, 5 * 86_400, accuracy: 1)
    }

    func testRelativeDurationHours() {
        let r = resolve("Finish report after 3 hours")
        XCTAssertEqual(r.interpretation, .relativeDuration)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.90)
        XCTAssertEqual(r.resolvedDuration!, 3 * 3600, accuracy: 1)
    }

    func testClockTime() {
        let r = resolve("Meeting at 7pm")
        XCTAssertEqual(r.interpretation, .clockTime)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.90)
        XCTAssertEqual(r.resolvedClockTime?.hour, 19)
        XCTAssertEqual(r.resolvedClockTime?.minute, 0)
    }

    func testISODate() {
        let r = resolve("Lunch on 2026-05-15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.95)
        XCTAssertNil(r.formatAssumption) // ISO is unambiguous
        assertDate(r.resolvedDate, month: 5, day: 15, year: 2026)
    }

    func testTomorrow() {
        let r = resolve("Workout tomorrow")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.95)
        assertDate(r.resolvedDate, month: 5, day: 13) // day after 2026-05-12
    }

    func testSlashNotation() {
        let r = resolve("Submit on 5/15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.85)
        assertDate(r.resolvedDate, month: 5, day: 15)
    }

    // MARK: - Mixed-signal cases (Step 2 resolves)

    func testBirthdayPartyResolverPath() {
        // "in" before dot notation → confidence 0.70 (Step 1)
        // "birthday"/"party" event keywords → +0.15 → 0.85 (Step 2)
        // resolverPath must be .semantic
        let r = resolve("Birthday party in 5.15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertEqual(r.resolverPath, .semantic)
        assertDate(r.resolvedDate, month: 5, day: 15)
    }

    func testEventKeywordBoostsDotNotation() {
        let r = resolve("Birthday gift submission deadline 5.15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        assertDate(r.resolvedDate, month: 5, day: 15)
        XCTAssertTrue(r.resolverPath == .deterministic || r.resolverPath == .semantic)
    }

    func testExplicitDurationBeatsEventContext() {
        // "in 5 days" is unambiguous — explicit unit word prevents dot-notation confusion
        let r = resolve("Plan party in 5 days")
        XCTAssertEqual(r.interpretation, .relativeDuration)
        XCTAssertEqual(r.resolverPath, .deterministic)
        XCTAssertEqual(r.resolvedDuration!, 5 * 86_400, accuracy: 1)
    }

    func testCoffeeEventImpliedByContext() {
        let r = resolve("Coffee with Sarah 5.15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        assertDate(r.resolvedDate, month: 5, day: 15)
    }

    // MARK: - Multi-resolution (date + time)

    func testFlightMultiResolution() {
        // "on 5.15" → calendarDate (confidence 0.85, "on" is not a preposition that reduces)
        // "at 7pm" → clockTime
        let resolutions = resolveAll("Flight to SF on 5.15 at 7pm")
        let dates  = resolutions.filter { $0.interpretation == .calendarDate }
        let clocks = resolutions.filter { $0.interpretation == .clockTime }
        XCTAssertFalse(dates.isEmpty,  "Expected calendarDate resolution for 'on 5.15'")
        XCTAssertFalse(clocks.isEmpty, "Expected clockTime resolution for 'at 7pm'")
        if let dateRes = dates.first {
            assertDate(dateRes.resolvedDate, month: 5, day: 15)
        }
        if let clockRes = clocks.first {
            XCTAssertEqual(clockRes.resolvedClockTime?.hour, 19)
        }
    }

    func testMultiResolutionCount() {
        // Should produce exactly 2 non-noSignal resolutions
        let resolutions = resolveAll("Flight to SF on 5.15 at 7pm")
            .filter { $0.resolverPath != .noSignal }
        XCTAssertEqual(resolutions.count, 2, "Expected calendarDate + clockTime")
    }

    // MARK: - Guard tests (dot notation should NOT classify as date)

    func testCurrencySignalBlocksDateClassification() {
        let r = resolve("Buy item for $5.15")
        XCTAssertEqual(r.interpretation, .unknown)
    }

    func testQuantitySignalBlocksDateClassification() {
        let r = resolve("Run 5.15 km")
        XCTAssertEqual(r.interpretation, .unknown)
    }

    func testVersionSignalBlocksDateClassification() {
        let r = resolve("Update to iOS 15.5")
        // 15 > 12 so guard fails on month range alone
        XCTAssertEqual(r.interpretation, .unknown)
    }

    func testOutOfRangeMonthIsUnknown() {
        // N=13 is not in 1-12 → not a valid US month
        let r = resolve("Score was 13.7")
        XCTAssertEqual(r.interpretation, .unknown)
    }

    // MARK: - Genuinely ambiguous / low-confidence (Step 3 handles)

    func testStandaloneDotNotationIsLowConfidence() {
        let r = resolve("5.15")
        // No surrounding context → calendarDate with low confidence, LLM tiebreaker invoked
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertLessThan(r.confidence, 0.85)
        XCTAssertEqual(r.resolverPath, .llmTiebreaker)
    }

    // MARK: - Format assumption tests

    func testFormatAssumptionForDotNotation() {
        let r = resolve("Dinner on 5.15")
        XCTAssertEqual(r.interpretation, .calendarDate)
        XCTAssertEqual(r.formatAssumption, "month.day (US format)")
    }

    func testNoFormatAssumptionForISODate() {
        let r = resolve("Dinner on 2026-05-15")
        XCTAssertNil(r.formatAssumption)
    }

    // MARK: - resolverPath populated on every result

    func testResolverPathAlwaysPopulated() {
        let inputs = [
            "Birthday party in 5.15",
            "Submit in 5 days",
            "Meeting at 7pm",
            "No dates here at all",
            "Buy for $5.15",
            "5.15",
        ]
        for input in inputs {
            let r = resolve(input)
            XCTAssertNotNil(r.resolverPath, "resolverPath must be set for: \(input)")
        }
    }

    // MARK: - Telemetry: tiebreaker and noSignal rates

    func testLLMTiebreakerRateBelow15Percent() {
        let standardInputs = [
            "Birthday party in 5.15",
            "Dinner on 10.3",
            "Submit assignment in 5 days",
            "Finish report after 3 hours",
            "Meeting at 7pm",
            "Lunch on 2026-05-15",
            "Workout tomorrow",
            "Submit on 5/15",
            "Coffee with Sarah 5.15",
            "Plan party in 5 days",
            "Buy item for $5.15",
            "Run 5.15 km",
            "Update to iOS 15.5",
            "Score was 13.7",
        ]
        let resolutions = standardInputs.map { resolve($0) }
        let tiebreakerCount = resolutions.filter { $0.resolverPath == .llmTiebreaker }.count
        let rate = Double(tiebreakerCount) / Double(resolutions.count)
        XCTAssertLessThan(rate, 0.15, "LLMTiebreaker rate \(rate) exceeds 15%")
    }

    func testNoSignalRateBelow5Percent() {
        let standardInputs = [
            "Birthday party in 5.15",
            "Dinner on 10.3",
            "Submit assignment in 5 days",
            "Finish report after 3 hours",
            "Meeting at 7pm",
            "Lunch on 2026-05-15",
            "Workout tomorrow",
            "Submit on 5/15",
            "Coffee with Sarah 5.15",
            "Plan party in 5 days",
            // guard-fail inputs still have a resolverPath (.deterministic), not .noSignal
            "Buy item for $5.15",
            "Run 5.15 km",
        ]
        let resolutions = standardInputs.map { resolve($0) }
        let noSignalCount = resolutions.filter { $0.resolverPath == .noSignal }.count
        let rate = Double(noSignalCount) / Double(resolutions.count)
        XCTAssertLessThan(rate, 0.05, "noSignal rate \(rate) exceeds 5%")
    }

    // MARK: - Helpers

    private func assertDate(
        _ date: Date?,
        month: Int,
        day: Int,
        year: Int? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let date else {
            XCTFail("resolvedDate is nil", file: file, line: line)
            return
        }
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: date), month, "month mismatch", file: file, line: line)
        XCTAssertEqual(cal.component(.day, from: date), day, "day mismatch", file: file, line: line)
        if let year {
            XCTAssertEqual(cal.component(.year, from: date), year, "year mismatch", file: file, line: line)
        }
    }
}
