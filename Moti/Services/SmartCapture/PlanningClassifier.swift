import Foundation

/// Stage 1 of Moti's two-stage intelligence flow: a fast, deterministic
/// classifier that decides whether a capture needs deep LLM planning before
/// any model is invoked.
///
/// Why deterministic? The most common input — a clear, atomic task like
/// "Email Andre tonight" — should be created instantly without a planning
/// round-trip and without being decomposed into invented subtasks. Only inputs
/// that genuinely benefit (explicit "plan this", multiple deadlines, multiple
/// deliverables, refinements, or vague input) escalate to Stage 2.
///
/// Reuses existing helpers rather than duplicating logic:
/// - `CapturedClassifier.hasActionVerb` / `isVeryVague`
/// - `CaptureSegmenter.segments` for deliverable counting
enum PlanningClassifier {

    static func classify(rawInput: String, isRefinement: Bool = false) -> PlanningDecision {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let wordCount = trimmed.split { $0.isWhitespace }.count

        // 1. Refining an existing plan → always deep, revise rather than restart.
        if isRefinement {
            return PlanningDecision(
                inputType: .refinementRequest,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "User is refining a previously generated plan.",
                confidence: 0.95
            )
        }

        // 2. Explicit request to plan / break down / organize.
        if containsPlanningKeyword(lower) {
            return PlanningDecision(
                inputType: .complexPlanning,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "User explicitly asked to plan, break down, or organize.",
                confidence: 0.9
            )
        }

        // 3. Multiple deadlines → one planning track per deadline.
        let deadlineCount = deadlineAnchorCount(in: lower)
        if deadlineCount >= 2 {
            return PlanningDecision(
                inputType: .multiDeadlinePlanning,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "Input contains \(deadlineCount) deadlines; each needs its own track.",
                confidence: 0.85
            )
        }

        // 4. Multiple distinct deliverables (lines / bullets / semicolons).
        if CaptureSegmenter.segments(from: trimmed).count >= 2 {
            return PlanningDecision(
                inputType: .complexPlanning,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "Input lists multiple deliverables.",
                confidence: 0.75
            )
        }

        let hasVerb = CapturedClassifier.hasActionVerb(trimmed)
        let isVague = CapturedClassifier.isVeryVague(trimmed)

        // 5. Project note / framing — knowledge about a project, not a task.
        if containsNoteKeyword(lower) {
            return PlanningDecision(
                inputType: .projectNote,
                shouldUseLLM: true, shouldGeneratePlan: false,
                reason: "Reads as project context or a note, not an action.",
                confidence: 0.7
            )
        }

        // 6. Status update on existing work.
        if containsStatusKeyword(lower) {
            return PlanningDecision(
                inputType: .statusUpdate,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "Reports progress on existing work.",
                confidence: 0.7
            )
        }

        // 7. Reminder.
        if lower.contains("remind me") || lower.hasPrefix("reminder") {
            return PlanningDecision(
                inputType: .reminder,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "Input is a reminder.",
                confidence: 0.8
            )
        }

        // 8. Too vague to act on → ask one clarifying question (LLM is good at this).
        if (wordCount <= 2 && !hasVerb && deadlineCount == 0) || (isVague && !hasVerb) {
            return PlanningDecision(
                inputType: .unclear,
                shouldUseLLM: true, shouldGeneratePlan: false, shouldAskForClarification: true,
                reason: "Too vague to act on; ask one clarifying question.",
                confidence: 0.6
            )
        }

        // 9. Atomic / simple task — the anti-overplanning core. Create directly.
        let isShort = wordCount <= 14
        if hasVerb && deadlineCount <= 1 && isShort {
            let atomic = deadlineCount == 1
            return PlanningDecision(
                inputType: atomic ? .atomicTask : .simpleTask,
                shouldUseLLM: false, shouldGeneratePlan: false, shouldCreateSubtasks: false,
                reason: atomic
                    ? "Clear single-action task with a due date; create directly without a plan."
                    : "Clear single-action task; create directly without a plan.",
                confidence: atomic ? 0.92 : 0.8
            )
        }

        // 10. A bare deadline with no real action.
        if !hasVerb && deadlineCount == 1 {
            return PlanningDecision(
                inputType: .deadlineOnly,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "A deadline with no explicit action; capture as a single dated item.",
                confidence: 0.7
            )
        }

        // 11. Longer actionable input with no explicit plan ask: a light plan
        //     helps reduce ambiguity. Shorter → still a single task.
        if hasVerb {
            if wordCount > 14 {
                return PlanningDecision(
                    inputType: .complexPlanning,
                    shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                    reason: "Broad multi-clause task; a light plan reduces ambiguity.",
                    confidence: 0.6
                )
            }
            return PlanningDecision(
                inputType: .simpleTask,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "Single actionable task; create directly.",
                confidence: 0.65
            )
        }

        // 12. Nothing matched confidently → let the LLM ask.
        return PlanningDecision(
            inputType: .unclear,
            shouldUseLLM: true, shouldGeneratePlan: false, shouldAskForClarification: true,
            reason: "Could not confidently classify; ask the user.",
            confidence: 0.5
        )
    }

    // MARK: - Keyword groups

    private static func containsPlanningKeyword(_ lower: String) -> Bool {
        let keywords = [
            "plan ", "plan my", "plan the", "plan out", "make a plan", "come up with a plan",
            "break down", "break it down", "break this down", "breakdown",
            "organize", "roadmap", "map out", "lay out", "step by step", "help me plan"
        ]
        return keywords.contains { lower.contains($0) }
    }

    private static func containsNoteKeyword(_ lower: String) -> Bool {
        let keywords = [
            "focus on", "should focus", "remember that", "note that", "keep in mind",
            "the goal is", "the audience is", "audience is", "constraint", "we should",
            "fyi", "context:", "idea:", "decided to", "prefers"
        ]
        return keywords.contains { lower.contains($0) }
    }

    private static func containsStatusKeyword(_ lower: String) -> Bool {
        let keywords = [
            "finished ", "completed ", "done with", "wrapped up", "i did ",
            "marked done", "just finished", "already did", "already finished"
        ]
        return keywords.contains { lower.contains($0) }
    }

    // MARK: - Deadline anchors

    /// Counts distinct date anchors (day names, near-term relatives, numeric
    /// dates). Deliberately conservative — markers like "by"/"due" are NOT
    /// counted, so "submit by Friday" reads as one deadline, not two. Under-
    /// counting is the safe direction: it favors the light path over planning.
    private static func deadlineAnchorCount(in lower: String) -> Int {
        let dayNames = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
        let relatives = "today|tonight|tomorrow|next week|next month"
        let numericDate = #"\b\d{1,2}[./]\d{1,2}\b"#
        let pattern = #"\b(?:"# + dayNames + "|" + relatives + #")\b|"# + numericDate
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(lower.startIndex..., in: lower)
        return regex.numberOfMatches(in: lower, range: range)
    }
}
