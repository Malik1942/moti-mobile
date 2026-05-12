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
        .modelContainer(for: [WorkItem.self, CompletionLog.self, Project.self])
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

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        selectedContent
                            .safeAreaPadding(.bottom, MotiTabBarMetrics.contentClearance(for: proxy.safeAreaInsets.bottom))

                        MotiTabBar(
                            selectedTab: $selectedTab,
                            bottomSafeArea: proxy.safeAreaInsets.bottom
                        ) { mode in
                            presentCapture(mode)
                        }
                    }
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
    static let plusSize: CGFloat = 56
    static let plusLift: CGFloat = 12

    static func totalHeight(for bottomSafeArea: CGFloat) -> CGFloat {
        rowHeight + max(bottomSafeArea, 8)
    }

    static func contentClearance(for bottomSafeArea: CGFloat) -> CGFloat {
        totalHeight(for: bottomSafeArea) + plusLift + 18
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
                .shadow(color: .indigo.opacity(0.24), radius: 8, y: 4)
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: MotiTabBarMetrics.plusSize, height: MotiTabBarMetrics.plusSize)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .offset(y: -MotiTabBarMetrics.plusLift)
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
