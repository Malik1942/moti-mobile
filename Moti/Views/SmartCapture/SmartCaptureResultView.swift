import SwiftUI

// MARK: - Top-Level Dispatcher

struct SmartCaptureResultView: View {
    let decision: ContextualCaptureDecision
    let projects: [Project]
    let onConfirmTask: (ProposedTask) -> Void
    let onAnswerClarification: (String) -> Void
    let onConfirmContext: (ExtractedProjectContext, UUID?) -> Void
    let onConfirmWorkspace: (PlanningWorkspace) -> Void
    let onRefinePlan: (String) -> Void
    /// Universal refine for non-plan results (atomic task, lightweight, context).
    /// Lets the user clarify, add context, make recurring, add a deadline,
    /// simplify, expand, or convert into a plan — the affordance always exists.
    let onRefine: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if decision.needsClarification || decision.clarificationQuestion != nil {
                ClarificationCard(
                    decision: decision,
                    onAnswer: onAnswerClarification,
                    onDismiss: onDismiss
                )
            } else if let workspace = decision.proposedWorkspace, !workspace.targets.isEmpty {
                WorkspacePreviewCard(
                    decision: decision,
                    workspace: workspace,
                    projects: projects,
                    onConfirm: onConfirmWorkspace,
                    onRefine: onRefinePlan,
                    onDismiss: onDismiss
                )
            } else if let task = decision.proposedTask, decision.isActionable {
                TaskPreviewCard(
                    decision: decision,
                    task: task,
                    onConfirm: onConfirmTask,
                    onRefine: onRefine,
                    onDismiss: onDismiss
                )
            } else if let context = decision.extractedContext, !context.isEmpty {
                ProjectContextPreviewCard(
                    decision: decision,
                    extractedContext: context,
                    onConfirm: onConfirmContext,
                    onRefine: onRefine,
                    onDismiss: onDismiss
                )
            } else {
                FallbackCard(onDismiss: onDismiss)
            }
        }
    }
}

// MARK: - Shared Card Style

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
            .padding(.horizontal, 16)
    }
}

extension View {
    fileprivate func cardStyle() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - Confidence Label

private func confidenceLabel(for confidence: Double) -> String {
    if confidence > 0.85 { return "High confidence" }
    if confidence >= 0.65 { return "Review suggested" }
    return "Needs clarification"
}

private func confidenceColor(for confidence: Double) -> Color {
    if confidence > 0.85 { return .green }
    if confidence >= 0.65 { return .orange }
    return .red
}

// MARK: - Dismiss Button

private struct DismissButton: View {
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

// MARK: - Clarification Card

private struct ClarificationCard: View {
    let decision: ContextualCaptureDecision
    let onAnswer: (String) -> Void
    let onDismiss: () -> Void

    @State private var freeformText: String = ""

    private var question: ClarificationQuestion? { decision.clarificationQuestion }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                Text("Quick question")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                DismissButton(onDismiss: onDismiss)
            }

            // Project pill
            if let projectName = decision.inferredProjectName {
                Text(projectName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Question text
            if let q = question {
                Text(q.question)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                // Choice buttons
                VStack(spacing: 8) {
                    ForEach(q.choices) { choice in
                        Button {
                            onAnswer(choice.value)
                        } label: {
                            Text(choice.label)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Freeform answer
                if q.allowsFreeformAnswer {
                    HStack(spacing: 8) {
                        TextField("Or describe in your own words…", text: $freeformText)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button("Send") {
                            let trimmed = freeformText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            onAnswer(trimmed)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .disabled(freeformText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(20)
        .cardStyle()
    }
}

// MARK: - Task Preview Card

private struct TaskPreviewCard: View {
    let decision: ContextualCaptureDecision
    let task: ProposedTask
    let onConfirm: (ProposedTask) -> Void
    let onRefine: (String) -> Void
    let onDismiss: () -> Void

    @State private var isRefining = false
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                Text("Proposed task")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                DismissButton(onDismiss: onDismiss)
            }

            // Task title
            Text(task.title)
                .font(.headline)
                .foregroundStyle(.primary)

            // Time expression
            if let timeExpr = task.timeExpression {
                Label(timeExpr, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Rationale
            if let rationale = task.rationale {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Project pill
            if let projectName = decision.inferredProjectName {
                Text(projectName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Confidence indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(confidenceColor(for: decision.confidence))
                    .frame(width: 7, height: 7)
                Text(confidenceLabel(for: decision.confidence))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if isRefining {
                RefineField(text: $feedbackText, focused: $feedbackFocused) { feedback in
                    onRefine(feedback)
                    isRefining = false
                    feedbackText = ""
                } onCancel: {
                    isRefining = false
                    feedbackText = ""
                    feedbackFocused = false
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    onConfirm(task)
                } label: {
                    Text("Add to Timeline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                RefineButton(isRefining: $isRefining, focused: $feedbackFocused)

                Button("Dismiss") {
                    onDismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .cardStyle()
        .animation(.snappy, value: isRefining)
    }
}

// MARK: - Reusable Refine Controls
//
// The Refine affordance is universal in Smart Capture — it exists on every
// result (atomic task, lightweight, context, and plans), not just plans. The
// behavior differs by depth, but the user can always clarify, add context, make
// a capture recurring, add a deadline, simplify, expand, or convert it into a
// plan. These two small views give the non-plan cards the same control the plan
// card already has.

/// The "Refine" pill that reveals the feedback field.
private struct RefineButton: View {
    @Binding var isRefining: Bool
    var focused: FocusState<Bool>.Binding

    var body: some View {
        Button {
            withAnimation(.snappy) {
                isRefining = true
                focused.wrappedValue = true
            }
        } label: {
            Label("Refine", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.indigo.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The expanding feedback field shown once Refine is tapped.
private struct RefineField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSend: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tell Moti what to change — clarify, add a deadline, make it recurring, turn it into a plan…", text: $text, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused(focused)

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSend(trimmed)
                } label: {
                    Text("Send")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.indigo)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Project Context Preview Card

private struct ProjectContextPreviewCard: View {
    let decision: ContextualCaptureDecision
    let extractedContext: ExtractedProjectContext
    let onConfirm: (ExtractedProjectContext, UUID?) -> Void
    let onRefine: (String) -> Void
    let onDismiss: () -> Void

    @State private var isRefining = false
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    private var saveLabel: String {
        if let name = decision.inferredProjectName {
            return "Save to \(name)"
        }
        return "Save to new project"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                Text("Project context found")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                DismissButton(onDismiss: onDismiss)
            }

            // Extracted fields
            VStack(alignment: .leading, spacing: 10) {
                if let goal = extractedContext.goal {
                    LabeledContent("Goal", value: goal)
                        .font(.subheadline)
                }
                if let audience = extractedContext.audience {
                    LabeledContent("Audience", value: audience)
                        .font(.subheadline)
                }
                if let deadline = extractedContext.deadlineExpression {
                    LabeledContent("Deadline", value: deadline)
                        .font(.subheadline)
                }
                if !extractedContext.keyReferences.isEmpty {
                    LabeledContent("References", value: extractedContext.keyReferences.joined(separator: ", "))
                        .font(.subheadline)
                }
                if !extractedContext.constraints.isEmpty {
                    LabeledContent("Constraints", value: extractedContext.constraints.joined(separator: ", "))
                        .font(.subheadline)
                }
                if !extractedContext.successCriteria.isEmpty {
                    LabeledContent("Success Criteria", value: extractedContext.successCriteria.joined(separator: ", "))
                        .font(.subheadline)
                }
                if !extractedContext.openQuestions.isEmpty {
                    LabeledContent("Open Questions", value: extractedContext.openQuestions.joined(separator: ", "))
                        .font(.subheadline)
                }
            }

            Divider()

            if isRefining {
                RefineField(text: $feedbackText, focused: $feedbackFocused) { feedback in
                    onRefine(feedback)
                    isRefining = false
                    feedbackText = ""
                } onCancel: {
                    isRefining = false
                    feedbackText = ""
                    feedbackFocused = false
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    onConfirm(extractedContext, decision.matchedProjectId)
                } label: {
                    Text(saveLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                RefineButton(isRefining: $isRefining, focused: $feedbackFocused)

                Button("Dismiss") {
                    onDismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .cardStyle()
        .animation(.snappy, value: isRefining)
    }
}

// MARK: - Plan Preview Card

/// Multi-target plan preview.
///
/// One target → renders much like the previous single-plan UI.
/// Two or more targets → header chip ("3 planning targets detected") plus each
/// target as its own section with title, due-expression, optional priority,
/// and tasks grouped by phase.
private struct WorkspacePreviewCard: View {
    let decision: ContextualCaptureDecision
    let workspace: PlanningWorkspace
    let projects: [Project]
    let onConfirm: (PlanningWorkspace) -> Void
    let onRefine: (String) -> Void
    let onDismiss: () -> Void

    @State private var isRefining = false
    @State private var feedbackText: String = ""
    @FocusState private var feedbackFocused: Bool

    private var isMultiTarget: Bool { workspace.targets.count > 1 }

    /// Context-line copy shown above the workspace title — tells the user
    /// whether the LLM had project context to anchor on, or was working from
    /// their input alone.
    private var contextLine: String {
        // If every target shares one project, surface that name explicitly.
        let projectNames = Set(workspace.targets.compactMap {
            $0.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        if projectNames.count == 1, let name = projectNames.first {
            return "Using context from: \(name)"
        }
        if !projectNames.isEmpty {
            return "Spanning \(projectNames.count) project\(projectNames.count == 1 ? "" : "s")"
        }
        if decision.extractedContext != nil {
            return "Draft plan based on your project context"
        }
        return "Draft plan based on your input"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            titleBlock
            scopeChip
            changeSummaryChip
            multiTargetChip
            assumptionsBlock

            // Targets — each rendered as its own section. Single-target
            // workspaces render the phases inline (no target header) for a
            // single-plan feel; multi-target workspaces show each target as
            // a separate section with its own due-date row.
            VStack(alignment: .leading, spacing: isMultiTarget ? 14 : 8) {
                ForEach(workspace.targets) { target in
                    TargetSectionView(
                        target: target,
                        index: indexOfTarget(target),
                        showHeader: isMultiTarget
                    )
                }
            }

            validationWarnings
            Divider()
            if isRefining { refineInput }
            actionRow
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack {
            Text(headerLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
            Spacer()
            DismissButton(onDismiss: onDismiss)
        }
    }

    private var headerLabel: String {
        var label = "Proposed plan"
        if workspace.revisionNumber > 0 {
            label += " (rev \(workspace.revisionNumber))"
        }
        return label
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contextLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(workspace.title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let summary = workspace.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var scopeChip: some View {
        if let scope = workspace.estimatedScope, !scope.isEmpty {
            Label(scope, systemImage: "calendar")
                .font(.caption.weight(.medium))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.indigo.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var changeSummaryChip: some View {
        if let change = workspace.planChangeSummary, !change.isEmpty {
            Label("Updated: \(change)", systemImage: "sparkles")
                .font(.caption.weight(.medium))
                .foregroundStyle(.indigo)
        }
    }

    /// "N planning targets detected" header when there's more than one target.
    @ViewBuilder
    private var multiTargetChip: some View {
        if isMultiTarget {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack")
                Text("\(workspace.targets.count) planning targets detected")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.indigo.opacity(0.10))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var assumptionsBlock: some View {
        if !workspace.assumptions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assumptions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(workspace.assumptions, id: \.self) { assumption in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(assumption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var validationWarnings: some View {
        let issues = workspace.validationIssues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Heads-up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.85))
                }
            }
        }
    }

    private var refineInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tell Moti what to change…", text: $feedbackText, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($feedbackFocused)

            HStack {
                Button("Cancel") {
                    isRefining = false
                    feedbackText = ""
                    feedbackFocused = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onRefine(trimmed)
                    isRefining = false
                    feedbackText = ""
                    feedbackFocused = false
                } label: {
                    Text("Send feedback")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.indigo)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .transition(.opacity)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                onConfirm(workspace)
            } label: {
                Text(createButtonLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.snappy) {
                    isRefining = true
                    feedbackFocused = true
                }
            } label: {
                Label("Refine", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.indigo.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button("Dismiss") {
                onDismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    /// "Create N tasks across M deadlines?" tailored to the workspace shape.
    private var createButtonLabel: String {
        let readyCount = workspace.readyTargets.count
        let totalTasks = workspace.readyTargets.reduce(0) { $0 + $1.taskCount }
        if readyCount <= 1 { return "Create Plan" }
        return "Create \(totalTasks) tasks across \(readyCount) deadlines"
    }

    private func indexOfTarget(_ target: PlanningTarget) -> Int {
        workspace.targets.firstIndex(where: { $0.id == target.id }) ?? 0
    }
}

/// One section per `PlanningTarget`. Single-target workspaces hide the header
/// so the UI reads as a regular single plan; multi-target workspaces show a
/// numbered header with due-date and status badges.
private struct TargetSectionView: View {
    let target: PlanningTarget
    let index: Int
    let showHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showHeader {
                header
            }

            if target.status == .ready {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(target.phases) { phase in
                        PhaseSectionView(phase: phase)
                    }
                }
            } else {
                needsClarificationCard
            }
        }
        .padding(showHeader ? 12 : 0)
        .background(showHeader ? AnyShapeStyle(Color.secondary.opacity(0.05)) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index + 1).")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.indigo)
                Text(target.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let priority = target.priority {
                    Text(priority.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityBackground(priority))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                if let due = target.dueTimeExpression, !due.isEmpty {
                    Label("Due: \(due)", systemImage: "flag.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.indigo)
                }
                if let project = target.projectName, !project.isEmpty {
                    Text(project)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.10))
                        .clipShape(Capsule())
                }
                if target.deliverableType != .unknown {
                    Text(target.deliverableType.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var needsClarificationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(target.status.label, systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            if let reason = target.needsClarificationReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Refine to add the missing details before this target is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func priorityBackground(_ priority: PriorityLevel) -> AnyShapeStyle {
        switch priority {
        case .low:    AnyShapeStyle(Color.secondary.opacity(0.10))
        case .medium: AnyShapeStyle(Color.indigo.opacity(0.12))
        case .high:   AnyShapeStyle(Color.orange.opacity(0.18))
        }
    }
}

private struct PhaseSectionView: View {
    let phase: TaskPhase
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    // Phase-level timing chip when set — preferred over per-task
                    // timing when the LLM grouped a phase under a single window.
                    if let timing = phase.phaseTimeExpression, !timing.isEmpty {
                        Label(timing, systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 2)
                    }
                    ForEach(phase.tasks) { task in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                HStack(spacing: 8) {
                                    if let project = task.projectName, !project.isEmpty {
                                        Text(project)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.indigo)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.indigo.opacity(0.10))
                                            .clipShape(Capsule())
                                    }
                                    if let time = task.timeExpression, !time.isEmpty {
                                        Label(time, systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let effort = task.estimatedEffort {
                                        Text(effort.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            },
            label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(phase.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        )
        .accentColor(.indigo)
    }
}

// MARK: - Fallback Card

private struct FallbackCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Could not understand input")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("Try rephrasing or adding more detail.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") {
                onDismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.indigo)
        }
        .padding(24)
        .cardStyle()
    }
}
