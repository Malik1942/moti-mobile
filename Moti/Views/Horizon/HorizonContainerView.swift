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
    @StateObject private var folds = HorizonFoldStore()

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
        // Past region (T10) is not wired yet — completions come in a later pass.
        return HorizonSnapshotBuilder.makeSnapshot(active: active, completed: [], now: now, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            HorizonView(snapshot: snapshot, now: now, calendar: calendar, folds: folds)
                .navigationTitle("Timeline")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingMap = true
                        } label: {
                            Image(systemName: "chart.xyaxis.line")
                        }
                        .accessibilityLabel("Trajectory Map")
                    }
                }
        }
        .onAppear { now = Date() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() } // foreground recompute
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = Date() // midnight crossing while foregrounded
        }
        #endif
        .sheet(isPresented: $showingMap) {
            // T11: the demoted axis view, reachable via the visible toolbar
            // button (never gesture-only). Presented so its own NavigationStack
            // is unchanged.
            TrajectoryTimelineView(
                onAddToTimeline: onAddToTimeline,
                onOpenInProjects: { id in
                    showingMap = false
                    onOpenInProjects(id)
                }
            )
        }
    }
}
