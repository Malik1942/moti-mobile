import SwiftUI

/// Pure mapping from a strand's *computed* presence to the handful of drawing
/// quantities the strand rendering needs. Keeping this separate (and trivially
/// inspectable) honors PRD §14: every visual property maps to a computed
/// quantity — lines must not become decoration.
///
/// Note the division of labour: position-vs-Now and node shape carry **state**
/// (legible in grayscale); the identity color is layered on top by the view and
/// never appears here.
struct StrandGeometry: Equatable {

    /// How the endpoint meets the Now axis.
    enum Node: Equatable {
        /// Active — being fed; a solid filled node sits on the axis.
        case filled
        /// Quiet — present but low activity; a hollow, faint node just reaches.
        case hollow
        /// Drifted — the slot on the axis is **empty**; the line never arrives.
        case empty
    }

    /// Fraction of the plot width at which the drawn line ends, `0...1`
    /// (`1` = touches the Now axis). Reaching strands end at `1`; a drifted
    /// strand stops short, opening the gap that is the loudest element on screen.
    let endFraction: CGFloat

    /// Node drawn at the Now axis.
    let node: Node

    /// Deliberate set-down — drawn dashed and labeled, held distinct from drift.
    let isDashed: Bool

    /// Line opacity — the *texture* of recency (active bright → quiet faint).
    /// Always paired with the position/node signal, never the sole channel.
    let intensity: Double

    /// Whether the strand still reaches Now (false only for drift).
    var reachesNow: Bool { node != .empty }

    /// Derive geometry from a strand. Paused is decided here (it is a UI choice
    /// layered on the computed state, not something the event stream infers).
    static func make(for strand: Strand) -> StrandGeometry {
        if strand.isPaused {
            // n/a reach: a dashed line spans the window with a quiet hollow node.
            return StrandGeometry(endFraction: 1.0, node: .hollow, isDashed: true, intensity: 0.4)
        }

        switch strand.presence.state {
        case .active:
            return StrandGeometry(endFraction: 1.0, node: .filled, isDashed: false, intensity: 1.0)

        case .quiet:
            // Just reaches — a hair short of the axis, faint, hollow node.
            return StrandGeometry(endFraction: 0.97, node: .hollow, isDashed: false, intensity: 0.5)

        case .drifted:
            // Stops well short of Now. The break position is cadence-relative so a
            // monthly strand and a daily strand both break "a rhythm or two ago,"
            // not at a raw calendar distance. Clamped to stay clearly mid-plot so
            // the gap to the empty slot always reads.
            let break_ = driftBreakFraction(for: strand.presence)
            return StrandGeometry(endFraction: break_, node: .empty, isDashed: false, intensity: 0.6)
        }
    }

    /// Where a drifted line breaks, as a plot fraction. Further past the strand's
    /// own drift horizon → breaks earlier (more obviously gone), bounded so it is
    /// always a visible gap rather than vanishing entirely.
    static func driftBreakFraction(for presence: StrandPresence) -> CGFloat {
        guard
            let baseline = presence.baselineCadenceDays,
            let daysSince = presence.daysSinceLastActivity,
            baseline > 0
        else { return 0.45 }

        // 1.0 at the moment of drift, easing toward 0 as silence deepens.
        let horizon = baseline * 2 // matches PresencePolicy.driftMultiplier default
        let overshoot = (Double(daysSince) - horizon) / max(horizon, 1)
        let fraction = 0.55 - overshoot * 0.25
        return CGFloat(min(0.55, max(0.18, fraction)))
    }
}
