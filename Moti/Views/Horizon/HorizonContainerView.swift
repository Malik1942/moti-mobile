import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Horizon Timeline v2 — T14. The live container: reads the same model data as
// the axis timeline, builds strands, maps them to the domain, assembles the
// snapshot, and renders HorizonView. Recomputes on foreground and on a
// significant time change (midnight crossing while foregrounded) — the snapshot
// is a pure projection, so bumping `now` re-derives everything (PRD §11 eng note:
// foreground-only recompute is acceptable for dogfooding).

struct HorizonContainerView: View {
    var onAddToTimeline: () -> Void = {}
    var onOpenInProjects: (String) -> Void = { _ in }

    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query private var completionLogs: [CompletionLog]
    @ObservedObject private var prefs = StrandPreferenceStore.shared
    #if DEBUG
    @ObservedObject private var typeOverrideStore = StrandTypeOverrideStore.shared
    #endif

    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var showingMap = false
    @State private var openedAt: Date?
    @StateObject private var folds = HorizonFoldStore()
    @StateObject private var bucketMemory = HorizonBucketMemory()

    private var calendar: Calendar { .current }

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
            now: now,
            pausedStrandIDs: pausedIDs,
            typeOverrides: typeOverrides
        ).build()
    }

    private var snapshot: HorizonSnapshot {
        let active = strands.map(HorizonStrand.init(from:))
        return HorizonSnapshotBuilder.makeSnapshot(active: active, completed: completions(),
                                                   now: now, calendar: calendar)
    }

    /// Completed futures for the Past region (PRD §6.5). A project has "arrived"
    /// when every one of its work items is in a terminal state and at least one
    /// is done — completion is a state, never a deletion, so these survive.
    /// Origin is the project's creation; completion is the latest done timestamp.
    /// Record how long Horizon was visible this foreground stretch (PRD §10).
    private func recordScanSession() {
        guard let start = openedAt else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        openedAt = nil
        guard seconds >= 0 else { return }
        HorizonInstrumentation.shared.record(.scanSessionLength, detail: "\(seconds)")
    }

    private func completions() -> [HorizonCompletion] {
        projects.compactMap { project in
            let items = project.workItems
            guard !items.isEmpty else { return nil }
            let allTerminal = items.allSatisfy { [.done, .skipped, .archived].contains($0.status) }
            let done = items.filter { $0.status == .done }
            guard allTerminal, let completedAt = done.map(\.updatedAt).max() else { return nil }
            return HorizonCompletion(id: project.id.uuidString, name: project.name,
                                     colorToken: project.colorToken,
                                     completedAt: completedAt, origin: project.createdAt)
        }
    }

    var body: some View {
        NavigationStack {
            HorizonView(snapshot: snapshot, now: now, calendar: calendar, folds: folds,
                        bucketMemory: bucketMemory)
                .navigationTitle("Timeline")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HorizonInstrumentation.shared.record(.mapOpen)
                            showingMap = true
                        } label: {
                            Image(systemName: "chart.xyaxis.line")
                        }
                        .accessibilityLabel("Trajectory Map")
                    }
                }
        }
        .onAppear {
            now = Date()
            openedAt = Date()
            HorizonInstrumentation.shared.record(.horizonOpen)
        }
        .onDisappear(perform: recordScanSession)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                now = Date()          // foreground recompute
                openedAt = Date()
            case .background, .inactive:
                recordScanSession()   // foreground→background delta while visible
            @unknown default:
                break
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = Date() // midnight crossing while foregrounded
        }
        #endif
        .sheet(isPresented: $showingMap) {
            // T11: the demoted axis view, reachable via the visible toolbar
            // button (never gesture-only). Presented so its own NavigationStack
            // is unchanged; a close affordance + drag indicator make dismissal
            // explicit (not gesture-only).
            HorizonMapSheet(
                onAddToTimeline: onAddToTimeline,
                onOpenInProjects: { id in
                    showingMap = false
                    onOpenInProjects(id)
                },
                onClose: { showingMap = false }
            )
        }
    }
}

/// Wraps the demoted axis Map with an explicit close affordance (PRD §6.6).
private struct HorizonMapSheet: View {
    let onAddToTimeline: () -> Void
    let onOpenInProjects: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        TrajectoryTimelineView(onAddToTimeline: onAddToTimeline, onOpenInProjects: onOpenInProjects)
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(HorizonTheme.hairline, lineWidth: HorizonTheme.hairlineWidth))
                }
                .padding(.trailing, HorizonTheme.leadingInset)
                .padding(.top, 6)
                .accessibilityLabel("Close Map")
            }
            .presentationDragIndicator(.visible)
    }
}
