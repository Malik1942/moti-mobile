import Foundation
import SwiftData

struct CompletionLogger {
    let modelContext: ModelContext

    func log(
        taskId: UUID,
        eventType: CompletionEventType,
        previousStatus: WorkItemStatus?,
        newStatus: WorkItemStatus,
        context: String? = nil
    ) {
        let entry = CompletionLog(
            taskId: taskId,
            eventType: eventType,
            previousStatus: previousStatus,
            newStatus: newStatus,
            context: context
        )
        modelContext.insert(entry)
    }
}
