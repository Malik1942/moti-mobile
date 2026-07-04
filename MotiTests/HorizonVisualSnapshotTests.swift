//
// HorizonVisualSnapshotTests.swift
//
// Horizon Timeline v2 — renders the row gallery to PNGs so the row rhythm,
// numeral alignment, baseline-aligned glyph, dark mode, and Dynamic Type XL can
// be eyeballed (T6/T7 visual validation; feeds the T12 sweep). Writes into the
// app's sandbox tmp and prints the host-visible path.
//

import XCTest
import SwiftUI
@testable import Moti

final class HorizonVisualSnapshotTests: XCTestCase {

    @MainActor
    func test_renderRowGallery_lightDarkAndXL() throws {
        let outDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("horizon-shots")
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let configs: [(name: String, scheme: ColorScheme, type: DynamicTypeSize)] = [
            ("light", .light, .large),
            ("dark", .dark, .large),
            ("xl", .light, .accessibility1),
        ]

        for config in configs {
            let content = HorizonRowGallery()
                .frame(width: 393)
                .environment(\.colorScheme, config.scheme)
                .environment(\.dynamicTypeSize, config.type)
                .background(config.scheme == .dark ? Color.black : HorizonTheme.background)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            renderer.isOpaque = true

            guard let image = renderer.uiImage, let data = image.pngData() else {
                XCTFail("ImageRenderer produced no image for \(config.name)")
                continue
            }
            let path = (outDir as NSString).appendingPathComponent("row-gallery-\(config.name).png")
            try data.write(to: URL(fileURLWithPath: path))
            print("HORIZON_SNAPSHOT \(config.name) -> \(path) (\(Int(image.size.width))x\(Int(image.size.height)))")
        }

        print("HORIZON_SNAPSHOT_DIR=\(outDir)")
    }
}
