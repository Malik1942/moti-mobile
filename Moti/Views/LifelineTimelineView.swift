import SwiftData
import SwiftUI

/// **Screen 1 — the Main Timeline.** Lifelines only: a 4-week window of presence
/// with a fixed Now axis on the right. One synthesized sentence on top, the
/// strands as lines in the middle, and a single "What matters now" focus at the
/// bottom. No tasks, no badges, no grids — calm by default, with only the
/// exception raising its voice (PRD §6.1).
struct LifelineTimelineView: View {
    var onAddToTimeline: () -> Void = {}
    var onOpenInProjects: (String) -> Void = { _ in }

    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query private var completionLogs: [CompletionLog]
    @ObservedObject private var prefs = StrandPreferenceStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var peekStrand: Strand?

    // MARK: - Derived (computed truth → render-ready strands)

    private var pausedIDs: Set<String> {
        let candidateIDs = projects.map { $0.id.uuidString } + [Strand.unassignedID]
        return Set(candidateIDs.filter { prefs.isPaused($0) })
    }

    private var strands: [Strand] {
        StrandTimelineBuilder(
            projects: projects,
            workItems: WorkItemScope.timeline(workItems),
            completionLogs: completionLogs,
            pausedStrandIDs: pausedIDs
        ).build()
    }

    private var attendedIDs: Set<String> {
        Set(strands.map(\.id).filter { prefs.isAttendedThisWeek($0) })
    }

    private var hasContent: Bool { !projects.isEmpty || !workItems.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if hasContent {
                        headline
                        lifelinePanel
                        focusCard
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, MotiLayout.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, MotiLayout.pageBottomPadding + 48)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Timeline")
            .sheet(item: $peekStrand) { strand in
                StrandPeekSheet(strand: strand, onOpenInProjects: onOpenInProjects)
            }
            #if DEBUG
            .onAppear {
                // Verification hook: -MotiPeekStrand <name> auto-opens that peek.
                if let name = UserDefaults.standard.string(forKey: "MotiPeekStrand"),
                   peekStrand == nil,
                   let match = strands.first(where: { $0.name == name }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { peekStrand = match }
                }
            }
            #endif
        }
    }

    // MARK: - Top synthesized sentence

    private var headline: some View {
        Text(TimelineNarrator.headline(for: strands))
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - The lifelines

    private var lifelinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowCaption
            ZStack(alignment: .trailing) {
                nowRule
                VStack(spacing: 2) {
                    ForEach(strands) { strand in
                        LifelineView(strand: strand) { peekStrand = strand }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
    }

    /// Tiny orientation row: the window on the left, Now on the right (over the axis).
    private var windowCaption: some View {
        HStack {
            Text("Past 4 weeks")
            Spacer()
            Text("Now")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                // Sit directly over the Now axis column.
                .padding(.trailing, LifelineMetrics.axisTrailingInset - 8)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
    }

    /// The single fixed Now axis, drawn behind the rows so the nodes rest on it.
    private var nowRule: some View {
        Rectangle()
            .fill(.secondary.opacity(0.28))
            .frame(width: 1)
            .padding(.trailing, LifelineMetrics.axisTrailingInset - 0.5)
            .allowsHitTesting(false)
    }

    // MARK: - "What matters now"

    @ViewBuilder
    private var focusCard: some View {
        switch TimelineNarrator.focus(for: strands, parkedIDs: attendedIDs) {
        case .calm(let message):
            calmCard(message)
        case .attention(let id, let title, let detail):
            attentionCard(strandID: id, title: title, detail: detail)
        }
    }

    private func calmCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
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
                Text("What matters now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                gentleButton("Make space", filled: true) {
                    haptic()
                    prefs.makeSpaceThisWeek(strandID)
                }
                gentleButton("Not this week", filled: false) {
                    haptic()
                    prefs.parkForThisWeek(strandID)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous)
                .stroke(.indigo.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func gentleButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .foregroundStyle(filled ? Color.white : .indigo)
                .background(filled ? Color.indigo : Color.indigo.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MotiLayout.emptyStateSpacing) {
            Text("Your futures will appear here.")
                .font(.headline)
            Text("As you capture and tend work, each future becomes a lifeline — and Moti shows you which ones are still reaching the present.")
                .font(.motiEmptySubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onAddToTimeline()
            } label: {
                Label("Add to Timeline", systemImage: "plus")
            }
            .font(.motiButtonLabel)
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.top, 4)
        }
        .padding(MotiLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
    }

    private func haptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}
