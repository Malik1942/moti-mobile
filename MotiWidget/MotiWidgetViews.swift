import SwiftUI
import WidgetKit

// MARK: - Router

struct MotiWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MotiWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small widget

struct SmallWidgetView: View {
    let entry: MotiWidgetEntry

    private var project: ProjectWidgetData? { entry.snapshot?.projects.first }

    var body: some View {
        Group {
            if let project {
                let item = widgetRankedItems(project.items, now: entry.date, maxCount: 1).first
                smallContent(project: project, item: item)
            } else {
                emptyStateView
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func smallContent(project: ProjectWidgetData, item: WidgetWorkItemData?) -> some View {
        let accent = Color.widgetProjectColor(token: project.colorToken)

        return VStack(alignment: .leading, spacing: 0) {
            projectLabel(project.name, accent: accent)

            if let item {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                if item.isEvent {
                    eventLabel(item: item)
                } else if item.hasTiming, let pct = item.progressPercentage(asOf: entry.date) {
                    timingContent(item: item, pct: pct, accent: accent)
                } else {
                    Text("Needs timing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No scheduled work")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func timingContent(item: WidgetWorkItemData, pct: Int, accent: Color) -> some View {
        HStack(spacing: 6) {
            MotiProgressBar(progress: Double(pct) / 100, color: accent)
            Text("\(pct)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }

        if let due = item.dueDate {
            Text("Due \(due.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
    }

    @ViewBuilder
    private func eventLabel(item: WidgetWorkItemData) -> some View {
        if let start = item.workingStartDate {
            Text(start.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let due = item.dueDate {
            Text(due.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Moti")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text("Your timeline is ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Add a project in Moti")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

// MARK: - Medium widget

struct MediumWidgetView: View {
    let entry: MotiWidgetEntry

    private var project: ProjectWidgetData? { entry.snapshot?.projects.first }

    var body: some View {
        Group {
            if let project {
                let items = widgetRankedItems(project.items, now: entry.date, maxCount: 3)
                mediumContent(project: project, items: items)
            } else {
                emptyStateView
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func mediumContent(project: ProjectWidgetData, items: [WidgetWorkItemData]) -> some View {
        let accent = Color.widgetProjectColor(token: project.colorToken)

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                projectLabel(project.name, accent: accent)
                Spacer()
                if project.activeCount > 0 {
                    Text("\(project.activeCount) active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                Text("No scheduled work yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        WidgetItemRow(item: item, accent: accent, now: entry.date)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Moti")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text("Your timeline is ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Add a project in Moti")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

// MARK: - Item row (medium widget)

struct WidgetItemRow: View {
    let item: WidgetWorkItemData
    let accent: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                percentageLabel
            }
            progressRow
        }
    }

    @ViewBuilder
    private var percentageLabel: some View {
        if item.isEvent {
            Text("Event")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if item.hasTiming, let pct = item.progressPercentage(asOf: now) {
            Text("\(pct)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
        } else {
            Text("–")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var progressRow: some View {
        if item.isEvent {
            if let start = item.workingStartDate {
                Text(start.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if item.hasTiming, let pct = item.progressPercentage(asOf: now) {
            MotiProgressBar(progress: Double(pct) / 100, color: accent, height: 5)
        } else {
            Text("Needs timing")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Shared components

/// Colored dot + project name label, used in both widget sizes.
private func projectLabel(_ name: String, accent: Color) -> some View {
    HStack(spacing: 5) {
        Circle()
            .fill(accent)
            .frame(width: 7, height: 7)
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .lineLimit(1)
    }
    .padding(.bottom, 2)
}

struct MotiProgressBar: View {
    let progress: Double  // 0.0–1.0
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(geo.size.width * min(max(progress, 0), 1), height), height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    MotiWidget()
} timeline: {
    MotiWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview("Medium", as: .systemMedium) {
    MotiWidget()
} timeline: {
    MotiWidgetEntry(date: .now, snapshot: .placeholder)
}
