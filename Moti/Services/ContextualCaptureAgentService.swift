import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Protocol

protocol ContextualCaptureAgentService: Sendable {
    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision
}

// MARK: - Environment Injection

private struct ContextualCaptureAgentKey: EnvironmentKey {
    static let defaultValue: any ContextualCaptureAgentService = RuleBasedContextualCaptureService()
}

extension EnvironmentValues {
    var contextualCaptureAgent: any ContextualCaptureAgentService {
        get { self[ContextualCaptureAgentKey.self] }
        set { self[ContextualCaptureAgentKey.self] = newValue }
    }
}

// MARK: - Factory

enum ContextualCaptureAgentFactory {
    /// Returns the active Smart Capture service for the app environment.
    ///
    /// The returned object is a thin dynamic resolver: every `analyze` call
    /// re-checks the API key store, so adding or clearing a key in Settings
    /// takes effect on the next capture without restarting the app.
    static func make() -> any ContextualCaptureAgentService {
        DynamicContextualCaptureService()
    }
}

/// Resolves the concrete Smart Capture service on every call.
///
/// Routing priority (highest first):
///   1. **Proxy mode** — `MotiProxy` URL and shared secret are configured.
///      Goes through your Cloudflare Worker. The real Gemini key never ships
///      in the app binary. This is the distribution-safe path.
///   2. **Direct mode** — a Gemini API key is configured (Keychain or DEBUG
///      `DevSecrets.geminiAPIKey`). Talks to Gemini directly. Convenient for
///      development but unsafe to ship — the key is embedded in the binary.
///   3. **On-device** — `FoundationModelsContextualCaptureService` runs the
///      decision locally through Apple Intelligence. Itself falls back to
///      rule-based when Foundation Models is unavailable.
///
/// Each higher tier uses the lower tier as its error fallback, so a network
/// failure in proxy mode silently degrades to direct (if available), then to
/// on-device, then to rule-based.
struct DynamicContextualCaptureService: ContextualCaptureAgentService {

    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision {
        try await resolve().analyze(context)
    }

    private func resolve() -> any ContextualCaptureAgentService {
        let onDeviceFallback = FoundationModelsContextualCaptureService(
            fallback: RuleBasedContextualCaptureService()
        )

        // Tier 1: proxy (distribution-safe).
        if let proxyURL = SmartCaptureKeyStore.proxyBaseURL,
           let sharedSecret = SmartCaptureKeyStore.proxySharedSecret {
            // Direct mode (if a key is also present) becomes the fallback,
            // so a proxy outage gracefully falls through to direct → on-device.
            let directOrOnDevice: any ContextualCaptureAgentService = {
                if let apiKey = SmartCaptureKeyStore.apiKey {
                    return GeminiContextualCaptureService(apiKey: apiKey, fallback: onDeviceFallback)
                }
                return onDeviceFallback
            }()
            return GeminiContextualCaptureService(
                transport: .proxy(baseURL: proxyURL, sharedSecret: sharedSecret),
                fallback: directOrOnDevice
            )
        }

        // Tier 2: direct (dev convenience, unsafe to ship).
        if let apiKey = SmartCaptureKeyStore.apiKey {
            return GeminiContextualCaptureService(apiKey: apiKey, fallback: onDeviceFallback)
        }

        // Tier 3: on-device.
        return onDeviceFallback
    }
}

// MARK: - Rule-Based Fallback

struct RuleBasedContextualCaptureService: ContextualCaptureAgentService {

    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision {
        let input = context.rawInput
        let words = input.split(separator: " ").map(String.init)
        let lowered = input.lowercased()

        // Short / vague input
        if words.count <= 2 {
            let matchedProject = context.activeProjects.first {
                lowered.contains($0.name.lowercased()) || $0.name.lowercased().contains(lowered)
            }
            let question = ClarificationQuestion(
                question: "What would you like to do with '\(input)'?",
                choices: [
                    ClarificationChoice(label: "Create a task", value: "task"),
                    ClarificationChoice(label: "Save project context", value: "context"),
                    ClarificationChoice(label: "Plan it out", value: "plan")
                ],
                allowsFreeformAnswer: true
            )
            return ContextualCaptureDecision(
                inputCompleteness: matchedProject != nil ? .projectSeed : .vagueTask,
                intentType: .unknown,
                confidence: matchedProject != nil ? 0.45 : 0.35,
                inferredProjectName: matchedProject?.name,
                matchedProjectId: matchedProject?.id,
                isActionable: false,
                needsClarification: true,
                clarificationQuestion: question
            )
        }

        // Contains timing keywords → actionable task
        let timingKeywords = [
            "today", "tomorrow", "next week", "monday", "tuesday", "wednesday",
            "thursday", "friday", "saturday", "sunday", "by ", "before ",
            "due ", "this week", "next month"
        ]
        let hasTimingKeyword = timingKeywords.contains { lowered.contains($0) }

        if hasTimingKeyword {
            let matchedProject = findProject(in: context, for: lowered)
            return ContextualCaptureDecision(
                inputCompleteness: .actionableTask,
                intentType: .createTask,
                confidence: 0.72,
                inferredProjectName: matchedProject?.name,
                matchedProjectId: matchedProject?.id,
                isActionable: true,
                needsClarification: false,
                proposedTask: ProposedTask(
                    title: input,
                    projectId: matchedProject?.id,
                    timeExpression: nil,
                    rationale: "Contains timing information"
                )
            )
        }

        // Planning keywords
        let planningKeywords = ["plan", "launch", "roadmap"]
        let hasPlanningKeyword = planningKeywords.contains { lowered.contains($0) }

        if hasPlanningKeyword {
            let matchedProject = findProject(in: context, for: lowered)
            let question = ClarificationQuestion(
                question: "What's the goal and timeline?",
                choices: [
                    ClarificationChoice(label: "This week", value: "this week"),
                    ClarificationChoice(label: "Next month", value: "next month"),
                    ClarificationChoice(label: "Next quarter", value: "next quarter")
                ],
                allowsFreeformAnswer: true
            )
            return ContextualCaptureDecision(
                inputCompleteness: .projectSeed,
                intentType: .createProjectPlan,
                confidence: 0.68,
                inferredProjectName: matchedProject?.name,
                matchedProjectId: matchedProject?.id,
                isActionable: false,
                needsClarification: true,
                clarificationQuestion: question
            )
        }

        // Default fallback
        let matchedProject = findProject(in: context, for: lowered)
        let defaultQuestion = ClarificationQuestion(
            question: "What are you trying to do?",
            choices: [
                ClarificationChoice(label: "Add a task", value: "task"),
                ClarificationChoice(label: "Plan a project", value: "plan"),
                ClarificationChoice(label: "Save a note", value: "note")
            ],
            allowsFreeformAnswer: true
        )
        return ContextualCaptureDecision(
            inputCompleteness: .vagueTask,
            intentType: .unknown,
            confidence: 0.50,
            inferredProjectName: matchedProject?.name,
            matchedProjectId: matchedProject?.id,
            isActionable: false,
            needsClarification: true,
            clarificationQuestion: defaultQuestion
        )
    }

    private func findProject(in context: SmartCaptureContext, for lowered: String) -> ProjectSummary? {
        context.activeProjects.first {
            lowered.contains($0.name.lowercased())
        }
    }
}

// MARK: - Foundation Models Service

struct FoundationModelsContextualCaptureService: ContextualCaptureAgentService {
    let fallback: RuleBasedContextualCaptureService

    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision {
        if #available(iOS 26, *) {
            let parser = ContextualCaptureParser(fallback: fallback)
            return try await parser.analyze(context)
        }
        return try await fallback.analyze(context)
    }
}

// MARK: - Foundation Models Parser

@available(iOS 26.0, *)
private struct ContextualCaptureParser {
    let fallback: RuleBasedContextualCaptureService

    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision {
        do {
            let session = LanguageModelSession(instructions: systemPrompt)
            var decision = try await runOnce(session: session, context: context, correction: nil)

            // Same validate-and-retry pattern as the Gemini path: if the workspace
            // dropped any extracted planning targets, retry once with a correction
            // prompt. If still missing after retry, surface a clarification.
            let missing = decision.missingExtractedTargets()
            if !missing.isEmpty {
                #if DEBUG
                print("[FM SmartCapture] Workspace dropped \(missing.count) extracted target(s); retrying with correction.")
                #endif
                let correction = PlanningCorrection(
                    missingTargets: missing,
                    priorWorkspace: decision.proposedWorkspace
                )
                let retried = try await runOnce(session: session, context: context, correction: correction)
                let stillMissing = retried.missingExtractedTargets()
                if stillMissing.isEmpty {
                    decision = retried
                } else {
                    decision = convertToTargetClarification(retried, missing: stillMissing)
                }
            }
            return decision
        } catch {
            return try await fallback.analyze(context)
        }
    }

    private func runOnce(
        session: LanguageModelSession,
        context: SmartCaptureContext,
        correction: PlanningCorrection?
    ) async throws -> ContextualCaptureDecision {
        let prompt = SmartCapturePromptBuilder.userPrompt(for: context, correction: correction)
        let draft = try await session.respond(to: prompt, generating: ContextualCaptureDraft.self)
        return map(draft.content, context: context)
    }

    private func convertToTargetClarification(
        _ decision: ContextualCaptureDecision,
        missing: [ExtractedPlanningTarget]
    ) -> ContextualCaptureDecision {
        let totalExtracted = decision.extractedPlanningTargets.count
        let planned = decision.proposedWorkspace?.targets.count ?? 0
        let missingTitles = missing.map(\.title).joined(separator: ", ")
        let question = ClarificationQuestion(
            question: "I found \(totalExtracted) deadlines but only planned \(planned). Create separate plans for the missing target\(missing.count == 1 ? "" : "s") (\(missingTitles))?",
            choices: [
                ClarificationChoice(label: "Create separate plans", value: "split"),
                ClarificationChoice(label: "Keep it as one plan", value: "merge"),
                ClarificationChoice(label: "Cancel", value: "cancel")
            ],
            allowsFreeformAnswer: true
        )
        return ContextualCaptureDecision(
            inputCompleteness: decision.inputCompleteness,
            intentType: decision.intentType,
            confidence: decision.confidence,
            inferredProjectName: decision.inferredProjectName,
            matchedProjectId: decision.matchedProjectId,
            isActionable: decision.isActionable,
            needsClarification: true,
            clarificationQuestion: question,
            extractedContext: decision.extractedContext,
            proposedTask: decision.proposedTask,
            proposedWorkspace: decision.proposedWorkspace,
            extractedPlanningTargets: decision.extractedPlanningTargets,
            safetyNote: decision.safetyNote
        )
    }

    // MARK: System Prompt

    var systemPrompt: String {
        """
        You are the Smart Capture intelligence layer inside Moti, a timeline planning app.

        Your job: understand messy or short user input, inspect available app context, identify missing information, ask one useful clarification question when needed, extract useful project context, and suggest tasks or plans.

        Rules:
        - You do not directly execute actions.
        - You do not save to the database.
        - You only return structured decisions.
        - Do not invent dates, project names, task targets, or user preferences.
        - Use existing project context before asking clarification.
        - Ask clarification only when missing information changes the action outcome.
        - Prefer one concise choice-based question. Maximum 4 choices.
        - Preserve original time expressions exactly as the user wrote them. Do not resolve exact dates.
        - Return only the structured object.

        Classification guide:
        - actionableTask: clear action + implicit or explicit timing. Example: "email Caleb tomorrow", "finish report by Friday"
        - vagueTask: action unclear or target unclear. Example: "portfolio", "visa", "Caleb"
        - projectSeed: names a project or goal without a specific action. Example: "Moti launch", "internship"
        - contextUpdate: describes knowledge, constraints, decisions, audience, goals about a project. Example: "Aura should focus on anticipation not symptom relief"
        - referenceOnly: saves information for future reference without any action. Example: "the API key is XYZ"
        - unknown: cannot classify

        Intent guide:
        - createTask: user wants a single concrete task added to timeline
        - createProjectPlan: user describes a complex goal, references multiple work streams, or mentions a planning horizon
        - updateProjectContext: input is framing, constraints, decisions, audience, goals about a project
        - askClarification: need more information before any action

        Clarification guide:
        - Only ask when the action would materially differ based on the answer.
        - Prefer choice-based questions over open-ended questions.
        - Encode choices as "Label|value" strings in the clarificationChoices array.

        Context extraction guide:
        - goal: what the user is trying to achieve
        - audience: who the work is for
        - deadlineExpression: raw time expression from the user (do NOT resolve to a date)
        - keyReferences: tools, projects, people, or resources mentioned
        - constraints: limitations mentioned
        - successCriteria: what done looks like
        - openQuestions: things still unresolved

        Project assignment:
        - The user's active projects are listed in the input. Read them before deciding.
        - For a single proposed task (proposedTask), set inferredProjectName to the existing project name that fits best. If none fits, set a short new project name (e.g., "Aura App", "Internship Prep", "Q4 Reading").
        - For a proposed workspace, every planned task MUST have projectName set. Prefer an existing project name; otherwise propose a short new project name that the task clearly belongs to. Never leave projectName blank, and never use "Uncategorized" for plan tasks.
        - A single plan can span multiple projects: assign each task to the project it most naturally fits, not just the one the plan's title implies.

        Date and timezone:
        - The actual current date, current time, weekday, and timezone are provided in the input. Use them when reasoning about expressions like "today", "tomorrow", "next week", "this Friday", "in two weeks", "before the deadline".
        - Preserve the user's original time expression in your output (timeExpression / deadlineExpression). Do not resolve to exact dates — a downstream Swift resolver does that.
        - Make scheduling realistic relative to the provided date. Do not invent a date that is in the past or wildly out of horizon.

        Anti-overplanning (read first):
        - Do NOT break down a clear, atomic task. If the input is one action with one deliverable and at most one deadline, return a single proposedTask — never a proposedWorkspace.
        - Do not invent preparation, research, or review steps the user did not ask for.
        - Preserve the user's explicit intent and wording.
        - Prefer the smallest useful structure; only add subtasks when they genuinely reduce ambiguity or scheduling risk.
        - When the input is already actionable as a single task, return that task, not a plan.
        - When in doubt between a task and a plan, choose the task.
        - Examples that must stay a SINGLE task (no workspace): "Email Andre my portfolio link tonight", "Submit the final PDF by Friday", "Buy coffee beans tomorrow", "Upload screenshots to App Store Connect".

        Multi-target planning (CRITICAL):
        - A user input may contain ONE OR MORE deliverables, each with its own deadline.
        - Identify EVERY planning target. Do not focus only on the first deadline. Do not discard later targets.
        - Words like "also", "and", "plus", "both", "two things", "first", "second" usually signal multiple targets. Extract each unless the user explicitly says they belong to the same deliverable.
        - Populate BOTH `extractedPlanningTargets` (one entry per deliverable + deadline) and `proposedWorkspace` (with the same number of `targets`).
        - extractedPlanningTargets.count MUST EQUAL proposedWorkspace.targets.count unless the user explicitly asked to merge targets.
        - Every extracted dueTimeExpression must appear unchanged in one workspace target.
        - If a target lacks enough info, KEEP it in the workspace with status="needsClarification" and a `needsClarificationReason`. Do not drop it.

        Plan granularity (per PlanningTarget):
        - Prefer 2 to 4 tasks per target (occasionally 5-6 for complex targets).
        - Each task is a meaningful work session of 30 min - 3 hours, concrete and outcome-based.
        - Do NOT split one action into multiple tasks. "Draft slides" + "write speaker notes" → one task.
        - Combine "Final review of slides" + "Prep Q&A" + "Check tech setup" → one "Run final delivery check" task.
        - Avoid generic "review for clarity" / "final check" unless they describe distinct work.
        - Small targets (2-4 tasks) live under a single phase. Bigger targets use 2-3 phases, never more than 5.
        - Prefer fewer, higher-quality tasks. When in doubt, merge.

        Plan scheduling:
        - Each target schedules INDEPENDENTLY against its own deadline.
        - If a target has a deadline, distribute its phases/tasks backward from that deadline.
        - If no deadline for a target, mark it status="missingDeadline" and don't force artificial dates.
        - Prefer phaseTimeExpression over noisy per-task timing when uncertain.
        - Always populate workspace summary, assumptions, and estimatedScope.

        Plan revision (when the input contains a "PLAN REFINEMENT" block):
        - You are revising the existing PlanningWorkspace. Do not generate an unrelated new workspace.
        - Preserve ALL existing PlanningTargets unless the user asked to remove or merge them.
        - If the user says a target was missed, ADD it as a new PlanningTarget.
        - If split, separate by deliverable. If merge, combine into one schedule but keep target metadata.
        - "Too detailed" → merge tasks. "Too broad" → add concrete tasks. "Already done" → remove/update those tasks.
        - Always set planChangeSummary to one sentence describing what changed.
        - Carry titles, deadlines, project assignments forward unless feedback specifically asks to change them.

        Multi-target examples (most important):
        Input: "Plan my research proposal due Friday and presentation due next Tuesday."
        → extractedPlanningTargets: 2 entries (research proposal/Friday, presentation/next Tuesday)
        → proposedWorkspace.targets: 2 PlanningTargets, each with 2-4 tasks.

        Input: "Report due Friday, slides due Monday, demo next Wednesday."
        → 3 extracted targets, 3 workspace targets.

        Input: "Plan my research proposal due Friday."
        → 1 extracted target, 1 workspace target.

        Classification examples (non-planning):
        A) Input: "portfolio" → vagueTask, needsClarification=true, question: "What do you want to do with Portfolio?"
        B) Input: "I need to update Aura and Moti before internship applications next month." → projectSeed, extractedGoal="prepare portfolio for internship applications"
        C) Input: "Aura should focus more on anticipation than symptom relief" → contextUpdate, intentType=updateProjectContext
        D) Input: "email Caleb tomorrow" → actionableTask, proposedTaskTitle="Email Caleb", proposedTaskTimeExpression="tomorrow"
        """
    }

    // MARK: User Prompt

    func userPrompt(for context: SmartCaptureContext) -> String {
        SmartCapturePromptBuilder.userPrompt(for: context)
    }

    // MARK: Mapping

    func map(_ draft: ContextualCaptureDraft, context: SmartCaptureContext) -> ContextualCaptureDecision {
        // Parse inputCompleteness
        let inputCompleteness = InputCompleteness(rawValue: draft.inputCompleteness) ?? .unknown

        // Parse intentType
        let intentType = CaptureIntentType(rawValue: draft.intentType) ?? .unknown

        // Clamp confidence
        let confidence = min(max(draft.confidence, 0.0), 1.0)

        // Parse clarification choices
        var clarificationChoices: [ClarificationChoice] = []
        if let rawChoices = draft.clarificationChoices {
            for rawChoice in rawChoices {
                let parts = rawChoice.split(separator: "|", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    clarificationChoices.append(ClarificationChoice(label: parts[0], value: parts[1]))
                } else if parts.count == 1 {
                    clarificationChoices.append(ClarificationChoice(label: parts[0], value: parts[0]))
                }
            }
        }

        // Build ClarificationQuestion
        let clarificationQuestion: ClarificationQuestion? = draft.clarificationQuestion.map { questionText in
            ClarificationQuestion(
                question: questionText,
                choices: clarificationChoices,
                allowsFreeformAnswer: draft.allowsFreeformAnswer
            )
        }

        // Build ExtractedProjectContext
        let extractedContext: ExtractedProjectContext? = {
            let ctx = ExtractedProjectContext(
                goal: draft.extractedGoal,
                audience: draft.extractedAudience,
                deadlineExpression: draft.extractedDeadlineExpression,
                keyReferences: draft.extractedKeyReferences ?? [],
                constraints: draft.extractedConstraints ?? [],
                successCriteria: draft.extractedSuccessCriteria ?? [],
                openQuestions: draft.extractedOpenQuestions ?? [],
                userPreferences: [],
                notes: draft.extractedNotes ?? []
            )
            return ctx.isEmpty ? nil : ctx
        }()

        // Build ProposedTask
        let proposedTask: ProposedTask? = draft.proposedTaskTitle.map { title in
            ProposedTask(
                title: title,
                projectId: nil,
                timeExpression: draft.proposedTaskTimeExpression,
                rationale: draft.proposedTaskRationale
            )
        }

        // Extracted planning targets (Part 3 of the multi-target spec).
        let extracted: [ExtractedPlanningTarget] = (draft.extractedPlanningTargets ?? []).map { e in
            ExtractedPlanningTarget(
                title: e.title,
                dueTimeExpression: e.dueTimeExpression,
                sourceTextSpan: e.sourceTextSpan,
                confidence: e.confidence ?? 0.7,
                missingFields: []
            )
        }

        // PlanningWorkspace.
        let workspace: PlanningWorkspace? = draft.proposedWorkspace.map { ws in
            let mappedTargets: [PlanningTarget] = ws.targets.map { td in
                let phases: [TaskPhase] = td.phases.map { phaseDraft in
                    let tasks: [PlannedTask] = phaseDraft.tasks.map { taskDraft in
                        PlannedTask(
                            title: taskDraft.title,
                            projectName: taskDraft.projectName,
                            timeExpression: taskDraft.timeExpression,
                            dependencyNote: taskDraft.dependencyNote,
                            estimatedEffort: taskDraft.estimatedEffort.flatMap { EffortLevel(rawValue: $0) }
                        )
                    }
                    return TaskPhase(
                        title: phaseDraft.title,
                        purpose: phaseDraft.purpose,
                        phaseTimeExpression: phaseDraft.phaseTimeExpression,
                        tasks: tasks
                    )
                }
                return PlanningTarget(
                    title: td.title,
                    deliverableType: td.deliverableType.flatMap { DeliverableType(rawValue: $0) } ?? .unknown,
                    dueTimeExpression: td.dueTimeExpression,
                    priority: td.priority.flatMap { PriorityLevel(rawValue: $0) },
                    sourceTextSpan: td.sourceTextSpan,
                    projectId: nil,
                    projectName: td.projectName,
                    phases: phases,
                    status: td.status.flatMap { PlanningTargetStatus(rawValue: $0) } ?? .ready,
                    needsClarificationReason: td.needsClarificationReason
                )
            }
            let carriedHistory = SmartCapturePromptBuilder.refinementHistory(
                from: context,
                appending: ws.planChangeSummary
            )
            return PlanningWorkspace(
                title: ws.title,
                summary: ws.summary,
                detectedTargetCount: ws.detectedTargetCount ?? mappedTargets.count,
                targets: mappedTargets,
                assumptions: ws.assumptions ?? [],
                conflicts: [],
                estimatedScope: ws.estimatedScope,
                planChangeSummary: ws.planChangeSummary,
                refinementHistory: carriedHistory
            ).deduplicatedTasks
        }

        // Match inferredProjectName → matchedProjectId
        let matchedProject: ProjectSummary? = draft.inferredProjectName.flatMap { inferredName in
            context.activeProjects.first {
                $0.name.lowercased() == inferredName.lowercased() ||
                $0.name.lowercased().contains(inferredName.lowercased())
            }
        }

        return ContextualCaptureDecision(
            inputCompleteness: inputCompleteness,
            intentType: intentType,
            confidence: confidence,
            inferredProjectName: draft.inferredProjectName,
            matchedProjectId: matchedProject?.id,
            isActionable: draft.isActionable,
            needsClarification: draft.needsClarification,
            clarificationQuestion: clarificationQuestion,
            extractedContext: extractedContext,
            proposedTask: proposedTask,
            proposedWorkspace: workspace,
            extractedPlanningTargets: extracted,
            safetyNote: draft.safetyNote
        )
    }
}

// MARK: - Generable Structs

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ContextualCaptureDraft {
    var inputCompleteness: String    // "actionableTask"|"vagueTask"|"projectSeed"|"contextUpdate"|"referenceOnly"|"unknown"
    var intentType: String           // CaptureIntentType raw value
    var confidence: Double
    var inferredProjectName: String?
    var isActionable: Bool
    var needsClarification: Bool
    var clarificationQuestion: String?
    var clarificationChoices: [String]?   // ["Label|value", "Label|value"]
    var allowsFreeformAnswer: Bool
    var proposedTaskTitle: String?
    var proposedTaskTimeExpression: String?
    var proposedTaskRationale: String?
    var extractedGoal: String?
    var extractedAudience: String?
    var extractedDeadlineExpression: String?
    var extractedKeyReferences: [String]?
    var extractedConstraints: [String]?
    var extractedSuccessCriteria: [String]?
    var extractedOpenQuestions: [String]?
    var extractedNotes: [String]?
    // Multi-target planning — see the Gemini service for the matching shape.
    // The model commits to BOTH the extraction list and the workspace so
    // post-validation can compare them.
    var extractedPlanningTargets: [PlanningExtractedTargetDraft]?
    var proposedWorkspace: PlanningWorkspaceDraft?
    var safetyNote: String?
}

@available(iOS 26.0, *)
@Generable
struct PlanningExtractedTargetDraft {
    var title: String
    var dueTimeExpression: String?
    var sourceTextSpan: String?
    var confidence: Double?
}

@available(iOS 26.0, *)
@Generable
struct PlanningWorkspaceDraft {
    var title: String
    var summary: String?
    var detectedTargetCount: Int?
    var estimatedScope: String?
    var assumptions: [String]?
    var planChangeSummary: String?
    var targets: [PlanningTargetDraft]
}

@available(iOS 26.0, *)
@Generable
struct PlanningTargetDraft {
    var title: String
    /// "assignment" | "presentation" | "application" | "meetingPrep" | "projectMilestone" | "personalTask" | "unknown"
    var deliverableType: String?
    var dueTimeExpression: String?
    /// "low" | "medium" | "high"
    var priority: String?
    var sourceTextSpan: String?
    /// Existing project name or short new project name. Never "Uncategorized".
    var projectName: String?
    /// "ready" | "needsClarification" | "missingDeadline" | "missingScope"
    var status: String?
    var needsClarificationReason: String?
    var phases: [CapturePhaseDraft]
}

@available(iOS 26.0, *)
@Generable
struct CapturePhaseDraft {
    var title: String
    var purpose: String
    /// Phase-level time hint (e.g. "this week"). Use when task-level timing would be noisy.
    var phaseTimeExpression: String?
    var tasks: [CaptureTaskDraft]
}

@available(iOS 26.0, *)
@Generable
struct CaptureTaskDraft {
    var title: String
    /// Project this task belongs to. Prefer an existing project name from the
    /// input context; otherwise propose a short new project name. Must be set.
    var projectName: String?
    var timeExpression: String?
    var dependencyNote: String?
    var estimatedEffort: String?  // "low"|"medium"|"high"
}
#endif
