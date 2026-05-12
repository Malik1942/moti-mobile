import EventKit
import Foundation

enum AppleCalendarSyncStatus: Equatable {
    case off
    case connected
    case permissionNeeded
    case unavailable

    var label: String {
        switch self {
        case .off: "Calendar Sync Off"
        case .connected: "Apple Calendar Connected"
        case .permissionNeeded: "Calendar Permission Needed"
        case .unavailable: "Apple Calendar Unavailable"
        }
    }
}

@MainActor
final class AppleCalendarSyncService {
    static let shared = AppleCalendarSyncService()

    private let eventStore = EKEventStore()
    private let calendar = Calendar.current

    private init() {}

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var syncStatus: AppleCalendarSyncStatus {
        switch authorizationStatus {
        case .fullAccess:
            return .connected
        case .writeOnly:
            return .permissionNeeded
        case .denied, .restricted:
            return .permissionNeeded
        case .notDetermined:
            return .permissionNeeded
        @unknown default:
            return .unavailable
        }
    }

    func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .fullAccess:
            return true
        case .writeOnly:
            return false
        case .notDetermined:
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        default:
            return false
        }
    }

    func sync(item: WorkItem, mode: CalendarSyncMode) throws {
        guard syncStatus == .connected else { return }
        guard !item.needsReview, item.hasCalendarTiming else {
            try deleteEvent(for: item)
            return
        }

        let event = existingEvent(for: item) ?? EKEvent(eventStore: eventStore)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.title = item.title
        event.notes = notes(for: item)
        applyTiming(from: item, to: event, mode: mode)

        try eventStore.save(event, span: .thisEvent, commit: true)
        item.calendarEventIdentifier = event.eventIdentifier
        item.calendarProvider = CalendarSyncProvider.appleCalendar.rawValue
        item.lastCalendarSyncAt = .now
    }

    func syncIfEnabled(item: WorkItem) throws {
        guard UserDefaults.standard.bool(forKey: "calendarSyncEnabled") else { return }
        let providerRawValue = UserDefaults.standard.string(forKey: "calendarSyncProvider") ?? CalendarSyncProvider.appleCalendar.rawValue
        guard CalendarSyncProvider(rawValue: providerRawValue) == .appleCalendar else { return }
        let modeRawValue = UserDefaults.standard.string(forKey: "calendarSyncMode") ?? CalendarSyncMode.event.rawValue
        let mode = CalendarSyncMode(rawValue: modeRawValue) ?? .event
        try sync(item: item, mode: mode)
    }

    func syncAfterItemChange(item: WorkItem) throws {
        if item.calendarEventIdentifier != nil, (item.needsReview || !item.hasCalendarTiming) {
            try deleteEvent(for: item)
            return
        }
        try syncIfEnabled(item: item)
    }

    func deleteEvent(for item: WorkItem) throws {
        guard let identifier = item.calendarEventIdentifier else { return }
        if let event = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        item.calendarEventIdentifier = nil
        item.calendarProvider = nil
        item.lastCalendarSyncAt = .now
    }

    private func existingEvent(for item: WorkItem) -> EKEvent? {
        guard let identifier = item.calendarEventIdentifier else { return nil }
        return eventStore.event(withIdentifier: identifier)
    }

    private func applyTiming(from item: WorkItem, to event: EKEvent, mode: CalendarSyncMode) {
        switch mode {
        case .event:
            event.isAllDay = false
            let start = item.workingStartDate ?? item.dueDate ?? item.createdAt
            let end = item.workingEndDate ?? item.dueDate ?? calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            event.startDate = start
            event.endDate = end > start ? end : calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        case .allDay:
            event.isAllDay = true
            let start = calendar.startOfDay(for: item.workingStartDate ?? item.dueDate ?? item.createdAt)
            let endSource = item.workingEndDate ?? item.dueDate ?? start
            let endDay = calendar.startOfDay(for: endSource)
            event.startDate = start
            event.endDate = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        }
    }

    private func notes(for item: WorkItem) -> String {
        """
        Original capture:
        \(item.rawInput)

        Project:
        \(item.displayProject)

        Created by Moti.
        """
    }
}

extension WorkItem {
    var hasCalendarTiming: Bool {
        dueDate != nil || (workingStartDate != nil && workingEndDate != nil)
    }
}
