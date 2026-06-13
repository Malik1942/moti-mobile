import Foundation
import SwiftData

enum CompletionLogger {
    static func log(
        taskId: UUID,
        eventType: CompletionEventType,
        previousStatus: WorkItemStatus?,
        newStatus: WorkItemStatus,
        context: String? = nil,
        in modelContext: ModelContext
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
