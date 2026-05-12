import SwiftData
import SwiftUI

struct TimelineView: View {
    var onAddToTimeline: () -> Void = {}

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @State private var selectedProject = ProjectCatalog.allProjectsLabel
    @State private var horizonDays = 30
    @State private var showingAddProject = false

    private var filteredItems: [WorkItem] {
        workItems.filter { item in
            item.status != .archived &&
            (selectedProject == ProjectCatalog.allProjectsLabel || item.projectName == selectedProject)
        }
    }

    private var hasAnyRuntimeContent: Bool {
        !projects.isEmpty || !workItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if hasAnyRuntimeContent {
                        projectSelector
                        horizonSelector
                        MultiWeekTimelineHeroView(
                            workItems: filteredItems,
                            projects: projects,
                            selectedProject: selectedProject,
                            horizonDays: horizonDays
                        )
                        summaryCards
                    } else {
                        emptyTimelineState
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
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
                ForEach([ProjectCatalog.allProjectsLabel] + projects.map(\.name), id: \.self) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        let runtimeProject = projects.first { $0.name == project }
                        if project == ProjectCatalog.allProjectsLabel {
                            Text(ProjectCatalog.allProjectsLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(selectedProject == project ? .white : .indigo)
                                .background(selectedProject == project ? .indigo : .indigo.opacity(0.12), in: Capsule())
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
        Picker("Horizon", selection: $horizonDays) {
            Text("2W").tag(14)
            Text("Month").tag(30)
            Text("Quarter").tag(90)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }

    private var upcomingDueDates: [WorkItem] {
        filteredItems
            .filter { !$0.needsReview && $0.dueDate != nil }
            .filter { $0.status != .done }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(5)
            .map { $0 }
    }

    private var activeWorkPeriods: [WorkItem] {
        filteredItems.filter { item in
            guard let start = item.workingStartDate, let end = item.workingEndDate else { return false }
            return start <= Date.now && Date.now <= end && !item.needsReview && item.status != .done
        }
    }

    private var needsReview: [WorkItem] {
        filteredItems.filter(\.needsReview).prefix(4).map { $0 }
    }

    private var summaryCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timeline Signals")
                    .font(.headline)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    compactSummary("Due Soon", items: upcomingDueDates)
                    compactSummary("Active Work", items: activeWorkPeriods)
                    compactSummary("Needs Review", items: needsReview, showRawInput: true)
                }
            }
        }
    }

    private var emptyTimelineState: some View {
        VStack(alignment: .leading, spacing: MotiLayout.emptyStateSpacing) {
            Text("Your timeline is ready.")
                .font(.headline)
            Text("Create a project or capture work with timing to start planning.")
                .font(.motiEmptySubtitle)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    showingAddProject = true
                } label: {
                    Label("Add Project", systemImage: "square.grid.2x2")
                }
                .font(.motiButtonLabel)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Button {
                    onAddToTimeline()
                } label: {
                    Label("Add to Timeline", systemImage: "plus")
                }
                .font(.motiButtonLabel)
                .buttonStyle(.bordered)
                .tint(.indigo)
            }

            Text("Try: \"Work on portfolio from Monday to Wednesday.\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(MotiLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}
