//
// HorizonBucketMemoryTests.swift
//
// Horizon Timeline v2 — T15. Detecting strands that moved toward Now between
// snapshots, so they can be animated in. First open animates nothing.
//

import XCTest
@testable import Moti

final class HorizonBucketMemoryTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 2
        return c
    }()
    private lazy var now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!

    private func snap(dueOffset: Double) -> HorizonSnapshot {
        let s = HorizonStrand(id: "x", name: "X", colorToken: "blue",
                              kind: .achievement(due: now.addingTimeInterval(dueOffset * day)),
                              type: .achievement)
        return HorizonSnapshotBuilder.makeSnapshot(active: [s], completed: [], now: now, calendar: cal)
    }
    private func fresh() -> HorizonBucketMemory {
        HorizonBucketMemory(defaults: UserDefaults(suiteName: "horizon.bm.\(UUID().uuidString)")!)
    }

    func test_firstOpen_animatesNothing() {
        XCTAssertTrue(fresh().migratedIDs(in: snap(dueOffset: 40)).isEmpty)
    }

    func test_movingToANearerBucket_isMigrated() {
        let memory = fresh()
        memory.record(snap(dueOffset: 40)) // Later
        XCTAssertEqual(memory.migratedIDs(in: snap(dueOffset: 1)), ["x"]) // Tomorrow — nearer
    }

    func test_movingFartherOrStaying_isNotMigrated() {
        let memory = fresh()
        memory.record(snap(dueOffset: 1)) // Tomorrow
        XCTAssertTrue(memory.migratedIDs(in: snap(dueOffset: 40)).isEmpty, "moved farther → no entrance")
        memory.record(snap(dueOffset: 40))
        XCTAssertTrue(memory.migratedIDs(in: snap(dueOffset: 40)).isEmpty, "same bucket → no entrance")
    }

    func test_persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "horizon.bm.\(UUID().uuidString)")!
        HorizonBucketMemory(defaults: defaults).record(snap(dueOffset: 40))
        XCTAssertEqual(HorizonBucketMemory(defaults: defaults).migratedIDs(in: snap(dueOffset: 1)), ["x"])
    }
}
