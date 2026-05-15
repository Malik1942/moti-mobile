import Foundation
import SwiftData
import UserNotifications

// MARK: - Checkpoint Coordinator
//
// Separate @Observable class so SwiftUI views can observe pendingCheckpoint
// without coupling to NSObject. The scheduler delegates to this for all
// state that drives the foreground floating card.

@Observable
final class CheckpointCoordinator {
    var pendingCheckpoint: CheckpointEvent?

    struct CheckpointEvent: Identifiable {
        let id        = UUID()
        let sessionID: UUID
        let progress:  Double
        let timestamp: Date
    }
}

// MARK: - TimelineCheckpointScheduler

final class TimelineCheckpointScheduler: NSObject {

    static let shared = TimelineCheckpointScheduler()

    /// The four progress fractions at which checkpoints fire.
    static let checkpointValues: [Double] = [0.25, 0.5, 0.75, 0.9]

    /// Observable state that the SwiftUI layer reads.
    let coordinator = CheckpointCoordinator()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    func requestAuthorizationIfNeeded() async -> Bool {
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedules local notifications for every unfired checkpoint in the session.
    /// Safe to call again after an app relaunch — already-pending notifications
    /// are removed first to prevent duplicates.
    func scheduleCheckpoints(for session: WorkSession) async {
        guard session.duration > 0 else { return }
        let center = UNUserNotificationCenter.current()

        for progress in Self.checkpointValues {
            guard !session.firedCheckpoints.contains(progress) else { continue }

            let triggerDate = session.startTime.addingTimeInterval(session.duration * progress)
            guard triggerDate > .now else {
                #if DEBUG
                print("[Checkpoints] Skipped past-due \(Int(progress * 100))% checkpoint")
                #endif
                continue
            }

            let notifID = notificationID(sessionID: session.id, progress: progress)

            // Remove any existing request to prevent duplicates on reschedule.
            center.removePendingNotificationRequests(withIdentifiers: [notifID])

            let content       = UNMutableNotificationContent()
            content.title     = "Timeline checkpoint"
            content.body      = "How are things feeling right now?"
            content.sound     = .default
            content.userInfo  = [
                "sessionID": session.id.uuidString,
                "progress":  progress
            ]

            let comps   = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: notifID, content: content, trigger: trigger)

            do {
                try await center.add(request)
                #if DEBUG
                print("[Checkpoints] Scheduled \(Int(progress * 100))% → \(triggerDate.formatted())")
                #endif
            } catch {
                #if DEBUG
                print("[Checkpoints] Failed to schedule \(Int(progress * 100))%: \(error)")
                #endif
            }
        }
    }

    /// Removes all pending notifications for the given session.
    func cancelCheckpoints(for sessionID: UUID) {
        let ids = Self.checkpointValues.map { notificationID(sessionID: sessionID, progress: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        #if DEBUG
        print("[Checkpoints] Cancelled all pending checkpoints for session \(sessionID)")
        #endif
    }

    // MARK: - Foreground resolution
    //
    // Called when the app returns to the foreground. If a checkpoint's trigger
    // time has passed while the app was suspended and the user did not interact
    // with the banner, we surface it as a floating card so it isn't silently lost.

    func resolvePassedCheckpoints(for session: WorkSession) {
        guard session.isActive, coordinator.pendingCheckpoint == nil else { return }
        let now = Date.now
        for progress in Self.checkpointValues.sorted() {
            guard !session.firedCheckpoints.contains(progress) else { continue }
            let triggerDate = session.startTime.addingTimeInterval(session.duration * progress)
            guard triggerDate <= now else { break }

            let event = CheckpointCoordinator.CheckpointEvent(
                sessionID: session.id,
                progress:  progress,
                timestamp: triggerDate
            )
            DispatchQueue.main.async {
                self.coordinator.pendingCheckpoint = event
            }
            #if DEBUG
            print("[Checkpoints] Surfaced passed checkpoint \(Int(progress * 100))% on foreground")
            #endif
            return // one at a time
        }
    }

    // MARK: - Helpers

    private func notificationID(sessionID: UUID, progress: Double) -> String {
        "moti-checkpoint-\(sessionID.uuidString)-\(Int(progress * 100))"
    }

    private func extractEvent(from userInfo: [AnyHashable: Any]) -> CheckpointCoordinator.CheckpointEvent? {
        guard
            let idStr     = userInfo["sessionID"] as? String,
            let sessionID = UUID(uuidString: idStr),
            let progress  = userInfo["progress"] as? Double
        else { return nil }
        return CheckpointCoordinator.CheckpointEvent(sessionID: sessionID, progress: progress, timestamp: .now)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension TimelineCheckpointScheduler: UNUserNotificationCenterDelegate {

    /// App is foregrounded when the notification fires.
    /// Suppress the system banner and drive the floating card instead.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard let event = extractEvent(from: notification.request.content.userInfo) else {
            completionHandler([.banner, .sound])
            return
        }
        DispatchQueue.main.async {
            self.coordinator.pendingCheckpoint = event
        }
        #if DEBUG
        print("[Checkpoints] Foreground intercept → \(Int(event.progress * 100))%")
        #endif
        completionHandler([]) // suppress system banner
    }

    /// User tapped a notification delivered while the app was backgrounded or killed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let event = extractEvent(from: response.notification.request.content.userInfo) {
            DispatchQueue.main.async {
                self.coordinator.pendingCheckpoint = event
            }
            #if DEBUG
            print("[Checkpoints] Notification tapped → \(Int(event.progress * 100))%")
            #endif
        }
        completionHandler()
    }
}
