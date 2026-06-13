import Foundation
import SwiftData

/// Single entry point for "the user marked this work item complete", so every
/// surface (detail view, project rows, quick actions) treats recurrence the
/// same way.
///
/// Product rule: a recurring WorkItem is a **living habit, not a one-time
/// task**. Completing it logs the occurrence and rolls the item forward to its
/// next due date while staying active — it only becomes permanently complete
/// when the user explicitly stops or archives it. Non-recurring items keep the
/// existing one-shot `.done` behavior.
enum WorkItemCompletion {

    /// Completes `item`. Returns `true` if the item stays active (a recurring
    /// occurrence rolled forward), `false` if it was marked `.done`.
    @discardableResult
    static func complete(
        _ item: WorkItem,
        in modelContext: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let previousStatus = item.status

        guard item.isRecurring else {
            // Non-recurring: unchanged one-shot completion.
            item.status = .done
            item.needsReview = false
            item.updatedAt = now
            try? modelContext.save()
            return false
        }

        // Recurring: record this occurrence in completion history, then advance
        // to the next due date and remain active.
        let completedOccurrence = item.completeRecurringOccurrence(now: now, calendar: calendar)
        item.needsReview = false

        CompletionLogger.log(
            taskId: item.id,
            eventType: .statusChanged,
            previousStatus: previousStatus,
            newStatus: .done,
            context: completedOccurrence.map { "recurring occurrence completed \(ISO8601DateFormatter().string(from: $0))" }
                ?? "recurring occurrence completed",
            in: modelContext
        )

        try? modelContext.save()
        return true
    }
}
