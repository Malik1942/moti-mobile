import SwiftData
import SwiftUI
import UIKit

@main
struct MotiApp: App {
    @AppStorage("taskUnderstandingMode") private var modeRawValue = TaskUnderstandingMode.foundationModel.rawValue
    @AppStorage("didPromoteFoundationModelDefault") private var didPromoteFoundationModelDefault = false

    private var requestedMode: TaskUnderstandingMode {
        TaskUnderstandingMode(rawValue: modeRawValue) ?? .foundationModel
    }

    private var activeMode: TaskUnderstandingMode {
        TaskUnderstandingServiceFactory.resolvedMode(for: requestedMode)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.taskUnderstandingService, TaskUnderstandingServiceFactory.make(mode: activeMode))
                .environment(\.contextualCaptureAgent, ContextualCaptureAgentFactory.make())
                .fontDesign(.rounded)
                .tint(.indigo)
                .onAppear {
                    if !didPromoteFoundationModelDefault && modeRawValue == TaskUnderstandingMode.mockSLM.rawValue {
                        modeRawValue = FoundationModelRuntime.status.isAvailable
                            ? TaskUnderstandingMode.foundationModel.rawValue
                            : TaskUnderstandingMode.ruleBased.rawValue
                        didPromoteFoundationModelDefault = true
                    }
                    #if DEBUG
                    print("Moti requested parser mode:", requestedMode.rawValue)
                    print("Moti active parser mode:", activeMode.rawValue)
                    print("Moti Foundation Model status:", FoundationModelRuntime.status.summary)
                    #endif
                }
        }
        .modelContainer(for: [
            WorkItem.self,
            CompletionLog.self,
            Project.self,
            WorkSession.self,
            SessionCheckIn.self,
            ProjectContext.self,
            ContextNote.self
        ])
    }
}

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: MotiTab = .timeline
    @State private var showingCapture = false
    @State private var captureStartMode: CaptureStartMode = .text
    // Controls which detent the sheet opens at.
    // tap plus → .large (text, keyboard ready); long press plus → .medium (voice, no keyboard)
    @State private var captureDetent: PresentationDetent = .large

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase)   private var scenePhase

    @Query(sort: \WorkItem.createdAt) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query private var allSessions: [WorkSession]

    private var scheduler: TimelineCheckpointScheduler { .shared }

    // Observed properties that trigger a widget snapshot refresh when any work item or project changes
    private var widgetChangeToken: String {
        let items = workItems.map { "\($0.id)\($0.title)\($0.statusRawValue)\($0.projectName ?? "")\($0.dueDate?.timeIntervalSinceReferenceDate ?? 0)\($0.workingStartDate?.timeIntervalSinceReferenceDate ?? 0)\($0.workingEndDate?.timeIntervalSinceReferenceDate ?? 0)" }.joined(separator: ",")
        let projs = projects.map { "\($0.id)\($0.name)\($0.colorToken)" }.joined(separator: ",")
        return items + "|" + projs
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        selectedContent
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Color.clear.frame(height: MotiTabBarMetrics.contentClearance(for: proxy.safeAreaInsets.bottom))
                            }

                        MotiTabBar(
                            selectedTab: $selectedTab,
                            bottomSafeArea: proxy.safeAreaInsets.bottom
                        ) { mode in
                            presentCapture(mode)
                        }

                        // Timeline checkpoint floating card — appears above the tab bar
                        // when a checkpoint fires while the app is foregrounded.
                        if let checkpoint = scheduler.coordinator.pendingCheckpoint {
                            CheckpointFloatingCard(
                                event: checkpoint,
                                onRespond: { state in
                                    handleCheckpointResponse(event: checkpoint, state: state)
                                },
                                onDismiss: {
                                    handleCheckpointDismiss(event: checkpoint)
                                }
                            )
                            .padding(.bottom, MotiTabBarMetrics.totalHeight(for: proxy.safeAreaInsets.bottom) + 10)
                            .transition(.asymmetric(
                                insertion: .offset(y: 80).combined(with: .opacity),
                                removal:   .offset(y: 80).combined(with: .opacity)
                            ))
                            .zIndex(10)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: scheduler.coordinator.pendingCheckpoint?.id)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
                .sheet(isPresented: $showingCapture) {
                    QuickCaptureView(
                        startWithVoice: captureStartMode == .voice,
                        selectedDetent: $captureDetent
                    )
                    .presentationDetents([.medium, .large], selection: $captureDetent)
                }
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .task {
            writeWidgetSnapshot()
            await WorkItemNotificationScheduler.shared.reconcile(workItems: workItems)
        }
        .onChange(of: widgetChangeToken) { _, _ in
            writeWidgetSnapshot()
            // Reschedule due-date reminders + progress check-ins whenever any
            // work item's title, project, status, or timing changes.
            Task { await WorkItemNotificationScheduler.shared.reconcile(workItems: workItems) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Re-sync notifications on foreground (covers permission granted
            // while away, and time passing while backgrounded).
            Task { await WorkItemNotificationScheduler.shared.reconcile(workItems: workItems) }
            if let active = allSessions.first(where: { $0.isActive }) {
                scheduler.resolvePassedCheckpoints(for: active)
            }
        }
    }

    // MARK: - Checkpoint handlers

    private func handleCheckpointResponse(
        event: CheckpointCoordinator.CheckpointEvent,
        state: SessionState
    ) {
        if let session = allSessions.first(where: { $0.id == event.sessionID }) {
            let checkIn = SessionCheckIn(progress: event.progress, state: state)
            session.checkIns.append(checkIn)
            markFired(event: event, in: session)
        }
        withAnimation(.spring(duration: 0.3)) {
            scheduler.coordinator.pendingCheckpoint = nil
        }
        #if DEBUG
        print("[Checkpoints] Response recorded: \(Int(event.progress * 100))% → \(state.rawValue)")
        #endif
    }

    private func handleCheckpointDismiss(event: CheckpointCoordinator.CheckpointEvent) {
        if let session = allSessions.first(where: { $0.id == event.sessionID }) {
            markFired(event: event, in: session)
        }
        withAnimation(.spring(duration: 0.3)) {
            scheduler.coordinator.pendingCheckpoint = nil
        }
        #if DEBUG
        print("[Checkpoints] Checkpoint dismissed: \(Int(event.progress * 100))%")
        #endif
    }

    private func markFired(event: CheckpointCoordinator.CheckpointEvent, in session: WorkSession) {
        if !session.firedCheckpoints.contains(event.progress) {
            session.firedCheckpoints.append(event.progress)
        }
        // Deactivate session once the final checkpoint has fired.
        if session.firedCheckpoints.count >= session.checkpointProgress.count {
            session.isActive = false
            scheduler.cancelCheckpoints(for: session.id)
        }
        try? modelContext.save()
    }

    private func writeWidgetSnapshot() {
        WidgetSnapshotWriter.write(projects: projects, workItems: workItems)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .timeline:
            TimelineView {
                presentCapture(.text)
            }
        case .projects:
            ProjectsView()
        case .review:
            ReviewView()
        case .settings:
            SettingsView()
        }
    }

    private func presentCapture(_ mode: CaptureStartMode) {
        guard !showingCapture else { return }
        captureStartMode = mode
        captureDetent = mode == .voice ? .medium : .large
        showingCapture = true
    }
}

enum MotiTabBarMetrics {
    static let rowHeight: CGFloat = 64
    static let plusSize: CGFloat = 52

    static func totalHeight(for bottomSafeArea: CGFloat) -> CGFloat {
        rowHeight + max(bottomSafeArea, 8)
    }

    static func contentClearance(for bottomSafeArea: CGFloat) -> CGFloat {
        totalHeight(for: bottomSafeArea) + 32
    }
}

enum CaptureStartMode {
    case text
    case voice
}

private enum MotiTab: String, CaseIterable, Identifiable {
    case timeline
    case projects
    case review
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .projects: "Projects"
        case .review: "Review"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .timeline: "calendar"
        case .projects: "square.grid.2x2"
        case .review: "tray"
        case .settings: "gearshape"
        }
    }
}

private struct MotiTabBar: View {
    @Binding var selectedTab: MotiTab
    let bottomSafeArea: CGFloat
    let onCapture: (CaptureStartMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(.timeline)
                tabButton(.projects)
                centerAction
                tabButton(.review)
                tabButton(.settings)
            }
            .frame(height: MotiTabBarMetrics.rowHeight)
            .padding(.horizontal, 6)

            Color.clear
                .frame(height: max(bottomSafeArea, 8))
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator).opacity(0.28))
                .frame(maxWidth: .infinity)
                .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 10, y: -2)
    }

    private func tabButton(_ tab: MotiTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                Text(tab.title)
                    .font(.caption2.weight(selectedTab == tab ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selectedTab == tab ? .indigo : .secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var centerAction: some View {
        ZStack {
            Circle()
                .fill(Color.indigo)
                .frame(width: MotiTabBarMetrics.plusSize, height: MotiTabBarMetrics.plusSize)
                .shadow(color: .indigo.opacity(0.18), radius: 6, y: 2)
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: MotiTabBarMetrics.plusSize, height: MotiTabBarMetrics.plusSize)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Circle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCapture(.text)
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCapture(.voice)
        }
        .accessibilityLabel("Add to Timeline")
        .accessibilityHint("Tap to type. Long press to speak.")
    }
}
