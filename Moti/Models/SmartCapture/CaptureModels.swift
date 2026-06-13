import Foundation

// MARK: - Input Classification

enum InputCompleteness: String, Codable, Equatable {
    case actionableTask
    case vagueTask
    case projectSeed
    case contextUpdate
    case referenceOnly
    case unknown
}

enum CaptureIntentType: String, Codable, Equatable {
    case createTask
    case createReminder
    case createProject
    case createProjectPlan
    case updateProjectContext
    case askClarification
    case saveReference
    case unknown
}

enum EffortLevel: String, Codable, Equatable {
    case low
    case medium
    case high

    var label: String { rawValue.capitalized }
}

enum ContextCategory: String, Codable, Equatable {
    case goal
    case audience
    case deadline
    case reference
    case constraint
    case successCriteria
    case decision
    case preference
    case openQuestion
    case generalNote

    var label: String {
        switch self {
        case .goal:            return "Goal"
        case .audience:        return "Audience"
        case .deadline:        return "Deadline"
        case .reference:       return "Reference"
        case .constraint:      return "Constraint"
        case .successCriteria: return "Success Criteria"
        case .decision:        return "Decision"
        case .preference:      return "Preference"
        case .openQuestion:    return "Open Question"
        case .generalNote:     return "General Note"
        }
    }
}

// MARK: - Clarification

struct ClarificationChoice: Identifiable, Codable, Equatable {
    let label: String
    let value: String

    var id: String { value }

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

struct ClarificationQuestion: Codable, Equatable {
    let question: String
    let choices: [ClarificationChoice]
    let allowsFreeformAnswer: Bool

    init(question: String, choices: [ClarificationChoice], allowsFreeformAnswer: Bool) {
        self.question = question
        self.choices = choices
        self.allowsFreeformAnswer = allowsFreeformAnswer
    }
}

struct ClarificationState: Codable, Equatable {
    let previousInput: String
    let previousQuestion: ClarificationQuestion
    let userAnswer: String

    init(previousInput: String, previousQuestion: ClarificationQuestion, userAnswer: String) {
        self.previousInput = previousInput
        self.previousQuestion = previousQuestion
        self.userAnswer = userAnswer
    }
}

// MARK: - Extracted Context

struct ExtractedProjectContext: Codable, Equatable {
    let goal: String?
    let audience: String?
    let deadlineExpression: String?
    let keyReferences: [String]
    let constraints: [String]
    let successCriteria: [String]
    let openQuestions: [String]
    let userPreferences: [String]
    let notes: [String]

    init(
        goal: String? = nil,
        audience: String? = nil,
        deadlineExpression: String? = nil,
        keyReferences: [String] = [],
        constraints: [String] = [],
        successCriteria: [String] = [],
        openQuestions: [String] = [],
        userPreferences: [String] = [],
        notes: [String] = []
    ) {
        self.goal = goal
        self.audience = audience
        self.deadlineExpression = deadlineExpression
        self.keyReferences = keyReferences
        self.constraints = constraints
        self.successCriteria = successCriteria
        self.openQuestions = openQuestions
        self.userPreferences = userPreferences
        self.notes = notes
    }

    var isEmpty: Bool {
        goal == nil &&
        audience == nil &&
        deadlineExpression == nil &&
        keyReferences.isEmpty &&
        constraints.isEmpty &&
        successCriteria.isEmpty &&
        openQuestions.isEmpty &&
        userPreferences.isEmpty &&
        notes.isEmpty
    }
}

// MARK: - Tasks & Plans

struct ProposedTask: Codable, Equatable {
    let title: String
    let projectId: UUID?
    let timeExpression: String?
    let rationale: String?

    init(title: String, projectId: UUID? = nil, timeExpression: String? = nil, rationale: String? = nil) {
        self.title = title
        self.projectId = projectId
        self.timeExpression = timeExpression
        self.rationale = rationale
    }
}

struct PlannedTask: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    /// The project this task belongs to. Should be set on every plan task in
    /// LLM mode — the agent either matches an existing project name or proposes
    /// a short new one. The view layer creates the project if it doesn't exist.
    let projectName: String?
    let timeExpression: String?
    let dependencyNote: String?
    let estimatedEffort: EffortLevel?

    init(
        id: UUID = UUID(),
        title: String,
        projectName: String? = nil,
        timeExpression: String? = nil,
        dependencyNote: String? = nil,
        estimatedEffort: EffortLevel? = nil
    ) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.timeExpression = timeExpression
        self.dependencyNote = dependencyNote
        self.estimatedEffort = estimatedEffort
    }
}

struct TaskPhase: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let purpose: String
    /// Optional phase-level time expression — used when task-level timing would
    /// be noisy (e.g. all four tasks in a phase happen "this week").
    let phaseTimeExpression: String?
    let tasks: [PlannedTask]

    init(
        id: UUID = UUID(),
        title: String,
        purpose: String,
        phaseTimeExpression: String? = nil,
        tasks: [PlannedTask]
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.phaseTimeExpression = phaseTimeExpression
        self.tasks = tasks
    }
}

struct ProposedPlan: Codable, Equatable {
    let title: String
    let projectId: UUID?
    let phases: [TaskPhase]
    /// One-sentence summary of what the plan is about.
    let planSummary: String?
    /// Things the LLM had to assume (deadline, scope, who it's for, etc.) so the
    /// user can verify them before tapping Create Plan.
    let assumptions: [String]
    /// Coarse-grained timeline hint — e.g. "2 weeks", "one focused day".
    let estimatedScope: String?
    /// Populated only on revised plans. Describes what changed since the prior
    /// revision in one sentence.
    let planChangeSummary: String?
    /// Chain of past refinements that produced this plan. Empty for the first
    /// draft. Carried forward across revisions so the UI can show history and
    /// the LLM can see what's already been tried.
    let refinementHistory: [PlanRefinementHistoryItem]

    init(
        title: String,
        projectId: UUID? = nil,
        phases: [TaskPhase],
        planSummary: String? = nil,
        assumptions: [String] = [],
        estimatedScope: String? = nil,
        planChangeSummary: String? = nil,
        refinementHistory: [PlanRefinementHistoryItem] = []
    ) {
        self.title = title
        self.projectId = projectId
        self.phases = phases
        self.planSummary = planSummary
        self.assumptions = assumptions
        self.estimatedScope = estimatedScope
        self.planChangeSummary = planChangeSummary
        self.refinementHistory = refinementHistory
    }

    var totalTaskCount: Int { phases.reduce(0) { $0 + $1.tasks.count } }
    var revisionNumber: Int { refinementHistory.count }
}

// MARK: - Plan validation & cleanup

extension ProposedPlan {
    /// Lightweight quality check. Returns human-readable issues; empty means the
    /// plan looks fine. Used as a soft signal — the caller decides whether to
    /// auto-refine, fall back to `deduplicatedTasks`, or just surface a warning.
    var validationIssues: [String] {
        var issues: [String] = []
        if phases.count > 5 { issues.append("Has \(phases.count) phases (prefer 3–5).") }
        if totalTaskCount > 12 { issues.append("Has \(totalTaskCount) tasks (prefer 4–12).") }
        if totalTaskCount < 1 { issues.append("Plan has no tasks.") }
        let oversizedPhases = phases.filter { $0.tasks.count > 4 || $0.tasks.isEmpty }.count
        if oversizedPhases > 0 {
            issues.append("\(oversizedPhases) phase(s) have too many or too few tasks.")
        }

        var seen: Set<String> = []
        var dupes = 0
        var emptyCount = 0
        for phase in phases {
            for task in phase.tasks {
                let key = task.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty { emptyCount += 1; continue }
                if !seen.insert(key).inserted { dupes += 1 }
            }
        }
        if emptyCount > 0 { issues.append("\(emptyCount) empty task title(s).") }
        if dupes > 0 { issues.append("\(dupes) duplicate task title(s).") }
        return issues
    }

    /// Returns a copy with duplicate-titled and empty tasks dropped, preserving
    /// document order. Safe fallback used before showing the preview so the UI
    /// never displays obvious garbage.
    var deduplicatedTasks: ProposedPlan {
        var seen: Set<String> = []
        let newPhases = phases.map { phase -> TaskPhase in
            let kept = phase.tasks.filter { task in
                let key = task.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return false }
                return seen.insert(key).inserted
            }
            return TaskPhase(
                id: phase.id,
                title: phase.title,
                purpose: phase.purpose,
                phaseTimeExpression: phase.phaseTimeExpression,
                tasks: kept
            )
        }
        return ProposedPlan(
            title: title,
            projectId: projectId,
            phases: newPhases,
            planSummary: planSummary,
            assumptions: assumptions,
            estimatedScope: estimatedScope,
            planChangeSummary: planChangeSummary,
            refinementHistory: refinementHistory
        )
    }
}

// MARK: - Refinement

struct PlanRefinementHistoryItem: Codable, Equatable, Identifiable {
    var id: UUID
    let feedback: String
    let createdAt: Date
    /// One-sentence summary of what changed in response to this feedback.
    /// Mirrors `PlanningWorkspace.planChangeSummary` for this specific round.
    let summaryOfChange: String

    init(id: UUID = UUID(), feedback: String, createdAt: Date = .now, summaryOfChange: String) {
        self.id = id
        self.feedback = feedback
        self.createdAt = createdAt
        self.summaryOfChange = summaryOfChange
    }
}

/// Carries the delta the LLM needs to revise an existing planning workspace
/// rather than generating a fresh one. Lives on
/// `SmartCaptureContext.planRefinement` so the existing `analyze(_:)` entry
/// point handles both initial planning and refinement without a second
/// protocol method.
///
/// Refinement operates on the whole workspace — the user can add a missing
/// target, split one target into multiple, merge several into a combined
/// schedule, or modify one target without disturbing the others.
struct PlanRefinementRequest: Codable, Equatable {
    let originalInput: String
    let previousWorkspace: PlanningWorkspace
    let feedback: String
    let history: [PlanRefinementHistoryItem]

    init(
        originalInput: String,
        previousWorkspace: PlanningWorkspace,
        feedback: String,
        history: [PlanRefinementHistoryItem] = []
    ) {
        self.originalInput = originalInput
        self.previousWorkspace = previousWorkspace
        self.feedback = feedback
        self.history = history
    }
}

// MARK: - Multi-target planning workspace
//
// The active planning surface. One input may contain multiple deliverables,
// each with its own deadline — the workspace is a container for N targets
// rather than collapsing them into a single plan.

enum DeliverableType: String, Codable, CaseIterable {
    case assignment
    case presentation
    case application
    case meetingPrep
    case projectMilestone
    case personalTask
    case unknown

    var label: String {
        switch self {
        case .assignment:       "Assignment"
        case .presentation:     "Presentation"
        case .application:      "Application"
        case .meetingPrep:      "Meeting prep"
        case .projectMilestone: "Project milestone"
        case .personalTask:     "Personal task"
        case .unknown:          "Task"
        }
    }
}

enum PriorityLevel: String, Codable, CaseIterable {
    case low, medium, high

    var label: String { rawValue.capitalized }
}

enum PlanningTargetStatus: String, Codable, CaseIterable {
    /// Has enough information to schedule and create tasks.
    case ready
    /// Title is clear but a key detail is missing — surface as a clarification
    /// instead of creating tasks.
    case needsClarification
    /// Specifically missing a deadline / time expression.
    case missingDeadline
    /// Specifically missing scope or detail.
    case missingScope

    var label: String {
        switch self {
        case .ready:              "Ready"
        case .needsClarification: "Needs clarification"
        case .missingDeadline:    "Missing deadline"
        case .missingScope:       "Missing scope"
        }
    }

    var isReady: Bool { self == .ready }
}

enum PlanningConflictSeverity: String, Codable, CaseIterable {
    case low, medium, high
}

struct PlanningConflict: Codable, Equatable, Identifiable {
    var id: UUID
    let description: String
    /// `PlanningTarget.id` values affected by this conflict.
    let affectedTargetIds: [UUID]
    let severity: PlanningConflictSeverity
    let suggestedResolution: String?

    init(
        id: UUID = UUID(),
        description: String,
        affectedTargetIds: [UUID] = [],
        severity: PlanningConflictSeverity = .low,
        suggestedResolution: String? = nil
    ) {
        self.id = id
        self.description = description
        self.affectedTargetIds = affectedTargetIds
        self.severity = severity
        self.suggestedResolution = suggestedResolution
    }
}

/// A single deliverable inside a planning workspace. Has its own deadline,
/// phases, and project assignment so a workspace can carry independent tracks
/// (e.g. "research proposal due Friday" + "presentation due next Tuesday").
struct PlanningTarget: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let deliverableType: DeliverableType
    let dueTimeExpression: String?
    let priority: PriorityLevel?
    /// The substring of the original capture this target was extracted from,
    /// useful for debugging and for the LLM during refinement.
    let sourceTextSpan: String?
    let projectId: UUID?
    let projectName: String?
    let phases: [TaskPhase]
    let status: PlanningTargetStatus
    /// Populated when `status != .ready` so the UI can show why the target is
    /// blocked and the LLM can pick up the thread on the next refinement.
    let needsClarificationReason: String?

    init(
        id: UUID = UUID(),
        title: String,
        deliverableType: DeliverableType = .unknown,
        dueTimeExpression: String? = nil,
        priority: PriorityLevel? = nil,
        sourceTextSpan: String? = nil,
        projectId: UUID? = nil,
        projectName: String? = nil,
        phases: [TaskPhase] = [],
        status: PlanningTargetStatus = .ready,
        needsClarificationReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.deliverableType = deliverableType
        self.dueTimeExpression = dueTimeExpression
        self.priority = priority
        self.sourceTextSpan = sourceTextSpan
        self.projectId = projectId
        self.projectName = projectName
        self.phases = phases
        self.status = status
        self.needsClarificationReason = needsClarificationReason
    }

    /// Total tasks across all phases for this target.
    var taskCount: Int { phases.reduce(0) { $0 + $1.tasks.count } }
}

/// Top-level container for a multi-target plan.
///
/// Backed by the same Smart Capture decision flow as everything else — the
/// LLM populates `targets` (1+) plus optional metadata like assumptions and
/// conflicts. Single-target workspaces render like the previous single-plan
/// UI; multi-target workspaces render each target in its own section.
struct PlanningWorkspace: Codable, Equatable {
    let title: String
    let summary: String?
    /// What the LLM thinks the target count *should* be. Compared against
    /// `targets.count` during validation to catch silent drops.
    let detectedTargetCount: Int
    let targets: [PlanningTarget]
    let assumptions: [String]
    let conflicts: [PlanningConflict]
    let estimatedScope: String?
    /// Populated only on revised workspaces. One sentence describing what
    /// changed since the prior revision.
    let planChangeSummary: String?
    /// Chain of past refinements that produced this workspace. Empty for the
    /// first draft. Carried forward across revisions.
    let refinementHistory: [PlanRefinementHistoryItem]

    init(
        title: String,
        summary: String? = nil,
        detectedTargetCount: Int? = nil,
        targets: [PlanningTarget],
        assumptions: [String] = [],
        conflicts: [PlanningConflict] = [],
        estimatedScope: String? = nil,
        planChangeSummary: String? = nil,
        refinementHistory: [PlanRefinementHistoryItem] = []
    ) {
        self.title = title
        self.summary = summary
        self.detectedTargetCount = detectedTargetCount ?? targets.count
        self.targets = targets
        self.assumptions = assumptions
        self.conflicts = conflicts
        self.estimatedScope = estimatedScope
        self.planChangeSummary = planChangeSummary
        self.refinementHistory = refinementHistory
    }

    var totalTaskCount: Int { targets.reduce(0) { $0 + $1.taskCount } }
    var revisionNumber: Int { refinementHistory.count }
    var readyTargets: [PlanningTarget] { targets.filter(\.status.isReady) }
}

// MARK: - Workspace validation & cleanup

extension PlanningWorkspace {
    /// Lightweight quality check. Same role as `ProposedPlan.validationIssues`
    /// — returns surface-able warnings so the UI can flag a noisy workspace
    /// and let the user refine before tapping Create Plan.
    var validationIssues: [String] {
        var issues: [String] = []

        if targets.isEmpty { issues.append("Workspace has no targets.") }
        if detectedTargetCount > targets.count {
            issues.append("Detected \(detectedTargetCount) targets but only \(targets.count) planned.")
        }
        if targets.count > 6 { issues.append("Has \(targets.count) targets (unusually many).") }

        for target in targets {
            if target.taskCount > 6 && target.status == .ready {
                issues.append("Target “\(target.title)” has \(target.taskCount) tasks (prefer 2–4).")
            }
            if target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("A target is missing its title.")
            }
        }

        // Duplicate target titles
        var seenTargetTitles: Set<String> = []
        for target in targets {
            let key = target.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if !seenTargetTitles.insert(key).inserted {
                issues.append("Duplicate target title: “\(target.title)”.")
            }
        }

        // Duplicate task titles across the whole workspace
        var seenTaskTitles: Set<String> = []
        var taskDupes = 0
        for target in targets {
            for phase in target.phases {
                for task in phase.tasks {
                    let key = task.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { continue }
                    if !seenTaskTitles.insert(key).inserted { taskDupes += 1 }
                }
            }
        }
        if taskDupes > 0 { issues.append("\(taskDupes) duplicate task title(s) across targets.") }

        return issues
    }

    /// Returns a copy with empty-titled and duplicate-titled tasks dropped
    /// across the whole workspace. Mirrors `ProposedPlan.deduplicatedTasks`.
    var deduplicatedTasks: PlanningWorkspace {
        var seenTaskTitles: Set<String> = []
        let newTargets = targets.map { target -> PlanningTarget in
            let newPhases = target.phases.map { phase -> TaskPhase in
                let kept = phase.tasks.filter { task in
                    let key = task.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return false }
                    return seenTaskTitles.insert(key).inserted
                }
                return TaskPhase(
                    id: phase.id,
                    title: phase.title,
                    purpose: phase.purpose,
                    phaseTimeExpression: phase.phaseTimeExpression,
                    tasks: kept
                )
            }
            return PlanningTarget(
                id: target.id,
                title: target.title,
                deliverableType: target.deliverableType,
                dueTimeExpression: target.dueTimeExpression,
                priority: target.priority,
                sourceTextSpan: target.sourceTextSpan,
                projectId: target.projectId,
                projectName: target.projectName,
                phases: newPhases,
                status: target.status,
                needsClarificationReason: target.needsClarificationReason
            )
        }
        return PlanningWorkspace(
            title: title,
            summary: summary,
            detectedTargetCount: detectedTargetCount,
            targets: newTargets,
            assumptions: assumptions,
            conflicts: conflicts,
            estimatedScope: estimatedScope,
            planChangeSummary: planChangeSummary,
            refinementHistory: refinementHistory
        )
    }
}

// MARK: - Pre-planning target extraction

/// A target the LLM extracted from the user's raw input *before* generating
/// task content. Compared against `PlanningWorkspace.targets` during validation
/// — if generation drops any extracted target, validation triggers a retry
/// with a correction prompt or surfaces a clarification to the user.
struct ExtractedPlanningTarget: Identifiable, Codable, Equatable {
    var id: UUID
    let title: String
    let dueTimeExpression: String?
    let sourceTextSpan: String?
    let confidence: Double
    let missingFields: [String]

    init(
        id: UUID = UUID(),
        title: String,
        dueTimeExpression: String? = nil,
        sourceTextSpan: String? = nil,
        confidence: Double = 0.5,
        missingFields: [String] = []
    ) {
        self.id = id
        self.title = title
        self.dueTimeExpression = dueTimeExpression
        self.sourceTextSpan = sourceTextSpan
        self.confidence = max(0, min(1, confidence))
        self.missingFields = missingFields
    }
}

// MARK: - Intelligence source (fallback honesty)

/// Which understanding path actually produced a capture decision. Lets the app
/// (and developers) tell a confident full-AI result apart from a deterministic
/// fallback, instead of every tier returning an indistinguishable decision.
/// Stamped at each tier's own production point; fallback results pass through
/// with the stamp the lower tier already set, so a rule-based result can never
/// masquerade as the LLM.
enum IntelligenceSource: String, Codable, Sendable, Equatable {
    /// Remote large model (Gemini via proxy or direct key).
    case fullLLM
    /// On-device Apple Foundation Models.
    case onDevice
    /// Deterministic rule-based path — no model produced this.
    case deterministic
    /// Not a confident plan/task: the capture is asking the user to clarify.
    /// Honesty state — it isn't pretending to be a finished result.
    case clarificationNeeded

    /// Short developer-facing label (for DEBUG logs / an optional subtle badge).
    /// Intentionally calm — never implies the app failed.
    var displayLabel: String {
        switch self {
        case .fullLLM: "AI"
        case .onDevice: "On-device"
        case .deterministic: "Quick"
        case .clarificationNeeded: "Needs a detail"
        }
    }

    /// True for results produced by a real language model (remote or on-device).
    var isModelBacked: Bool { self == .fullLLM || self == .onDevice }
}

// MARK: - Decision

struct ContextualCaptureDecision: Codable, Equatable {
    let inputCompleteness: InputCompleteness
    let intentType: CaptureIntentType
    let confidence: Double
    let inferredProjectName: String?
    let matchedProjectId: UUID?
    let isActionable: Bool
    let needsClarification: Bool
    let clarificationQuestion: ClarificationQuestion?
    let extractedContext: ExtractedProjectContext?
    let proposedTask: ProposedTask?
    /// Multi-target planning surface. Replaces the single `ProposedPlan` for
    /// active code paths — one workspace carries N planning targets, each with
    /// its own deadline, phases, and project. Use this for both single- and
    /// multi-deliverable plans.
    let proposedWorkspace: PlanningWorkspace?
    /// Pre-planning extraction pass. The LLM enumerates every deliverable +
    /// deadline it found in the user's input *before* generating tasks. Used
    /// by `analyze` to validate that workspace generation didn't silently drop
    /// any targets.
    let extractedPlanningTargets: [ExtractedPlanningTarget]
    let safetyNote: String?
    /// How this decision was produced. Defaults to `.deterministic` so a result
    /// built without an explicit stamp never over-claims AI provenance; the
    /// service layer stamps the true source at each tier's `analyze` boundary.
    var intelligenceSource: IntelligenceSource

    init(
        inputCompleteness: InputCompleteness,
        intentType: CaptureIntentType,
        confidence: Double,
        inferredProjectName: String? = nil,
        matchedProjectId: UUID? = nil,
        isActionable: Bool,
        needsClarification: Bool,
        clarificationQuestion: ClarificationQuestion? = nil,
        extractedContext: ExtractedProjectContext? = nil,
        proposedTask: ProposedTask? = nil,
        proposedWorkspace: PlanningWorkspace? = nil,
        extractedPlanningTargets: [ExtractedPlanningTarget] = [],
        safetyNote: String? = nil,
        intelligenceSource: IntelligenceSource = .deterministic
    ) {
        self.inputCompleteness = inputCompleteness
        self.intentType = intentType
        self.confidence = confidence
        self.inferredProjectName = inferredProjectName
        self.matchedProjectId = matchedProjectId
        self.isActionable = isActionable
        self.needsClarification = needsClarification
        self.clarificationQuestion = clarificationQuestion
        self.extractedContext = extractedContext
        self.proposedTask = proposedTask
        self.proposedWorkspace = proposedWorkspace
        self.extractedPlanningTargets = extractedPlanningTargets
        self.safetyNote = safetyNote
        self.intelligenceSource = intelligenceSource
    }

    var requiresClarification: Bool {
        needsClarification || confidence < 0.65
    }

    /// Returns a copy stamped with how it was produced. A result that is asking
    /// the user to clarify is marked `.clarificationNeeded` regardless of which
    /// engine ran (it isn't pretending to be a confident plan); otherwise it
    /// carries the provenance of the engine that produced it.
    func stamped(provenance: IntelligenceSource) -> ContextualCaptureDecision {
        var copy = self
        copy.intelligenceSource = needsClarification ? .clarificationNeeded : provenance
        return copy
    }
}

// MARK: - Workspace ↔ extraction validation

extension ContextualCaptureDecision {
    /// Returns extracted targets that don't appear to be represented in the
    /// generated workspace. Used by `analyze` to decide whether to retry the
    /// LLM call with a correction prompt (Part 4 + Part 9 of the multi-target
    /// planning spec).
    ///
    /// Matching strategy: case-insensitive prefix / contains comparison on
    /// both `title` and `sourceTextSpan` so the LLM can paraphrase the
    /// workspace target's title without tripping a false-positive miss.
    func missingExtractedTargets() -> [ExtractedPlanningTarget] {
        guard let workspace = proposedWorkspace else {
            // If the LLM said this was a planning request and extracted
            // targets but didn't produce a workspace, everything is "missing".
            return extractedPlanningTargets
        }
        guard !extractedPlanningTargets.isEmpty else { return [] }

        func normalized(_ s: String?) -> String {
            (s ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let workspaceTitles = workspace.targets.map { normalized($0.title) }
        let workspaceSources = workspace.targets.map { normalized($0.sourceTextSpan) }

        return extractedPlanningTargets.filter { extracted in
            let title = normalized(extracted.title)
            let source = normalized(extracted.sourceTextSpan)
            if title.isEmpty { return false }
            // A target is considered "matched" if any workspace target's title
            // or source span overlaps with the extracted one.
            for wTitle in workspaceTitles where !wTitle.isEmpty {
                if wTitle.contains(title) || title.contains(wTitle) { return false }
            }
            if !source.isEmpty {
                for wSource in workspaceSources where !wSource.isEmpty {
                    if wSource.contains(source) || source.contains(wSource) { return false }
                }
            }
            return true
        }
    }
}

// MARK: - Summary Types

struct TaskSummary: Codable, Equatable {
    let id: UUID
    let title: String
    let projectName: String?
    let status: String
    let dueDate: Date?
    /// Raw user-style time expression (e.g. "tomorrow") when no resolved due date exists.
    let timeExpression: String?
    let createdAt: Date
    /// Reserved for future prioritization signal; nil today.
    let priority: String?

    init(
        id: UUID,
        title: String,
        projectName: String? = nil,
        status: String,
        dueDate: Date? = nil,
        timeExpression: String? = nil,
        createdAt: Date = .now,
        priority: String? = nil
    ) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.status = status
        self.dueDate = dueDate
        self.timeExpression = timeExpression
        self.createdAt = createdAt
        self.priority = priority
    }
}

/// Deterministic time information extracted before the LLM runs. Smart Capture
/// treats these as known planning slots, so clarification should not ask for a
/// timeline when a deadline/duration was already provided by the user.
struct SmartCaptureTimeSignal: Codable, Equatable {
    let rawText: String
    let interpretation: TemporalInterpretation
    let resolvedDate: Date?
    let resolvedDuration: TimeInterval?
    let confidence: Double
    let resolverPath: ResolverPath

    init(
        rawText: String,
        interpretation: TemporalInterpretation,
        resolvedDate: Date? = nil,
        resolvedDuration: TimeInterval? = nil,
        confidence: Double,
        resolverPath: ResolverPath
    ) {
        self.rawText = rawText
        self.interpretation = interpretation
        self.resolvedDate = resolvedDate
        self.resolvedDuration = resolvedDuration
        self.confidence = confidence
        self.resolverPath = resolverPath
    }
}

struct ProjectSummary: Codable, Equatable {
    let id: UUID
    let name: String
    let activeItemCount: Int

    init(id: UUID, name: String, activeItemCount: Int) {
        self.id = id
        self.name = name
        self.activeItemCount = activeItemCount
    }
}

/// Compact, LLM-friendly summary of a project's persisted context.
///
/// Built by `QuickCaptureView` from the `ProjectContext` SwiftData model and
/// fed into Smart Capture so the LLM can ground plans in what the user has
/// already told it — goal, audience, deadline, constraints, recent notes —
/// instead of inventing generic structure.
struct ProjectContextSummary: Codable, Equatable {
    let projectId: UUID
    let projectName: String
    let goal: String?
    let audience: String?
    let deadlineExpression: String?
    let keyReferences: [String]
    let constraints: [String]
    let successCriteria: [String]
    let openQuestions: [String]
    let userPreferences: [String]
    /// Most-recent context notes for this project, capped (typically 5).
    /// Each entry is pre-formatted: "Category: content".
    let recentContextNotes: [String]

    init(
        projectId: UUID,
        projectName: String,
        goal: String? = nil,
        audience: String? = nil,
        deadlineExpression: String? = nil,
        keyReferences: [String] = [],
        constraints: [String] = [],
        successCriteria: [String] = [],
        openQuestions: [String] = [],
        userPreferences: [String] = [],
        recentContextNotes: [String] = []
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.goal = goal
        self.audience = audience
        self.deadlineExpression = deadlineExpression
        self.keyReferences = keyReferences
        self.constraints = constraints
        self.successCriteria = successCriteria
        self.openQuestions = openQuestions
        self.userPreferences = userPreferences
        self.recentContextNotes = recentContextNotes
    }
}

// MARK: - Capture Context

struct SmartCaptureContext: Codable, Equatable {
    let rawInput: String

    // Time / locale (always populated — the LLM gets the actual current date)
    let currentDate: Date
    let timezone: TimeZone
    let locale: Locale

    // Surface signals
    let currentScreen: String
    let selectedProject: ProjectSummary?
    let selectedTask: TaskSummary?

    // Projects
    let activeProjects: [ProjectSummary]
    let projectContextSummaries: [ProjectContextSummary]

    // Task signal — both general recents (for dedup hints) and open tasks for
    // the most-relevant project (for stronger dedup at plan time).
    let recentTasks: [TaskSummary]
    let openTasksForRelevantProject: [TaskSummary]

    // Project history — lets the LLM plan around what already happened: don't
    // re-suggest overdue work as new, account for what's done, respect skips.
    let overdueTasks: [TaskSummary]
    let recentlyCompletedTasks: [TaskSummary]
    let skippedTasks: [TaskSummary]

    // Flow state
    let clarificationState: ClarificationState?
    let planRefinement: PlanRefinementRequest?
    let timeSignals: [SmartCaptureTimeSignal]

    // How much structure Stage 1 authorized for this capture. The LLM must not
    // exceed it: `.none`/`.lightweight` mean a single task (no plan, no
    // subtasks), `.structured`/`.deep` permit decomposition. Defaults to
    // `.none` so any context built without an explicit decision stays atomic.
    let planningDepth: PlanningDepth

    init(
        rawInput: String,
        currentDate: Date,
        timezone: TimeZone,
        locale: Locale = .current,
        currentScreen: String,
        selectedProject: ProjectSummary? = nil,
        selectedTask: TaskSummary? = nil,
        activeProjects: [ProjectSummary] = [],
        projectContextSummaries: [ProjectContextSummary] = [],
        recentTasks: [TaskSummary] = [],
        openTasksForRelevantProject: [TaskSummary] = [],
        overdueTasks: [TaskSummary] = [],
        recentlyCompletedTasks: [TaskSummary] = [],
        skippedTasks: [TaskSummary] = [],
        clarificationState: ClarificationState? = nil,
        planRefinement: PlanRefinementRequest? = nil,
        timeSignals: [SmartCaptureTimeSignal] = [],
        planningDepth: PlanningDepth = .none
    ) {
        self.rawInput = rawInput
        self.currentDate = currentDate
        self.timezone = timezone
        self.locale = locale
        self.currentScreen = currentScreen
        self.selectedProject = selectedProject
        self.selectedTask = selectedTask
        self.activeProjects = activeProjects
        self.projectContextSummaries = projectContextSummaries
        self.recentTasks = recentTasks
        self.openTasksForRelevantProject = openTasksForRelevantProject
        self.overdueTasks = overdueTasks
        self.recentlyCompletedTasks = recentlyCompletedTasks
        self.skippedTasks = skippedTasks
        self.clarificationState = clarificationState
        self.planRefinement = planRefinement
        self.timeSignals = timeSignals
        self.planningDepth = planningDepth
    }
}
