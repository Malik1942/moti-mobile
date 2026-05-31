//
// ClockTimeInferenceTests.swift
//
// Covers ambiguous same-day clock-time resolution in DateResolver: a casual
// capture like "before 3:45 today" should resolve to the nearest reasonable
// FUTURE time (3:45 PM when it's 2 PM), not a passed morning time — while
// explicit AM/PM input is never altered.
//
// NOTE: like the other files in MotiTests/, this is not yet wired into an
// xcodebuild test target; it documents expected behavior as runnable XCTest
// methods that compile as-is once a target with `@testable import Moti` exists.
//

import XCTest
@testable import Moti

final class ClockTimeInferenceTests: XCTestCase {

    private let cal = Calendar.current

    /// A fixed "now" on 2026-05-12 so "today" is deterministic.
    private func now(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: hour, minute: minute))!
    }

    private func hourMinute(_ date: Date) -> (Int, Int) {
        (cal.component(.hour, from: date), cal.component(.minute, from: date))
    }

    private func resolve(_ input: String, at reference: Date) throws -> Date {
        try XCTUnwrap(DateResolver.resolve(in: input, now: reference)?.date,
                      "Expected a resolved date for \"\(input)\"")
    }

    // MARK: - Ambiguous same-day times resolve to the next future time

    func test_before345Today_resolvesToPMWhenAfternoon() throws {
        // 2 PM now → 3:45 AM has passed, 3:45 PM is the next occurrence.
        let date = try resolve("finish video filming before 3:45 today", at: now(14))
        XCTAssertEqual(hourMinute(date).0, 15)
        XCTAssertEqual(hourMinute(date).1, 45)
        XCTAssertEqual(cal.component(.day, from: date), 12, "Stays today.")
    }

    func test_at5Today_resolvesToFivePMWhenAfternoon() throws {
        let date = try resolve("review resume at 5 today", at: now(14))
        XCTAssertEqual(hourMinute(date).0, 17)
        XCTAssertEqual(hourMinute(date).1, 0)
    }

    func test_submitBy7_noDayWord_impliesTodayPM() throws {
        // No "today" word — a bare "by 7" still implies today, future time.
        let date = try resolve("submit by 7", at: now(14))
        XCTAssertEqual(hourMinute(date).0, 19)
    }

    func test_amStillAheadResolvesToAM() throws {
        // 6 AM now → "at 9" is still ahead this morning, so AM wins.
        let date = try resolve("standup at 9 today", at: now(6))
        XCTAssertEqual(hourMinute(date).0, 9)
    }

    // MARK: - Explicit AM/PM is never altered

    func test_explicitFiveAM_staysFiveAM() throws {
        let date = try resolve("review resume at 5 am today", at: now(14))
        XCTAssertEqual(hourMinute(date).0, 5)
    }

    func test_explicitFivePM_staysFivePM() throws {
        let date = try resolve("review resume at 5 pm today", at: now(9))
        XCTAssertEqual(hourMinute(date).0, 17)
    }

    // MARK: - Plain numbers are not mistaken for times

    func test_plainNumber_isNotAClockTime() throws {
        // "3 roles" has no clock lead-in → not a time; falls back to end-of-day.
        let date = try resolve("apply to 3 roles today", at: now(14))
        XCTAssertEqual(hourMinute(date).0, 23)
        XCTAssertEqual(hourMinute(date).1, 59)
    }

    // MARK: - Both readings already passed → flagged for review

    func test_bothAMandPMPassed_isFlaggedForReview() {
        // 8 PM now → 5 AM and 5 PM both passed.
        XCTAssertTrue(DateResolver.ambiguousClockTimeAlreadyPassed(in: "at 5 today", now: now(20)))
    }

    func test_futurePM_isNotFlaggedForReview() {
        XCTAssertFalse(DateResolver.ambiguousClockTimeAlreadyPassed(in: "at 5 today", now: now(14)))
    }

    func test_explicitTime_isNeverFlaggedForReview() {
        // Explicit AM/PM is the user's call, even if in the past — not "ambiguous".
        XCTAssertFalse(DateResolver.ambiguousClockTimeAlreadyPassed(in: "at 5 am today", now: now(20)))
    }

    func test_otherDay_isNotTreatedAsToday() {
        // "tomorrow at 3" is not a same-day ambiguity.
        XCTAssertFalse(DateResolver.ambiguousClockTimeAlreadyPassed(in: "ship it tomorrow at 3", now: now(20)))
    }
}
