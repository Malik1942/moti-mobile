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
            .foregroundStyle(.primary)
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
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What matters now: \(message)")
    }

    private func attentionCard(strandID: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WHAT MATTERS NOW").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
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
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous).stroke(.indigo.opacity(0.16), lineWidth: 1))
    }

    /// App-control styling — the original app purple, never the chart palette.
    private func gentleButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .foregroundStyle(filled ? Color.white : .indigo)
                .background(filled ? Color.indigo : Color.indigo.opacity(0.12), in: Capsule())
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

    /// System-native card surface (Apple Health / Stocks chart-card feel).
    static var surface: Color { Color(.secondarySystemGroupedBackground) }

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

    // Apple-system color energy: richer and clearly readable on the light card,
    // but a touch deeper than pure neon system colors (not candy). Chart-only.
    private static let tokenColors: [String: Color] = [
        "blue": color(light: (0.04, 0.42, 0.88), dark: (0.32, 0.62, 1.00)),     // refined iOS blue
        "green": color(light: (0.16, 0.62, 0.33), dark: (0.30, 0.80, 0.46)),    // calm but visible green
        "purple": color(light: (0.52, 0.24, 0.80), dark: (0.69, 0.46, 0.95)),   // rich, not neon
        "indigo": color(light: (0.29, 0.30, 0.76), dark: (0.52, 0.52, 0.94)),   // deep indigo
        "orange": color(light: (0.92, 0.50, 0.08), dark: (1.00, 0.62, 0.24)),   // warm, clear amber
        "gray": color(light: (0.42, 0.44, 0.47), dark: (0.62, 0.64, 0.67))      // neutral, readable
    ]

    private static let fallbackColors: [Color] = [
        color(light: (0.10, 0.58, 0.60), dark: (0.34, 0.78, 0.80)), // teal
        color(light: (0.80, 0.28, 0.42), dark: (0.92, 0.46, 0.58)), // rose
        color(light: (0.62, 0.46, 0.16), dark: (0.80, 0.64, 0.32)), // amber-stone
        color(light: (0.16, 0.50, 0.78), dark: (0.40, 0.68, 0.95)), // cyan-blue
        color(light: (0.40, 0.42, 0.46), dark: (0.60, 0.62, 0.66))  // graphite
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

    let labelColumnWidth: CGFloat = 116
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
                    .fill(.secondary.opacity(abs(x - geometry.nowX) < 1 ? 0.11 : 0.05))
                    .frame(width: 1, height: geometry.trackBottomY - geometry.trackTopY)
                    .offset(x: x, y: geometry.trackTopY)
            }

            ForEach(0..<strands.count, id: \.self) { index in
                Rectangle()
                    .fill(.secondary.opacity(0.035))
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
                .fill(.primary.opacity(0.2))
                .frame(width: 1)
            Circle()
                .fill(.primary.opacity(0.6))
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
            .foregroundStyle(.secondary.opacity(0.6))
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
        HStack(alignment: .center, spacing: 0) {
            ProjectIdentityMark(color: color, isPaused: strand.isPaused)
                .padding(.trailing, 6)
            // Text expands to fill all remaining space so the icon is always
            // pinned to the same trailing-edge position across every row.
            Text(strand.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: stateGlyph)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(strand.isPaused ? 0.36 : 0.48))
                .frame(width: 12, height: 13)
        }
        // Fill the full lane height so HStack content centers on the same
        // vertical axis as the trajectory curves opposite it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(strand.name), \(stateText)")
    }

    private var stateGlyph: String {
        if strand.isPaused { return "pause.fill" }
        switch strand.trajectory.outcome {
        case .onTrack: return "arrow.up.right"
        case .slipping: return "arrow.down.right"
        case .stalled: return "exclamationmark"
        case .completed: return "checkmark"
        case .sustained: return "waveform.path"
        case .quiet: return "minus"
        case .fading: return "circle.dotted"
        }
    }

    private var stateText: String {
        if strand.isPaused { return "Paused" }
        switch strand.trajectory.outcome {
        case .onTrack: return "On track"
        case .slipping: return "Slipping"
        case .stalled: return "Stalled"
        case .completed: return "Completed"
        case .sustained: return "Sustained"
        case .quiet: return "Quiet"
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
            drawCurve(in: &ctx, points: actual, width: actualLineWidth, opacity: strand.isPaused ? 0.5 : 1.0)
            drawActualMarkers(in: &ctx, points: actual)

            if strand.isPaused {
                // Muted interrupted continuation — no directional amplification.
                drawProjectedCurve(in: &ctx, points: projection, width: 1.9, opacity: 0.38, dash: [1.5, 5.5])
                return
            }

            switch outcome {
            case .onTrack:
                // Guaranteed 13pt rise regardless of actual.last position.
                let pts = directionalProjectionPoints(endOffset: -13)
                drawProjectedCurve(in: &ctx, points: pts, width: 2.1, opacity: 0.68, dash: [2.0, 5.5])
                if let last = pts.last { drawEndpoint(in: &ctx, at: last, opacity: 0.72) }
            case .slipping:
                // Guaranteed 12pt fall + deadline tick at the descent midpoint.
                drawSlippingProjection(in: &ctx, points: directionalProjectionPoints(endOffset: 12), size: size)
            case .stalled:
                // Momentum gone — 11pt fall then fading opacity dissolve.
                drawStalledProjection(in: &ctx, points: directionalProjectionPoints(endOffset: 11), size: size)
            case .fading:
                // 8pt fall + strong opacity decay — the fade is the primary signal.
                drawFadingProjection(in: &ctx, points: directionalProjectionPoints(endOffset: 8))
            case .completed:
                // Confident stable high — 10pt rise toward ceiling.
                let pts = directionalProjectionPoints(endOffset: -10)
                drawProjectedCurve(in: &ctx, points: pts, width: 2.1, opacity: 0.65, dash: [2.0, 5.0])
                if let last = pts.last { drawCompletionMarker(in: &ctx, at: last) }
            case .quiet:
                // Gentle 8pt fall — present but thinning.
                let pts = directionalProjectionPoints(endOffset: 8)
                drawProjectedCurve(in: &ctx, points: pts, width: 1.9, opacity: 0.58, dash: [1.5, 5.5])
                if let last = pts.last { drawEndpoint(in: &ctx, at: last, opacity: 0.58) }
            case .sustained:
                // Flat — fed at its own rhythm, no drift.
                let pts = directionalProjectionPoints(endOffset: 0)
                drawProjectedCurve(in: &ctx, points: pts, width: 2.0, opacity: 0.62, dash: [2.0, 5.5])
                if let last = pts.last { drawEndpoint(in: &ctx, at: last, opacity: 0.60) }
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
        // Position the deadline tick along the projection's descent at that x-fraction.
        let projSpan = geometry.visibleFutureWidth * 0.95
        let deadlineFrac: CGFloat = projSpan > 0 ? min(1, max(0, (deadlineX - geometry.nowX) / projSpan)) : 0.5
        let tickY: CGFloat
        if let first = projection.first, let last = projection.last {
            tickY = lerp(first.y, last.y, deadlineFrac)
        } else {
            tickY = yValue(for: 0.46)
        }
        drawDeadlineTick(in: &ctx, x: deadlineX, y: tickY)
        // Descending curve continues past the deadline tick — showing the slipping momentum.
        drawProjectedCurve(in: &ctx, points: projection, width: 2.0, opacity: 0.65, dash: [1.5, 5.0])
        if let last = projection.last { drawEndpoint(in: &ctx, at: last, opacity: 0.68) }
    }

    /// Stalled: momentum gone before the deadline. The deadline tick stays
    /// visible (it still matters), but the projection flattens low and dissolves
    /// — distinct from slipping, which still moves toward (past) the marker.
    private func drawStalledProjection(in ctx: inout GraphicsContext, points projection: [CGPoint], size: CGSize) {
        if let deadline = strand.deadline {
            let deadlineX = min(geometry.contentEndX,
                                max(geometry.nowX + 24, geometry.x(date: deadline)))
            drawDeadlineTick(in: &ctx, x: deadlineX, y: yValue(for: 0.46))
        }
        drawFadingProjection(in: &ctx, points: projection)
    }

    private func drawCompletionMarker(in ctx: inout GraphicsContext, at point: CGPoint) {
        let r: CGFloat = 3.4
        let circle = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        ctx.fill(circle, with: .color(color.opacity(0.85)))
        ctx.stroke(circle, with: .color(Color(.secondarySystemGroupedBackground)), lineWidth: 0.9)
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
                with: .color(color.opacity(0.60 * (1 - t * 0.85))),
                style: StrokeStyle(lineWidth: 2.0 - CGFloat(t) * 0.7, lineCap: .round, lineJoin: .round, dash: [1.5, 5])
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
        ctx.fill(area, with: .color(color.opacity(strand.isPaused ? 0.03 : 0.06)))
    }

    private func drawActualMarkers(in ctx: inout GraphicsContext, points: [CGPoint]) {
        for index in markerIndexes(count: points.count) {
            let point = points[index]
            let radius: CGFloat = index == points.count - 1 ? 3.0 : 2.4
            let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            ctx.fill(circle, with: .color(color.opacity(strand.isPaused ? 0.5 : 1.0)))
            ctx.stroke(circle, with: .color(TrajectoryColorPalette.surface), lineWidth: 1.0)
        }
    }

    private func drawEndpoint(in ctx: inout GraphicsContext, at point: CGPoint, opacity: Double) {
        let radius: CGFloat = 3.2
        let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                            width: radius * 2, height: radius * 2))
        // Filled ring: soft inner fill anchors the endpoint; ring stroke gives it weight.
        ctx.fill(circle, with: .color(color.opacity(opacity * 0.50)))
        ctx.stroke(circle, with: .color(color.opacity(opacity)), lineWidth: 1.1)
    }

    private func drawDeadlineTick(in ctx: inout GraphicsContext, x: CGFloat, y: CGFloat) {
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: y - 9))
        tick.addLine(to: CGPoint(x: x, y: y + 9))
        ctx.stroke(tick, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    private func effortPoints(projected: Bool) -> [CGPoint] {
        let values = projected ? displayCurve.projected : displayCurve.actual
        let xStart: CGFloat
        let xEnd: CGFloat
        if projected {
            xStart = geometry.nowX
            xEnd = geometry.nowX + geometry.visibleFutureWidth * 0.95
        } else {
            // Actual history begins at the real first event (date-accurate), not a
            // shared default. A young strand starts near Now; an old one extends
            // back into the pannable past. No evidence → a short stub at Now.
            if let start = strand.trajectory.actualStartDate {
                xStart = max(4, geometry.x(date: start))
            } else {
                xStart = geometry.nowX - 6
            }
            xEnd = geometry.nowX
        }
        let count = max(values.count, 1)
        return values.enumerated().map { index, value in
            let fraction = count == 1 ? 0 : CGFloat(index) / CGFloat(count - 1)
            return CGPoint(
                x: lerp(xStart, xEnd, fraction),
                y: yValue(for: value)
            )
        }
    }

    /// Projection points with a guaranteed visual slope, independent of where `actual.last` sits.
    ///
    /// Factor-based amplification fails when the compute's clamped targets produce tiny deltas
    /// (e.g. onTrack when actual.last is already 0.8 → target = min(0.82, 0.96) → delta 0.02).
    /// Instead, `endOffset` is a fixed pt displacement from `actual.last`'s Y-position:
    /// negative = visually rises (toward top of lane), positive = falls toward bottom.
    ///
    /// The first point always equals actual.last's exact Y — zero discontinuity at Now.
    /// Endpoint is clamped to lane bounds so no state escapes the visible area.
    private func directionalProjectionPoints(endOffset: CGFloat) -> [CGPoint] {
        let n = max(displayCurve.projected.count, 2)
        let startY = yValue(for: displayCurve.actual.last ?? 0.4)
        let minY = geometry.laneHeight * 0.10
        let maxY = geometry.laneHeight * 0.90
        let endY = min(maxY, max(minY, startY + endOffset))
        let xStart = geometry.nowX
        let xEnd = geometry.nowX + geometry.visibleFutureWidth * 0.95
        return (0..<n).map { index in
            let t = index == 0 ? 0 : CGFloat(index) / CGFloat(n - 1)
            return CGPoint(
                x: lerp(xStart, xEnd, t),
                y: lerp(startY, endY, t)
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
        if strand.isPaused { return 1.9 }
        return outcome.needsAttention ? 2.4 : 2.15
    }

    /// The strand's shape comes from the computed, **behavior-derived** series on
    /// the trajectory — the actual region is the real feeding history, the
    /// projected region is the directional continuation (PRD: visual variation
    /// must map to real behavioral signals). No canned templates.
    private var displayCurve: (actual: [Double], projected: [Double]) {
        let actual = strand.trajectory.actualSeries
        let projected = strand.trajectory.projectedSeries
        return (
            actual.count >= 2 ? actual : [0.4, 0.4],
            projected.count >= 2 ? projected : [0.4, 0.4]
        )
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
