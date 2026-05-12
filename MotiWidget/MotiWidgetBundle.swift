import WidgetKit
import SwiftUI

// MARK: - Entry

struct MotiWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ProjectWidgetSnapshot?
}

// MARK: - Provider

struct MotiWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MotiWidgetEntry {
        MotiWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MotiWidgetEntry) -> Void) {
        completion(MotiWidgetEntry(date: .now, snapshot: context.isPreview ? .placeholder : .readFromAppGroup()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MotiWidgetEntry>) -> Void) {
        let snapshot = ProjectWidgetSnapshot.readFromAppGroup()
        let now = Date.now

        // Entries every 15 minutes for 4 hours so the progress bar advances smoothly
        var entries: [MotiWidgetEntry] = []
        for minuteOffset in stride(from: 0, through: 240, by: 15) {
            let entryDate = now.addingTimeInterval(TimeInterval(minuteOffset * 60))
            entries.append(MotiWidgetEntry(date: entryDate, snapshot: snapshot))
        }

        // After 4 hours re-fetch the snapshot in case the app has written new data
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(4 * 3600))))
    }
}

// MARK: - Bundle

@main
struct MotiWidgetBundle: WidgetBundle {
    var body: some Widget {
        MotiWidget()
    }
}

struct MotiWidget: Widget {
    let kind = "MotiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MotiWidgetProvider()) { entry in
            MotiWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Project Pulse")
        .description("See the time progress of your active project at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Placeholder snapshot

extension ProjectWidgetSnapshot {
    static let placeholder = ProjectWidgetSnapshot(
        generatedAt: .now,
        projects: [
            ProjectWidgetData(
                id: UUID(),
                name: "Job Search",
                colorToken: "blue",
                activeCount: 3,
                items: [
                    WidgetWorkItemData(
                        id: UUID(),
                        title: "Apply to 5 roles",
                        statusRawValue: "active",
                        dueDate: Calendar.current.date(byAdding: .day, value: 12, to: .now),
                        workingStartDate: Calendar.current.date(byAdding: .day, value: -10, to: .now),
                        workingEndDate: Calendar.current.date(byAdding: .day, value: 14, to: .now),
                        isEvent: false
                    ),
                    WidgetWorkItemData(
                        id: UUID(),
                        title: "Prepare interview",
                        statusRawValue: "active",
                        dueDate: nil,
                        workingStartDate: Calendar.current.date(byAdding: .day, value: -2, to: .now),
                        workingEndDate: Calendar.current.date(byAdding: .day, value: 9, to: .now),
                        isEvent: false
                    ),
                    WidgetWorkItemData(
                        id: UUID(),
                        title: "Refine portfolio",
                        statusRawValue: "active",
                        dueDate: nil,
                        workingStartDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
                        workingEndDate: Calendar.current.date(byAdding: .day, value: 10, to: .now),
                        isEvent: false
                    ),
                ]
            )
        ]
    )
}
