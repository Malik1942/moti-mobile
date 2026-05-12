import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @State private var showingAddProject = false

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyProjectsState
                } else {
                    List {
                        ForEach(projects) { project in
                            let items = workItems.filter { $0.projectName == project.name && !$0.needsReview }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    ProjectPill(project: project.name, colorToken: project.colorToken)
                                    Spacer()
                                    Text("\(items.count) active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let nextDeadline = items.compactMap(\.dueDate).sorted().first {
                                    Label(nextDeadline.formatted(date: .abbreviated, time: .shortened), systemImage: "flag.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No scheduled work yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                workloadBar(count: items.count)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add project")
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectSheet()
            }
        }
    }

    private var emptyProjectsState: some View {
        VStack(alignment: .leading, spacing: MotiLayout.emptyStateSpacing) {
            MotiEmptyStateIcon(systemName: "square.grid.2x2")
            Text("Add your first project.")
                .font(.motiEmptyTitle)
            Text("Projects help Moti organize work across your timeline.")
                .font(.motiEmptySubtitle)
                .foregroundStyle(.secondary)
            Button {
                showingAddProject = true
            } label: {
                Label("Add Project", systemImage: "square.grid.2x2")
            }
            .font(.motiButtonLabel)
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }

    private func workloadBar(count: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.06))
                Capsule().fill(.indigo.opacity(0.45)).frame(width: min(proxy.size.width, CGFloat(count) / 8 * proxy.size.width))
            }
        }
        .frame(height: 8)
    }
}
