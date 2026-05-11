import Foundation
import SwiftData

@Model
final class CompletionLog {
    @Attribute(.unique) var id: UUID
    var taskId: UUID
    var eventTypeRawValue: String
    var previousStatusRawValue: String?
    var newStatusRawValue: String
    var timestamp: Date
    var context: String?

    init(
        id: UUID = UUID(),
        taskId: UUID,
        eventType: CompletionEventType,
        previousStatus: WorkItemStatus? = nil,
        newStatus: WorkItemStatus,
        timestamp: Date = .now,
        context: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.eventTypeRawValue = eventType.rawValue
        self.previousStatusRawValue = previousStatus?.rawValue
        self.newStatusRawValue = newStatus.rawValue
        self.timestamp = timestamp
        self.context = context
    }

    var eventType: CompletionEventType {
        get { CompletionEventType(rawValue: eventTypeRawValue) ?? .edited }
        set { eventTypeRawValue = newValue.rawValue }
    }

    var previousStatus: WorkItemStatus? {
        get { previousStatusRawValue.flatMap(WorkItemStatus.init(rawValue:)) }
        set { previousStatusRawValue = newValue?.rawValue }
    }

    var newStatus: WorkItemStatus {
        get { WorkItemStatus(rawValue: newStatusRawValue) ?? .active }
        set { newStatusRawValue = newValue.rawValue }
    }
}
