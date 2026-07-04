//
// HorizonBucketPlacementTests.swift
//
// Horizon Timeline v2 — T2. Bucket assignment (PRD §6.2). Output is data only.
// Anchor: Wednesday 2026-06-17 12:00 America/New_York, Monday-first calendar.
// Windows this cycle:
//   today          [06-17, 06-18)
//   tomorrow       [06-18, 06-19)
//   restOfThisWeek [06-19, 06-22)   (Fri/Sat/Sun)
//   nextWeek       [06-22, 06-29)
//   restOfThisMonth[06-29, 07-01)   (Mon/Tue)
//   later          [07-01, ∞)
//

import XCTest
@testable import Moti

final class HorizonBucketPlacementTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var comp = DateComponents()
        comp.year = y; comp.month = mo; comp.day = d; comp.hour = h; comp.minute = min
        return cal.date(from: comp)!
    }

    private lazy var now = date(2026, 6, 17, 12, 0)
    private lazy var windows = HorizonBuckets.windows(now: now, calendar: cal)
    private let day: TimeInterval = 86_400

    private func assign(_ kind: HorizonItem.Kind) -> BucketPlacement {
        BucketAssigner.assign(HorizonItem(id: "x", kind: kind), windows: windows, now: now, calendar: cal)
    }

    // MARK: - Assertion helpers

    private func assertDueIn(_ p: BucketPlacement, bucket: TimeBucket, days: Int,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard case let .dueIn(b, c) = p else { return XCTFail("expected dueIn, got \(p)", file: file, line: line) }
        XCTAssertEqual(b, bucket, "bucket", file: file, line: line)
        XCTAssertEqual(c.daysRemaining, days, "daysRemaining", file: file, line: line)
        XCTAssertNil(c.requiredDuration, "requiredDuration must be nil in Phase 1", file: file, line: line)
        XCTAssertEqual(p.bucket, bucket, file: file, line: line)
        XCTAssertFalse(p.isPinnedToTodayTop, file: file, line: line)
    }

    // MARK: - Achievement placement

    func test_achievement_dueToday_isInTodayZeroDaysLeft() {
        assertDueIn(assign(.achievement(due: date(2026, 6, 17, 18, 0))), bucket: .today, days: 0)
    }

    func test_achievement_dueTomorrow() {
        assertDueIn(assign(.achievement(due: date(2026, 6, 18))), bucket: .tomorrow, days: 1)
    }

    func test_achievement_dueLaterThisWeek() {
        assertDueIn(assign(.achievement(due: date(2026, 6, 20))), bucket: .restOfThisWeek, days: 3)
    }

    func test_achievement_dueNextWeek() {
        assertDueIn(assign(.achievement(due: date(2026, 6, 25))), bucket: .nextWeek, days: 8)
    }

    func test_achievement_dueRestOfThisMonth() {
        assertDueIn(assign(.achievement(due: date(2026, 6, 30))), bucket: .restOfThisMonth, days: 13)
    }

    func test_achievement_dueBeyondMonth_isLater() {
        assertDueIn(assign(.achievement(due: date(2026, 8, 1))), bucket: .later, days: 45)
    }

    func test_achievement_overdue_pinnedToTodayWithElapsedDays() {
        let p = assign(.achievement(due: date(2026, 6, 15))) // 2 days ago
        guard case let .overdue(overdueDays, c) = p else { return XCTFail("expected overdue, got \(p)") }
        XCTAssertEqual(overdueDays, 2)
        XCTAssertEqual(c.daysRemaining, -2)
        XCTAssertNil(c.requiredDuration)
        XCTAssertEqual(p.bucket, .today, "overdue pins into Today (never migrates to Past until done)")
        XCTAssertTrue(p.isPinnedToTodayTop)
    }

    func test_achievement_noDueDate_fallsToLater_countdownSuppressed() {
        let p = assign(.achievement(due: nil))
        XCTAssertEqual(p, .achievementNoDueDate)
        XCTAssertEqual(p.bucket, .later)
        XCTAssertFalse(p.isPinnedToTodayTop)
    }

    // MARK: - Maintenance placement

    func test_maintenance_feedByLaterThisWeek_notYetApproaching() {
        // lastFed 06-12, gap 7d → nextFeedBy 06-19 (Fri). elapsed 5d < 0.8*7=5.6.
        let p = assign(.maintenance(lastFed: date(2026, 6, 12), typicalGap: 7 * day))
        guard case let .feedBy(bucket, r) = p else { return XCTFail("expected feedBy, got \(p)") }
        XCTAssertEqual(bucket, .restOfThisWeek)
        XCTAssertEqual(r.typicalGap, 7 * day)
        XCTAssertEqual(r.nextFeedBy, date(2026, 6, 19))
        XCTAssertEqual(r.daysSinceLastFed, 5)
        XCTAssertEqual(r.daysUntilFeedBy, 2)
        XCTAssertFalse(r.isApproaching, "5 days elapsed is below the 0.8×7 threshold")
        XCTAssertFalse(p.isPinnedToTodayTop)
    }

    func test_maintenance_feedByTomorrow_approaching() {
        // lastFed 06-11, gap 7d → nextFeedBy 06-18. elapsed 6d ≥ 5.6 → approaching.
        let p = assign(.maintenance(lastFed: date(2026, 6, 11), typicalGap: 7 * day))
        guard case let .feedBy(bucket, r) = p else { return XCTFail("expected feedBy, got \(p)") }
        XCTAssertEqual(bucket, .tomorrow)
        XCTAssertTrue(r.isApproaching)
    }

    func test_maintenance_feedByNextWeek() {
        let p = assign(.maintenance(lastFed: date(2026, 6, 16), typicalGap: 7 * day))
        guard case let .feedBy(bucket, _) = p else { return XCTFail("expected feedBy, got \(p)") }
        XCTAssertEqual(bucket, .nextWeek)
    }

    func test_maintenance_pastFeedBy_isFeedOverduePinnedToToday() {
        // lastFed 06-01, gap 7d → nextFeedBy 06-08 (past). now > nextFeedBy.
        let p = assign(.maintenance(lastFed: date(2026, 6, 1), typicalGap: 7 * day))
        guard case let .feedOverdue(r) = p else { return XCTFail("expected feedOverdue, got \(p)") }
        XCTAssertEqual(r.daysSinceLastFed, 16)
        XCTAssertEqual(r.typicalGap, 7 * day)
        XCTAssertTrue(r.isApproaching)
        XCTAssertEqual(p.bucket, .today)
        XCTAssertTrue(p.isPinnedToTodayTop)
    }

    func test_maintenance_noDerivableGap_fallsToLater() {
        XCTAssertEqual(assign(.maintenance(lastFed: date(2026, 6, 12), typicalGap: nil)), .maintenanceNoRhythm)
        XCTAssertEqual(assign(.maintenance(lastFed: date(2026, 6, 12), typicalGap: 0)), .maintenanceNoRhythm)
        XCTAssertEqual(assign(.maintenance(lastFed: nil, typicalGap: 7 * day)), .maintenanceNoRhythm)
        XCTAssertEqual(BucketPlacement.maintenanceNoRhythm.bucket, .later)
        XCTAssertFalse(BucketPlacement.maintenanceNoRhythm.isPinnedToTodayTop)
    }
}
