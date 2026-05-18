import Foundation

enum TaskUnderstandingServiceFactory {
    static func resolvedMode(for requestedMode: TaskUnderstandingMode) -> TaskUnderstandingMode {
        switch requestedMode {
        case .foundationModel:
            return FoundationModelRuntime.status.isAvailable ? .foundationModel : .ruleBased
        case .ruleBased:
            return requestedMode
        case .mockSLM:
            return FoundationModelRuntime.status.isAvailable ? .foundationModel : .ruleBased
        case .llm:
            // LLM mode is always usable: ContextualCaptureAgentService has its own
            // rule-based fallback. The underlying TaskUnderstandingService is still
            // needed to resolve dates for confirmed Smart Capture output.
            return .llm
        }
    }

    static func make(mode: TaskUnderstandingMode) -> any TaskUnderstandingService {
        #if DEBUG
        print("TaskUnderstandingServiceFactory active mode:", mode.rawValue)
        #endif
        switch mode {
        case .foundationModel, .llm:
            return FoundationModelsTaskUnderstandingService(fallback: RuleBasedTaskUnderstandingService())
        case .ruleBased:
            return RuleBasedTaskUnderstandingService()
        case .mockSLM:
            return MockSLMTaskUnderstandingService()
        }
    }
}
