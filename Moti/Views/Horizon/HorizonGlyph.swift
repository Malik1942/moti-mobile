import SwiftUI

// Horizon Timeline v2 — type glyphs (PRD §6.3, §7.1). Custom 8pt shapes, no
// legend: filled circle = achievement (has a landing); half-ring = maintenance
// (cyclical). Optically aligned to the name's text baseline by the row scaffold.

/// The strand-type glyph. Near-monochrome by default (secondary label); the row
/// tints it amber only when the strand is a divergence/overdue signal.
struct HorizonGlyph: View {
    let type: StrandType
    var color: Color = HorizonTheme.secondaryLabel

    private var ringWidth: CGFloat { max(1, HorizonTheme.glyphSize * 0.22) }

    var body: some View {
        Group {
            switch type {
            case .achievement:
                // ● a solid landing point.
                Circle().fill(color)
            case .maintenance:
                // ◐ a ring with one half filled — a cycle, not a point.
                ZStack {
                    Circle().strokeBorder(color, lineWidth: ringWidth)
                    Circle()
                        .fill(color)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()      // left half opaque
                                Color.clear      // right half clear
                            }
                        )
                }
            }
        }
        .frame(width: HorizonTheme.glyphSize, height: HorizonTheme.glyphSize)
        .accessibilityHidden(true) // the row's combined label speaks the type
    }
}

#if DEBUG
#Preview("Glyphs") {
    HStack(spacing: 24) {
        HorizonGlyph(type: .achievement)
        HorizonGlyph(type: .maintenance)
        HorizonGlyph(type: .achievement, color: HorizonTheme.divergenceAccent)
        HorizonGlyph(type: .maintenance, color: HorizonTheme.divergenceAccent)
    }
    .scaleEffect(8) // enlarge to inspect the 8pt shapes
    .padding(60)
}
#endif
