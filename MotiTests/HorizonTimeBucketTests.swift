//
// HorizonTimeBucketTests.swift
//
// Horizon Timeline v2 — T1. Calendar-aligned, half-open bucket windows
// (PRD §6.1). Boundaries follow `calendar.firstWeekday` (device locale), not a
// hardcoded Sunday. Deterministic: every test builds an explicit Gregorian
// calendar with a fixed timeZone + firstWeekday so results never depend on the
// machine locale.
//

import XCTest
@testable import Moti

final class HorizonTimeBucketTests: XCTestCase {

    private let order: [TimeBucket] = [.today, .tomorrow, .restOfThisWeek, .nextWeek, .restOfThisMonth, .later]

    // MARK: - Fixtures

    private func calendar(firstWeekday: Int, tz: String = "America/New_York") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, cal: Calendar) -> Date {
        var comp = DateComponents()
        comp.year = y; comp.month = mo; comp.day = d; comp.hour = h; comp.minute = min
        return cal.date(from: comp)!
    }

    /// Asserts the six windows tile `[startOfToday, distantFuture)` with no gaps,
    /// no overlaps, and no backward runs.
    private func assertValidPartition(_ ws: [BucketWindow], startOfToday: Date,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ws.map(\.bucket), order, "bucket order", file: file, line: line)
        XCTAssertEqual(ws.first?.start, startOfToday, "starts at start of today", file: file, line: line)
        for i in ws.indices.dropFirst() {
            XCTAssertEqual(ws[i].start, ws[i - 1].end, "contiguous at \(ws[i].bucket)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(ws[i].end, ws[i].start, "monotonic at \(ws[i].bucket)", file: file, line: line)
        }
        XCTAssertEqual(ws.last?.bucket, .later, file: file, line: line)
        XCTAssertEqual(ws.last?.end, .distantFuture, "Later is unbounded", file: file, line: line)
    }

    private func window(_ b: TimeBucket, _ ws: [BucketWindow]) -> BucketWindow {
        ws.first { $0.bucket == b }!
    }

    // MARK: - Structure

    func test_sixBucketsInFixedOrder_contiguousAndMonotonic() {
        let cal = calendar(firstWeekday: 2) // Monday-first
        let now = date(2026, 6, 17, 9, 30, cal: cal) // an ordinary Wednesday
        let ws = HorizonBuckets.windows(now: now, calendar: cal)
        XCTAssertEqual(ws.count, 6)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: now))
    }

    func test_todayIsAlwaysExactlyOneCalendarDay() {
        let cal = calendar(firstWeekday: 1)
        let now = date(2026, 6, 17, 23, 59, cal: cal)
        let ws = HorizonBuckets.windows(now: now, calendar: cal)
        let today = window(.today, ws)
        XCTAssertEqual(today.start, cal.startOfDay(for: now))
        XCTAssertEqual(today.end, cal.startOfDay(for: today.end), "Today ends on a midnight boundary")
        XCTAssertEqual(cal.dateComponents([.day], from: today.start, to: today.end).day, 1)
        XCTAssertFalse(today.isEmpty)
    }

    // MARK: - Week-boundary behaviour (locale-sensitive)

    func test_sunday_mondayFirstLocale_tomorrowSpansWeekBoundary_restOfWeekEmpty() {
        let cal = calendar(firstWeekday: 2) // Monday-first: Sunday is the LAST day of the week
        let sunday = date(2026, 7, 5, 12, 0, cal: cal)
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1, "fixture really is a Sunday")

        let ws = HorizonBuckets.windows(now: sunday, calendar: cal)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: sunday))

        // Rest-of-this-week collapses: nothing sits between tomorrow and next week.
        XCTAssertTrue(window(.restOfThisWeek, ws).isEmpty, "Sunday (Mon-first) has no rest-of-week")

        // Tomorrow (Monday) is the first day of next week by the calendar, but the
        // nearer Tomorrow bucket claims it.
        let monday = date(2026, 7, 6, 12, 0, cal: cal)
        XCTAssertEqual(HorizonBuckets.bucket(for: monday, in: ws), .tomorrow)
        // A day deeper into the coming week lands in Next week, not Tomorrow.
        let wednesday = date(2026, 7, 8, 12, 0, cal: cal)
        XCTAssertEqual(HorizonBuckets.bucket(for: wednesday, in: ws), .nextWeek)
    }

    func test_sunday_sundayFirstLocale_restOfWeekIsNonEmpty() {
        let cal = calendar(firstWeekday: 1) // Sunday-first (US): Sunday STARTS the week
        let sunday = date(2026, 7, 5, 12, 0, cal: cal)
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1)

        let ws = HorizonBuckets.windows(now: sunday, calendar: cal)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: sunday))

        // The rest of this week (Mon-Sat) is still ahead.
        XCTAssertFalse(window(.restOfThisWeek, ws).isEmpty, "Sunday (Sun-first) still has a week ahead")
        let saturday = date(2026, 7, 11, 12, 0, cal: cal)
        XCTAssertEqual(HorizonBuckets.bucket(for: saturday, in: ws), .restOfThisWeek)
    }

    // MARK: - Month / year edges

    func test_lastDayOfMonth_tomorrowFallsIntoNextMonth() {
        let cal = calendar(firstWeekday: 2)
        let jul31 = date(2026, 7, 31, 10, 0, cal: cal)
        let ws = HorizonBuckets.windows(now: jul31, calendar: cal)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: jul31))

        let aug1 = date(2026, 8, 1, 10, 0, cal: cal)
        XCTAssertEqual(HorizonBuckets.bucket(for: aug1, in: ws), .tomorrow,
                       "tomorrow keeps a day even across the month boundary")
    }

    func test_lastWeekOfYear_nextWeekCrossesIntoNewYear() {
        let cal = calendar(firstWeekday: 2)
        let dec29 = date(2026, 12, 29, 12, 0, cal: cal) // Tuesday
        let ws = HorizonBuckets.windows(now: dec29, calendar: cal)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: dec29))

        // Next week reaches into 2027 without breaking monotonicity.
        let jan4 = date(2027, 1, 4, 12, 0, cal: cal)
        XCTAssertEqual(HorizonBuckets.bucket(for: jan4, in: ws), .nextWeek)
    }

    // MARK: - DST transition days (America/New_York)

    func test_dstSpringForward_todayIsStillOneCalendarDay() {
        let cal = calendar(firstWeekday: 1)
        let springForward = date(2026, 3, 8, 12, 0, cal: cal) // 23-hour local day
        let ws = HorizonBuckets.windows(now: springForward, calendar: cal)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: springForward))

        let today = window(.today, ws)
        XCTAssertEqual(cal.dateComponents([.day], from: today.start, to: today.end).day, 1)
        XCTAssertEqual(today.end, cal.startOfDay(for: today.end))
        // Real elapsed time is 23h, proving we used calendar arithmetic not +86_400s.
        XCTAssertEqual(today.end.timeIntervalSince(today.start), 23 * 3600, accuracy: 1)
    }

    func test_dstFallBack_todayIsStillOneCalendarDay() {
        let cal = calendar(firstWeekday: 1)
        let fallBack = date(2026, 11, 1, 12, 0, cal: cal) // 25-hour local day
        let ws = HorizonBuckets.windows(now: fallBack, calendar: cal)
        assertValidPartition(ws, startOfToday: cal.startOfDay(for: fallBack))

        let today = window(.today, ws)
        XCTAssertEqual(cal.dateComponents([.day], from: today.start, to: today.end).day, 1)
        XCTAssertEqual(today.end.timeIntervalSince(today.start), 25 * 3600, accuracy: 1)
    }

    // MARK: - Membership semantics

    func test_contains_isHalfOpen_startInclusiveEndExclusive() {
        let cal = calendar(firstWeekday: 2)
        let now = date(2026, 6, 17, 12, 0, cal: cal)
        let ws = HorizonBuckets.windows(now: now, calendar: cal)
        let today = window(.today, ws)
        XCTAssertTrue(today.contains(today.start), "start is inclusive")
        XCTAssertFalse(today.contains(today.end), "end is exclusive")
        XCTAssertEqual(HorizonBuckets.bucket(for: today.end, in: ws), .tomorrow,
                       "the exclusive end belongs to the next bucket")
    }

    func test_bucketFor_pastDate_isNil() {
        let cal = calendar(firstWeekday: 2)
        let now = date(2026, 6, 17, 12, 0, cal: cal)
        let ws = HorizonBuckets.windows(now: now, calendar: cal)
        let yesterday = date(2026, 6, 16, 12, 0, cal: cal)
        XCTAssertNil(HorizonBuckets.bucket(for: yesterday, in: ws),
                     "a date before today belongs to the Past region, not a forward bucket")
    }

    func test_bucketFor_todayAndTomorrow_andLater() {
        let cal = calendar(firstWeekday: 2)
        let now = date(2026, 6, 17, 12, 0, cal: cal) // Wednesday
        let ws = HorizonBuckets.windows(now: now, calendar: cal)
        XCTAssertEqual(HorizonBuckets.bucket(for: now, in: ws), .today)
        XCTAssertEqual(HorizonBuckets.bucket(for: date(2026, 6, 18, 8, 0, cal: cal), in: ws), .tomorrow)
        XCTAssertEqual(HorizonBuckets.bucket(for: date(2026, 9, 1, 12, 0, cal: cal), in: ws), .later)
    }

    func test_emptyWindow_ownsNoInstant() {
        // Construct an intentionally-empty window and confirm it matches nothing.
        let t = Date(timeIntervalSince1970: 1_000_000)
        let empty = BucketWindow(bucket: .restOfThisWeek, start: t, end: t)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.contains(t))
    }
}
