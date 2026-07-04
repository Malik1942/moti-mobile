//
// HorizonCopyTests.swift
//
// Horizon Timeline v2 — T7 copy layer (PRD §7.3). Descriptive, never evaluative.
// Verifies exact strings AND that no output uses a banned word.
//

import XCTest
@testable import Moti

final class HorizonCopyTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        c.firstWeekday = 2
        return c
    }()
    private func date(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: 12))!
    }

    // MARK: - Countdown

    func test_daysLeft() {
        XCTAssertEqual(HorizonCopy.daysLeft(4), "4d left")
        XCTAssertEqual(HorizonCopy.daysLeft(1), "1d left")
        XCTAssertEqual(HorizonCopy.daysLeft(0), "today")
        XCTAssertEqual(HorizonCopy.daysLeft(-3), "today")
    }

    func test_daysOver() {
        XCTAssertEqual(HorizonCopy.daysOver(2), "2d over")
        XCTAssertEqual(HorizonCopy.daysOver(0), "1d over") // floored
    }

    // MARK: - Feed-by phrasing

    func test_feedBy_relativePhrases() {
        let now = date(2026, 6, 17) // Wednesday
        XCTAssertEqual(HorizonCopy.feedBy(date(2026, 6, 17), now: now, calendar: cal), "feed by today")
        XCTAssertEqual(HorizonCopy.feedBy(date(2026, 6, 18), now: now, calendar: cal), "feed by tomorrow")
        XCTAssertEqual(HorizonCopy.feedBy(date(2026, 6, 20), now: now, calendar: cal), "feed by Sat")
        XCTAssertTrue(HorizonCopy.feedBy(date(2026, 7, 27), now: now, calendar: cal).hasPrefix("feed by Jul"))
    }

    // MARK: - Rhythm

    func test_rhythm_andOverdueRhythm() {
        XCTAssertEqual(HorizonCopy.rhythm(daysSinceLastFed: 5, typicalGap: 7 * day),
                       "last fed 5d ago · usually every 7d")
        XCTAssertEqual(HorizonCopy.daysSinceLast(14), "14d since last")
        XCTAssertEqual(HorizonCopy.usualRhythm(typicalGap: 7 * day), "usually every 7d")
        XCTAssertEqual(HorizonCopy.gapDays(7.4 * day), 7)
        XCTAssertEqual(HorizonCopy.gapDays(0), 1)
    }

    // MARK: - Folds & headers

    func test_folds() {
        XCTAssertEqual(HorizonCopy.onCourse(3), "3 more on course")
        XCTAssertEqual(HorizonCopy.collapsedCount(5), "5 futures")
        XCTAssertEqual(HorizonCopy.collapsedCount(1), "1 future")
    }

    func test_bucketTitles() {
        XCTAssertEqual(HorizonCopy.bucketTitle(.today), "Today")
        XCTAssertEqual(HorizonCopy.bucketTitle(.restOfThisWeek), "Rest of this week")
        XCTAssertEqual(HorizonCopy.bucketTitle(.later), "Later")
    }

    // MARK: - Past region

    func test_pastOrigin_andHeader() {
        XCTAssertEqual(HorizonCopy.origin(began: date(2026, 3, 2), until: date(2026, 6, 28), calendar: cal),
                       "began Mar 2 · 118 days")
        XCTAssertEqual(HorizonCopy.pastHeader(year: 2026, count: 3), "Arrived in 2026 · 3 futures")
        XCTAssertEqual(HorizonCopy.pastHeader(year: 2026, count: 1), "Arrived in 2026 · 1 future")
    }

    // MARK: - Voice compliance (PRD §7.3)

    func test_noBannedWordsAnywhere() {
        let now = date(2026, 6, 17)
        let samples: [String] = [
            HorizonCopy.daysLeft(4), HorizonCopy.daysLeft(0), HorizonCopy.daysOver(2),
            HorizonCopy.feedBy(date(2026, 6, 20), now: now, calendar: cal),
            HorizonCopy.feedBy(date(2026, 6, 17), now: now, calendar: cal),
            HorizonCopy.rhythm(daysSinceLastFed: 5, typicalGap: 7 * day),
            HorizonCopy.daysSinceLast(14), HorizonCopy.usualRhythm(typicalGap: 7 * day),
            HorizonCopy.onCourse(3), HorizonCopy.collapsedCount(5), HorizonCopy.nothingToday,
        ] + TimeBucket.allCases.map(HorizonCopy.bucketTitle)

        // Whole-word matching: "over" (in "2d over") is allowed, "overdue" is not;
        // "Later" is a bucket title, not the adjective "late".
        let banned: Set<String> = ["behind", "late", "failing", "overdue", "streak"]
        for text in samples {
            let words = text.lowercased().split { !$0.isLetter }.map(String.init)
            for word in words {
                XCTAssertFalse(banned.contains(word), "\"\(text)\" uses banned word \"\(word)\"")
            }
        }
    }
}
