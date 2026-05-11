import SwiftUI

protocol TaskUnderstandingService {
    func parse(_ input: String) async throws -> ParsedWorkItem
}

enum TaskUnderstandingError: LocalizedError {
    case foundationModelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .foundationModelUnavailable(let reason):
            "Foundation Model parsing is unavailable: \(reason)"
        }
    }
}

private struct TaskUnderstandingServiceKey: EnvironmentKey {
    static let defaultValue: any TaskUnderstandingService = RuleBasedTaskUnderstandingService()
}

extension EnvironmentValues {
    var taskUnderstandingService: any TaskUnderstandingService {
        get { self[TaskUnderstandingServiceKey.self] }
        set { self[TaskUnderstandingServiceKey.self] = newValue }
    }
}
