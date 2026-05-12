import Foundation

enum MotiDebugDataLogger {
    static func log(
        source: String,
        projects: [Project],
        workItems: [WorkItem],
        hasCompletedOnboarding: Bool
    ) {
        #if DEBUG
        print("[Moti Debug] Source: \(source)")
        print("[Moti Debug] Onboarding completed: \(hasCompletedOnboarding)")
        print("[Moti Debug] Projects count: \(projects.count)")
        if projects.isEmpty {
            print("[Moti Debug] Projects: []")
        } else {
            for project in projects {
                print("[Moti Debug] Project: name=\"\(project.name)\", colorToken=\"\(project.colorToken)\"")
            }
        }

        print("[Moti Debug] WorkItems count: \(workItems.count)")
        if workItems.isEmpty {
            print("[Moti Debug] WorkItems: []")
        } else {
            for item in workItems {
                print(
                    """
                    [Moti Debug] WorkItem: title="\(item.title)", projectName=\(item.projectName ?? "nil"), suggestedProjectName=\(item.suggestedProjectName ?? "nil"), needsReview=\(item.needsReview), dueDate=\(item.dueDate?.description ?? "nil"), workingStartDate=\(item.workingStartDate?.description ?? "nil"), workingEndDate=\(item.workingEndDate?.description ?? "nil")
                    """
                )
            }
        }
        #endif
    }
}
