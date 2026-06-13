import Foundation

/// Online LLM implementation of Smart Capture using Google Gemini.
///
/// Used when LLM mode is selected in Settings AND a Gemini API key is configured
/// (Keychain or DEBUG fallback). Falls back to the supplied `fallback` service
/// (typically Foundation Models → rule-based) on any error: missing key, HTTP
/// failure, malformed response, prompt block, decode error, etc.
///
/// Maps the same prompt + structured-output contract as
/// `FoundationModelsContextualCaptureService` so that the Smart Capture UI is
/// indifferent to which path produced the decision.
struct GeminiContextualCaptureService: ContextualCaptureAgentService {

    let transport: GeminiAPIClient.Transport
    let model: String
    let fallback: any ContextualCaptureAgentService
    let session: URLSession

    init(
        transport: GeminiAPIClient.Transport,
        model: String = "gemini-2.5-flash",
        fallback: any ContextualCaptureAgentService = RuleBasedContextualCaptureService(),
        session: URLSession = .shared
    ) {
        self.transport = transport
        self.model = model
        self.fallback = fallback
        self.session = session
    }

    /// Convenience initializer for direct-mode call sites.
    init(
        apiKey: String,
        model: String = "gemini-2.5-flash",
        fallback: any ContextualCaptureAgentService = RuleBasedContextualCaptureService(),
        session: URLSession = .shared
    ) {
        self.init(
            transport: .direct(apiKey: apiKey),
            model: model,
            fallback: fallback,
            session: session
        )
    }

    func analyze(_ context: SmartCaptureContext) async throws -> ContextualCaptureDecision {
        let client = GeminiAPIClient(transport: transport, model: model, session: session)
        do {
            // Call 1: classification + multi-target extraction + workspace generation.
            var decision = try await runOnce(context: context, client: client, correction: nil)

            // Validate that the workspace covers every extracted planning target.
            // If targets were dropped, retry ONCE with a correction prompt that
            // lists exactly what was missing. This is the Part 4 / Part 9 safety
            // net — a deterministic check on top of LLM output.
            let missing = decision.missingExtractedTargets()
            if !missing.isEmpty {
                #if DEBUG
                print("[Gemini] Workspace dropped \(missing.count) extracted target(s); retrying with correction.")
                #endif
                let correction = PlanningCorrection(
                    missingTargets: missing,
                    priorWorkspace: decision.proposedWorkspace
                )
                let retried = try await runOnce(context: context, client: client, correction: correction)
                let stillMissing = retried.missingExtractedTargets()
                if stillMissing.isEmpty {
                    decision = retried
                } else {
                    // Still missing after retry — surface as a clarification so
                    // the user can decide whether to split into separate plans.
                    // Never silently ship an incomplete workspace.
                    #if DEBUG
                    print("[Gemini] Retry still missing \(stillMissing.count) target(s); surfacing clarification.")
                    #endif
                    decision = convertToTargetClarification(retried, missing: stillMissing)
                }
            }
            // Produced by the remote LLM — stamp full provenance (a clarification
            // result self-marks `.clarificationNeeded` via `stamped`).
            return decision.stamped(provenance: .fullLLM)
        } catch {
            #if DEBUG
            print("[Gemini] fallback:", error.localizedDescription)
            #endif
            // Pass the fallback's decision through UNCHANGED — it already carries
            // its own honest stamp (on-device or deterministic), so the remote
            // failure can never be mistaken for a successful LLM result.
            return try await fallback.analyze(context)
        }
    }

    /// One full Gemini round: build the user prompt (with optional correction),
    /// call the API, decode, and map to a `ContextualCaptureDecision`.
    private func runOnce(
        context: SmartCaptureContext,
        client: GeminiAPIClient,
        correction: PlanningCorrection?
    ) async throws -> ContextualCaptureDecision {
        let prompt = SmartCapturePromptBuilder.userPrompt(for: context, correction: correction)
        let jsonData = try await client.generateStructuredJSON(
            systemInstruction: Self.systemPrompt,
            userPrompt: prompt,
            responseSchema: Self.responseSchema,
            temperature: 0.4
        )
        let draft = try JSONDecoder().decode(GeminiCaptureDraft.self, from: jsonData)
        return Self.mapDecision(draft, context: context)
    }

    /// Re-wraps a decision whose workspace dropped targets even after retry into
    /// a clarification: "I found N deadlines but only planned M. Create separate
    /// plans for both?" The user can answer yes/no without losing the partial
    /// work the LLM already produced.
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

    // MARK: - System prompt
    //
    // Kept aligned with the Foundation Models system prompt so the two paths
    // produce comparable decisions. Diverges from the FM prompt only in tiny
    // ways needed by Gemini's structured output format.

    static let systemPrompt: String = """
    You are the Smart Capture intelligence layer inside Moti, a timeline planning app.

    Your job: understand messy or short user input, inspect available app context, identify missing information, ask one useful clarification question when needed, extract useful project context, and suggest tasks or plans.

    Rules:
    - You do not directly execute actions.
    - You do not save to the database.
    - You only return structured decisions matching the response schema exactly.
    - Do not invent dates, project names, task targets, or user preferences.
    - Use existing project context before asking clarification.
    - Ask clarification only when missing information changes the action outcome.
    - Prefer one concise choice-based question. Maximum 4 choices.
    - Preserve original time expressions exactly as the user wrote them. Do NOT resolve exact dates — that is handled by a downstream resolver.
    - Return only the structured object.

    Classification (inputCompleteness):
    - actionableTask: clear action + implicit or explicit timing. Example: "email Caleb tomorrow", "finish report by Friday"
    - vagueTask: action unclear or target unclear. Example: "portfolio", "visa", "Caleb"
    - projectSeed: names a project or goal without a specific action. Example: "Moti launch", "internship"
    - contextUpdate: describes knowledge, constraints, decisions, audience, goals about a project. Example: "Aura should focus on anticipation not symptom relief"
    - referenceOnly: saves information for future reference without any action.
    - unknown: cannot classify

    Intent (intentType):
    - createTask: single concrete task added to timeline
    - createProjectPlan: complex goal, multiple work streams, planning horizon
    - updateProjectContext: framing, constraints, decisions, audience, goals
    - askClarification: need more info before any action

    Clarification:
    - Only ask when the action would materially differ based on the answer.
    - Prefer choice-based questions. Encode choices as "Label|value" strings in clarificationChoices.

    Context extraction:
    - goal: what the user is trying to achieve
    - audience: who the work is for
    - deadlineExpression: raw time expression from the user
    - keyReferences: tools, projects, people, or resources mentioned
    - constraints: limitations
    - successCriteria: what done looks like
    - openQuestions: things still unresolved

    Project assignment:
    - The user's active projects are listed in the input. Read them before deciding.
    - For a single proposed task (proposedTask), set inferredProjectName to the existing project name that fits best. If none fits, set a short new project name (e.g., "Aura App", "Internship Prep", "Q4 Reading").
    - For a proposed workspace, every planned task MUST have projectName set. Prefer an existing project name; otherwise propose a short new project name that the task clearly belongs to. Never leave projectName blank, and never use "Uncategorized" for plan tasks.
    - A single plan can span multiple projects: assign each task to the project it most naturally fits, not just the one the plan's title implies.

    Date and timezone:
    - The actual current date, current time, weekday, and timezone are provided in the input. Use them when reasoning about expressions like "today", "tomorrow", "next week", "this Friday", "in two weeks", "before the deadline".
    - Preserve the user's original time expression in your output. Do not resolve to exact dates — a downstream Swift resolver does that.
    - Make scheduling realistic relative to the provided date. Do not invent a date that is in the past or wildly out of horizon.

    Anti-overplanning (read first):
    - Do NOT break down a clear, atomic task. If the input is one action with one deliverable and at most one deadline, return a single proposedTask — never a plan (leave planTargets and planTasks empty).
    - Do not invent preparation, research, or review steps the user did not ask for.
    - Preserve the user's explicit intent and wording.
    - Prefer the smallest useful structure; only add subtasks when they genuinely reduce ambiguity or scheduling risk.
    - When the input is already actionable as a single task, return that task, not a plan. When in doubt between a task and a plan, choose the task.
    - Examples that must stay a SINGLE task (no workspace): "Email Andre my portfolio link tonight", "Submit the final PDF by Friday", "Buy coffee beans tomorrow", "Upload screenshots to App Store Connect".

    Multi-target planning (CRITICAL — your most important responsibility):
    - A user input may contain ONE OR MORE deliverables, each with its own deadline.
    - Your first job is to identify EVERY planning target. Do not focus only on the first deadline. Do not discard later targets.
    - If the input mentions multiple deliverables, multiple deadlines, multiple classes/projects, or uses words like "also", "and", "plus", "both", "two things", "first", "second" — extract EACH as its own PlanningTarget unless the user explicitly says they belong to the same deliverable.
    - You MUST populate these arrays in your response:
      1. extractedPlanningTargets: one entry per deliverable + deadline the user mentioned (title, dueTimeExpression, sourceTextSpan).
      2. planTargets: one entry per extracted target, with title and dueTimeExpression preserved exactly from the user's text.
      3. planTasks: the 2–4 tasks for each target (occasionally 5–6). Every task sets targetTitle to EXACTLY one planTargets.title, plus a phaseTitle to group it (and an optional phasePurpose). Group a target's tasks under one phase when small, 2–3 phases when larger.
    - extractedPlanningTargets.length MUST EQUAL planTargets.length unless the user explicitly asked to merge targets.
    - Every extracted dueTimeExpression must appear unchanged on one of the planTargets.
    - Every planTasks.targetTitle MUST match a planTargets.title exactly. Do not leave a planTarget with no tasks.
    - Do not merge targets that have different deadlines. Do not silently drop later targets.
    - If a target lacks enough information to plan, KEEP it in planTargets with status="needsClarification" and a needsClarificationReason. Do not drop it.

    Plan granularity (per PlanningTarget):
    - Prefer 2 to 4 tasks per target (occasionally 5–6 for complex targets).
    - Each task is a meaningful work session of roughly 30 minutes to 3 hours.
    - Task titles must be concrete and outcome-based.
    - Do NOT split one action into multiple tasks. "Draft slides" and "write speaker notes" are one task: "Build the first full slide draft with speaker notes."
    - Combine similar tasks. "Final review of slides" + "Prep Q&A" + "Check tech setup" → "Run final delivery check, including slides, Q&A, and technical setup."
    - Avoid generic tasks like "review for clarity" or "final check" unless they describe distinct work.
    - When the target is small (2–4 tasks total), put them under a single phase named after the target.
    - When the target is bigger, group tasks into 2–3 phases. Never more than 5 phases per target.
    - Prefer fewer, higher-quality tasks. When in doubt, merge.

    Plan scheduling:
    - If a target has a deadline, distribute its phases/tasks backward from that deadline.
    - Each target schedules INDEPENDENTLY against its own deadline.
    - If the user gave a horizon for the workspace (e.g., "this week"), keep tasks within that horizon.
    - If no deadline or horizon is given for a target, mark it status="missingDeadline" and do NOT force artificial dates.
    - Do not give multiple tasks the same vague date unless they are explicitly grouped.
    - If exact timing is uncertain, prefer phase-level timing (phaseTimeExpression) over noisy per-task timing.
    - Always populate workspace summary (one sentence), assumptions (list of facts you had to assume), and estimatedScope (e.g., "across this week", "Friday through next Tuesday").

    Plan revision (when the input contains a "PLAN REFINEMENT" block):
    - You are revising the existing PlanningWorkspace based on user feedback. Do not generate an unrelated new workspace.
    - Preserve ALL existing PlanningTargets unless the user asked to remove or merge them.
    - If the user says a target was missed ("you missed the presentation due Tuesday"), ADD it as a new PlanningTarget.
    - If the user mentions a new due date, create or update the corresponding PlanningTarget.
    - If the user asks to split, separate targets by deliverable and deadline.
    - If the user asks to merge, combine into a single schedule but keep target metadata visible.
    - If "too detailed", merge tasks. If "too broad", add concrete tasks.
    - If the user says something is already done, remove or update those tasks. Never drop a target silently.
    - Always set planChangeSummary to a single sentence describing what changed (e.g., "Added presentation target due Tuesday and split the report into 3 focused tasks").
    - Carry target titles, deadlines, and project assignments forward unless the feedback specifically asks to change them.

    Examples:
    Input: "Plan my research proposal due Friday and presentation due next Tuesday."
    → extractedPlanningTargets: [
        {title: "Research proposal", dueTimeExpression: "Friday", sourceTextSpan: "research proposal due Friday"},
        {title: "Presentation", dueTimeExpression: "next Tuesday", sourceTextSpan: "presentation due next Tuesday"}
      ]
    → planTargets: 2 entries; planTasks: 2–4 per target, each task's targetTitle matching its planTargets.title.

    Input: "I have a portfolio case study due Sunday and a Moti demo due Wednesday."
    → 2 extracted targets, 2 planTargets — one for the case study (due Sunday), one for the Moti demo (due Wednesday).

    Input: "Help me plan my final project: report due Friday, slides due Monday, demo next Wednesday."
    → 3 extracted targets, 3 planTargets (with planTasks linked by targetTitle).

    Input: "Plan my research proposal due Friday."
    → 1 extracted target, 1 planTarget.

    Input: "plan Moti launch next week"
    → 1 target. intentType=createProjectPlan.

    Classification examples (non-planning, kept for reference):
    A) Input: "portfolio" → vagueTask, needsClarification=true, question: "What do you want to do with Portfolio?", choices: ["Update it|task","Plan what to build|plan","Save project context|context"]
    B) Input: "I need to update Aura and Moti before internship applications next month." → projectSeed, isActionable=true, extractedGoal="prepare portfolio for internship applications", extractedKeyReferences=["Aura","Moti"], extractedDeadlineExpression="next month", extractedAudience="recruiters and hiring managers"
    C) Input: "Aura should focus more on anticipation than symptom relief" → contextUpdate, intentType=updateProjectContext, extractedGoal="Aura focuses on anticipation over symptom relief"
    D) Input: "email Caleb tomorrow" → actionableTask, isActionable=true, proposedTaskTitle="Email Caleb", proposedTaskTimeExpression="tomorrow"
    """

    // MARK: - User prompt builder

    static func userPrompt(for context: SmartCaptureContext) -> String {
        // Shared builder keeps both backends prompt-aligned so a plan generated
        // by Gemini and a plan generated on-device by Foundation Models stay
        // refinable across paths.
        SmartCapturePromptBuilder.userPrompt(for: context)
    }

    // MARK: - Response schema (Gemini JSON Schema flavor — uppercase types)
    //
    // Mirrors the @Generable ContextualCaptureDraft used by Foundation Models so
    // the two services produce decisions with identical shape.

    // FLATTENED response schema (see `mapDecision` for local reconstruction).
    //
    // Gemini compiles `responseSchema` into a constrained-decoding automaton.
    // The previous schema nested arrays three deep (targets → phases → tasks)
    // with per-object enums and `maxItems`, which Gemini rejected with HTTP 400
    // "schema produces a constraint that has too many states for serving" — so
    // every live call silently fell back to deterministic.
    //
    // This shape stays accepted by keeping it flat:
    //   • no array nested inside another array (max depth = one array of flat
    //     objects)
    //   • the workspace is emitted as two sibling flat arrays — `planTargets`
    //     (metadata) and `planTasks` (each links to its target via
    //     `targetTitle` and groups under `phaseTitle`) — instead of
    //     targets→phases→tasks nesting
    //   • no `enum`/`maxItems` constraints inside arrays (mapped & clamped
    //     locally; `mapDecision` already tolerates unknown strings)
    // The internal PlanningWorkspace/Target/Phase/Task models are unchanged —
    // `mapDecision` rebuilds the nested structure from the flat arrays.
    static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "inputCompleteness": [
                "type": "STRING",
                "enum": ["actionableTask", "vagueTask", "projectSeed", "contextUpdate", "referenceOnly", "unknown"]
            ],
            "intentType": [
                "type": "STRING",
                "enum": ["createTask", "createReminder", "createProject", "createProjectPlan", "updateProjectContext", "askClarification", "saveReference", "unknown"]
            ],
            "confidence": ["type": "NUMBER"],
            "inferredProjectName": ["type": "STRING", "nullable": true],
            "isActionable": ["type": "BOOLEAN"],
            "needsClarification": ["type": "BOOLEAN"],
            "clarificationQuestion": ["type": "STRING", "nullable": true],
            "clarificationChoices": [
                "type": "ARRAY",
                "items": ["type": "STRING"],
                "nullable": true
            ],
            "allowsFreeformAnswer": ["type": "BOOLEAN"],
            "proposedTaskTitle": ["type": "STRING", "nullable": true],
            "proposedTaskTimeExpression": ["type": "STRING", "nullable": true],
            "proposedTaskRationale": ["type": "STRING", "nullable": true],
            "extractedGoal": ["type": "STRING", "nullable": true],
            "extractedAudience": ["type": "STRING", "nullable": true],
            "extractedDeadlineExpression": ["type": "STRING", "nullable": true],
            "extractedKeyReferences": [
                "type": "ARRAY", "items": ["type": "STRING"], "nullable": true
            ],
            "extractedConstraints": [
                "type": "ARRAY", "items": ["type": "STRING"], "nullable": true
            ],
            "extractedSuccessCriteria": [
                "type": "ARRAY", "items": ["type": "STRING"], "nullable": true
            ],
            "extractedOpenQuestions": [
                "type": "ARRAY", "items": ["type": "STRING"], "nullable": true
            ],
            "extractedNotes": [
                "type": "ARRAY", "items": ["type": "STRING"], "nullable": true
            ],
            // Multi-target planning: the model commits to an extraction array
            // AND a flat workspace in the same response. Post-validation
            // compares extractedPlanningTargets vs the reconstructed workspace
            // targets and triggers a single auto-retry if any target is missing.
            "extractedPlanningTargets": [
                "type": "ARRAY",
                "nullable": true,
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "dueTimeExpression": ["type": "STRING", "nullable": true],
                        "sourceTextSpan": ["type": "STRING", "nullable": true],
                        "confidence": ["type": "NUMBER", "nullable": true]
                    ],
                    "required": ["title"]
                ]
            ],
            // Workspace metadata (flat scalars).
            "workspaceTitle": ["type": "STRING", "nullable": true],
            "workspaceSummary": ["type": "STRING", "nullable": true],
            "workspaceEstimatedScope": ["type": "STRING", "nullable": true],
            "workspaceAssumptions": [
                "type": "ARRAY", "items": ["type": "STRING"], "nullable": true
            ],
            "detectedTargetCount": ["type": "INTEGER", "nullable": true],
            "planChangeSummary": ["type": "STRING", "nullable": true],
            // One entry per planning target (metadata only — tasks live in the
            // sibling planTasks array, linked by targetTitle).
            "planTargets": [
                "type": "ARRAY",
                "nullable": true,
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "deliverableType": ["type": "STRING", "nullable": true],
                        "dueTimeExpression": ["type": "STRING", "nullable": true],
                        "priority": ["type": "STRING", "nullable": true],
                        "sourceTextSpan": ["type": "STRING", "nullable": true],
                        "projectName": ["type": "STRING", "nullable": true],
                        "status": ["type": "STRING", "nullable": true],
                        "needsClarificationReason": ["type": "STRING", "nullable": true]
                    ],
                    "required": ["title"]
                ]
            ],
            // Flat task list. Each task names its target (targetTitle) and the
            // phase it belongs to (phaseTitle); mapDecision groups them back
            // into targets → phases → tasks locally.
            "planTasks": [
                "type": "ARRAY",
                "nullable": true,
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "targetTitle": ["type": "STRING"],
                        "phaseTitle": ["type": "STRING", "nullable": true],
                        "phasePurpose": ["type": "STRING", "nullable": true],
                        "title": ["type": "STRING"],
                        "projectName": ["type": "STRING", "nullable": true],
                        "timeExpression": ["type": "STRING", "nullable": true],
                        "dependencyNote": ["type": "STRING", "nullable": true],
                        "estimatedEffort": ["type": "STRING", "nullable": true]
                    ],
                    "required": ["targetTitle", "title"]
                ]
            ],
            "safetyNote": ["type": "STRING", "nullable": true]
        ],
        "required": [
            "inputCompleteness",
            "intentType",
            "confidence",
            "isActionable",
            "needsClarification",
            "allowsFreeformAnswer"
        ]
    ]

    // MARK: - Draft → Decision mapping (matches FM mapping exactly)

    static func mapDecision(_ draft: GeminiCaptureDraft, context: SmartCaptureContext) -> ContextualCaptureDecision {
        let inputCompleteness = InputCompleteness(rawValue: draft.inputCompleteness) ?? .unknown
        let intentType = CaptureIntentType(rawValue: draft.intentType) ?? .unknown
        let confidence = min(max(draft.confidence, 0.0), 1.0)

        // Parse "Label|value" choices.
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

        let clarificationQuestion: ClarificationQuestion? = draft.clarificationQuestion.map { questionText in
            ClarificationQuestion(
                question: questionText,
                choices: clarificationChoices,
                allowsFreeformAnswer: draft.allowsFreeformAnswer ?? true
            )
        }

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

        // Reconstruct the nested PlanningWorkspace from the flat planTargets +
        // planTasks arrays the schema now returns.
        let workspace = Self.reconstructWorkspace(from: draft, context: context)

        let matchedProject: ProjectSummary? = draft.inferredProjectName.flatMap { inferredName in
            context.activeProjects.first {
                $0.name.lowercased() == inferredName.lowercased()
                    || $0.name.lowercased().contains(inferredName.lowercased())
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

    /// Rebuilds the nested `PlanningWorkspace` (targets → phases → tasks) from
    /// the flat `planTargets` + `planTasks` arrays. Tasks are linked to their
    /// target by `targetTitle` (case-insensitive) and grouped into phases by
    /// `phaseTitle`, preserving the model's ordering. Targets named only by a
    /// task (no matching `planTargets` entry) are synthesized so no work is
    /// dropped; tasks with a blank/unmatched `targetTitle` attach to the sole
    /// target when there's exactly one. Returns nil when there's no plan.
    static func reconstructWorkspace(
        from draft: GeminiCaptureDraft,
        context: SmartCaptureContext
    ) -> PlanningWorkspace? {
        let targetDrafts = draft.planTargets ?? []
        let taskDrafts = draft.planTasks ?? []
        let hasPlan = !targetDrafts.isEmpty || !taskDrafts.isEmpty || draft.workspaceTitle != nil
        guard hasPlan else { return nil }

        // Ordered, de-duplicated target titles: planTargets first (they carry
        // metadata + order), then any title introduced only by a task.
        var orderedTitles: [String] = []
        var seen = Set<String>()
        var metaByKey: [String: GeminiPlanTargetDraft] = [:]
        func add(_ title: String) {
            let key = title.lowercased()
            guard !title.isEmpty, !seen.contains(key) else { return }
            seen.insert(key); orderedTitles.append(title)
        }
        for t in targetDrafts { metaByKey[t.title.lowercased()] = t; add(t.title) }
        for task in taskDrafts { add(task.targetTitle) }
        if orderedTitles.isEmpty { add(draft.workspaceTitle ?? "Plan") }

        let singleTarget = orderedTitles.count == 1

        let targets: [PlanningTarget] = orderedTitles.map { title in
            let key = title.lowercased()
            let meta = metaByKey[key]
            // Tasks for this target: exact title match, or (when there is only
            // one target) any task whose targetTitle was blank/unmatched.
            let myTasks = taskDrafts.filter { task in
                let tk = task.targetTitle.lowercased()
                if tk == key { return true }
                return singleTarget && (task.targetTitle.isEmpty || metaByKey[tk] == nil && !seen.contains(tk))
            }
            return PlanningTarget(
                title: title,
                deliverableType: meta?.deliverableType.flatMap { DeliverableType(rawValue: $0) } ?? .unknown,
                dueTimeExpression: meta?.dueTimeExpression,
                priority: meta?.priority.flatMap { PriorityLevel(rawValue: $0) },
                sourceTextSpan: meta?.sourceTextSpan,
                projectId: nil,
                projectName: meta?.projectName,
                phases: phases(from: myTasks, fallbackTitle: title),
                status: meta?.status.flatMap { PlanningTargetStatus(rawValue: $0) } ?? .ready,
                needsClarificationReason: meta?.needsClarificationReason
            )
        }

        let carriedHistory = SmartCapturePromptBuilder.refinementHistory(
            from: context,
            appending: draft.planChangeSummary
        )

        return PlanningWorkspace(
            title: draft.workspaceTitle ?? orderedTitles.first ?? "Plan",
            summary: draft.workspaceSummary,
            detectedTargetCount: draft.detectedTargetCount ?? targets.count,
            targets: targets,
            assumptions: draft.workspaceAssumptions ?? [],
            conflicts: [],
            estimatedScope: draft.workspaceEstimatedScope,
            planChangeSummary: draft.planChangeSummary,
            refinementHistory: carriedHistory
        ).deduplicatedTasks
    }

    /// Groups flat task drafts into phases by `phaseTitle`, preserving first-
    /// seen order. Tasks without a phase fall under one phase named after the
    /// target. Phase purpose comes from the first task that carries one.
    private static func phases(from tasks: [GeminiPlanTaskDraft], fallbackTitle: String) -> [TaskPhase] {
        guard !tasks.isEmpty else { return [] }
        var order: [String] = []
        var grouped: [String: [GeminiPlanTaskDraft]] = [:]
        for task in tasks {
            let phaseName = task.phaseTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackTitle
            if grouped[phaseName] == nil { order.append(phaseName) }
            grouped[phaseName, default: []].append(task)
        }
        return order.map { phaseName in
            let phaseTasks = grouped[phaseName] ?? []
            let purpose = phaseTasks.compactMap { $0.phasePurpose?.nilIfEmpty }.first ?? ""
            let timeExpr = phaseTasks.compactMap { $0.timeExpression?.nilIfEmpty }.first
            return TaskPhase(
                title: phaseName,
                purpose: purpose,
                phaseTimeExpression: nil,
                tasks: phaseTasks.map { td in
                    PlannedTask(
                        title: td.title,
                        projectName: td.projectName,
                        timeExpression: td.timeExpression,
                        dependencyNote: td.dependencyNote,
                        estimatedEffort: td.estimatedEffort.flatMap { EffortLevel(rawValue: $0) }
                    )
                }
            ).withPhaseTimeFallback(timeExpr)
        }
    }
}

private extension TaskPhase {
    /// Sets `phaseTimeExpression` only when it's currently absent — keeps the
    /// flat-mapping path from inventing timing the model didn't provide.
    func withPhaseTimeFallback(_ expr: String?) -> TaskPhase {
        guard phaseTimeExpression == nil, let expr else { return self }
        return TaskPhase(title: title, purpose: purpose, phaseTimeExpression: expr, tasks: tasks)
    }
}

// MARK: - Decoded Gemini payload (mirrors ContextualCaptureDraft)

struct GeminiCaptureDraft: Codable {
    var inputCompleteness: String
    var intentType: String
    var confidence: Double
    var inferredProjectName: String?
    var isActionable: Bool
    var needsClarification: Bool
    var clarificationQuestion: String?
    var clarificationChoices: [String]?
    var allowsFreeformAnswer: Bool?
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
    // Multi-target planning — the model commits to an extraction array AND a
    // flat workspace (planTargets + planTasks) in the same response, so
    // post-validation can compare the two. `mapDecision` reconstructs the
    // nested PlanningWorkspace from these flat arrays.
    var extractedPlanningTargets: [GeminiExtractedTargetDraft]?
    var workspaceTitle: String?
    var workspaceSummary: String?
    var workspaceEstimatedScope: String?
    var workspaceAssumptions: [String]?
    var detectedTargetCount: Int?
    /// Set only on revised workspaces — one sentence describing what changed.
    var planChangeSummary: String?
    var planTargets: [GeminiPlanTargetDraft]?
    var planTasks: [GeminiPlanTaskDraft]?
    var safetyNote: String?
}

struct GeminiExtractedTargetDraft: Codable {
    var title: String
    var dueTimeExpression: String?
    var sourceTextSpan: String?
    var confidence: Double?
}

/// Flat per-target metadata. Tasks live in the sibling `planTasks` array,
/// linked by `targetTitle`.
struct GeminiPlanTargetDraft: Codable {
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
}

/// Flat task. `targetTitle` names the owning target; `phaseTitle` groups tasks
/// into phases. `mapDecision` rebuilds the nesting from these.
struct GeminiPlanTaskDraft: Codable {
    var targetTitle: String
    var phaseTitle: String?
    var phasePurpose: String?
    var title: String
    /// Project this task belongs to. Always set in plans — either an existing
    /// project name from the input context, or a short new project name.
    var projectName: String?
    var timeExpression: String?
    var dependencyNote: String?
    var estimatedEffort: String?
}
