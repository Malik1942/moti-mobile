import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(ProjectCatalog.defaultProjects, id: \.self) { project in
                    let items = workItems.filter { $0.projectName == project && !$0.needsReview }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ProjectPill(project: project)
                            Spacer()
                            Text("\(items.count) active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let nextDeadline = items.compactMap(\.dueDate).sorted().first {
                            Label(nextDeadline.formatted(date: .abbreviated, time: .shortened), systemImage: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        workloadBar(count: items.count)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Projects")
        }
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
