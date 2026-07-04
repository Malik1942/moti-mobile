//
// HorizonSnapshotTests.swift
//
// Horizon Timeline v2 — T5. Deterministic snapshot assembly (PRD §6). A golden
// fixture strand set exercises every rule at once; focused tests pin individual
// behaviours. Anchor: Wednesday 2026-06-17 12:00 America/New_York, Monday-first.
//   today          [06-17, 06-18)
//   tomorrow       [06-18, 06-19)
//   restOfThisWeek [06-19, 06-22)
//   nextWeek       [06-22, 06-29)
//   restOfThisMonth[06-29, 07-01)
//   later          [07-01, ∞)
//

import XCTest
@testable import Moti

final class HorizonSnapshotTests: XCTestCase {

    private let day: TimeInterval = 86_400

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

    // MARK: - Fixture builders

    private func ach(_ id: String, due: Date?) -> HorizonStrand {
        HorizonStrand(id: id, name: id, colorToken: "blue", kind: .achievement(due: due), type: .achievement)
    }
    private func maint(_ id: String, lastFed: Date?, gap: TimeInterval?) -> HorizonStrand {
        HorizonStrand(id: id, name: id, colorToken: "green",
                      kind: .maintenance(lastFed: lastFed, typicalGap: gap), type: .maintenance)
    }

    /// The golden active set — one strand per placement branch across buckets.
    private func goldenActive() -> [HorizonStrand] {
        [
            ach("overdue", due: date(2026, 6, 15)),                       // today, pinned
            maint("feedOverdue", lastFed: date(2026, 6, 1), gap: 7 * day),// today, pinned (nextFeedBy 06-08)
            ach("todayOnTrack", due: date(2026, 6, 17, 18)),             // today, quiet
            maint("todayApproach", lastFed: date(2026, 6, 10, 15), gap: 7 * day), // today, loud (approaching)
            maint("tmrApproach", lastFed: date(2026, 6, 11), gap: 7 * day),      // tomorrow, loud
            ach("tmrOnTrack1", due: date(2026, 6, 18, 9)),              // tomorrow, quiet
            ach("tmrOnTrack2", due: date(2026, 6, 18, 20)),             // tomorrow, quiet
            ach("weekOnTrack", due: date(2026, 6, 20)),                  // restOfThisWeek, quiet
            ach("month1", due: date(2026, 6, 29)),                       // restOfThisMonth
            ach("month2", due: date(2026, 6, 30)),                       // restOfThisMonth
            ach("laterFar", due: date(2026, 9, 1)),                      // later
            ach("laterNoDue", due: nil),                                 // later
            maint("laterNoRhythm", lastFed: date(2026, 6, 1), gap: nil), // later
        ]
    }

    private func goldenCompleted() -> [HorizonCompletion] {
        [
            HorizonCompletion(id: "compA", name: "compA", colorToken: "purple",
                              completedAt: date(2026, 6, 14), origin: date(2026, 3, 2)),
            HorizonCompletion(id: "compB", name: "compB", colorToken: "indigo",
                              completedAt: date(2026, 5, 20), origin: date(2026, 1, 10)),
        ]
    }

    private func make(_ active: [HorizonStrand], _ completed: [HorizonCompletion] = [],
                      quietness: QuietnessProvider = CalmQuietnessProvider()) -> HorizonSnapshot {
        HorizonSnapshotBuilder.makeSnapshot(active: active, completed: completed,
                                            now: now, calendar: cal, quietness: quietness)
    }

    private func section(_ snap: HorizonSnapshot, _ bucket: TimeBucket) -> BucketSection? {
        snap.sections.first { $0.bucket == bucket }
    }

    // MARK: - Golden

    func test_golden_fullStructure() {
        let snap = make(goldenActive(), goldenCompleted())

        // Section order: nextWeek is empty → omitted.
        XCTAssertEqual(snap.sections.map(\.bucket),
                       [.today, .tomorrow, .restOfThisWeek, .restOfThisMonth, .later])

        // Today: pinned overdue first (by soonest action date), then loud, then fold.
        let today = section(snap, .today)!
        XCTAssertEqual(today.rows.map(\.strandID), ["feedOverdue", "overdue", "todayApproach"])
        XCTAssertEqual(today.rows.prefix(2).map(\.isPinnedToTodayTop), [true, true])
        XCTAssertFalse(today.rows[2].isPinnedToTodayTop)
        XCTAssertEqual(today.fold, FoldSummary(count: 1, strandIDs: ["todayOnTrack"], reason: .onCourse))

        // Tomorrow: one loud row, two folded on course.
        let tomorrow = section(snap, .tomorrow)!
        XCTAssertEqual(tomorrow.rows.map(\.strandID), ["tmrApproach"])
        XCTAssertEqual(tomorrow.fold, FoldSummary(count: 2, strandIDs: ["tmrOnTrack1", "tmrOnTrack2"], reason: .onCourse))

        // Rest of week: nothing loud → just the fold.
        let week = section(snap, .restOfThisWeek)!
        XCTAssertTrue(week.rows.isEmpty)
        XCTAssertEqual(week.fold, FoldSummary(count: 1, strandIDs: ["weekOnTrack"], reason: .onCourse))

        // Far buckets: collapsed count rows.
        XCTAssertEqual(section(snap, .restOfThisMonth)!.fold,
                       FoldSummary(count: 2, strandIDs: ["month1", "month2"], reason: .collapsedBucket))
        XCTAssertTrue(section(snap, .restOfThisMonth)!.rows.isEmpty)
        XCTAssertEqual(section(snap, .later)!.fold,
                       FoldSummary(count: 3, strandIDs: ["laterFar", "laterNoDue", "laterNoRhythm"], reason: .collapsedBucket))

        // Past: reverse-chronological, origins carried.
        XCTAssertEqual(snap.past.entries.map(\.strandID), ["compA", "compB"])
        XCTAssertEqual(snap.past.entries.first?.origin, date(2026, 3, 2))
    }

    func test_golden_isDeterministic() {
        XCTAssertEqual(make(goldenActive(), goldenCompleted()), make(goldenActive(), goldenCompleted()))
    }

    // MARK: - Empty / Today-always

    func test_empty_todayRendersEmpty_nothingElse() {
        let snap = make([], [])
        XCTAssertEqual(snap.sections.map(\.bucket), [.today])
        XCTAssertTrue(section(snap, .today)!.isEmpty, "empty Today still renders (voice line)")
        XCTAssertTrue(snap.past.isEmpty)
    }

    func test_emptyNearBucket_isOmitted_butTodayIsNot() {
        // Only a tomorrow strand: today renders empty, tomorrow renders, week/next omitted.
        let snap = make([ach("t", due: date(2026, 6, 18))])
        XCTAssertEqual(snap.sections.map(\.bucket), [.today, .tomorrow])
        XCTAssertTrue(section(snap, .today)!.isEmpty)
    }

    // MARK: - Far-bucket collapse

    func test_farBucket_collapsesEvenASingleStrand() {
        let snap = make([ach("far", due: date(2026, 9, 1))])
        let later = section(snap, .later)!
        XCTAssertTrue(later.rows.isEmpty)
        XCTAssertEqual(later.fold?.reason, .collapsedBucket)
        XCTAssertEqual(later.fold?.count, 1)
    }

    // MARK: - Injectable provider changes folding, not structure

    func test_injectingAlwaysLoud_unfoldsNearBuckets() {
        struct AlwaysLoud: QuietnessProvider {
            func isQuiet(_ strand: HorizonStrand, placement: BucketPlacement) -> Bool { false }
        }
        let snap = make(goldenActive(), quietness: AlwaysLoud())

        // Tomorrow's on-track strands now surface as rows; no on-course fold.
        let tomorrow = section(snap, .tomorrow)!
        XCTAssertEqual(Set(tomorrow.rows.map(\.strandID)), ["tmrApproach", "tmrOnTrack1", "tmrOnTrack2"])
        XCTAssertNil(tomorrow.fold)

        // Far buckets still collapse regardless of loudness (PRD §6.4).
        XCTAssertEqual(section(snap, .later)!.fold?.reason, .collapsedBucket)
        XCTAssertTrue(section(snap, .later)!.rows.isEmpty)
    }

    // MARK: - Past ordering

    func test_past_reverseChron_withStableTieBreak() {
        let sameDay = date(2026, 4, 1)
        let completed = [
            HorizonCompletion(id: "b", name: "b", colorToken: "blue", completedAt: sameDay, origin: date(2026, 1, 1)),
            HorizonCompletion(id: "a", name: "a", colorToken: "blue", completedAt: sameDay, origin: date(2026, 1, 1)),
            HorizonCompletion(id: "newer", name: "newer", colorToken: "blue", completedAt: date(2026, 5, 1), origin: date(2026, 2, 1)),
        ]
        let snap = make([], completed)
        XCTAssertEqual(snap.past.entries.map(\.strandID), ["newer", "a", "b"],
                       "most recent first; equal dates tie-break by id ascending")
    }
}
