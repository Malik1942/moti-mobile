import SwiftUI

/// Shared geometry so every row's Now axis lines up into one column and the
/// parent can draw a single vertical "Now" rule through the nodes.
enum LifelineMetrics {
    static let nodeRadius: CGFloat = 5
    /// Distance from the track's trailing edge to the node centers.
    static let axisTrailingInset: CGFloat = nodeRadius + 1
}

/// One strand rendered as a lifeline: a label, a line that flows from the past
/// (left, receding) toward the fixed Now axis (right), a recency fade, and a
/// node — or, for a drifted strand, an **empty slot** at the axis.
///
/// This is the atom the Main Timeline composes. It is deliberately static (no
/// decorative animation) so it honors reduced-motion by construction, and its
/// state is legible in grayscale: the node *shape* (filled / hollow / empty) and
/// the *gap* before Now do the work; color only says which future this is.
struct LifelineView: View {
    let strand: Strand
    /// Pixel x of the shared Now axis inside the plot (so every row's axis lines
    /// up and the empty slot reads as one column).
    var labelWidth: CGFloat = 96
    var rowHeight: CGFloat = 46
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { .projectToken(strand.colorToken) }
    private var geo: LifelineGeometry { .make(for: strand) }

    var body: some View {
        HStack(spacing: 10) {
            label
            track
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this strand")
    }

    // MARK: - Label (identity + state word, never color-only)

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(strand.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(strand.presence.state == .drifted ? Color.primary : Color.primary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(stateWord)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(width: labelWidth, alignment: .leading)
    }

    // MARK: - Track (the line + node)

    private var track: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let nowX = size.width - LifelineMetrics.axisTrailingInset // node column
            let startX: CGFloat = 0
            let endX = startX + (nowX - startX) * geo.endFraction

            // Baseline "Now" tick is drawn by the parent across all rows; here we
            // only draw this strand's own line and node.

            // --- The line ---------------------------------------------------
            var line = Path()
            line.move(to: CGPoint(x: startX, y: midY))
            line.addLine(to: CGPoint(x: endX, y: midY))

            let style = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                dash: geo.isDashed ? [4, 5] : []
            )

            // Past recedes: fade in from the left. Trailing end carries the
            // recency intensity. For a drifted line, also fade out at the break.
            let leadColor = color.opacity(0.06)
            let bodyColor = color.opacity(geo.intensity)
            let tailColor = geo.node == .empty ? color.opacity(0.0) : bodyColor
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: leadColor, location: 0.0),
                    .init(color: bodyColor, location: geo.node == .empty ? 0.55 : 0.7),
                    .init(color: tailColor, location: 1.0)
                ]),
                startPoint: CGPoint(x: startX, y: midY),
                endPoint: CGPoint(x: endX, y: midY)
            )
            context.stroke(line, with: shading, style: style)

            // --- The node at the Now axis -----------------------------------
            let nodeRect = CGRect(
                x: nowX - nodeRadius, y: midY - nodeRadius,
                width: nodeRadius * 2, height: nodeRadius * 2
            )
            let circle = Path(ellipseIn: nodeRect)

            switch geo.node {
            case .filled:
                context.fill(circle, with: .color(color))
            case .hollow:
                context.stroke(circle, with: .color(color.opacity(0.7)), lineWidth: 1.5)
                context.fill(circle, with: .color(color.opacity(0.10)))
            case .empty:
                // The empty slot: a faint dashed ring with nothing arriving. This
                // is the loudest element on screen — the silence made visible.
                context.stroke(
                    circle,
                    with: .color(.secondary.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .drawingGroup() // flatten; also keeps it crisp. Static — no animation.
    }

    // MARK: - Derived presentation

    private var nodeRadius: CGFloat { LifelineMetrics.nodeRadius }

    private var lineWidth: CGFloat {
        switch strand.presence.state {
        case .active:  return 2.6
        case .quiet:   return 1.6
        case .drifted: return 2.0
        }
    }

    private var stateWord: String {
        if strand.isPaused { return "Paused" }
        switch strand.presence.state {
        case .active:  return "Active"
        case .quiet:   return "Quiet"
        case .drifted:
            if let d = strand.presence.daysSinceLastActivity { return "Drifted · \(d)d" }
            return "Drifted"
        }
    }

    private var accessibilityLabel: String {
        var parts = [strand.name]
        if strand.isPaused {
            parts.append("paused")
        } else {
            switch strand.presence.state {
            case .active: parts.append("active, reaching now")
            case .quiet:  parts.append("quiet, low activity")
            case .drifted:
                if let d = strand.presence.daysSinceLastActivity {
                    parts.append("drifted, quiet for \(d) days, not reaching now")
                } else {
                    parts.append("drifted, not reaching now")
                }
            }
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
private func previewStrand(
    _ name: String, color: String, state: PresenceState,
    days: Int?, paused: Bool = false, baseline: Double? = 7
) -> Strand {
    Strand(
        id: name, name: name, colorToken: color,
        computedType: .maintenance, userOverrideType: nil, eventCount: days == nil ? 0 : 3,
        presence: StrandPresence(
            state: state,
            reach: state == .active ? 0.9 : (state == .quiet ? 0.3 : 0),
            lastActivity: days.map { Date().addingTimeInterval(Double(-$0) * 86_400) },
            daysSinceLastActivity: days,
            baselineCadenceDays: baseline,
            baselineSource: .recurrence
        ),
        trajectory: .directional(state == .drifted ? .fading : .sustained),
        isPaused: paused, recurrenceCadenceDays: baseline, openCount: 2, deferredCount: 0,
        completedActionCount: 0, totalActionCount: 0,
        deadline: nil, forwardNodes: [], lastTraces: [], coOccurringStrandNames: []
    )
}

#Preview("Lifelines") {
    VStack(spacing: 0) {
        LifelineView(strand: previewStrand("Work", color: "blue", state: .active, days: 1))
        LifelineView(strand: previewStrand("Move", color: "purple", state: .active, days: 0))
        LifelineView(strand: previewStrand("Reading", color: "green", state: .quiet, days: 9))
        LifelineView(strand: previewStrand("Fitness", color: "orange", state: .drifted, days: 22))
        LifelineView(strand: previewStrand("Parents", color: "indigo", state: .drifted, days: 34, baseline: 7))
        LifelineView(strand: previewStrand("Spanish", color: "gray", state: .quiet, days: 6, paused: true))
    }
    .padding()
    .overlay(alignment: .trailing) {
        Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1).padding(.trailing, 5)
    }
}
#endif
