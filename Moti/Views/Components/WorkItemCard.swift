import SwiftUI

struct WorkItemCard: View {
    let item: WorkItem
    var showRawInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(showRawInput ? item.rawInput : item.title)
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                ProjectPill(project: item.projectName)
                if let dueDate = item.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let start = item.workingStartDate, let end = item.workingEndDate {
                Label("\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = item.reviewReason, item.needsReview {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(Color.motiSurface, in: RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous)
                .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
        }
    }
}
