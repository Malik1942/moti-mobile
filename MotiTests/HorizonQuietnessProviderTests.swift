//
// HorizonQuietnessProviderTests.swift
//
// Horizon Timeline v2 — T4. The fold predicate (PRD §6.4). Phase-1 rule:
// quiet = not overdue AND not feed-approaching. Also proves the protocol is a
// clean injectable seam for the Phase-2 divergence provider.
//

import XCTest
@testable import Moti

final class HorizonQuietnessProviderTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let provider = CalmQuietnessProvider()

    private func strand(_ type: StrandType = .achievement, divergence: HorizonDivergence? = nil) -> HorizonStrand {
        HorizonStrand(id: "s", name: "S", colorToken: "blue",
                      kind: type == .achievement ? .achievement(due: nil) : .maintenance(lastFed: nil, typicalGap: nil),
                      type: type, divergence: divergence)
    }

    private func countdown(_ days: Int) -> CountdownPayload {
        CountdownPayload(daysRemaining: days, dueDate: Date(timeIntervalSince1970: 0))
    }

    private func rhythm(approaching: Bool) -> MaintenanceRhythm {
        MaintenanceRhythm(lastFed: Date(timeIntervalSince1970: 0), typicalGap: 7 * day,
                          nextFeedBy: Date(timeIntervalSince1970: 7 * day),
                          daysSinceLastFed: approaching ? 6 : 2,
                          daysUntilFeedBy: approaching ? 1 : 5,
                          isApproaching: approaching)
    }

    // MARK: - Phase-1 rule

    func test_overdueAchievement_isLoud() {
        XCTAssertFalse(provider.isQuiet(strand(), placement: .overdue(overdueDays: 2, countdown: countdown(-2))))
    }

    func test_feedOverdueMaintenance_isLoud() {
        XCTAssertFalse(provider.isQuiet(strand(.maintenance), placement: .feedOverdue(rhythm: rhythm(approaching: true))))
    }

    func test_feedApproaching_isLoud() {
        XCTAssertFalse(provider.isQuiet(strand(.maintenance),
                                        placement: .feedBy(bucket: .tomorrow, rhythm: rhythm(approaching: true))))
    }

    func test_feedNotApproaching_isQuiet() {
        XCTAssertTrue(provider.isQuiet(strand(.maintenance),
                                       placement: .feedBy(bucket: .nextWeek, rhythm: rhythm(approaching: false))))
    }

    func test_onTrackAchievement_isQuiet_evenWhenDueToday() {
        // Phase 1 has no divergence signal, so an on-track achievement folds
        // regardless of how near its due date is.
        XCTAssertTrue(provider.isQuiet(strand(), placement: .dueIn(bucket: .today, countdown: countdown(0))))
    }

    func test_noDueDate_andNoRhythm_areQuiet() {
        XCTAssertTrue(provider.isQuiet(strand(), placement: .achievementNoDueDate))
        XCTAssertTrue(provider.isQuiet(strand(.maintenance), placement: .maintenanceNoRhythm))
    }

    func test_phase1_ignoresDivergenceField() {
        // Divergence is the Phase-2 seam; the Phase-1 provider must not read it.
        let diverging = HorizonDivergence(requiredDuration: 12 * day, exceedsThreshold: true, direction: .trendingLater)
        XCTAssertTrue(provider.isQuiet(strand(divergence: diverging),
                                       placement: .dueIn(bucket: .today, countdown: countdown(4))),
                      "Phase 1 folds an on-track row even if a divergence value is present")
    }

    // MARK: - Injectable seam

    /// A Phase-2-shaped provider: Phase-1 loudness OR divergence past threshold.
    private struct DivergenceStub: QuietnessProvider {
        func isQuiet(_ strand: HorizonStrand, placement: BucketPlacement) -> Bool {
            if !CalmQuietnessProvider().isQuiet(strand, placement: placement) { return false }
            return !(strand.divergence?.exceedsThreshold ?? false)
        }
    }

    func test_seam_divergenceProviderSurfacesWhatPhase1Folds() {
        let diverging = HorizonDivergence(requiredDuration: 12 * day, exceedsThreshold: true, direction: .trendingLater)
        let s = strand(divergence: diverging)
        let placement = BucketPlacement.dueIn(bucket: .today, countdown: countdown(4))

        let phase2: QuietnessProvider = DivergenceStub()
        XCTAssertTrue(provider.isQuiet(s, placement: placement), "Phase 1 folds it")
        XCTAssertFalse(phase2.isQuiet(s, placement: placement), "Phase 2 surfaces it — no change to rows/snapshot")
    }

    func test_seam_isPolymorphicThroughProtocol() {
        let providers: [QuietnessProvider] = [CalmQuietnessProvider(), DivergenceStub()]
        for p in providers {
            // An overdue strand is loud under every provider.
            XCTAssertFalse(p.isQuiet(strand(), placement: .overdue(overdueDays: 1, countdown: countdown(-1))))
        }
    }
}
