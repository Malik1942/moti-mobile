import Foundation

/// Stage 1 of Moti's two-stage intelligence flow: a fast, deterministic
/// classifier that decides how much structure a capture is allowed to produce
/// before any model is invoked.
///
/// **Core rule (anti-overplanning).** If the user does not explicitly ask for a
/// plan, breakdown, schedule, sequence, roadmap, or steps, the first response
/// must NOT generate a plan or subtasks. The default is a single atomic task,
/// reminder, habit, or recurring task that preserves the original intent.
///
/// Structure is only unlocked when:
///   1. The user explicitly asks to plan / split / break down / schedule /
///      organize / create steps (or asks for a routine).
///   2. The user is refining a previously generated plan.
///   3. The captured intent is clearly project-scale (e.g. "prepare portfolio
///      for recruiting season", "ship beta version by June").
///
/// Note the "too large" exception keys off project-scale *scope*, never raw
/// length — short phrases can be huge in scope, and long sentences are usually
/// still one task. Under-counting favors the light path, which is the desired
/// default; over-planning is the failure mode we avoid.
///
/// Reuses existing helpers rather than duplicating logic:
/// - `CapturedClassifier.hasActionVerb` / `isVeryVague`
/// - `CaptureSegmenter.segments` for deliverable counting
enum PlanningClassifier {

    static func classify(rawInput: String, isRefinement: Bool = false) -> PlanningDecision {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let wordCount = trimmed.split { $0.isWhitespace }.count

        // 1. Refining an existing plan → the user is steering structure
        //    themselves, so this is an explicit request to add depth.
        if isRefinement {
            return PlanningDecision(
                inputType: .refinementRequest,
                planningDepth: .structured,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "User is refining a previously generated plan.",
                confidence: 0.95
            )
        }

        // Semantic planning desire (none / mild / explicit) + project-scale scope
        // are the two signals that gate structure. Detected up front so the rest
        // of the rules can stay focused on shape (recurrence, notes, deadlines).
        let intent = PlanningIntentDetector.detect(lower)
        let projectScale = containsProjectScaleKeyword(lower)

        // 2. Explicit ask to plan / structure / organize / break down / map out /
        //    make a timeline. Project-scale wording bumps it to a full multi-phase
        //    plan; otherwise structured. This is the primary planning entry point
        //    and is intentionally semantic, not keyword-exact.
        if intent == .explicit {
            return PlanningDecision(
                inputType: .complexPlanning,
                planningDepth: projectScale ? .deep : .structured,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "User explicitly asked to plan, structure, or break this down.",
                confidence: 0.9
            )
        }

        let hasVerb = CapturedClassifier.hasActionVerb(trimmed)
        let isVague = CapturedClassifier.isVeryVague(trimmed)
        let deadlineCount = TemporalAnchors.count(in: lower)

        // 4. Recurring behaviour / habit ("every day", "daily", "build a habit").
        //    One lightweight recurring task with cadence + metadata — never
        //    decomposed into procedural steps. The LLM runs only to extract the
        //    cadence/duration/project, not to plan. Checked before the
        //    multi-deadline rule: "gym every monday and thursday" mentions two
        //    weekdays but is one recurring habit, not two deadline tracks.
        if containsRecurrenceKeyword(lower) && !isVague {
            return PlanningDecision(
                inputType: .recurringTask,
                planningDepth: .lightweight,
                shouldUseLLM: true, shouldGeneratePlan: false, shouldCreateSubtasks: false,
                reason: "Recurring behaviour; capture one recurring task with cadence, not a plan.",
                confidence: 0.85
            )
        }

        // 5. Project note / framing — knowledge about a project, not a task.
        //    Stays ahead of multi-deadline: "note that the report is due Friday
        //    and the demo Tuesday" is context, not two new tasks.
        if containsNoteKeyword(lower) {
            return PlanningDecision(
                inputType: .projectNote,
                planningDepth: .none,
                shouldUseLLM: true, shouldGeneratePlan: false,
                reason: "Reads as project context or a note, not an action.",
                confidence: 0.7
            )
        }

        // 6. Status update on existing work. Past-tense keywords, so future
        //    multi-deadline inputs never land here; kept ahead of rule 7 so a
        //    report about two finished items doesn't spawn two new tasks.
        if containsStatusKeyword(lower) {
            return PlanningDecision(
                inputType: .statusUpdate,
                planningDepth: .none,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "Reports progress on existing work.",
                confidence: 0.7
            )
        }

        // 7. Multiple deadlines → one top-level task per deadline. These are
        //    distinct items, not subtasks, so allow several tracks but forbid
        //    procedural decomposition of each. Deliberately checked BEFORE
        //    project-scale wording and the reminder rule: several explicit
        //    date anchors are stronger evidence than a scope keyword ("finish
        //    my capstone by June 20" inside a three-deadline list is one of
        //    three tracks, not a deep plan), and "remind me to X by Friday and
        //    Y by Monday" is two dated items, not one reminder.
        if deadlineCount >= 2 {
            return PlanningDecision(
                inputType: .multiDeadlinePlanning,
                planningDepth: .structured,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: false,
                reason: "Input contains \(deadlineCount) deadlines; each needs its own task.",
                confidence: 0.8
            )
        }

        // 8. Project-scale intent with at most one deadline — clearly too large
        //    to be one task even without an explicit ask. (With two or more
        //    deadlines rule 7 already produced one track per deadline.)
        if projectScale {
            return PlanningDecision(
                inputType: .complexPlanning,
                planningDepth: .deep,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: true,
                reason: "Captured intent is project-scale; a multi-phase plan fits.",
                confidence: 0.7
            )
        }

        // 9. Reminder (single-dated; multi-deadline reminders split in rule 7).
        if lower.contains("remind me") || lower.hasPrefix("reminder") {
            return PlanningDecision(
                inputType: .reminder,
                planningDepth: .none,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "Input is a reminder.",
                confidence: 0.8
            )
        }

        // 10. Multiple distinct deliverables (lines / bullets / semicolons) → one
        //    top-level task each, again without inventing subtasks.
        if CaptureSegmenter.segments(from: trimmed).count >= 2 {
            return PlanningDecision(
                inputType: .multiDeadlinePlanning,
                planningDepth: .structured,
                shouldUseLLM: true, shouldGeneratePlan: true, shouldCreateSubtasks: false,
                reason: "Input lists multiple distinct deliverables; one task each.",
                confidence: 0.7
            )
        }

        // 11. Too vague to act on → ask one clarifying question (LLM is good at this).
        if (wordCount <= 2 && !hasVerb && deadlineCount == 0) || (isVague && !hasVerb) {
            return PlanningDecision(
                inputType: .unclear,
                planningDepth: .none,
                shouldUseLLM: true, shouldGeneratePlan: false, shouldAskForClarification: true,
                reason: "Too vague to act on; ask one clarifying question.",
                confidence: 0.6
            )
        }

        // 12. Atomic / simple task — the anti-overplanning core. Create directly,
        //     regardless of length: a long single-clause sentence is still one
        //     task. No subtasks, no plan.
        if hasVerb && deadlineCount <= 1 {
            let atomic = deadlineCount == 1
            return PlanningDecision(
                inputType: atomic ? .atomicTask : .simpleTask,
                planningDepth: .none,
                shouldUseLLM: false, shouldGeneratePlan: false, shouldCreateSubtasks: false,
                reason: atomic
                    ? "Clear single-action task with a due date; create directly without a plan."
                    : "Clear single-action task; create directly without a plan.",
                confidence: atomic ? 0.92 : 0.8
            )
        }

        // 13. A bare deadline with no real action.
        if !hasVerb && deadlineCount == 1 {
            return PlanningDecision(
                inputType: .deadlineOnly,
                planningDepth: .none,
                shouldUseLLM: false, shouldGeneratePlan: false,
                reason: "A deadline with no explicit action; capture as a single dated item.",
                confidence: 0.7
            )
        }

        // 14. Nothing matched confidently → let the LLM ask. Never auto-plan.
        return PlanningDecision(
            inputType: .unclear,
            planningDepth: .none,
            shouldUseLLM: true, shouldGeneratePlan: false, shouldAskForClarification: true,
            reason: "Could not confidently classify; ask the user.",
            confidence: 0.5
        )
    }

    // MARK: - Keyword groups

    /// Scope words that mark an intent as genuinely project-scale — too large to
    /// be a single task even when phrased in a few words. Deliberately tight:
    /// a false negative just yields the (desired) light path, while a false
    /// positive over-plans. Length is never used as a signal here.
    private static func containsProjectScaleKeyword(_ lower: String) -> Bool {
        let keywords = [
            "recruiting season", "prepare portfolio", "prepare my portfolio",
            "ship beta", "ship the beta", "ship a beta", "beta version", "ship version",
            "launch ", "go to market", "go-to-market", "fundraising round", "raise a round",
            "thesis", "dissertation", "capstone", "rebrand", "redesign the", "migrate the",
            "get ready for the", "prep for the season", "wedding", "relocation", "relocate to"
        ]
        return keywords.contains { lower.contains($0) }
    }

    /// Cadence / habit markers. When present (and the input isn't vague), Moti
    /// captures one recurring task with cadence + metadata instead of a plan.
    private static func containsRecurrenceKeyword(_ lower: String) -> Bool {
        let keywords = [
            "every day", "everyday", "each day", "daily", "every morning", "each morning",
            "every evening", "every night", "each night", "every week", "each week", "weekly",
            "every month", "each month", "monthly", "every other day", "twice a week",
            "times a week", "times a day", "weekday", "on weekdays",
            "every monday", "every tuesday", "every wednesday", "every thursday",
            "every friday", "every saturday", "every sunday",
            "on mondays", "on tuesdays", "on wednesdays", "on thursdays",
            "on fridays", "on saturdays", "on sundays",
            "build a habit", "habit of", "recurring", "on a regular basis", "regularly"
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

}
