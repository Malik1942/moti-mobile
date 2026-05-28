import Foundation

/// Drives the **Timeline Check-in** feedback sheet for `WorkItem` progress
/// checkpoint notifications.
///
/// Companion to `CheckpointCoordinator` (which drives the in-session floating
/// card from manual focus blocks). Kept deliberately small: just one
/// `pendingRequest` that the SwiftUI layer presents as a sheet.
///
/// Routing into here lives in `TimelineCheckpointScheduler`'s notification
/// delegate methods — when an incoming notification is identified as a
/// `moti-progress-*` from `WorkItemNotificationScheduler`, the delegate
/// forwards the extracted payload to `TaskCheckInCoordinator.shared.request(...)`.
@Observable
final class TaskCheckInCoordinator {

    static let shared = TaskCheckInCoordinator()

    /// Represents a pending check-in awaiting the user's response.
    /// `Identifiable` so SwiftUI's `sheet(item:)` re-presents cleanly when a
    /// new event arrives while one is already on screen.
    struct Request: Identifiable, Equatable {
        let id           = UUID()
        let workItemID:    UUID
        let progress:      Double
        /// Originating notification identifier — used to dedup repeated taps.
        let checkpointID:  String
    }

    var pendingRequest: Request?

    private init() {}

    /// Called by the notification delegate when a progress check-in fires or
    /// is tapped. Drops duplicates if the same checkpointID is already
    /// pending (e.g., user taps the banner twice from the lock screen).
    func request(workItemID: UUID, progress: Double, checkpointID: String) {
        if let existing = pendingRequest, existing.checkpointID == checkpointID {
            return
        }
        let req = Request(workItemID: workItemID, progress: progress, checkpointID: checkpointID)
        DispatchQueue.main.async {
            self.pendingRequest = req
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.pendingRequest = nil
        }
    }
}
