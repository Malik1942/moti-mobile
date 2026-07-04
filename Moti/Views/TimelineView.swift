import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TimelineView: View {
    var onAddToTimeline: () -> Void = {}

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @State private var selectedProject = ProjectCatalog.allProjectsLabel
    @State private var selectedHorizon: TimelineHorizonScale = .month
    @State private var showingAddProject = false

    /// Timeline scope: past + present + future, archived hidden. Past work stays
    /// visible — Moti is a temporal memory, not an upcoming-only scheduler.
    private var filteredItems: [WorkItem] {
        WorkItemScope.timeline(workItems).filter { item in
            selectedProject == ProjectCatalog.allProjectsLabel || item.projectName == selectedProject
        }
    }

    private var hasAnyRuntimeContent: Bool {
        !projects.isEmpty || !workItems.isEmpty
    }

    private var orderedProjects: [Project] {
        projects.motiOrdered
    }

    private var horizonDays: Int {
        selectedHorizon.futureDays
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MotiLayout.sectionSpacing) {
                    if hasAnyRuntimeContent {
                        projectSelector
                        horizonSelector
                        MultiWeekTimelineHeroView(
                            workItems: filteredItems,
                            projects: orderedProjects,
                            selectedProject: selectedProject,
                            horizonDays: horizonDays,
                            horizonLabel: selectedHorizon.label
                        )
                        summaryCards
                    } else {
                        emptyTimelineState
                    }
                }
                .padding()
                .padding(.bottom, 64)
            }
            .background(Color.motiGroupedBackground)
            .navigationTitle("Timeline")
            .sheet(isPresented: $showingAddProject) {
                AddProjectSheet()
            }
            .onAppear {
                MotiDebugDataLogger.log(
                    source: "TimelineView.onAppear",
                    projects: projects,
                    workItems: workItems,
                    hasCompletedOnboarding: hasCompletedOnboarding
                )
            }
            .onChange(of: workItems.count) { _, _ in
                MotiDebugDataLogger.log(
                    source: "TimelineView.workItemsChanged",
                    projects: projects,
                    workItems: workItems,
                    hasCompletedOnboarding: hasCompletedOnboarding
                )
            }
            .onChange(of: projects.count) { _, _ in
                if selectedProject != ProjectCatalog.allProjectsLabel,
                   !projects.contains(where: { $0.name == selectedProject }) {
                    selectedProject = ProjectCatalog.allProjectsLabel
                }
                MotiDebugDataLogger.log(
                    source: "TimelineView.projectsChanged",
                    projects: projects,
                    workItems: workItems,
                    hasCompletedOnboarding: hasCompletedOnboarding
                )
            }
        }
    }

    private var projectSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([ProjectCatalog.allProjectsLabel] + orderedProjects.map(\.name), id: \.self) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        let runtimeProject = orderedProjects.first { $0.name == project }
                        if project == ProjectCatalog.allProjectsLabel {
                            Text(ProjectCatalog.allProjectsLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(selectedProject == project ? .white : .primary)
                                .background(selectedProject == project ? Color.motiAccent : Color.motiQuietFill, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(selectedProject == project ? .clear : Color.motiAccent.opacity(0.18), lineWidth: 0.5)
                                }
                        } else {
                            ProjectPill(
                                project: project,
                                isSelected: selectedProject == project,
                                colorToken: runtimeProject?.colorToken
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var horizonSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimelineHorizonScale.allCases) { horizon in
                horizonButton(horizon)
            }
        }
        .padding(4)
        .background(Color.motiQuietFill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timeline period, \(selectedHorizon.longLabel) selected")
    }

    private func horizonButton(_ horizon: TimelineHorizonScale) -> some View {
        let isSelected = selectedHorizon == horizon
        return Button {
            selectedHorizon = horizon
            haptic()
        } label: {
            Text(horizon.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary.opacity(0.82) : Color.secondary.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.motiSurface)
                            .overlay {
                                Capsule()
                                    .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
                            }
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // Due Soon = upcoming + overdue (most-urgent first). Overdue is intentionally
    // included so a passed deadline stays in view.
    private var upcomingDueDates: [WorkItem] {
        Array(WorkItemScope.dueSoon(filteredItems).prefix(5))
    }

    // Active Queue = work live right now (in-window, due today, or untimed-open).
    private var activeWorkPeriods: [WorkItem] {
        WorkItemScope.activeQueue(filteredItems)
    }

    // Recently Completed = past work kept visible as Timeline memory.
    private var recentlyCompleted: [WorkItem] {
        Array(WorkItemScope.recentlyCompleted(filteredItems).prefix(5))
    }

    private var needsReview: [WorkItem] {
        filteredItems.filter(\.needsReview).prefix(4).map { $0 }
    }

    private var summaryCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("At a Glance")
                    .font(.headline)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    compactSummary("Due", items: upcomingDueDates)
                    compactSummary("Active Work", items: activeWorkPeriods)
                    compactSummary("Completed", items: recentlyCompleted)
                    compactSummary("Review", items: needsReview, showRawInput: true)
                }
            }
        }
    }

    private var emptyTimelineState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.motiAccent)
                    .frame(width: 38, height: 38)
                    .background(Color.motiAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Your timeline is ready.")
                        .font(.headline)
                    Text("Capture work with timing, or create a project first.")
                        .font(.motiEmptySubtitle)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    onAddToTimeline()
                } label: {
                    Label("Add to Timeline", systemImage: "plus")
                }
                .buttonStyle(MotiPrimaryButtonStyle(isFullWidth: true))

                Button {
                    showingAddProject = true
                } label: {
                    Label("New Project", systemImage: "square.grid.2x2")
                }
                .buttonStyle(MotiSecondaryButtonStyle(isFullWidth: true))
            }

            Text("Try: \"Work on portfolio from Monday to Wednesday.\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.motiSurface, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous)
                .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
        }
    }

    private func compactSummary(_ title: String, items: [WorkItem], showRawInput: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if items.isEmpty {
                Text("Clear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items.prefix(2)) { item in
                    NavigationLink {
                        WorkItemDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(showRawInput ? item.rawInput : item.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                            ProjectPill(project: item.projectName)
                            if item.isRecurring {
                                Label(item.recurrence.displayLabel, systemImage: "repeat")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.motiAccent)
                            }
                            if let dueDate = item.dueDate {
                                Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 178, alignment: .topLeading)
        .frame(minHeight: 112, alignment: .topLeading)
        .background(Color.motiSurface, in: RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous)
                .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
        }
    }

    private func haptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}

private enum TimelineHorizonScale: String, CaseIterable, Identifiable {
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

    var longLabel: String {
        switch self {
        case .week: return "1 week"
        case .month: return "1 month"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .year: return "1 year"
        }
    }

    var futureDays: Int {
        switch self {
        case .week: return 7
        case .month: return 28
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        }
    }
}
