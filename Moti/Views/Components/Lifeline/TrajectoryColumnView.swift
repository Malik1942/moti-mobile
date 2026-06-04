import Foundation
import SwiftUI

enum TrajectoryColumnRegion {
    case evidence
    case future
}

/// One future drawn as a vertical column on the shared time axis (PRD §5–§6.1):
/// recent actual marks above Now, the present-moment node at the Now band, solid
/// committed near-term plans just below, then the **dashed, fading projection**
/// against a goal/deadline tick. The four trajectory outcomes are legible from
/// the projected path alone; solid vs dashed is the certainty channel; color is
/// identity only. Static (Canvas) — reduced-motion safe by construction.
struct TrajectoryColumnView: View {
    let strand: Strand
    let axis: TrajectoryAxis
    let region: TrajectoryColumnRegion
    let contentHeight: CGFloat

    private var color: Color { .projectToken(strand.colorToken) }
    private var outcome: TrajectoryOutcome { strand.trajectory.outcome }
    private var isAchievement: Bool { strand.effectiveType == .achievement }

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
        switch region {
        case .evidence:
            drawEvidence(in: &ctx, cx: cx)
        case .future:
            drawFuture(in: &ctx, cx: cx, size: size)
        }
    }

    private func drawEvidence(in ctx: inout GraphicsContext, cx: CGFloat) {
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
            let opacity = strand.presence.state == .drifted ? 0.0 : 0.32
            let start = CGPoint(x: cx - identityDrift * 0.08, y: min(topMost, nowY))
            let end = CGPoint(x: cx, y: nowY)
            drawSolidRibbon(in: &ctx, from: start, to: end, width: 3.8, opacity: opacity, glow: false)
        }
        // --- Present-moment node at the Now band ---------------------------
        drawPresentNode(in: &ctx, cx: cx, nowY: nowY)
    }

    private func drawFuture(in ctx: inout GraphicsContext, cx: CGFloat, size: CGSize) {
        if strand.isPaused {
            drawPaused(in: &ctx, cx: cx)
            return
        }

        // --- Solid certain segment: now → committed near-term --------------
        let solidEndDays = solidExtentDays
        let solidEndY = futureY(daysFromNow: solidEndDays)
        let solidEndX = futureX(cx: cx, y: solidEndY, size: size, emphasis: .certain)
        drawCertainRibbon(in: &ctx, from: CGPoint(x: cx, y: 0), to: CGPoint(x: solidEndX, y: solidEndY))

        // Committed forward nodes as small squares. They carry meaning by form,
        // not task titles; titles stay in Peek/Projects.
        for node in strand.forwardNodes where !node.isDeadline {
            guard let d = node.date else { continue }
            let dd = d.timeIntervalSince(axis.now) / 86_400
            guard dd > 0 else { continue }
            let y = futureY(daysFromNow: dd)
            guard y >= -4, y <= size.height + 4 else { continue }
            let x = futureX(cx: cx, y: y, size: size, emphasis: .certain)
            drawCommittedNode(in: &ctx, cx: x, y: y)
        }

        // --- Dashed, fading projection ------------------------------------
        drawProjection(in: &ctx, cx: cx, from: CGPoint(x: solidEndX, y: solidEndY), size: size)
    }

    private func drawPresentNode(in ctx: inout GraphicsContext, cx: CGFloat, nowY: CGFloat) {
        let glowR: CGFloat = 9
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - glowR, y: nowY - glowR, width: glowR * 2, height: glowR * 2)),
            with: .color(color.opacity(0.12))
        )
        let r: CGFloat = 5.5
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

    private func drawPaused(in ctx: inout GraphicsContext, cx: CGFloat) {
        let endY = futureY(daysFromNow: axis.nearDays)
        drawProjectedRibbon(
            in: &ctx,
            from: CGPoint(x: cx, y: 0),
            to: CGPoint(x: cx - 4, y: endY),
            startWidth: 5.2,
            endWidth: 4.2,
            startOpacity: 0.42,
            endOpacity: 0.25,
            segmentCount: 13,
            gapEvery: 2,
            glow: true
        )
        drawInlineLabel("Paused", in: &ctx, cx: cx - 5, y: endY + 9, size: CGSize(width: 56, height: contentHeight), prominent: true)
    }

    private func drawProjection(in ctx: inout GraphicsContext, cx: CGFloat, from: CGPoint, size: CGSize) {
        switch outcome {
        case .onTime, .behind:
            guard let deadline = strand.deadline else { return }
            let tickY = max(0, futureY(date: deadline))
            let dueX = futureX(cx: cx, y: tickY, size: size, emphasis: .target)
            drawDeadlineMarker(in: &ctx, cx: dueX, y: tickY, size: size, date: deadline, labeled: outcome == .behind)
            // On-time meets the marker; behind overshoots past it (gap = slippage,
            // directional — not a measured distance).
            if outcome == .behind {
                let lateY = tickY + behindOvershoot
                let lateX = futureX(cx: cx, y: lateY, size: size, emphasis: .late)
                drawProjectedRibbon(
                    in: &ctx,
                    from: from,
                    to: CGPoint(x: dueX, y: tickY),
                    startWidth: 5.6,
                    endWidth: 4.4,
                    startOpacity: 0.58,
                    endOpacity: 0.34,
                    segmentCount: 12,
                    gapEvery: 3,
                    glow: true
                )
                drawProjectedRibbon(
                    in: &ctx,
                    from: CGPoint(x: dueX, y: tickY),
                    to: CGPoint(x: lateX, y: lateY),
                    startWidth: 4.4,
                    endWidth: 2.2,
                    startOpacity: 0.32,
                    endOpacity: 0.05,
                    segmentCount: 6,
                    gapEvery: 2,
                    glow: false
                )
            } else {
                drawProjectedRibbon(
                    in: &ctx,
                    from: from,
                    to: CGPoint(x: dueX, y: tickY),
                    startWidth: 5.4,
                    endWidth: 3.4,
                    startOpacity: 0.58,
                    endOpacity: 0.22,
                    segmentCount: 12,
                    gapEvery: 3,
                    glow: true
                )
            }

        case .sustained:
            // Continues at a steady rhythm through the near future, without a
            // deadline target marker.
            let endY = min(size.height - axis.bottomPadding * 0.5, futureY(daysFromNow: 30))
            let endX = futureX(cx: cx, y: endY, size: size, emphasis: .steady)
            drawProjectedRibbon(
                in: &ctx,
                from: from,
                to: CGPoint(x: endX, y: endY),
                startWidth: 5.2,
                endWidth: 3.2,
                startOpacity: 0.48,
                endOpacity: 0.18,
                segmentCount: 14,
                gapEvery: 4,
                glow: true
            )

        case .fading:
            // Thins, drifts sideways, and ends before the next horizon.
            let endY = min(size.height - axis.bottomPadding, from.y + CGFloat(12) * axis.pointsPerDay)
            let endX = futureX(cx: cx, y: endY, size: size, emphasis: .fading)
            drawProjectedRibbon(
                in: &ctx,
                from: from,
                to: CGPoint(x: endX, y: endY),
                startWidth: 5.0,
                endWidth: 1.0,
                startOpacity: 0.38,
                endOpacity: 0.0,
                segmentCount: 9,
                gapEvery: 2,
                glow: false
            )
            drawDissolveEnd(in: &ctx, cx: endX, y: endY)
            drawInlineLabel("Fading", in: &ctx, cx: endX, y: endY + 9, size: size, prominent: true)
        }
    }

    private func drawCertainRibbon(in ctx: inout GraphicsContext, from: CGPoint, to: CGPoint) {
        let width: CGFloat = outcome.needsAttention ? 6.2 : 5.4
        drawSolidRibbon(in: &ctx, from: from, to: to, width: width + 6, opacity: 0.09, glow: false)
        drawSolidRibbon(in: &ctx, from: from, to: to, width: width, opacity: 0.76, glow: false)
        drawRibbonHighlight(in: &ctx, from: from, to: to, width: max(1.2, width * 0.28), opacity: 0.26)
    }

    private func drawSolidRibbon(
        in ctx: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        width: CGFloat,
        opacity: Double,
        glow: Bool
    ) {
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: ribbonControl(from: from, to: to))
        ctx.stroke(
            path,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
        if glow {
            ctx.stroke(
                path,
                with: .color(color.opacity(opacity * 0.18)),
                style: StrokeStyle(lineWidth: width + 7, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawRibbonHighlight(in ctx: inout GraphicsContext, from: CGPoint, to: CGPoint, width: CGFloat, opacity: Double) {
        var path = Path()
        let start = CGPoint(x: from.x - 1.1, y: from.y)
        let end = CGPoint(x: to.x - 0.8, y: to.y)
        path.move(to: start)
        path.addQuadCurve(to: end, control: ribbonControl(from: start, to: end))
        ctx.stroke(
            path,
            with: .color(Color.white.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawProjectedRibbon(
        in ctx: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        startOpacity: Double,
        endOpacity: Double,
        segmentCount: Int,
        gapEvery: Int,
        glow: Bool
    ) {
        guard to.y > from.y, segmentCount > 0 else { return }
        if glow {
            drawSegmentedRibbonLayer(
                in: &ctx,
                from: from,
                to: to,
                startWidth: startWidth + 7,
                endWidth: endWidth + 4,
                startOpacity: startOpacity * 0.12,
                endOpacity: endOpacity * 0.08,
                segmentCount: segmentCount,
                gapEvery: gapEvery
            )
        }
        drawSegmentedRibbonLayer(
            in: &ctx,
            from: from,
            to: to,
            startWidth: startWidth,
            endWidth: endWidth,
            startOpacity: startOpacity,
            endOpacity: endOpacity,
            segmentCount: segmentCount,
            gapEvery: gapEvery
        )
        drawSegmentedRibbonLayer(
            in: &ctx,
            from: CGPoint(x: from.x - 0.9, y: from.y),
            to: CGPoint(x: to.x - 0.7, y: to.y),
            startWidth: max(1, startWidth * 0.22),
            endWidth: max(0.5, endWidth * 0.18),
            startOpacity: startOpacity * 0.28,
            endOpacity: endOpacity * 0.18,
            segmentCount: segmentCount,
            gapEvery: gapEvery
        )
    }

    private func drawSegmentedRibbonLayer(
        in ctx: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        startOpacity: Double,
        endOpacity: Double,
        segmentCount: Int,
        gapEvery: Int
    ) {
        let control = ribbonControl(from: from, to: to)
        for index in 0..<segmentCount {
            guard gapEvery <= 1 || index % gapEvery != gapEvery - 1 else { continue }
            let t0 = CGFloat(index) / CGFloat(segmentCount)
            let t1 = CGFloat(index + 1) / CGFloat(segmentCount) - 0.018
            let mid = (t0 + t1) / 2
            let start = quadraticPoint(t0, from: from, control: control, to: to)
            let end = quadraticPoint(max(t0, t1), from: from, control: control, to: to)
            let cp = quadraticPoint(mid, from: from, control: control, to: to)
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: cp)
            ctx.stroke(
                path,
                with: .color(color.opacity(lerp(startOpacity, endOpacity, Double(mid)))),
                style: StrokeStyle(
                    lineWidth: lerp(startWidth, endWidth, mid),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func ribbonControl(from: CGPoint, to: CGPoint) -> CGPoint {
        let shallowBend = min(5, max(-5, (to.x - from.x) * 0.55 + identityDrift * 0.18))
        return CGPoint(x: (from.x + to.x) / 2 + shallowBend, y: (from.y + to.y) / 2)
    }

    private func quadraticPoint(_ t: CGFloat, from: CGPoint, control: CGPoint, to: CGPoint) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x,
            y: inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y
        )
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        start + (end - start) * min(1, max(0, t))
    }

    private func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
        start + (end - start) * min(1, max(0, t))
    }

    private func drawDeadlineMarker(in ctx: inout GraphicsContext, cx: CGFloat, y: CGFloat, size: CGSize, date: Date, labeled: Bool) {
        var tick = Path()
        tick.move(to: CGPoint(x: cx - 6, y: y))
        tick.addLine(to: CGPoint(x: cx + 6, y: y))
        ctx.stroke(tick, with: .color(.secondary.opacity(0.42)), lineWidth: 1.2)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(color.opacity(0.58)))
        if labeled {
            drawInlineLabel("Due\n\(Self.markerDate.string(from: date))", in: &ctx, cx: cx, y: y - 18, size: size, prominent: true)
        }
    }

    private func drawCommittedNode(in ctx: inout GraphicsContext, cx: CGFloat, y: CGFloat) {
        let rect = CGRect(x: cx - 2.8, y: y - 2.8, width: 5.6, height: 5.6)
        let path = Path(roundedRect: rect, cornerRadius: 1.5)
        ctx.fill(path, with: .color(color.opacity(0.56)))
        ctx.stroke(path, with: .color(Color.white.opacity(0.55)), lineWidth: 0.8)
    }

    private func drawProjectedOutcome(in ctx: inout GraphicsContext, cx: CGFloat, y: CGFloat, emphatic: Bool) {
        var diamond = Path()
        diamond.move(to: CGPoint(x: cx, y: y - 5))
        diamond.addLine(to: CGPoint(x: cx + 5, y: y))
        diamond.addLine(to: CGPoint(x: cx, y: y + 5))
        diamond.addLine(to: CGPoint(x: cx - 5, y: y))
        diamond.closeSubpath()
        if emphatic {
            ctx.fill(diamond, with: .color(color.opacity(0.78)))
        } else {
            ctx.stroke(diamond, with: .color(color.opacity(0.55)), lineWidth: 1.4)
        }
    }

    private func drawDissolveEnd(in ctx: inout GraphicsContext, cx: CGFloat, y: CGFloat) {
        let opacities: [Double] = [0.36, 0.22, 0.12]
        for (index, opacity) in opacities.enumerated() {
            let offset = CGFloat(index) * 4
            let r: CGFloat = max(1.1, 2.4 - CGFloat(index) * 0.45)
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r + offset, y: y - r + offset * 0.25, width: r * 2, height: r * 2)),
                with: .color(color.opacity(opacity))
            )
        }
    }

    private func drawInlineLabel(
        _ text: String,
        in ctx: inout GraphicsContext,
        cx: CGFloat,
        y: CGFloat,
        size: CGSize,
        prominent: Bool = false
    ) {
        let x = min(size.width - 16, max(16, cx))
        ctx.draw(
            Text(text)
                .font(.system(size: 8.5, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.78)),
            at: CGPoint(x: x, y: y),
            anchor: .center
        )
    }

    // MARK: - Derived

    private func futureY(daysFromNow days: Double) -> CGFloat {
        axis.y(daysFromNow: days) - axis.nowY
    }

    private func futureY(date: Date) -> CGFloat {
        axis.y(date: date) - axis.nowY
    }

    private enum PathEmphasis {
        case certain
        case target
        case late
        case steady
        case fading
    }

    private func futureX(cx: CGFloat, y: CGFloat, size: CGSize, emphasis: PathEmphasis) -> CGFloat {
        let drift = identityDrift
        let raw: CGFloat
        switch emphasis {
        case .certain:
            raw = drift * 0.25 + (isAchievement ? 0 : (outcome == .fading ? -4 : 4))
        case .target:
            raw = drift * 0.35 + (isAchievement ? 0 : 3)
        case .late:
            raw = drift * 0.35 + 11
        case .steady:
            raw = drift * 0.4 + 6
        case .fading:
            raw = drift * 0.35 - 12
        }
        return min(size.width - 10, max(10, cx + raw))
    }

    private var identityDrift: CGFloat {
        let seed = strand.id.unicodeScalars.reduce(0) { partial, scalar in
            (partial + Int(scalar.value)) % 9
        }
        let bucket = seed - 4
        return CGFloat(bucket)
    }

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

    private static let markerDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

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
