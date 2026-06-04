import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// **Main Timeline — the trajectory field** (PRD v2.1). Horizontal time,
/// vertically stacked projects: recent behavior sits left of Now, current pace
/// crosses the Now anchor, and the future projects rightward as silk strands.
/// Timeline remains directional and behavioral — detail and execution stay in
/// Peek, Plan, and Projects.
struct TrajectoryTimelineView: View {
    var onAddToTimeline: () -> Void = {}
    var onOpenInProjects: (String) -> Void = { _ in }

    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query private var completionLogs: [CompletionLog]
    @ObservedObject private var prefs = StrandPreferenceStore.shared
    @ObservedObject private var metrics = LifelineInstrumentation.shared
    #if DEBUG
    @ObservedObject private var typeOverrideStore = LifelineTypeOverrideStore.shared
    #endif

    @State private var peekStrand: Strand?
    @State private var didTapStrand = false
    @State private var surfacedStrandID: String?
    @State private var surfacedOutcomeRecorded = false
    @State private var selectedScale: TimelineScale = .month

    private let axis = TrajectoryAxis(now: .now)
    private let laneHeight: CGFloat = 62
    private let fieldHeaderHeight: CGFloat = 40
    private let fieldBottomPadding: CGFloat = 8

    // MARK: - Derived

    private var typeOverrides: [String: StrandType] {
        #if DEBUG
        return typeOverrideStore.overrides
        #else
        return [:]
        #endif
    }

    private var pausedIDs: Set<String> {
        Set((projects.map { $0.id.uuidString } + [Strand.unassignedID]).filter { prefs.isPaused($0) })
    }

    private var strands: [Strand] {
        StrandTimelineBuilder(
            projects: projects,
            workItems: WorkItemScope.timeline(workItems),
            completionLogs: completionLogs,
            now: axis.now,
            pausedStrandIDs: pausedIDs,
            typeOverrides: typeOverrides
        ).build()
    }

    private var attendedIDs: Set<String> {
        Set(strands.map(\.id).filter { prefs.isAttendedThisWeek($0) })
    }

    private var focus: TimelineFocus {
        TimelineNarrator.trajectoryFocus(for: strands, parkedIDs: attendedIDs)
    }

    private var hasContent: Bool { !projects.isEmpty || !workItems.isEmpty }

    private var visibleStrands: [Strand] { Array(strands.prefix(6)) }

    private var timelineFieldHeight: CGFloat {
        fieldHeaderHeight + CGFloat(max(visibleStrands.count, 1)) * laneHeight + fieldBottomPadding
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasContent {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            scaleSelector
                            headline
                            timelineSurface
                        }
                        .padding(.horizontal, MotiLayout.pagePadding)
                        .padding(.top, 8)
                        .padding(.bottom, MotiLayout.pageBottomPadding)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    emptyState
                        .padding(MotiLayout.pagePadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { recordOpen() }
            .onDisappear { recordClose() }
            .sheet(item: $peekStrand) { strand in
                StrandPeekSheet(strand: strand, onOpenInProjects: onOpenInProjects)
            }
            #if DEBUG
            .onAppear {
                if let name = UserDefaults.standard.string(forKey: "MotiPeekStrand"),
                   peekStrand == nil, let match = strands.first(where: { $0.name == name }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { peekStrand = match }
                }
            }
            #endif
        }
    }

    // MARK: - Top synthesized (forward-looking) sentence

    private var headline: some View {
        Text(TimelineNarrator.trajectoryHeadline(for: strands))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.84))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var scaleSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimelineScale.allCases) { scale in
                scaleButton(scale)
            }
        }
        .padding(4)
        .background(.secondary.opacity(0.055), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timeline scale, \(selectedScale.label) selected")
    }

    private func scaleButton(_ scale: TimelineScale) -> some View {
        let isSelected = selectedScale == scale
        return Button {
            selectedScale = scale
            haptic()
        } label: {
            Text(scale.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary.opacity(0.82) : Color.secondary.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.background)
                            .shadow(color: .black.opacity(0.035), radius: 4, x: 0, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var timelineField: some View {
        GeometryReader { proxy in
            let geometry = TimelineFieldGeometry(
                size: proxy.size,
                scale: selectedScale,
                now: axis.now,
                laneCount: visibleStrands.count
            )

            HStack(spacing: 0) {
                fixedIdentityColumn(geometry)

                TimelineChartViewport(
                    strands: visibleStrands,
                    geometry: geometry,
                    scaleID: selectedScale.id,
                    onTap: recordPeek
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, 10)
            .background(TrajectoryColorPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.secondary.opacity(0.045), lineWidth: 0.7)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityLabel("Timeline trajectory field")
    }

    private var timelineSurface: some View {
        VStack(spacing: 18) {
            timelineField
                .frame(height: timelineFieldHeight)

            focusCard
                .padding(.horizontal, 2)
        }
        .padding(.bottom, 8)
    }

    private func fixedIdentityColumn(_ geometry: TimelineFieldGeometry) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.headerHeight)
            ForEach(Array(visibleStrands.enumerated()), id: \.element.id) { _, strand in
                ProjectLaneLabel(strand: strand)
                    .frame(height: geometry.laneHeight)
            }
        }
        .frame(width: geometry.labelColumnWidth)
        .padding(.leading, 12)
        .padding(.trailing, 4)
    }

    // MARK: - "What matters now" (forward-looking)

    @ViewBuilder
    private var focusCard: some View {
        switch focus {
        case .calm(let message):
            calmCard(message)
        case .attention(let id, let title, let detail):
            attentionCard(strandID: id, title: title, detail: detail)
        }
    }

    private func calmCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.forward").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            Text(message).font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrajectoryColorPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What matters now: \(message)")
    }

    private func attentionCard(strandID: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WHAT MATTERS NOW").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary.opacity(0.72))
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary.opacity(0.88))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary.opacity(0.82))
            }
            HStack(spacing: 10) {
                gentleButton("Make space", filled: true) {
                    haptic(); recordOutcome(strandID: strandID, detail: "make-space"); prefs.makeSpaceThisWeek(strandID)
                }
                gentleButton("Not this week", filled: false) {
                    haptic(); recordOutcome(strandID: strandID, detail: "not-this-week"); prefs.parkForThisWeek(strandID)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrajectoryColorPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.secondary.opacity(0.045), lineWidth: 0.7))
    }

    private func gentleButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        let accent = TrajectoryColorPalette.color(for: "indigo", name: "Moti")
        return Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .foregroundStyle(filled ? Color.white.opacity(0.92) : accent.opacity(0.8))
                .background(filled ? accent.opacity(0.86) : accent.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MotiLayout.emptyStateSpacing) {
            Text("Your futures will appear here.").font(.headline)
            Text("As you capture and tend work, each future becomes a trajectory — and Moti projects, from your actual pace, where each one is heading.")
                .font(.motiEmptySubtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { onAddToTimeline() } label: { Label("Add to Timeline", systemImage: "plus") }
                .font(.motiButtonLabel).buttonStyle(.borderedProminent).tint(.indigo).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MotiLayout.cardPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
    }

    // MARK: - Instrumentation (local-only; PRD §9.4)

    private func recordOpen() {
        didTapStrand = false
        surfacedOutcomeRecorded = false
        let snap = metrics.coverage(for: strands)
        let attn = strands.filter { !$0.isPaused && $0.trajectory.outcome.needsAttention }.count
        metrics.record(.open, detail: "attention:\(attn) zero:\(snap.zeroEvents)/\(snap.total)")
        if case let .attention(id, _, _) = focus, let s = strands.first(where: { $0.id == id }) {
            surfacedStrandID = id
            metrics.record(.surface, strandID: id, effectiveType: s.effectiveType.rawValue,
                           presenceState: s.trajectory.outcome.rawValue)
        } else {
            surfacedStrandID = nil
        }
    }

    private func recordClose() {
        if let id = surfacedStrandID, !surfacedOutcomeRecorded {
            metrics.record(.outcome, strandID: id, detail: "ignored")
        }
        metrics.record(.close, detail: didTapStrand ? "tapped" : "glance-close")
    }

    private func recordPeek(_ strand: Strand) {
        didTapStrand = true
        metrics.record(.peek, strandID: strand.id, effectiveType: strand.effectiveType.rawValue,
                       presenceState: strand.trajectory.outcome.rawValue)
        peekStrand = strand
    }

    private func recordOutcome(strandID: String, detail: String) {
        if strandID == surfacedStrandID { surfacedOutcomeRecorded = true }
        metrics.record(.outcome, strandID: strandID, detail: detail)
    }

    private func haptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}

// MARK: - Horizontal trajectory field

private enum TrajectoryColorPalette {
    static func color(for token: String, name: String) -> Color {
        let normalized = token.lowercased()
        if let color = tokenColors[normalized] { return color }

        let palette = fallbackColors
        let seed = abs(name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return palette[seed % palette.count]
    }

    static var surface: Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.105, green: 0.108, blue: 0.118, alpha: 1)
            : UIColor(red: 0.985, green: 0.982, blue: 0.972, alpha: 1)
        })
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    static var plotWash: Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
            : UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1)
        })
        #else
        Color.secondary
        #endif
    }

    private static let tokenColors: [String: Color] = [
        "blue": color(light: (0.22, 0.47, 0.68), dark: (0.45, 0.65, 0.82)),     // soft cobalt
        "green": color(light: (0.34, 0.57, 0.42), dark: (0.48, 0.68, 0.52)),    // moss
        "purple": color(light: (0.55, 0.40, 0.66), dark: (0.68, 0.56, 0.78)),   // smoky lavender
        "indigo": color(light: (0.39, 0.43, 0.64), dark: (0.55, 0.58, 0.78)),   // muted indigo
        "orange": color(light: (0.73, 0.48, 0.27), dark: (0.82, 0.58, 0.38)),   // muted amber/coral
        "gray": color(light: (0.48, 0.49, 0.50), dark: (0.64, 0.65, 0.66))
    ]

    private static let fallbackColors: [Color] = [
        color(light: (0.28, 0.55, 0.58), dark: (0.48, 0.70, 0.72)), // muted teal
        color(light: (0.65, 0.39, 0.48), dark: (0.78, 0.55, 0.62)), // faded rose
        color(light: (0.56, 0.51, 0.40), dark: (0.72, 0.66, 0.52)), // warm stone
        color(light: (0.39, 0.50, 0.67), dark: (0.56, 0.66, 0.80)), // faded cyan
        color(light: (0.43, 0.44, 0.47), dark: (0.62, 0.63, 0.66))  // graphite
    ]

    private static func color(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            let values = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

private enum TimelineScale: String, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case sixMonths
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "1W"
        case .month: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .year: return "Y"
        }
    }

    var pastDays: Double {
        switch self {
        case .week: return 7
        case .month: return 28
        case .threeMonths: return 45
        case .sixMonths: return 90
        case .year: return 120
        }
    }

    var futureDays: Double {
        switch self {
        case .week: return 7
        case .month: return 28
        case .threeMonths: return 75
        case .sixMonths: return 120
        case .year: return 245
        }
    }

    var recentLabel: String {
        switch self {
        case .week: return "Past 7d"
        case .month: return "Past 4w"
        case .threeMonths: return "Past 6w"
        case .sixMonths: return "Past 3m"
        case .year: return "Past qtr"
        }
    }

    func nearFutureLabel(from now: Date) -> String {
        Self.shortDate.string(from: now.addingTimeInterval(futureDays * 0.38 * 86_400))
    }

    func laterLabel(from now: Date) -> String {
        Self.shortDate.string(from: now.addingTimeInterval(futureDays * 86_400))
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

private struct TimelineFieldGeometry {
    let size: CGSize
    let scale: TimelineScale
    let now: Date
    let laneCount: Int

    let labelColumnWidth: CGFloat = 86
    let headerHeight: CGFloat = 40
    let laneHeight: CGFloat = 62

    var chartViewportWidth: CGFloat { max(190, size.width - labelColumnWidth - 26) }
    var chartHeight: CGFloat { headerHeight + CGFloat(laneCount) * laneHeight + 4 }
    var contentWidth: CGFloat { chartViewportWidth * 1.9 }
    var nowX: CGFloat { chartViewportWidth * 0.65 }
    var defaultScrollX: CGFloat { max(0, nowX - chartViewportWidth * 0.25) }
    var visiblePastWidth: CGFloat { chartViewportWidth * 0.25 }
    var visibleFutureWidth: CGFloat { chartViewportWidth * 0.75 }
    var contentEndX: CGFloat { contentWidth - 12 }
    var trackTopY: CGFloat { 16 }
    var trackBottomY: CGFloat { headerHeight + CGFloat(laneCount) * laneHeight - 4 }

    var guideXs: [CGFloat] {
        [
            nowX - visiblePastWidth,
            nowX,
            nowX + visibleFutureWidth * 0.38,
            nowX + visibleFutureWidth
        ]
    }

    func laneTop(_ index: Int) -> CGFloat {
        headerHeight + CGFloat(index) * laneHeight
    }

    func laneCenterY(_ index: Int) -> CGFloat {
        laneTop(index) + laneHeight * 0.52
    }

    func x(date: Date) -> CGFloat {
        x(daysFromNow: date.timeIntervalSince(now) / 86_400)
    }

    func x(daysFromNow days: Double) -> CGFloat {
        if days < 0 {
            return nowX + CGFloat(days / scale.pastDays) * visiblePastWidth
        }
        return nowX + CGFloat(days / scale.futureDays) * visibleFutureWidth
    }
}

private struct TimelineChartViewport: View {
    let strands: [Strand]
    let geometry: TimelineFieldGeometry
    let scaleID: String
    let onTap: (Strand) -> Void

    private let defaultAnchorID = "trajectory-default-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    chartAtmosphere

                    ForEach(Array(strands.enumerated()), id: \.element.id) { index, strand in
                        ProjectTrajectoryLane(strand: strand, index: index, geometry: geometry)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(strand) }
                    }

                    nowMarker

                    HStack(spacing: 0) {
                        Color.clear.frame(width: geometry.defaultScrollX)
                        Color.clear.frame(width: 1, height: 1).id(defaultAnchorID)
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: geometry.contentWidth, height: geometry.chartHeight, alignment: .topLeading)
            }
            .scrollClipDisabled(false)
            .onAppear { scrollToDefault(proxy) }
            .onChange(of: scaleID) { _, _ in scrollToDefault(proxy) }
        }
        .frame(width: geometry.chartViewportWidth, height: geometry.chartHeight)
    }

    private var chartAtmosphere: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(geometry.guideXs.enumerated()), id: \.offset) { _, x in
                Rectangle()
                    .fill(.secondary.opacity(abs(x - geometry.nowX) < 1 ? 0.075 : 0.03))
                    .frame(width: 1, height: geometry.trackBottomY - geometry.trackTopY)
                    .offset(x: x, y: geometry.trackTopY)
            }

            ForEach(0..<strands.count, id: \.self) { index in
                Rectangle()
                    .fill(.secondary.opacity(0.014))
                    .frame(width: geometry.contentWidth, height: 0.5)
                    .offset(x: 0, y: geometry.laneTop(index) + geometry.laneHeight - 1)
            }

            chartLabel(geometry.scale.nearFutureLabel(from: geometry.now), x: geometry.nowX + geometry.visibleFutureWidth * 0.38, alignment: .center)
            chartLabel(geometry.scale.laterLabel(from: geometry.now), x: geometry.nowX + geometry.visibleFutureWidth, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }

    private var nowMarker: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.primary.opacity(0.095))
                .frame(width: 1)
            Circle()
                .fill(.primary.opacity(0.48))
                .frame(width: 4, height: 4)
                .offset(y: 34)
        }
        .frame(height: geometry.trackBottomY - geometry.trackTopY)
        .offset(x: geometry.nowX, y: geometry.trackTopY)
        .allowsHitTesting(false)
    }

    private func chartLabel(_ title: String, x: CGFloat, alignment: HorizontalAlignment) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.38))
        .frame(width: 64, alignment: frameAlignment(for: alignment))
        .offset(x: x - xOffset(for: alignment), y: 18)
    }

    private func frameAlignment(for alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private func xOffset(for alignment: HorizontalAlignment) -> CGFloat {
        switch alignment {
        case .leading: return 0
        case .trailing: return 64
        default: return 32
        }
    }

    private func scrollToDefault(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(defaultAnchorID, anchor: .leading)
            }
        }
    }
}

private struct ProjectLaneLabel: View {
    let strand: Strand

    private var color: Color { TrajectoryColorPalette.color(for: strand.colorToken, name: strand.name) }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ProjectIdentityMark(color: color, isPaused: strand.isPaused)
            Text(strand.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Image(systemName: stateGlyph)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(color.opacity(strand.isPaused ? 0.36 : 0.48))
                .frame(width: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(strand.name), \(stateText)")
    }

    private var stateGlyph: String {
        if strand.isPaused { return "pause.fill" }
        switch strand.trajectory.outcome {
        case .onTime: return "arrow.up.right"
        case .behind: return "arrow.down.right"
        case .sustained: return "waveform.path"
        case .fading: return "circle"
        }
    }

    private var glyphSize: CGFloat {
        strand.trajectory.outcome == .sustained ? 8 : 9
    }

    private var stateText: String {
        if strand.isPaused { return "Paused" }
        switch strand.trajectory.outcome {
        case .onTime: return "On track"
        case .behind: return "Slipping"
        case .sustained: return "Sustained"
        case .fading: return "Fading"
        }
    }
}

private struct ProjectIdentityMark: View {
    let color: Color
    let isPaused: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(isPaused ? 0.18 : 0.32), lineWidth: 1)
                .frame(width: 10, height: 10)
            Circle()
                .fill(color.opacity(isPaused ? 0.2 : 0.62))
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
    }
}

private struct ProjectTrajectoryLane: View {
    let strand: Strand
    let index: Int
    let geometry: TimelineFieldGeometry

    var body: some View {
        TrajectoryCurveRenderer(strand: strand, laneIndex: index, geometry: geometry)
            .frame(width: geometry.contentWidth, height: geometry.laneHeight)
            .offset(y: geometry.laneTop(index))
    }
}

private struct TrajectoryCurveRenderer: View {
    let strand: Strand
    let laneIndex: Int
    let geometry: TimelineFieldGeometry

    private var color: Color { TrajectoryColorPalette.color(for: strand.colorToken, name: strand.name) }
    private var outcome: TrajectoryOutcome { strand.trajectory.outcome }

    var body: some View {
        Canvas { ctx, size in
            let actual = effortPoints(projected: false)
            let projection = effortPoints(projected: true)

            drawArea(in: &ctx, points: actual, baseline: geometry.laneHeight - 12)
            drawCurve(in: &ctx, points: actual, width: actualLineWidth, opacity: strand.isPaused ? 0.3 : 0.62)
            drawActualMarkers(in: &ctx, points: actual)

            if strand.isPaused {
                drawProjectedCurve(in: &ctx, points: projection, width: 1.15, opacity: 0.18, dash: [1, 6.5])
                return
            }

            switch outcome {
            case .behind:
                drawSlippingProjection(in: &ctx, points: projection, size: size)
            case .fading:
                drawFadingProjection(in: &ctx, points: projection)
            case .onTime:
                drawProjectedCurve(in: &ctx, points: projection, width: 1.2, opacity: 0.22, dash: [1, 6.2])
            case .sustained:
                drawProjectedCurve(in: &ctx, points: projection, width: 1.2, opacity: 0.23, dash: [1, 6.2])
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func drawSlippingProjection(in ctx: inout GraphicsContext, points projection: [CGPoint], size: CGSize) {
        let deadlineX = min(
            geometry.nowX + geometry.visibleFutureWidth * 0.58,
            max(geometry.nowX + 28, strand.deadline.map { geometry.x(date: $0) } ?? geometry.nowX + geometry.visibleFutureWidth * 0.5)
        )
        let targetY = yValue(for: 0.48)
        drawDeadlineTick(in: &ctx, x: deadlineX, y: targetY)

        var slipping = projection.filter { $0.x <= deadlineX }
        if slipping.count < 2, let first = projection.first { slipping = [first] }
        slipping.append(CGPoint(x: deadlineX, y: targetY + 2))
        slipping.append(CGPoint(x: min(geometry.contentEndX, deadlineX + geometry.visibleFutureWidth * 0.24), y: targetY + 12))

        drawProjectedCurve(in: &ctx, points: slipping, width: 1.25, opacity: 0.27, dash: [1, 6.2])
        if let last = slipping.last { drawEndpoint(in: &ctx, at: last, opacity: 0.24) }
    }

    private func drawFadingProjection(in ctx: inout GraphicsContext, points projection: [CGPoint]) {
        guard projection.count >= 2 else { return }
        let segments = zip(projection.dropLast(), projection.dropFirst()).map { ($0, $1) }
        for (index, segment) in segments.enumerated() {
            let t = Double(index) / Double(max(1, segments.count - 1))
            var path = Path()
            path.move(to: segment.0)
            path.addLine(to: segment.1)
            ctx.stroke(
                path,
                with: .color(color.opacity(0.17 * (1 - t))),
                style: StrokeStyle(lineWidth: 1.1 - CGFloat(t) * 0.28, lineCap: .round, lineJoin: .round, dash: [1, 6.6])
            )
        }
    }

    private func drawCurve(in ctx: inout GraphicsContext, points: [CGPoint], width: CGFloat, opacity: Double) {
        guard points.count >= 2 else { return }
        ctx.stroke(
            smoothedPath(points),
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawProjectedCurve(in ctx: inout GraphicsContext, points: [CGPoint], width: CGFloat, opacity: Double, dash: [CGFloat]) {
        guard points.count >= 2 else { return }
        ctx.stroke(
            smoothedPath(points),
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
        )
    }

    private func drawArea(in ctx: inout GraphicsContext, points: [CGPoint], baseline: CGFloat) {
        guard points.count >= 2, let first = points.first, let last = points.last else { return }
        var area = smoothedPath(points)
        area.addLine(to: CGPoint(x: last.x, y: baseline))
        area.addLine(to: CGPoint(x: first.x, y: baseline))
        area.closeSubpath()
        ctx.fill(area, with: .color(color.opacity(strand.isPaused ? 0.012 : 0.024)))
    }

    private func drawActualMarkers(in ctx: inout GraphicsContext, points: [CGPoint]) {
        for index in markerIndexes(count: points.count) {
            let point = points[index]
            let radius: CGFloat = index == points.count - 1 ? 2.5 : 2.0
            let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            ctx.fill(circle, with: .color(color.opacity(strand.isPaused ? 0.28 : 0.58)))
            ctx.stroke(circle, with: .color(TrajectoryColorPalette.surface.opacity(0.82)), lineWidth: 0.7)
        }
    }

    private func drawEndpoint(in ctx: inout GraphicsContext, at point: CGPoint, opacity: Double) {
        let radius: CGFloat = 2.8
        let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        ctx.stroke(circle, with: .color(color.opacity(opacity)), lineWidth: 0.9)
    }

    private func drawDeadlineTick(in ctx: inout GraphicsContext, x: CGFloat, y: CGFloat) {
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: y - 9))
        tick.addLine(to: CGPoint(x: x, y: y + 9))
        ctx.stroke(tick, with: .color(color.opacity(0.26)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
    }

    private func effortPoints(projected: Bool) -> [CGPoint] {
        let values = projected ? displayCurve.projected : displayCurve.actual
        let xStart = projected ? geometry.nowX : geometry.nowX - geometry.visiblePastWidth
        let xEnd = projected ? geometry.nowX + geometry.visibleFutureWidth * 0.88 : geometry.nowX
        let count = max(values.count, 1)
        return values.enumerated().map { index, value in
            let fraction = count == 1 ? 0 : CGFloat(index) / CGFloat(count - 1)
            return CGPoint(
                x: lerp(xStart, xEnd, fraction),
                y: yValue(for: value)
            )
        }
    }

    private func yValue(for value: Double) -> CGFloat {
        let clamped = min(0.86, max(0.14, value))
        let center = geometry.laneHeight * 0.52
        let amplitude = min(17, geometry.laneHeight * 0.28)
        return center - CGFloat(clamped - 0.5) * amplitude * 2
    }

    private var actualLineWidth: CGFloat {
        if strand.isPaused { return 1.2 }
        return outcome.needsAttention ? 1.75 : 1.55
    }

    private var displayCurve: (actual: [Double], projected: [Double]) {
        if strand.isPaused {
            return ([0.31, 0.35, 0.40, 0.38, 0.39, 0.37, 0.34],
                    [0.33, 0.32, 0.31, 0.31, 0.30, 0.30])
        }
        switch outcome {
        case .onTime:
            return ([0.34, 0.38, 0.43, 0.42, 0.49, 0.47, 0.51],
                    [0.51, 0.50, 0.49, 0.49, 0.50, 0.50])
        case .behind:
            return ([0.42, 0.49, 0.47, 0.54, 0.53, 0.52, 0.48],
                    [0.47, 0.44, 0.41, 0.37, 0.35, 0.33])
        case .sustained:
            return ([0.45, 0.48, 0.46, 0.50, 0.47, 0.49, 0.48],
                    [0.48, 0.49, 0.47, 0.48, 0.47, 0.48])
        case .fading:
            return ([0.34, 0.43, 0.62, 0.51, 0.43, 0.36, 0.31],
                    [0.29, 0.25, 0.22, 0.20, 0.19, 0.18])
        }
    }

    private func smoothedPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }

    private func markerIndexes(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return [count - 1]
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        start + (end - start) * min(1, max(0, t))
    }

    private static let markerDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
