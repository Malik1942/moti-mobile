import SwiftUI

/// One future drawn as a vertical column on the shared time axis (PRD §5–§6.1):
/// recent actual marks above Now, the present-moment node at the Now band, solid
/// committed near-term plans just below, then the **dashed, fading projection**
/// against a goal/deadline tick. The four trajectory outcomes are legible from
/// the projected path alone; solid vs dashed is the certainty channel; color is
/// identity only. Static (Canvas) — reduced-motion safe by construction.
struct TrajectoryColumnView: View {
    let strand: Strand
    let axis: TrajectoryAxis
    let contentHeight: CGFloat

    private var color: Color { .projectToken(strand.colorToken) }
    private var outcome: TrajectoryOutcome { strand.trajectory.outcome }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            draw(in: &ctx, cx: cx, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentHeight)
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext, cx: CGFloat, size: CGSize) {
        let nowY = axis.nowY

        // --- Bounded recent past: actual marks above Now -------------------
        let pastMarks = strand.lastTraces
            .map { axis.y(date: $0.date) }
            .filter { $0 <= nowY + 1 && $0 >= axis.topPadding - 2 }
        for y in pastMarks {
            let r: CGFloat = 2.4
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(color.opacity(0.8)))
        }
        // A faint thread connecting the recent past up to Now (presence trail).
        if let topMost = pastMarks.max() {
            var trail = Path()
            trail.move(to: CGPoint(x: cx, y: min(topMost, nowY)))
            trail.addLine(to: CGPoint(x: cx, y: nowY))
            ctx.stroke(trail, with: .color(color.opacity(strand.presence.state == .drifted ? 0.0 : 0.35)),
                       style: StrokeStyle(lineWidth: 1.5))
        }

        // --- Present-moment node at the Now band ---------------------------
        drawPresentNode(in: &ctx, cx: cx, nowY: nowY)

        if strand.isPaused {
            drawPaused(in: &ctx, cx: cx, nowY: nowY)
            return
        }

        // --- Solid certain segment: now → committed near-term --------------
        let solidEndDays = solidExtentDays
        let solidEndY = axis.y(daysFromNow: solidEndDays)
        var solid = Path()
        solid.move(to: CGPoint(x: cx, y: nowY))
        solid.addLine(to: CGPoint(x: cx, y: solidEndY))
        ctx.stroke(solid, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

        // committed forward nodes as points on the solid part
        for node in strand.forwardNodes where !node.isDeadline {
            guard let d = node.date else { continue }
            let dd = d.timeIntervalSince(axis.now) / 86_400
            guard dd > 0, dd <= solidEndDays + 0.5 else { continue }
            let y = axis.y(daysFromNow: dd)
            let r: CGFloat = 3
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(color))
        }

        // --- Dashed, fading projection ------------------------------------
        drawProjection(in: &ctx, cx: cx, fromY: solidEndY, size: size)
    }

    private func drawPresentNode(in ctx: inout GraphicsContext, cx: CGFloat, nowY: CGFloat) {
        let r: CGFloat = 5
        let rect = CGRect(x: cx - r, y: nowY - r, width: r * 2, height: r * 2)
        let circle = Path(ellipseIn: rect)
        switch strand.presence.state {
        case .active:
            ctx.fill(circle, with: .color(color))
        case .quiet:
            ctx.stroke(circle, with: .color(color.opacity(0.7)), lineWidth: 1.5)
        case .drifted:
            // The drift gap: a faint empty ring at Now with nothing arriving.
            ctx.stroke(circle, with: .color(.secondary.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }

    private func drawPaused(in ctx: inout GraphicsContext, cx: CGFloat, nowY: CGFloat) {
        var dashed = Path()
        dashed.move(to: CGPoint(x: cx, y: nowY))
        dashed.addLine(to: CGPoint(x: cx, y: axis.y(daysFromNow: axis.nearDays)))
        ctx.stroke(dashed, with: .color(color.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1.6, dash: [3, 5]))
    }

    private func drawProjection(in ctx: inout GraphicsContext, cx: CGFloat, fromY: CGFloat, size: CGSize) {
        let dash = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4])

        switch outcome {
        case .onTime, .behind:
            guard let deadline = strand.deadline else { return }
            let tickY = axis.y(date: deadline)
            drawDeadlineTick(in: &ctx, cx: cx, y: tickY)
            // On-time meets the marker; behind overshoots past it (gap = slippage,
            // directional — not a measured distance).
            let endY = outcome == .onTime ? tickY : tickY + behindOvershoot
            strokeFading(&ctx, cx: cx, fromY: fromY, toY: endY, dash: dash, baseOpacity: 0.9)
            // A node where the projection completes.
            let r: CGFloat = 3
            let endColor = outcome == .onTime ? color.opacity(0.9) : color.opacity(0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: endY - r, width: r * 2, height: r * 2)),
                     with: .color(endColor))

        case .sustained:
            // Continues at a steady rhythm, gently fading far out.
            strokeFading(&ctx, cx: cx, fromY: fromY, toY: size.height - axis.bottomPadding * 0.5,
                         dash: dash, baseOpacity: 0.75)

        case .fading:
            // Thins and fades to nothing over a short distance.
            let endY = fromY + CGFloat(14) * axis.pointsPerDay
            strokeFading(&ctx, cx: cx, fromY: fromY, toY: endY, dash: dash, baseOpacity: 0.55, fadeToZero: true)
        }
    }

    /// Stroke a vertical dashed segment whose opacity falls with distance
    /// (certainty decreases the further out you look).
    private func strokeFading(
        _ ctx: inout GraphicsContext, cx: CGFloat, fromY: CGFloat, toY: CGFloat,
        dash: StrokeStyle, baseOpacity: Double, fadeToZero: Bool = false
    ) {
        guard toY > fromY else { return }
        var path = Path()
        path.move(to: CGPoint(x: cx, y: fromY))
        path.addLine(to: CGPoint(x: cx, y: toY))
        let endOpacity = fadeToZero ? 0.0 : baseOpacity * 0.25
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [color.opacity(baseOpacity), color.opacity(endOpacity)]),
            startPoint: CGPoint(x: cx, y: fromY),
            endPoint: CGPoint(x: cx, y: toY)
        )
        ctx.stroke(path, with: shading, style: dash)
    }

    private func drawDeadlineTick(in ctx: inout GraphicsContext, cx: CGFloat, y: CGFloat) {
        var tick = Path()
        tick.move(to: CGPoint(x: cx - 7, y: y))
        tick.addLine(to: CGPoint(x: cx + 7, y: y))
        ctx.stroke(tick, with: .color(.secondary.opacity(0.55)), lineWidth: 1.5)
        // a small flag
        ctx.fill(Path(CGRect(x: cx + 7, y: y - 5, width: 5, height: 5)), with: .color(color.opacity(0.8)))
    }

    // MARK: - Derived

    /// How far down the solid (certain) segment runs, in days from Now: the
    /// later of the last committed plan and the signal-strength solid fraction.
    private var solidExtentDays: Double {
        let committed = strand.forwardNodes.compactMap { node -> Double? in
            guard let d = node.date, !node.isDeadline else { return nil }
            let dd = d.timeIntervalSince(axis.now) / 86_400
            return dd > 0 ? dd : nil
        }.max() ?? 0
        let bySignal = strand.trajectory.solidFraction * axis.nearDays
        return min(axis.nearDays, max(committed, bySignal, 3))
    }

    private var behindOvershoot: CGFloat { 26 } // directional slippage, not a number

    private var accessibilityText: String {
        let outcomeWord: String
        switch outcome {
        case .onTime:    outcomeWord = "on track for its deadline"
        case .behind:    outcomeWord = "slipping behind its deadline"
        case .sustained: outcomeWord = "sustained at its current rhythm"
        case .fading:    outcomeWord = "fading at the current pace"
        }
        return strand.isPaused ? "\(strand.name), paused" : "\(strand.name), \(outcomeWord)"
    }
}
