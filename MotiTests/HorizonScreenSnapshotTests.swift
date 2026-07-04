//
// HorizonScreenSnapshotTests.swift
//
// Horizon Timeline v2 — T12 state-sweep first pass. Renders the assembled
// HorizonView across the required states (PRD §6/§7) to PNGs for review:
// zero strands, only-maintenance, only-achievement, overdue pile-up, dark mode,
// Dynamic Type XXL, a 4-inch-class width, and an expanded-fold example.
//

import XCTest
import SwiftUI
@testable import Moti

final class HorizonScreenSnapshotTests: XCTestCase {

    private let outDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("horizon-shots")

    @MainActor
    private func render(_ name: String, _ view: some View,
                        scheme: ColorScheme = .light, type: DynamicTypeSize = .large,
                        width: CGFloat = 393, height: CGFloat = 1200) {
        let content = view
            .frame(width: width) // height is intrinsic (non-lazy list renders fully)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, type)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("no image for \(name)"); return
        }
        let path = (outDir as NSString).appendingPathComponent("\(name).png")
        try? data.write(to: URL(fileURLWithPath: path))
        print("HORIZON_SNAPSHOT \(name) -> \(path)")
    }

    private func horizon(_ snapshot: HorizonSnapshot, folds: HorizonFoldStore? = nil) -> HorizonView {
        HorizonView(snapshot: snapshot,
                    now: HorizonSnapshotPreviewData.now,
                    calendar: HorizonSnapshotPreviewData.calendar,
                    folds: folds ?? HorizonFoldStore(defaults: freshDefaults()),
                    scrolls: false) // non-lazy static list for faithful ImageRenderer output
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "horizon.snap.\(UUID().uuidString)")!
    }

    @MainActor
    func test_stateSweep() {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        render("screen-mixed-light", horizon(HorizonSnapshotPreviewData.mixed()))
        render("screen-mixed-dark", horizon(HorizonSnapshotPreviewData.mixed()), scheme: .dark)
        render("screen-mixed-xxl", horizon(HorizonSnapshotPreviewData.mixed()), type: .accessibility2, height: 2000)
        render("screen-mixed-narrow", horizon(HorizonSnapshotPreviewData.mixed()), width: 320)
        render("screen-empty-firstrun", horizon(HorizonSnapshotPreviewData.empty()), height: 500)
        render("screen-only-maintenance", horizon(HorizonSnapshotPreviewData.onlyMaintenance()), height: 800)
        render("screen-only-achievement", horizon(HorizonSnapshotPreviewData.onlyAchievement()), height: 800)
        render("screen-overdue-pileup", horizon(HorizonSnapshotPreviewData.overduePileUp()), height: 800)

        // Expanded folds: open the far buckets to prove expansion reveals rows.
        let expanded = HorizonFoldStore(defaults: freshDefaults())
        expanded.toggle(TimeBucket.later.rawValue)
        expanded.toggle(TimeBucket.restOfThisMonth.rawValue)
        expanded.toggle(TimeBucket.today.rawValue)
        render("screen-mixed-expanded", horizon(HorizonSnapshotPreviewData.mixed(), folds: expanded), height: 1500)

        print("HORIZON_SNAPSHOT_DIR=\(outDir)")
    }
}
