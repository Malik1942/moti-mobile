import Foundation

enum TaskUnderstandingServiceFactory {
    static func resolvedMode(for requestedMode: TaskUnderstandingMode) -> TaskUnderstandingMode {
        switch requestedMode {
        case .foundationModel:
            return FoundationModelRuntime.status.isAvailable ? .foundationModel : .ruleBased
        case .ruleBased, .mockSLM:
            return requestedMode
        }
    }

    static func make(mode: TaskUnderstandingMode) -> any TaskUnderstandingService {
        #if DEBUG
        print("TaskUnderstandingServiceFactory active mode:", mode.rawValue)
        #endif
        switch mode {
        case .foundationModel:
            return FoundationModelsTaskUnderstandingService(fallback: RuleBasedTaskUnderstandingService())
        case .ruleBased:
            return RuleBasedTaskUnderstandingService()
        case .mockSLM:
            return MockSLMTaskUnderstandingService()
        }
    }
}
