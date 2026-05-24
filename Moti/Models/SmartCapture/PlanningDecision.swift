import Foundation

/// Coarse classification of what a capture actually needs, decided *before* any
/// deep LLM planning call. Lets Moti avoid invoking the planner for input that
/// is already a clear, atomic task.
enum PlanningInputType: String, CaseIterable {
    case simpleTask            // one action, no/loose timing — create directly
    case atomicTask            // one action + one deadline — create directly, never decompose
    case deadlineOnly          // a date with little/no action
    case reminder              // "remind me to …"
    case projectNote           // framing / knowledge about a project, not a task
    case statusUpdate          // reports progress on existing work
    case complexPlanning       // broad / explicit "plan this" → deep planning
    case multiDeadlinePlanning // multiple deadlines → one track each
    case refinementRequest     // revising a previously generated plan
    case unclear               // too vague to act on → ask one question

    var label: String {
        switch self {
        case .simpleTask:            "Simple task"
        case .atomicTask:            "Atomic task"
        case .deadlineOnly:          "Deadline"
        case .reminder:              "Reminder"
        case .projectNote:           "Project note"
        case .statusUpdate:          "Status update"
        case .complexPlanning:       "Complex planning"
        case .multiDeadlinePlanning: "Multi-deadline planning"
        case .refinementRequest:     "Refinement"
        case .unclear:               "Unclear"
        }
    }
}

/// The output of Stage 1 (classification). Drives whether Stage 2 (deep LLM
/// planning) runs at all. Produced deterministically by `PlanningClassifier`
/// — no network, no model — so the common atomic-task path is instant and
/// never over-plans.
struct PlanningDecision: Equatable {
    let inputType: PlanningInputType
    /// Whether to invoke the deep contextual capture agent at all. When false,
    /// the input is handled by the lightweight parser (single task, date +
    /// project extracted, no plan).
    let shouldUseLLM: Bool
    /// Whether the agent should produce a multi-target plan / workspace.
    let shouldGeneratePlan: Bool
    /// Whether subtask decomposition is permitted for this input.
    let shouldCreateSubtasks: Bool
    /// Whether the agent should ask a clarifying question instead of acting.
    let shouldAskForClarification: Bool
    /// Human-readable explanation (shown in debug logs / future UI).
    let reason: String
    /// 0...1 confidence in the classification.
    let confidence: Double

    init(
        inputType: PlanningInputType,
        shouldUseLLM: Bool,
        shouldGeneratePlan: Bool,
        shouldCreateSubtasks: Bool = false,
        shouldAskForClarification: Bool = false,
        reason: String,
        confidence: Double
    ) {
        self.inputType = inputType
        self.shouldUseLLM = shouldUseLLM
        self.shouldGeneratePlan = shouldGeneratePlan
        self.shouldCreateSubtasks = shouldCreateSubtasks
        self.shouldAskForClarification = shouldAskForClarification
        self.reason = reason
        self.confidence = max(0, min(1, confidence))
    }
}
