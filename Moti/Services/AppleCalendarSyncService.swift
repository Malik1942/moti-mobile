import EventKit
import Foundation
import UIKit

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

enum AppleCalendarSyncError: LocalizedError {
    case noWritableCalendarSource

    var errorDescription: String? {
        switch self {
        case .noWritableCalendarSource:
            "No writable Apple Calendar source is available."
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

    func sync(item: WorkItem, projects: [Project], mode: CalendarSyncMode) throws {
        guard syncStatus == .connected else { return }
        guard !item.needsReview, item.hasCalendarTiming else {
            try deleteEvent(for: item)
            return
        }

        let targetCalendar = try calendar(for: item, projects: projects)
        let event = existingEvent(for: item) ?? EKEvent(eventStore: eventStore)
        event.calendar = targetCalendar
        event.title = item.title
        event.notes = notes(for: item)
        applyTiming(from: item, to: event, mode: mode)

        try eventStore.save(event, span: .thisEvent, commit: true)
        item.calendarEventIdentifier = event.eventIdentifier
        item.calendarIdentifier = targetCalendar.calendarIdentifier
        item.calendarProvider = CalendarSyncProvider.appleCalendar.rawValue
        item.lastCalendarSyncAt = .now
    }

    func syncIfEnabled(item: WorkItem, projects: [Project]) throws {
        guard UserDefaults.standard.bool(forKey: "calendarSyncEnabled") else { return }
        let providerRawValue = UserDefaults.standard.string(forKey: "calendarSyncProvider") ?? CalendarSyncProvider.appleCalendar.rawValue
        guard CalendarSyncProvider(rawValue: providerRawValue) == .appleCalendar else { return }
        let modeRawValue = UserDefaults.standard.string(forKey: "calendarSyncMode") ?? CalendarSyncMode.event.rawValue
        let mode = CalendarSyncMode(rawValue: modeRawValue) ?? .event
        try sync(item: item, projects: projects, mode: mode)
    }

    func syncAfterItemChange(item: WorkItem, projects: [Project]) throws {
        if item.calendarEventIdentifier != nil, (item.needsReview || !item.hasCalendarTiming) {
            try deleteEvent(for: item)
            return
        }
        try syncIfEnabled(item: item, projects: projects)
    }

    func prepareProjectCalendars(projects: [Project]) throws {
        guard syncStatus == .connected else { return }
        for project in projects {
            _ = try calendar(for: project)
        }
    }

    func syncExistingScheduledItems(workItems: [WorkItem], projects: [Project], mode: CalendarSyncMode) throws {
        guard syncStatus == .connected else { return }
        try prepareProjectCalendars(projects: projects)
        for item in workItems where !item.needsReview && item.hasCalendarTiming {
            try sync(item: item, projects: projects, mode: mode)
        }
    }

    func deleteEvent(for item: WorkItem) throws {
        guard let identifier = item.calendarEventIdentifier else { return }
        if let event = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        item.calendarEventIdentifier = nil
        item.calendarIdentifier = nil
        item.calendarProvider = nil
        item.lastCalendarSyncAt = .now
    }

    private func existingEvent(for item: WorkItem) -> EKEvent? {
        guard let identifier = item.calendarEventIdentifier else { return nil }
        return eventStore.event(withIdentifier: identifier)
    }

    private func calendar(for item: WorkItem, projects: [Project]) throws -> EKCalendar {
        if let projectName = item.projectName,
           let project = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(projectName) == .orderedSame }) {
            return try calendar(for: project)
        }

        if let projectName = item.projectName, !projectName.isEmpty {
            return try namedCalendar(
                title: projectName,
                storedIdentifier: item.calendarIdentifier,
                colorToken: ProjectCatalog.color(for: projectName),
                onResolve: { item.calendarIdentifier = $0 }
            )
        }

        return try unassignedCalendar(for: item)
    }

    private func calendar(for project: Project) throws -> EKCalendar {
        try namedCalendar(
            title: project.name,
            storedIdentifier: project.calendarIdentifier,
            colorToken: project.colorToken,
            onResolve: { project.calendarIdentifier = $0 }
        )
    }

    private func unassignedCalendar(for item: WorkItem) throws -> EKCalendar {
        let storedIdentifier = UserDefaults.standard.string(forKey: "calendarSyncUnassignedCalendarIdentifier")
        return try namedCalendar(
            title: "Moti Unassigned",
            storedIdentifier: storedIdentifier,
            colorToken: "gray",
            onResolve: { identifier in
                item.calendarIdentifier = identifier
                UserDefaults.standard.set(identifier, forKey: "calendarSyncUnassignedCalendarIdentifier")
            }
        )
    }

    private func namedCalendar(
        title: String,
        storedIdentifier: String?,
        colorToken: String,
        onResolve: (String) -> Void
    ) throws -> EKCalendar {
        if
            let storedIdentifier,
            let calendar = eventStore.calendar(withIdentifier: storedIdentifier),
            calendar.allowsContentModifications
        {
            if calendar.title != title {
                calendar.title = title
                try? eventStore.saveCalendar(calendar, commit: true)
            }
            onResolve(calendar.calendarIdentifier)
            return calendar
        }

        if let matched = findWritableCalendar(named: title) {
            onResolve(matched.calendarIdentifier)
            return matched
        }

        let created = try createCalendar(named: title, colorToken: colorToken)
        onResolve(created.calendarIdentifier)
        return created
    }

    private func findWritableCalendar(named title: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        return calendars.first {
            $0.title == title && $0.allowsContentModifications
        } ?? calendars.first {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame && $0.allowsContentModifications
        }
    }

    private func createCalendar(named title: String, colorToken: String) throws -> EKCalendar {
        guard let source = writableSource() else {
            throw AppleCalendarSyncError.noWritableCalendarSource
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = title
        calendar.source = source
        calendar.cgColor = calendarColor(for: colorToken)
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func writableSource() -> EKSource? {
        if let source = eventStore.defaultCalendarForNewEvents?.source {
            return source
        }
        return eventStore.sources.first { $0.sourceType == .calDAV }
            ?? eventStore.sources.first { $0.sourceType == .local }
            ?? eventStore.sources.first
    }

    private func calendarColor(for token: String) -> CGColor {
        switch token {
        case "blue":
            return UIColor.systemBlue.cgColor
        case "green":
            return UIColor.systemGreen.cgColor
        case "purple":
            return UIColor.systemPurple.cgColor
        case "indigo":
            return UIColor.systemIndigo.cgColor
        case "orange":
            return UIColor.systemOrange.cgColor
        default:
            return UIColor.systemGray.cgColor
        }
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
