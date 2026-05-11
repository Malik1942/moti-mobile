import SwiftData
import SwiftUI

struct TimelineView: View {
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @State private var selectedProject = ProjectCatalog.allProjectsLabel
    @State private var horizonDays = 28

    private var filteredItems: [WorkItem] {
        workItems.filter { item in
            item.status != .archived &&
            (selectedProject == ProjectCatalog.allProjectsLabel || item.projectName == selectedProject)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    projectSelector
                    horizonSelector
                    MultiWeekTimelineHeroView(workItems: filteredItems, selectedProject: selectedProject, horizonDays: horizonDays)
                    summaryCards
                }
                .padding()
                .padding(.bottom, 24)
            }
            .navigationTitle("Timeline")
        }
    }

    private var projectSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([ProjectCatalog.allProjectsLabel] + ProjectCatalog.defaultProjects, id: \.self) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        ProjectPill(project: project == ProjectCatalog.allProjectsLabel ? nil : project, isSelected: selectedProject == project)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var horizonSelector: some View {
        Picker("Horizon", selection: $horizonDays) {
            Text("2W").tag(14)
            Text("4W").tag(28)
            Text("Month").tag(30)
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
