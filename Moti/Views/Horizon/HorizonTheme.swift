import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Horizon Timeline v2 — T6. The single source of design truth for the Horizon
// surface (PRD §7). Views consume ONLY these tokens — no hardcoded values that
// should be tokens.
//
// Near-monochrome with exactly ONE accent: a desaturated amber for divergence
// and overdue signals. There is deliberately NO red token. The current axis
// timeline's red overdue marker (`MotiTheme.today = systemRed`) is consciously
// re-expressed as amber here (PRD §7.1: "No red anywhere on this surface").
// Horizon views must never reference `MotiTheme.today` or `Color.motiAccent`
// (systemBlue) — colour scarcity is what makes the amber legible.

enum HorizonTheme {

    // MARK: - Colour (semantic only)

    /// The one accent on this surface, in both appearances: a desaturated amber
    /// for divergence / overdue. Statement, not blame — never red. Tuned from the
    /// app's existing muted "amber-stone" so it sits in the same family as the
    /// adjacent trajectory surface.
    static let divergenceAccent = dynamic(light: (0.62, 0.46, 0.16), dark: (0.80, 0.64, 0.32))

    static let primaryLabel = Color.primary
    static let secondaryLabel = Color.secondary
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

    /// System grouped backgrounds so content scrolls under sticky material headers.
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    /// The one hairline weight/colour on this surface — reuses the house
    /// `subtleStroke` (separator @ 0.14) paired with `hairlineWidth` (0.5).
    static let hairline = MotiTheme.subtleStroke
    /// Quiet fill behind the folded "on course" summary row.
    static let foldFill = Color(uiColor: .secondarySystemFill)

    // MARK: - Type

    /// Strand name — the anchor of the row.
    static let nameStyle = Font.body.weight(.semibold)
    /// Countdown numerals — SF Pro Rounded, monospaced digits so numbers don't
    /// jitter as they change (PRD §7.1).
    static let countdownStyle = Font.system(.body, design: .rounded).weight(.semibold).monospacedDigit()
    /// Secondary / rhythm line.
    static let secondaryStyle = Font.subheadline
    /// The folded "N on course" / count row.
    static let foldStyle = Font.subheadline
    /// Sticky bucket header.
    static let bucketHeaderStyle = Font.footnote.weight(.semibold)
    /// Letter-spacing applied to bucket headers for the small-caps feel (PRD §7.1).
    static let bucketHeaderTracking: CGFloat = 0.5

    // MARK: - Metrics

    static let rowMinHeight: CGFloat = 52
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 20
    /// Custom type-glyph size (optically aligned to the text baseline).
    static let glyphSize: CGFloat = 8
    static let hairlineWidth: CGFloat = 0.5
    static let rowVerticalPadding: CGFloat = 9
    static let glyphToNameGap: CGFloat = 12
    /// Gap between the primary line and the (optional) second line.
    static let secondLineGap: CGFloat = 3

    // MARK: - Motion (PRD §7.2)

    /// The single content spring. No linear / ease-in-out on content.
    static let settleSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Per-row stagger for the bucket-migration entrance (T15).
    static let staggerDelay: Double = 0.04

    /// All motion is gated on this — Reduce Motion means no animation (PRD §7.2).
    static var motionEnabled: Bool {
        #if canImport(UIKit)
        !UIAccessibility.isReduceMotionEnabled
        #else
        true
        #endif
    }

    // MARK: - Helpers

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}
