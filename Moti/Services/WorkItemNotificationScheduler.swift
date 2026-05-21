import Foundation
import SwiftData
import UserNotifications

/// Schedules local notifications derived automatically from work items:
///
///   - **Due-date reminders** — a "morning of" heads-up at 9:00 and a
///     "1 hour before" nudge, both ahead of the deadline (never at/after it).
///   - **Progress check-ins** — at 25 / 50 / 75 / 90% of a task's planned
///     working period (workingStartDate → workingEndDate).
///
/// Distinct from `TimelineCheckpointScheduler`, which handles manually-started
/// `WorkSession` focus blocks and drives the in-app floating card. This one is
/// fully automatic — driven by each work item's own schedule — and delivers
/// plain banners. Notification identifiers are namespaced (`moti-due-`,
/// `moti-progress-`) so the two systems never collide or clobber each other.
///
/// Never writes to SwiftData. Pure notification scheduling.
final class WorkItemNotificationScheduler {

    static let shared = WorkItemNotificationScheduler()
    private init() {}

    static let progressValues: [Double] = [0.25, 0.5, 0.75, 0.9]

    // UserDefaults keys — shared with the Settings @AppStorage toggles.
    static let dueRemindersKey   = "notifyDueReminders"
    static let progressChecksKey = "notifyProgressChecks"

    private let duePrefix      = "moti-due-"
    private let progressPrefix = "moti-progress-"

    // iOS allows ~64 pending local notifications per app. Stay under it and
    // prioritize the soonest-firing reminders.
    private let maxScheduled = 60

    private var dueRemindersEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.dueRemindersKey) as? Bool ?? true
    }
    private var progressChecksEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.progressChecksKey) as? Bool ?? true
    }

    /// Cancels all managed notifications and reschedules from the current work
    /// items. Safe to call frequently — app launch, item changes, toggle flips.
    func reconcile(workItems: [WorkItem]) async {
        let center = UNUserNotificationCenter.current()

        // Always clear our previously-scheduled notifications first so deleted
        // / completed / edited items don't leave stale reminders behind.
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter {
            $0.hasPrefix(duePrefix) || $0.hasPrefix(progressPrefix)
        }
        if !ourIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ourIDs)
        }

        // Only schedule when the user has granted permission.
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let now = Date.now
        var dated: [(date: Date, request: UNNotificationRequest)] = []

        for item in workItems where isSchedulable(item) {
            if dueRemindersEnabled, let due = item.dueDate {
                dated.append(contentsOf: dueRequests(for: item, due: due, now: now))
            }
            if progressChecksEnabled,
               let start = item.workingStartDate,
               let end = item.workingEndDate,
               end > start {
                dated.append(contentsOf: progressRequests(for: item, start: start, end: end, now: now))
            }
        }

        // Soonest first, capped to stay under the iOS pending-notification limit.
        let capped = dated.sorted { $0.date < $1.date }.prefix(maxScheduled)
        for entry in capped {
            try? await center.add(entry.request)
        }

        #if DEBUG
        print("[WorkItemNotifications] Scheduled \(capped.count) of \(dated.count) candidate notifications across \(workItems.count) items.")
        #endif
    }

    /// Removes every managed notification (used when both toggles are off, or
    /// when permission is revoked).
    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter {
            $0.hasPrefix(duePrefix) || $0.hasPrefix(progressPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ourIDs)
    }

    // MARK: - Eligibility

    private func isSchedulable(_ item: WorkItem) -> Bool {
        item.status != .done && item.status != .archived && !item.needsReview
    }

    private func displayTitle(_ item: WorkItem) -> String {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "your task" : trimmed
    }

    // MARK: - Due reminders

    private func dueRequests(for item: WorkItem, due: Date, now: Date) -> [(Date, UNNotificationRequest)] {
        var out: [(Date, UNNotificationRequest)] = []
        let title = displayTitle(item)
        let calendar = Calendar.current

        // Morning-of heads-up at 9:00 on the due date — only if it lands before
        // the deadline itself and is still in the future.
        if let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due),
           morning > now, morning < due {
            out.append((morning, makeRequest(
                id: "\(duePrefix)\(item.id.uuidString)-morning",
                title: "Due today",
                body: "“\(title)” is due today.",
                date: morning
            )))
        }

        // One hour before the deadline.
        let hourBefore = due.addingTimeInterval(-3600)
        if hourBefore > now {
            out.append((hourBefore, makeRequest(
                id: "\(duePrefix)\(item.id.uuidString)-hour",
                title: "Due soon",
                body: "“\(title)” is due in about an hour.",
                date: hourBefore
            )))
        }

        return out
    }

    // MARK: - Progress checks

    private func progressRequests(for item: WorkItem, start: Date, end: Date, now: Date) -> [(Date, UNNotificationRequest)] {
        let title = displayTitle(item)
        let duration = end.timeIntervalSince(start)
        var out: [(Date, UNNotificationRequest)] = []
        for pct in Self.progressValues {
            let fire = start.addingTimeInterval(duration * pct)
            guard fire > now else { continue }
            out.append((fire, makeRequest(
                id: "\(progressPrefix)\(item.id.uuidString)-\(Int(pct * 100))",
                title: "Progress check",
                body: "You're \(Int(pct * 100))% through the planned time for “\(title).” How's it going?",
                date: fire
            )))
        }
        return out
    }

    // MARK: - Helpers

    private func makeRequest(id: String, title: String, body: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
