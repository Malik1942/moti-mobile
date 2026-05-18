import SwiftData
import SwiftUI

struct QuickCaptureView: View {
    let startWithVoice: Bool
    @Binding var selectedDetent: PresentationDetent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskUnderstandingService) private var parser
    @Environment(\.contextualCaptureAgent) private var captureAgent

    @AppStorage("taskUnderstandingMode") private var modeRawValue = TaskUnderstandingMode.foundationModel.rawValue

    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \WorkItem.createdAt) private var workItems: [WorkItem]
    @Query private var projectContexts: [ProjectContext]

    @FocusState private var isInputFocused: Bool

    @StateObject private var speechService = SpeechTranscriptionService()
    @State private var input = ""
    @State private var inputBeforeRecording = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didAutoStartVoice = false
    @State private var isInVoiceMode: Bool

    // MARK: Smart Capture state (LLM mode only)
    @State private var smartDecision: ContextualCaptureDecision?
    @State private var clarificationState: ClarificationState?
    @State private var smartCaptureError: String?

    init(startWithVoice: Bool = false, selectedDetent: Binding<PresentationDetent>) {
        self.startWithVoice = startWithVoice
        self._selectedDetent = selectedDetent
        self._isInVoiceMode = State(initialValue: startWithVoice)
    }

    // MARK: - Intelligence mode gate

    private var intelligenceMode: TaskUnderstandingMode {
        TaskUnderstandingMode(rawValue: modeRawValue) ?? .foundationModel
    }

    /// Smart Capture is gated entirely behind LLM mode. Every other mode keeps
    /// the original capture behavior and never shows `SmartCaptureResultView`.
    private var isLLMMode: Bool { intelligenceMode == .llm }

    private var isShowingSmartResult: Bool {
        isLLMMode && smartDecision != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isShowingSmartResult, let decision = smartDecision {
                    smartResultBody(decision)
                } else if isInVoiceMode {
                    voiceBody
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                } else {
                    textBody
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navBarToolbar }
            .task {
                if startWithVoice {
                    guard !didAutoStartVoice else { return }
                    didAutoStartVoice = true
                    await startVoiceCapture()
                } else {
                    isInputFocused = true
                }
            }
            .onChange(of: speechService.transcript) { _, transcript in
                applyTranscript(transcript)
            }
            .onDisappear {
                speechService.stopTranscription()
            }
        }
    }

    private var navTitle: String {
        if isShowingSmartResult { return "Smart Capture" }
        return isInVoiceMode ? "Voice Capture" : "Add to Timeline"
    }

    /// Loading-state label. Smart Capture is "thinking"; standard capture is
    /// placing the item directly on the timeline.
    private var processingLabel: String {
        isLLMMode ? "Thinking…" : "Placing it on your timeline…"
    }

    // MARK: - Toolbar builders

    @ToolbarContentBuilder
    private var navBarToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                speechService.stopTranscription()
                dismiss()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isShowingSmartResult {
                // While a Smart Capture result is shown, the nav action returns
                // the user to editing their input rather than submitting again.
                Button("Edit") { resetSmartCapture() }
                    .font(.motiButtonLabel)
                    .disabled(isSubmitting)
            } else {
                Button("Submit") { submit() }
                    .font(.motiButtonLabel)
                    .disabled(submitDisabled)
            }
        }
        // No keyboard toolbar — tapping outside the TextField (the .onTapGesture
        // on the textBody background) dismisses focus and folds the keyboard.
    }

    private var submitDisabled: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isSubmitting
            || speechService.isRecording
    }

    // MARK: - Voice layout (compact / medium detent)

    private var voiceBody: some View {
        VStack(spacing: 20) {
            Spacer()

            recordingStatusRow

            if !input.isEmpty {
                Text(input)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Centered — voice mode is the primary interaction here, so the
            // big mic lives in the middle of the sheet rather than under one thumb.
            Button { toggleVoiceCapture() } label: {
                ZStack {
                    Circle()
                        .fill(speechService.isRecording ? .red.opacity(0.10) : .indigo.opacity(0.10))
                        .frame(width: 96, height: 96)
                    Image(systemName: speechService.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(speechService.isRecording ? .red : .indigo)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)

            voiceActionRow

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let smartCaptureError {
                Text(smartCaptureError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(processingLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var recordingStatusRow: some View {
        if speechService.isRecording {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("Listening…")
                    .font(.callout.weight(.semibold))
            }
        } else if input.isEmpty {
            Text("Tap the mic to start speaking.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Transcript ready.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var voiceActionRow: some View {
        // Centered to match the big mic above. Both buttons (when present)
        // sit side-by-side rather than pinned to opposite edges.
        HStack(spacing: 18) {
            if !input.isEmpty {
                Button("Clear & Re-record") { clearAndReRecord() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Type instead") { switchToTextMode() }
                .font(.subheadline)
                .foregroundStyle(.indigo)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Text layout (tap-plus, folded or expanded)

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Tell Moti what you need to work on…", text: $input, axis: .vertical)
                .font(.body)
                .lineLimit(4...10)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($isInputFocused)
                // Return key inserts a newline. Submit is in the nav bar.

            if speechService.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Listening…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear & Re-record") { clearAndReRecord() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }

            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(processingLabel)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            // Smart Capture failures fall back here so the user can retry or
            // switch Intelligence mode in Settings — partial output is never saved.
            if let smartCaptureError {
                Text(smartCaptureError)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Spacer()

            textModeActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
    }

    // Persistent mic row for text mode. Mic is anchored to the right edge so
    // it lives under the thumb in a right-hand grip. Keyboard fold is handled
    // by tapping any blank area in the sheet (the textBody's onTapGesture).
    private var textModeActionBar: some View {
        HStack(spacing: 14) {
            Spacer()

            Button {
                isInputFocused = false
                toggleVoiceCapture()
            } label: {
                ZStack {
                    Circle()
                        .fill((speechService.isRecording ? Color.red : Color.indigo).opacity(0.10))
                        .frame(width: 64, height: 64)
                    Image(systemName: speechService.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(speechService.isRecording ? .red : .indigo)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityLabel(speechService.isRecording ? "Stop recording" : "Start voice capture")
        }
        .padding(.bottom, 8)
    }

    // MARK: - Smart Capture result layout (LLM mode only)

    @ViewBuilder
    private func smartResultBody(_ decision: ContextualCaptureDecision) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                capturedRecap

                if let safetyNote = decision.safetyNote,
                   !safetyNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(safetyNote, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                // SmartCaptureResultView manages its own horizontal padding.
                SmartCaptureResultView(
                    decision: decision,
                    projects: projects,
                    onConfirmTask: { task in confirmTask(task, decision: decision) },
                    onAnswerClarification: { answer in answerClarification(answer, decision: decision) },
                    onConfirmContext: { context, projectId in
                        confirmContext(context, projectId: projectId, decision: decision)
                    },
                    onConfirmWorkspace: { workspace in confirmWorkspace(workspace, decision: decision) },
                    onRefinePlan: { feedback in refinePlan(feedback, decision: decision) },
                    onDismiss: { resetSmartCapture() }
                )

                if isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Working on it…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                }

                if let smartCaptureError {
                    Text(smartCaptureError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var capturedRecap: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You captured")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(input.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Mode switching

    private func switchToTextMode() {
        speechService.stopTranscription()
        isInVoiceMode = false
        selectedDetent = .large
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isInputFocused = true
        }
    }

    // MARK: - Voice capture actions

    private func clearAndReRecord() {
        input = ""
        inputBeforeRecording = ""
        speechService.stopTranscription()
        Task { await startVoiceCapture() }
    }

    private func toggleVoiceCapture() {
        if speechService.isRecording {
            speechService.stopTranscription()
            return
        }
        Task { await startVoiceCapture() }
    }

    private func startVoiceCapture() async {
        guard !speechService.isRecording, !isSubmitting else { return }
        inputBeforeRecording = input.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        do {
            try await speechService.startTranscription()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func applyTranscript(_ transcript: String) {
        let spokenText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }
        input = inputBeforeRecording.isEmpty ? spokenText : "\(inputBeforeRecording) \(spokenText)"
    }

    // MARK: - Submit routing

    @MainActor
    private func submit() {
        guard !isSubmitting else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Lock immediately, before any branch. Closes the small window between
        // the rapid-tap gesture firing and the branch functions setting their
        // own state — a key source of duplicate-task creation.
        isSubmitting = true

        speechService.stopTranscription()
        errorMessage = nil
        smartCaptureError = nil

        if isLLMMode {
            // A fresh submit starts a new Smart Capture round; drop any prior
            // clarification chain.
            clarificationState = nil
            runSmartCapture(text: text)
        } else {
            runStandardCapture(text: text)
        }
    }

    // MARK: - Standard capture (non-LLM modes — original behavior preserved)

    @MainActor
    private func runStandardCapture(text: String) {
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                try await createWorkItems(from: text)
                input = ""
                dismiss()
            } catch {
                errorMessage = "I could not parse that yet."
            }
        }
    }

    // MARK: - Smart Capture (LLM mode only)

    @MainActor
    private func runSmartCapture(
        text: String,
        clarification: ClarificationState? = nil,
        planRefinement: PlanRefinementRequest? = nil
    ) {
        isSubmitting = true
        smartCaptureError = nil
        Task { @MainActor in
            defer { isSubmitting = false }
            let context = buildSmartCaptureContext(
                rawInput: text,
                clarification: clarification,
                planRefinement: planRefinement
            )
            do {
                // ContextualCaptureAgentService only returns a structured decision.
                // No SwiftData write happens here — that waits for user confirmation.
                let decision = try await captureAgent.analyze(context)
                smartDecision = decision
            } catch {
                // Safe fallback: surface a small error and let the user retry or
                // switch modes. Never auto-save partial LLM output, never crash.
                smartDecision = nil
                smartCaptureError = "Smart Capture could not process that. Try again, or switch Intelligence mode in Settings."
            }
        }
    }

    /// User tapped "Send feedback" on the workspace preview. Re-runs the agent
    /// with the previous workspace + their feedback so the agent can revise
    /// instead of starting from scratch. Never persists anything until the
    /// user taps Create Plan on the revised draft. Refinement operates on the
    /// whole workspace, so the user can add a missing target, split one target
    /// into multiple, merge several, or modify one without touching the others.
    @MainActor
    private func refinePlan(_ feedback: String, decision: ContextualCaptureDecision) {
        guard let previousWorkspace = decision.proposedWorkspace else { return }
        guard !isSubmitting else { return }

        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Recover the original raw input. If we're already on a revision, the
        // history's first entry was created from the first refinement round;
        // otherwise use the live `input` field.
        let originalInput = previousWorkspace.refinementHistory.first.map { _ in input }
            ?? input.trimmingCharacters(in: .whitespacesAndNewlines)

        let refinement = PlanRefinementRequest(
            originalInput: originalInput,
            previousWorkspace: previousWorkspace,
            feedback: trimmed,
            history: previousWorkspace.refinementHistory
        )

        runSmartCapture(text: originalInput, clarification: nil, planRefinement: refinement)
    }

    /// Continues a clarification round: re-runs the agent with the prior question
    /// and the user's answer. Only reachable while a Smart Capture result is shown,
    /// so this path exists exclusively in LLM mode.
    @MainActor
    private func answerClarification(_ answer: String, decision: ContextualCaptureDecision) {
        guard !isSubmitting else { return }
        let originalInput = clarificationState?.previousInput
            ?? input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let question = decision.clarificationQuestion else {
            // No question to continue from — treat the answer as fresh input.
            clarificationState = nil
            runSmartCapture(text: answer)
            return
        }

        let state = ClarificationState(
            previousInput: originalInput,
            previousQuestion: question,
            userAnswer: answer
        )
        clarificationState = state
        runSmartCapture(text: originalInput, clarification: state)
    }

    /// Confirms a proposed task. The agent preserved the raw time expression;
    /// the existing temporal resolver does the actual date resolution here.
    @MainActor
    private func confirmTask(_ task: ProposedTask, decision: ContextualCaptureDecision) {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            let rawText = [task.title, task.timeExpression]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !rawText.isEmpty else {
                smartCaptureError = "That task has no title to save."
                return
            }
            do {
                try await createWorkItems(from: rawText, preferredProjectName: decision.inferredProjectName)
                resetSmartCapture()
                input = ""
                dismiss()
            } catch {
                smartCaptureError = "Could not save that task. Try again."
            }
        }
    }

    /// Confirms a staged workspace. Every ready PlanningTarget becomes one or
    /// more work items, one per `PlannedTask` across its phases. A workspace
    /// can span multiple deadlines and multiple projects — each target is
    /// resolved independently:
    ///
    ///   - Per-target project: prefer the target's own `projectName`, falling
    ///     back to the workspace-level inferred project. Auto-create the
    ///     project if it doesn't exist yet.
    ///   - Per-task time expression: passed through to the existing temporal
    ///     resolver via `createWorkItems`. The target's `dueTimeExpression`
    ///     is folded into each task's raw text when the task has no timing
    ///     of its own, so the resolver schedules backward from the deadline.
    ///
    /// Targets whose status is not `.ready` are skipped — the user must
    /// refine to fill in their missing details before they generate tasks.
    @MainActor
    private func confirmWorkspace(_ workspace: PlanningWorkspace, decision: ContextualCaptureDecision) {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            let workspaceLevelProjectName = resolveProjectName(for: decision)
            do {
                for target in workspace.targets where target.status.isReady {
                    // Per-target project: target's own hint takes priority over
                    // the workspace-level project so a workspace with two
                    // targets in two different projects lands correctly.
                    let targetProjectName = resolveTargetProjectName(
                        target: target,
                        workspaceFallback: workspaceLevelProjectName
                    )

                    for plannedTask in target.phases.flatMap(\.tasks) {
                        // Compose raw text: task title + its own time expression,
                        // OR fall back to the target's deadline so the resolver
                        // schedules backward from "due Friday".
                        let timeBit = plannedTask.timeExpression?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? target.dueTimeExpression?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        let rawText = [plannedTask.title, timeBit]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        guard !rawText.isEmpty else { continue }

                        // Per-task project hint trumps the target's project hint
                        // if the LLM specifically labeled a task differently.
                        let perTaskProjectName = resolveProjectName(
                            for: plannedTask,
                            planFallback: targetProjectName
                        )

                        try await createWorkItems(
                            from: rawText,
                            preferredProjectName: perTaskProjectName
                        )
                    }
                }
                resetSmartCapture()
                input = ""
                dismiss()
            } catch {
                smartCaptureError = "Could not create the plan. Try again."
            }
        }
    }

    /// Confirms extracted project context. The actual SwiftData write is delegated
    /// to `ProjectContextCoordinator` — context is appended, never overwritten.
    @MainActor
    private func confirmContext(
        _ extracted: ExtractedProjectContext,
        projectId: UUID?,
        decision: ContextualCaptureDecision
    ) {
        guard !isSubmitting else { return }

        let targetProjectId: UUID
        if let projectId {
            targetProjectId = projectId
        } else if let matchedId = decision.matchedProjectId {
            targetProjectId = matchedId
        } else if let inferred = decision.inferredProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines), !inferred.isEmpty {
            // Use the fuzzy matcher before creating a new project so a parser
            // hint like "Job Search" still attaches context to the user's
            // existing "Q4 Job Hunt" rather than spawning a duplicate.
            if let matched = ProjectMatcher.match(
                projectHint: inferred,
                taskTitle: "",
                rawInput: "",
                existingProjects: projects
            ) {
                targetProjectId = matched.id
            } else {
                let newProject = Project(
                    name: inferred,
                    colorToken: ProjectCatalog.colorToken(forProjectNamed: inferred),
                    sortIndex: projects.nextSortIndex
                )
                modelContext.insert(newProject)
                targetProjectId = newProject.id
            }
        } else {
            smartCaptureError = "No project to attach this context to."
            return
        }

        ProjectContextCoordinator.saveExtractedContext(
            extracted,
            to: targetProjectId,
            sourceInput: input.trimmingCharacters(in: .whitespacesAndNewlines),
            in: modelContext
        )
        resetSmartCapture()
        input = ""
        dismiss()
    }

    private func resetSmartCapture() {
        smartDecision = nil
        clarificationState = nil
        smartCaptureError = nil
    }

    // MARK: - Smart Capture context construction

    private func buildSmartCaptureContext(
        rawInput: String,
        clarification: ClarificationState? = nil,
        planRefinement: PlanRefinementRequest? = nil
    ) -> SmartCaptureContext {
        // Active project lightweight summaries (used in the projects list line).
        let projectSummaries = projects.map { project in
            ProjectSummary(
                id: project.id,
                name: project.name,
                activeItemCount: workItems.filter {
                    $0.projectName == project.name && $0.status != .archived
                }.count
            )
        }

        // Rich, structured project context — only included for projects that
        // actually have a ProjectContext row. The shared prompt builder caps
        // each project's recent-notes list to keep tokens bounded.
        let contextSummaries: [ProjectContextSummary] = projectContexts.compactMap { ctx in
            guard let project = projects.first(where: { $0.id == ctx.projectId }) else { return nil }
            let recentNotes = ctx.notes
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(5)
                .map { "\($0.category.label): \($0.content)" }
            let summary = ProjectContextSummary(
                projectId: project.id,
                projectName: project.name,
                goal: ctx.goal,
                audience: ctx.audience,
                deadlineExpression: ctx.deadlineExpression,
                keyReferences: ctx.keyReferences,
                constraints: ctx.constraints,
                successCriteria: ctx.successCriteria,
                openQuestions: ctx.openQuestions,
                userPreferences: ctx.userPreferences,
                recentContextNotes: Array(recentNotes)
            )
            return summary
        }

        // Recent tasks (any project) — gives the LLM signal on what's already
        // on the user's plate. Cap at 10.
        let recentTaskSummaries: [TaskSummary] = workItems
            .filter { $0.status != .archived }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(10)
            .map { item in
                TaskSummary(
                    id: item.id,
                    title: item.title,
                    projectName: item.projectName,
                    status: item.status.rawValue,
                    dueDate: item.dueDate,
                    timeExpression: nil,
                    createdAt: item.createdAt
                )
            }

        // Open tasks across all active projects — used during plan generation so
        // the LLM can avoid duplicating work already on the timeline. Cap at 8.
        let openTaskSummaries: [TaskSummary] = workItems
            .filter { $0.status != .archived && $0.status != .done && !$0.needsReview }
            .sorted(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) })
            .prefix(8)
            .map { item in
                TaskSummary(
                    id: item.id,
                    title: item.title,
                    projectName: item.projectName,
                    status: item.status.rawValue,
                    dueDate: item.dueDate,
                    timeExpression: nil,
                    createdAt: item.createdAt
                )
            }

        return SmartCaptureContext(
            rawInput: rawInput,
            currentDate: .now,
            timezone: .current,
            locale: .current,
            currentScreen: "QuickCapture",
            selectedProject: nil,
            selectedTask: nil,
            activeProjects: projectSummaries,
            projectContextSummaries: contextSummaries,
            recentTasks: recentTaskSummaries,
            openTasksForRelevantProject: openTaskSummaries,
            clarificationState: clarification,
            planRefinement: planRefinement
        )
    }

    /// Resolves a project name for confirmed Smart Capture output, creating a new
    /// `Project` record when the agent inferred a name that does not yet exist.
    /// Uses `ProjectMatcher` so user-named variants ("Q4 Job Hunt") match parser
    /// hints ("Job Search") before any new project is created.
    private func resolveProjectName(for decision: ContextualCaptureDecision) -> String? {
        if let matchedId = decision.matchedProjectId,
           let matched = projects.first(where: { $0.id == matchedId }) {
            return matched.name
        }
        guard let inferred = decision.inferredProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines), !inferred.isEmpty else {
            return nil
        }
        if let matched = ProjectMatcher.match(
            projectHint: inferred,
            taskTitle: "",
            rawInput: "",
            existingProjects: projects
        ) {
            return matched.name
        }
        let newProject = Project(
            name: inferred,
            colorToken: ProjectCatalog.colorToken(forProjectNamed: inferred),
            sortIndex: projects.nextSortIndex
        )
        modelContext.insert(newProject)
        return newProject.name
    }

    /// Resolves a project for a single planned task. Uses (in order):
    ///   1. Fuzzy match of the task's own `projectName` hint via `ProjectMatcher`
    ///      (with the task title as additional context).
    ///   2. Auto-create a new project from the task's hint if it didn't match.
    ///   3. Fall back to the plan-level project name when the task has no hint.
    ///
    /// Called once per `PlannedTask` in `confirmPlan` so a plan can span
    /// multiple projects — each task lands where it semantically belongs.
    private func resolveProjectName(
        for plannedTask: PlannedTask,
        planFallback: String?
    ) -> String? {
        let hint = plannedTask.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableHint: String? = {
            guard let hint, !hint.isEmpty,
                  hint.localizedCaseInsensitiveCompare("Uncategorized") != .orderedSame
            else { return nil }
            return hint
        }()

        if let usableHint {
            if let matched = ProjectMatcher.match(
                projectHint: usableHint,
                taskTitle: plannedTask.title,
                rawInput: plannedTask.title,
                existingProjects: projects
            ) {
                return matched.name
            }
            // Hint provided but no existing project matched — create one. This
            // is the "create a new project for it" behavior the user asked for
            // in LLM mode for plans.
            let newProject = Project(
                name: usableHint,
                colorToken: ProjectCatalog.colorToken(forProjectNamed: usableHint),
                sortIndex: projects.nextSortIndex
            )
            modelContext.insert(newProject)
            #if DEBUG
            print("Smart Capture plan: created new project '\(usableHint)' for task '\(plannedTask.title)'.")
            #endif
            return newProject.name
        }

        // No per-task hint — fall back to the plan-level project.
        return planFallback
    }

    /// Resolves a project for a single PlanningTarget. Mirrors the per-task
    /// helper above — fuzzy match the target's own `projectName`, auto-create
    /// from the hint when no match, fall back to the workspace-level project
    /// when the target has no hint. Called once per target in `confirmWorkspace`
    /// so a workspace can span multiple projects.
    private func resolveTargetProjectName(
        target: PlanningTarget,
        workspaceFallback: String?
    ) -> String? {
        let hint = target.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableHint: String? = {
            guard let hint, !hint.isEmpty,
                  hint.localizedCaseInsensitiveCompare("Uncategorized") != .orderedSame
            else { return nil }
            return hint
        }()

        if let usableHint {
            if let matched = ProjectMatcher.match(
                projectHint: usableHint,
                taskTitle: target.title,
                rawInput: target.title,
                existingProjects: projects
            ) {
                return matched.name
            }
            let newProject = Project(
                name: usableHint,
                colorToken: ProjectCatalog.colorToken(forProjectNamed: usableHint),
                sortIndex: projects.nextSortIndex
            )
            modelContext.insert(newProject)
            #if DEBUG
            print("Smart Capture workspace: created new project '\(usableHint)' for target '\(target.title)'.")
            #endif
            return newProject.name
        }
        return workspaceFallback
    }

    // MARK: - Work item creation (shared pipeline)

    /// Parses raw text into work items, maps projects, inserts and saves.
    /// Used by both standard capture and confirmed Smart Capture output so date
    /// resolution always flows through the existing `TaskUnderstandingService`.
    @MainActor
    private func createWorkItems(from text: String, preferredProjectName: String? = nil) async throws {
        let parsedItems = try await parser.parseMany(text)
        guard !parsedItems.isEmpty else {
            throw TaskUnderstandingError.foundationModelUnavailable("no work items returned")
        }

        // Universal duplicate guard: collapses identical parses (same title,
        // project, dates, temporal intent) into a single item. Runs in every
        // mode — Foundation Model, rule-based, Smart Capture confirm. Catches
        // LLM non-determinism, segmenter over-splits, and any input the user
        // accidentally entered twice (e.g. duplicate lines).
        let uniqueItems = parsedItems.deduplicatedByContent()

        #if DEBUG
        if uniqueItems.count != parsedItems.count {
            print(
                "QuickCapture dedup: collapsed \(parsedItems.count) parsed items → \(uniqueItems.count) unique"
            )
        }
        #endif

        var timelineCount = 0
        var reviewCount = 0
        for parsed in uniqueItems {
            let item = WorkItem(parsed: parsed)
            applyProjectMapping(from: parsed, to: item)

            // Smart Capture: when the agent matched an existing project, prefer it
            // over the parser's own keyword inference.
            if let preferredProjectName,
               let matched = projects.first(where: {
                   $0.name.localizedCaseInsensitiveCompare(preferredProjectName) == .orderedSame
               }) {
                item.projectName = matched.name
                item.suggestedProjectName = nil
            }

            if parsed.needsReview {
                item.status = .needsReview
                reviewCount += 1
            } else {
                timelineCount += 1
            }

            #if DEBUG
            print(
                """
                QuickCapture created:
                input=\(parsed.rawInput)
                title=\(parsed.title)
                savedProject=\(item.projectName ?? "nil")
                suggestedProject=\(item.suggestedProjectName ?? "nil")
                needsReview=\(parsed.needsReview)
                """
            )
            #endif

            modelContext.insert(item)
            try? AppleCalendarSyncService.shared.syncAfterItemChange(item: item, projects: projects)
        }

        #if DEBUG
        if uniqueItems.count > 1 {
            print("QuickCapture added \(uniqueItems.count) work items: \(timelineCount) timeline, \(reviewCount) review.")
        }
        #endif

        try modelContext.save()
    }

    // MARK: - Project mapping

    private func applyProjectMapping(from parsed: ParsedWorkItem, to item: WorkItem) {
        // Smarter matching: fuzzy match the parser's hint plus the task's own
        // title and raw input against existing projects. This catches cases the
        // parsers miss — e.g. parser hint "Job Search" mapping to a user-named
        // project "Q4 Job Hunt", or no parser hint at all but the task title
        // contains the project name. Works for every mode.
        if let matched = ProjectMatcher.match(
            projectHint: parsed.projectGuess,
            taskTitle: parsed.title,
            rawInput: parsed.rawInput,
            existingProjects: projects
        ) {
            item.projectName = matched.name
            item.suggestedProjectName = nil
            return
        }

        // No existing project matched. Preserve the parser's hint as a suggestion
        // so the user can promote it to a real project from the work item detail
        // view. Non-LLM modes intentionally do not auto-create projects.
        guard let inferredProject = parsed.projectGuess?.trimmingCharacters(in: .whitespacesAndNewlines),
              !inferredProject.isEmpty,
              inferredProject.localizedCaseInsensitiveCompare("Uncategorized") != .orderedSame
        else {
            item.projectName = nil
            item.suggestedProjectName = nil
            return
        }
        item.projectName = nil
        item.suggestedProjectName = ProjectCatalog.normalizedTemplateName(inferredProject) ?? inferredProject
    }
}
