//
// HorizonFoldStoreTests.swift
//
// Horizon Timeline v2 — fold expansion state persists per day and resets daily
// (PRD §6.4 / P1.4).
//

import XCTest
@testable import Moti

final class HorizonFoldStoreTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private func day(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "horizon.folds.test.\(UUID().uuidString)")!
    }

    func test_toggle_setsAndClears() {
        let store = HorizonFoldStore(now: day(2026, 6, 17), calendar: cal, defaults: freshDefaults())
        XCTAssertFalse(store.isExpanded("today"))
        store.toggle("today")
        XCTAssertTrue(store.isExpanded("today"))
        store.toggle("today")
        XCTAssertFalse(store.isExpanded("today"))
    }

    func test_persistsAcrossInstances_sameDay() {
        let defaults = freshDefaults()
        let morning = HorizonFoldStore(now: day(2026, 6, 17, 9), calendar: cal, defaults: defaults)
        morning.toggle("later")
        let evening = HorizonFoldStore(now: day(2026, 6, 17, 23), calendar: cal, defaults: defaults)
        XCTAssertTrue(evening.isExpanded("later"), "expansion survives within the same day")
    }

    func test_resetsOnNewDay() {
        let defaults = freshDefaults()
        let today = HorizonFoldStore(now: day(2026, 6, 17), calendar: cal, defaults: defaults)
        today.toggle("later")
        today.toggle("restOfThisMonth")
        let tomorrow = HorizonFoldStore(now: day(2026, 6, 18), calendar: cal, defaults: defaults)
        XCTAssertFalse(tomorrow.isExpanded("later"), "a new day opens fully folded")
        XCTAssertFalse(tomorrow.isExpanded("restOfThisMonth"))
        // and storage was cleared, so a third instance the same new day is still folded
        let alsoTomorrow = HorizonFoldStore(now: day(2026, 6, 18, 20), calendar: cal, defaults: defaults)
        XCTAssertFalse(alsoTomorrow.isExpanded("later"))
    }
}
