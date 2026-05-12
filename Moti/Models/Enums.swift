import Foundation

enum MissingInfoType: String, Codable, CaseIterable, Identifiable {
    case time
    case project
    case action
    case person
    case location
    case context
    case scope

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

enum CompletionEventType: String, Codable, CaseIterable {
    case created
    case statusChanged
    case edited
    case dismissed
    case convertedFromCaptured
}

enum WorkItemStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case active
    case done
    case deferred
    case needsReview
    case archived

    var id: String { rawValue }

    static let visibleCases: [WorkItemStatus] = [.active, .done, .needsReview]

    var label: String {
        switch self {
        case .planned: "Planned"
        case .active: "Active"
        case .done: "Done"
        case .deferred: "Deferred"
        case .needsReview: "Needs Review"
        case .archived: "Archived"
        }
    }
}

enum ProjectCatalog {
    static let suggestedTemplates = ["Job Search", "School", "Portfolio", "Personal"]
    static let parserSuggestions = ["Job Search", "School", "Portfolio", "Moti", "Personal"]
    static let allProjectsLabel = "All Projects"
    static let unassignedLabel = "Unassigned"
    static let colorTokens = ["blue", "green", "purple", "indigo", "orange", "gray"]

    static func color(for project: String?) -> String {
        switch project {
        case "Job Search": "blue"
        case "School": "green"
        case "Portfolio": "purple"
        case "Moti": "indigo"
        case "Personal": "orange"
        default: "gray"
        }
    }

    static func colorToken(forProjectNamed name: String) -> String {
        color(for: name)
    }

    static func normalizedTemplateName(_ value: String?) -> String? {
        guard let value else { return nil }
        return parserSuggestions.first { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
    }
}

enum TaskUnderstandingMode: String, CaseIterable, Identifiable {
    case foundationModel
    case ruleBased
    case mockSLM

    var id: String { rawValue }

    static var releaseOptions: [TaskUnderstandingMode] {
        [.foundationModel, .ruleBased]
    }

    var label: String {
        switch self {
        case .foundationModel: "Foundational Model"
        case .ruleBased: "Rule-based"
        case .mockSLM: "Mock SLM"
        }
    }

    var detailLabel: String {
        switch self {
        case .foundationModel: "On-device"
        case .ruleBased: "Fallback"
        case .mockSLM: "Debug Only"
        }
    }
}

enum CalendarSyncProvider: String, CaseIterable, Identifiable {
    case appleCalendar
    case googleCalendar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleCalendar: "Apple Calendar"
        case .googleCalendar: "Google Calendar"
        }
    }

    var detailLabel: String? {
        switch self {
        case .appleCalendar: nil
        case .googleCalendar: "Coming Soon"
        }
    }
}

enum CalendarSyncMode: String, CaseIterable, Identifiable {
    case event
    case allDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .event: "Events"
        case .allDay: "All-day Events"
        }
    }
}
