//
// HorizonStrandAdapterTests.swift
//
// Horizon Timeline v2 — the domain ↔ app seam. Maps an app `Strand` to the
// domain `HorizonStrand`: achievement deadline, maintenance last-fed + typical
// gap (declared cadence preferred over derived baseline), no engine types.
//

import XCTest
@testable import Moti

final class HorizonStrandAdapterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    private func presence(lastActivity: Date?, baselineCadenceDays: Double?) -> StrandPresence {
        StrandPresence(state: .quiet, reach: 0.5, lastActivity: lastActivity,
                       daysSinceLastActivity: nil, baselineCadenceDays: baselineCadenceDays,
                       baselineSource: baselineCadenceDays == nil ? .none : .history)
    }

    private func strand(type: StrandType, deadline: Date? = nil, recurrenceCadenceDays: Double? = nil,
                        lastActivity: Date? = nil, baselineCadenceDays: Double? = nil) -> Strand {
        let p = presence(lastActivity: lastActivity, baselineCadenceDays: baselineCadenceDays)
        let trajectory = TrajectoryProjector.project(events: [], type: type, presence: p, deadline: deadline,
                                                     completedCount: 0, totalCount: 0, now: now)
        return Strand(id: "s", name: "S", colorToken: "blue", computedType: type, userOverrideType: nil,
                      eventCount: 0, presence: p, trajectory: trajectory, isPaused: false,
                      recurrenceCadenceDays: recurrenceCadenceDays, openCount: 0, deferredCount: 0,
                      completedActionCount: 0, totalActionCount: 0, deadline: deadline,
                      forwardNodes: [], lastTraces: [], coOccurringStrandNames: [])
    }

    func test_achievement_mapsDeadline() {
        let due = now.addingTimeInterval(4 * day)
        let h = HorizonStrand(from: strand(type: .achievement, deadline: due))
        XCTAssertEqual(h.type, .achievement)
        XCTAssertEqual(h.kind, .achievement(due: due))
    }

    func test_achievement_noDeadline_mapsToNilDue() {
        let h = HorizonStrand(from: strand(type: .achievement, deadline: nil))
        XCTAssertEqual(h.kind, .achievement(due: nil))
    }

    func test_maintenance_prefersDeclaredCadenceOverBaseline() {
        let last = now.addingTimeInterval(-3 * day)
        let h = HorizonStrand(from: strand(type: .maintenance, recurrenceCadenceDays: 7,
                                           lastActivity: last, baselineCadenceDays: 30))
        XCTAssertEqual(h.kind, .maintenance(lastFed: last, typicalGap: 7 * day),
                       "declared cadence wins over derived baseline")
    }

    func test_maintenance_fallsBackToDerivedBaseline() {
        let last = now.addingTimeInterval(-2 * day)
        let h = HorizonStrand(from: strand(type: .maintenance, lastActivity: last, baselineCadenceDays: 5))
        XCTAssertEqual(h.kind, .maintenance(lastFed: last, typicalGap: 5 * day))
    }

    func test_maintenance_noCadence_hasNoRhythm() {
        let h = HorizonStrand(from: strand(type: .maintenance))
        XCTAssertEqual(h.kind, .maintenance(lastFed: nil, typicalGap: nil))
    }

    func test_carriesIdentity_andDivergenceIsNilInPhase1() {
        let h = HorizonStrand(from: strand(type: .achievement, deadline: now))
        XCTAssertEqual(h.id, "s")
        XCTAssertEqual(h.name, "S")
        XCTAssertEqual(h.colorToken, "blue")
        XCTAssertNil(h.divergence, "Phase 1 never fills the divergence seam")
    }
}
