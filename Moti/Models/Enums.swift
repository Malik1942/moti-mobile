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
    /// User intentionally decided not to do this. Preserved as history,
    /// never silently deleted.
    case skipped

    var id: String { rawValue }

    /// Statuses a user can pick in the work-item editor.
    static let visibleCases: [WorkItemStatus] = [.active, .done, .skipped, .needsReview]

    var label: String {
        switch self {
        case .planned: "Planned"
        case .active: "Active"
        case .done: "Done"
        case .deferred: "Deferred"
        case .needsReview: "Needs Review"
        case .archived: "Archived"
        case .skipped: "Skipped"
        }
    }
}

enum TimelineTaskSort: String, CaseIterable, Identifiable {
    case projectPriority
    case time

    var id: String { rawValue }

    var label: String {
        switch self {
        case .projectPriority: "Project Priority"
        case .time: "Time"
        }
    }

    var description: String {
        switch self {
        case .projectPriority:
            "Groups Timeline tasks by your Projects order, then by due date inside each project."
        case .time:
            "Shows Timeline tasks strictly by due date across all projects."
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
    case llm

    var id: String { rawValue }

    static var releaseOptions: [TaskUnderstandingMode] {
        [.foundationModel, .ruleBased, .llm]
    }

    var label: String {
        switch self {
        case .foundationModel: "Foundational Model"
        case .ruleBased: "Rule-based"
        case .mockSLM: "Mock SLM"
        case .llm: "LLM"
        }
    }

    var detailLabel: String {
        switch self {
        case .foundationModel: "On-device"
        case .ruleBased: "Fallback"
        case .mockSLM: "Debug Only"
        case .llm: "Smart Capture"
        }
    }

    /// Longer-form explanation shown in Settings for modes that need it.
    var modeDescription: String? {
        switch self {
        case .llm:
            return "Uses Smart Capture to clarify vague input, save project context, and generate task plans."
        case .foundationModel, .ruleBased, .mockSLM:
            return nil
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
