//
// HorizonThemeTests.swift
//
// Horizon Timeline v2 — T6. Guards the design-token invariants (PRD §7.1):
// exactly one amber accent, NO red on this surface, and the metric tokens that
// downstream rows depend on.
//

import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import Moti

final class HorizonThemeTests: XCTestCase {

    private func rgba(_ color: Color, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    // MARK: - The one accent is amber, not red

    func test_divergenceAccent_isAmber_inBothAppearances() {
        for dark in [false, true] {
            let c = rgba(HorizonTheme.divergenceAccent, dark: dark)
            // Amber: warm, red ≳ green ≳ blue, with a substantial green channel —
            // the opposite of a red (which would have green/blue near zero).
            XCTAssertGreaterThan(c.r, c.g, "amber is warm (r > g), \(dark ? "dark" : "light")")
            XCTAssertGreaterThan(c.g, c.b, "amber has more green than blue")
            XCTAssertGreaterThan(c.g, 0.35, "green channel is substantial — not a red")
        }
    }

    func test_divergenceAccent_isNotSystemRed() {
        for dark in [false, true] {
            let accent = rgba(HorizonTheme.divergenceAccent, dark: dark)
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
            UIColor.systemRed.resolvedColor(with: traits).getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
            let distance = abs(accent.r - rr) + abs(accent.g - rg) + abs(accent.b - rb)
            XCTAssertGreaterThan(distance, 0.3, "divergence accent must be clearly distinct from systemRed")
        }
    }

    // MARK: - Metric tokens (downstream rows depend on these exact values)

    func test_metricTokens() {
        XCTAssertEqual(HorizonTheme.rowMinHeight, 52)
        XCTAssertEqual(HorizonTheme.leadingInset, 20)
        XCTAssertEqual(HorizonTheme.glyphSize, 8)
        XCTAssertEqual(HorizonTheme.hairlineWidth, 0.5)
    }
}
