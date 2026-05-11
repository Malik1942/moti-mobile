import SwiftData
import SwiftUI

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
                        modeRawValue = TaskUnderstandingMode.foundationModel.rawValue
                        didPromoteFoundationModelDefault = true
                    }
                    #if DEBUG
                    print("Moti requested parser mode:", requestedMode.rawValue)
                    print("Moti active parser mode:", activeMode.rawValue)
                    print("Moti Foundation Model status:", FoundationModelRuntime.status.summary)
                    #endif
                }
        }
        .modelContainer(for: [WorkItem.self, CompletionLog.self])
    }
}

struct RootTabView: View {
    @State private var selectedTab: MotiTab = .timeline
    @State private var showingCapture = false

    var body: some View {
        selectedContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MotiTabBar(selectedTab: $selectedTab) {
                    showingCapture = true
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $showingCapture) {
                QuickCaptureView()
                    .presentationDetents([.medium, .large])
            }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .timeline:
            TimelineView()
        case .projects:
            ProjectsView()
        case .review:
            ReviewView()
        case .settings:
            SettingsView()
        }
    }
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
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.timeline)
            tabButton(.projects)
            centerAction
            tabButton(.review)
            tabButton(.settings)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.28))
        }
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
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
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.indigo.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var centerAction: some View {
        Button {
            onCapture()
        } label: {
            ZStack {
                Circle()
                    .fill(.indigo)
                    .frame(width: 56, height: 56)
                    .shadow(color: .indigo.opacity(0.28), radius: 10, y: 5)
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to Timeline")
    }
}
