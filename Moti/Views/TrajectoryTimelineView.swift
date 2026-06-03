import SwiftData
import SwiftUI

/// **Main Timeline — the trajectory engine** (revised PRD §6.1). Vertical,
/// future-primary: `Now` near the top, a bounded ~2-week past above it, the
/// future expanding downward through scroll (scroll = forward). Each future is a
/// column; solid = certain (recent actual + committed plans), dashed/fading =
/// projection. The four outcomes (on-time / behind / sustained / fading) read
/// from the projected path alone. Calm by default — only the slipping or fading
/// future raises its voice. This supersedes the presence-first `LifelineTimelineView`.
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

    private let axis = TrajectoryAxis(now: .now)

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

    private var horizonDays: Double {
        let deadlineDays = strands.compactMap { $0.deadline?.timeIntervalSince(axis.now) }
            .map { $0 / 86_400 }.max() ?? 0
        return min(120, max(60, deadlineDays + 10))
    }

    private var contentHeight: CGFloat { axis.contentHeight(horizonDays: horizonDays) }

    var body: some View {
        NavigationStack {
            Group {
                if hasContent {
                    VStack(spacing: 14) {
                        headline
                        legend
                        plot
                        focusCard
                    }
                    .padding(.horizontal, MotiLayout.pagePadding)
                    .padding(.top, 8)
                } else {
                    emptyState
                        .padding(MotiLayout.pagePadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Timeline")
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
            .font(.system(size: 17, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Column legend (identity: dot + name)

    private var legend: some View {
        HStack(spacing: 6) {
            ForEach(strands) { strand in
                HStack(spacing: 4) {
                    Circle().fill(Color.projectToken(strand.colorToken)).frame(width: 7, height: 7)
                    Text(strand.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - The plot (vertical time, columns, scroll = forward)

    private var plot: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                nowBand
                HStack(spacing: 6) {
                    ForEach(strands) { strand in
                        TrajectoryColumnView(strand: strand, axis: axis, contentHeight: contentHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { recordPeek(strand) }
                    }
                }
            }
            .frame(height: contentHeight)
        }
        .frame(maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
    }

    /// The fixed Now band + a faint bounded-past tint above it.
    private var nowBand: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.secondary.opacity(0.05))
                .frame(height: axis.pastHeight)
                .offset(y: axis.topPadding)
            ZStack(alignment: .trailing) {
                Rectangle().fill(.secondary.opacity(0.35)).frame(height: 1)
                Text("NOW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
                    .background(Color(.systemBackground).opacity(0.001))
            }
            .offset(y: axis.nowY)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
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
