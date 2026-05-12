import Foundation
import WidgetKit

enum WidgetSnapshotWriter {
    static func write(projects: [Project], workItems: [WorkItem]) {
        let projectData: [ProjectWidgetData] = projects.motiOrdered.map { project in
            let projectItems = workItems.filter {
                $0.projectName == project.name &&
                $0.status != .archived &&
                !$0.needsReview
            }.map(WidgetWorkItemData.init(workItem:))

            let activeCount = projectItems.filter { $0.statusRawValue == WorkItemStatus.active.rawValue }.count
            return ProjectWidgetData(
                id: project.id,
                name: project.name,
                colorToken: project.colorToken,
                activeCount: activeCount,
                items: projectItems
            )
        }

        let snapshot = ProjectWidgetSnapshot(generatedAt: .now, projects: projectData)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ProjectWidgetSnapshot.appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }

        let url = container.appendingPathComponent(ProjectWidgetSnapshot.snapshotFilename)
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension WidgetWorkItemData {
    init(workItem: WorkItem) {
        id = workItem.id
        title = workItem.title
        statusRawValue = workItem.statusRawValue
        dueDate = workItem.dueDate
        workingStartDate = workItem.workingStartDate
        workingEndDate = workItem.workingEndDate
        // An item is a point event when start and end fall on the same calendar day
        isEvent = {
            guard let start = workItem.workingStartDate, let end = workItem.workingEndDate else { return false }
            let cal = Calendar.current
            return !(cal.startOfDay(for: start) < cal.startOfDay(for: end))
        }()
    }
}
