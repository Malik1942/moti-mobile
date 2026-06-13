//
// IntelligenceAuditTests.swift
//
// Regression suite from the June 2026 intelligence/timeline QA audit.
//
// Every audit bug it identified is now fixed (Steps 1–3): unified temporal
// parsing, multi-deadline understanding + segmentation, and everyday-verb
// breadth. The original `XCTExpectFailure` wrappers that encoded those bugs
// have all been unwrapped into plain regression tests as each fix landed.
//
// The suite locks in: multi-date extraction, prompt/commit date agreement,
// comma/"and"/semicolon multi-deadline splitting, atomic-vs-planning routing,
// everyday-verb recognition + vague/emotional/project-scale guardrails, the
// dropped-target safety net, project matching, and trajectory visibility of
// overdue/completed work.
//

import XCTest
@testable import Moti

final class IntelligenceAuditTests: XCTestCase {

    // Friday, June 12, 2026, 10:00 local. A fixed anchor keeps weekday math
    // deterministic ("next Friday", "this week") regardless of run date.
    private var friday: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 12; comps.hour = 10
        return Calendar.current.date(from: comps)!
    }

    /// Wednesday, June 10, 2026 — two days before `friday`.
    private var wednesday: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 10; comps.hour = 10
        return Calendar.current.date(from: comps)!
    }

    private func day(of date: Date?) -> Int? {
        date.map { Calendar.current.component(.day, from: $0) }
    }

    // MARK: - Multi-date extraction (locks current-correct behavior)

    func test_threeCommaSeparatedDeadlines_allThreeDatesExtracted() {
        let input = "I need to finish my portfolio by June 25, apply to 5 jobs by June 18, and prepare my capstone presentation by June 20."
        let results = TemporalResolver.resolve(input: input, now: friday)
            .filter { $0.resolverPath != .noSignal }

        XCTAssertEqual(results.count, 3, "every deadline in the sentence must be extracted, not just the first")
        XCTAssertEqual(results.compactMap { day(of: $0.resolvedDate) }.sorted(), [18, 20, 25])
        XCTAssertTrue(results.allSatisfy { $0.interpretation == .calendarDate })
    }

    func test_twoWeekdayDeadlinesInOneSentence_bothExtracted() {
        let results = TemporalResolver.resolve(input: "finish by Friday and submit by Monday", now: friday)
            .filter { $0.resolverPath != .noSignal }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.originalText)), ["friday", "monday"])
    }

    func test_namedMonthDateAndClockTime_bothSignalsSurvive() {
        let results = TemporalResolver.resolve(input: "by June 30 at 5pm", now: friday)
        XCTAssertTrue(results.contains { $0.interpretation == .calendarDate && day(of: $0.resolvedDate) == 30 })
        XCTAssertTrue(results.contains { $0.interpretation == .clockTime })
    }

    // MARK: - Relative date handling

    func test_spelledDuration_resolvesAtTemporalLayer() {
        let results = TemporalResolver.resolve(input: "in two weeks", now: friday)
        XCTAssertEqual(results.first?.interpretation, .relativeDuration)
        XCTAssertEqual(results.first?.resolvedDuration, 14 * 86_400)
    }

    func test_nextFriday_fromWednesday_isStrictlyNextWeek_atTemporalLayer() {
        let results = TemporalResolver.resolve(input: "TestFlight ready by next Friday", now: wednesday)
        // Wed Jun 10 → "next Friday" must be Jun 19, not Jun 12 (this week's).
        XCTAssertEqual(day(of: results.first?.resolvedDate), 19)
    }

    func test_commitPath_nextFriday_matchesTemporalLayer() {
        // Wed Jun 10 → "next Friday" must be Jun 19 at BOTH layers, never
        // this week's Friday (Jun 12).
        let parse = DateResolver.resolveTemporal(in: "TestFlight ready by next Friday", now: wednesday)
        XCTAssertEqual(day(of: parse.dueDate), 19, "commit-path date must match what the user was shown")
    }

    func test_commitPath_parsesSpelledDurations() {
        let parse = DateResolver.resolveTemporal(in: "Finish the draft in two weeks", now: friday)
        XCTAssertEqual(day(of: parse.dueDate), 26, "spelled durations must work like digits")
    }

    func test_commitPath_parsesEndOfMonth() {
        let parse = DateResolver.resolveTemporal(in: "App Store submission by the end of the month", now: friday)
        XCTAssertEqual(day(of: parse.dueDate), 30, "June ends on the 30th")
    }

    func test_commitPath_parsesNextMonth() {
        let parse = DateResolver.resolveTemporal(in: "Submit report next month", now: friday)
        XCTAssertEqual(day(of: parse.dueDate), 31, "bare 'next month' reads as a deadline at the end of July")
        XCTAssertEqual(parse.dueDate.map { Calendar.current.component(.month, from: $0) }, 7)
    }

    func test_temporalLayer_resolvesThisWeekend() {
        let results = TemporalResolver.resolve(input: "Clean the garage this weekend", now: friday)
        let signal = results.first { $0.resolverPath != .noSignal }
        XCTAssertEqual(day(of: signal?.resolvedDate), 14, "weekend after Fri Jun 12 ends Sun Jun 14")
    }

    func test_temporalLayer_resolvesEndOfMonthAndNextMonth() {
        let endOfMonth = TemporalResolver.resolve(input: "by the end of the month", now: friday)
        XCTAssertEqual(day(of: endOfMonth.first?.resolvedDate), 30)

        let nextMonth = TemporalResolver.resolve(input: "next month", now: friday)
        XCTAssertEqual(day(of: nextMonth.first?.resolvedDate), 31)
    }

    func test_thisWeek_onAFriday_staysInCurrentWeek() {
        // Today IS Friday Jun 12 — "this week" must not jump to Jun 19.
        let promptLayer = TemporalResolver.resolve(input: "wrap this up this week", now: friday)
        XCTAssertEqual(day(of: promptLayer.first?.resolvedDate), 12)

        let commitLayer = DateResolver.resolveTemporal(in: "wrap this up this week", now: friday)
        XCTAssertEqual(day(of: commitLayer.dueDate), 12)
    }

    /// The Step-1 contract itself: for every expression class the prompt layer
    /// resolves confidently, the saved dueDate lands on the SAME day.
    func test_promptLayerAndCommitPath_neverDisagree() {
        let inputs = [
            "Finish my portfolio by June 25",
            "TestFlight ready by next Friday",
            "Screenshots by Wednesday",
            "App Store submission by the end of the month",
            "Finish the draft in two weeks",
            "Submit report next month",
            "Clean the garage this weekend",
            "Finish this in 10 days",
            "Email Caleb tomorrow",
            "wrap this up this week"
        ]
        for input in inputs {
            let promptSignal = TemporalResolver.resolve(input: input, now: friday)
                .first { $0.resolvedDate != nil && $0.confidence >= 0.85 }
            let committed = DateResolver.resolveTemporal(in: input, now: friday)
            XCTAssertNotNil(promptSignal?.resolvedDate, "prompt layer must resolve: \(input)")
            XCTAssertNotNil(committed.dueDate, "commit path must resolve: \(input)")
            XCTAssertEqual(
                day(of: promptSignal?.resolvedDate), day(of: committed.dueDate),
                "layers disagree on day for: \(input)"
            )
        }
    }

    // MARK: - Atomic task vs planning classification

    func test_clearAtomicTasks_neverTriggerPlanning() {
        let atomicInputs = [
            "Buy coffee beans tomorrow",
            "Email Andre my portfolio link tonight",
            "Submit the final PDF by Friday"
        ]
        for input in atomicInputs {
            let p = PlanningClassifier.classify(rawInput: input)
            XCTAssertFalse(p.shouldGeneratePlan, "\(input) must stay a single task")
            XCTAssertFalse(p.shouldCreateSubtasks, "\(input) must not be decomposed")
        }
    }

    func test_emotionalPressureInput_doesNotTriggerHeavyPlanning() {
        let p = PlanningClassifier.classify(rawInput: "I'm overwhelmed and need to finish this in 10 days")
        XCTAssertFalse(p.shouldGeneratePlan)
        XCTAssertFalse(p.shouldCreateSubtasks)
    }

    func test_multiDeadlineWeekdayList_routesToOneTaskPerDeadline() {
        let input = "I have three things this week: finish design critique by Tuesday, revise prototype by Thursday, and submit the report on Sunday."
        let p = PlanningClassifier.classify(rawInput: input)
        XCTAssertEqual(p.inputType, .multiDeadlinePlanning)
        XCTAssertTrue(p.shouldGeneratePlan)
        XCTAssertFalse(p.shouldCreateSubtasks, "distinct deadlines are separate tasks, not decomposed plans")
    }

    func test_clearDatedTasksWithEverydayVerbs_noClarification() {
        // Everyday verbs now recognized (Step 3) AND carrying a date anchor →
        // an atomic dated task, never a clarification question.
        for input in [
            "Pay rent by the end of the month",
            "Clean the garage this weekend"
        ] {
            let p = PlanningClassifier.classify(rawInput: input)
            XCTAssertFalse(p.shouldAskForClarification, "\(input) is a clear dated task; no question needed")
            XCTAssertFalse(p.shouldGeneratePlan)
        }
    }

    func test_everydayVerbWithoutDateAnchor_becomesTaskNotClarification() {
        // The confirmed gap: "renew" wasn't in the closed verb list, so this
        // fell through to "unclear" → clarification. Step 3 recognizes it.
        let p = PlanningClassifier.classify(rawInput: "Renew my passport before graduation")
        XCTAssertFalse(p.shouldAskForClarification, "a clear action; no question needed")
        XCTAssertFalse(p.shouldGeneratePlan, "one action, not a project")
        XCTAssertEqual(p.inputType, .simpleTask)
    }

    func test_everydayActionVerbs_recognizedAsActions() {
        // A spread of everyday verbs absent from the original 30-word list.
        for verb in ["Renew", "Pay", "Clean", "Book", "Cancel", "Print", "Pack",
                     "Register", "Deposit", "Reschedule"] {
            XCTAssertTrue(
                CapturedClassifier.hasActionVerb("\(verb) the thing"),
                "\(verb) should read as an action verb"
            )
        }
    }

    func test_structuralLeadIn_recognizesVerbsOutsideTheList() {
        // Generalization beyond the list: the word after a personal-intent
        // lead-in is treated as the action, even for verbs Moti has never seen.
        XCTAssertTrue(CapturedClassifier.hasActionVerb("I need to winterize the cabin"))
        XCTAssertTrue(CapturedClassifier.hasActionVerb("I have to defrost the freezer"))
        XCTAssertTrue(CapturedClassifier.hasActionVerb("please refurbish the old desk"))
    }

    // MARK: - Step 3 guardrails: vague thoughts / emotions / project goals

    func test_vagueThought_doesNotBecomeATask() {
        let p = PlanningClassifier.classify(rawInput: "Think about my future")
        XCTAssertFalse(CapturedClassifier.hasActionVerb("Think about my future"),
                       "a reflective 'think about' is not a concrete action")
        XCTAssertNotEqual(p.inputType, .atomicTask)
        XCTAssertNotEqual(p.inputType, .simpleTask)
    }

    func test_cognitionVerbAfterLeadIn_stillNotAnAction() {
        XCTAssertFalse(CapturedClassifier.hasActionVerb("I need to think about my future"))
        XCTAssertFalse(CapturedClassifier.hasActionVerb("I want to feel less stressed"))
    }

    func test_emotionalStatement_doesNotBecomeATask() {
        let p = PlanningClassifier.classify(rawInput: "I feel overwhelmed about graduation")
        XCTAssertFalse(CapturedClassifier.hasActionVerb("I feel overwhelmed about graduation"),
                       "an emotional statement is not an action")
        XCTAssertFalse(p.shouldGeneratePlan)
        XCTAssertNotEqual(p.inputType, .atomicTask)
        XCTAssertNotEqual(p.inputType, .simpleTask)
    }

    func test_vagueFiller_doesNotBecomeATask() {
        XCTAssertFalse(CapturedClassifier.hasActionVerb("I need to handle some stuff"))
        XCTAssertTrue(CapturedClassifier.isVeryVague("visa stuff"))
    }

    func test_projectScaleGoal_staysPlanningNotAtomic() {
        // "launch" is project-scale: even with one deadline and a clear verb,
        // it must route to a multi-phase plan, never a single atomic task.
        let p = PlanningClassifier.classify(rawInput: "Launch my app by the end of the month")
        XCTAssertEqual(p.inputType, .complexPlanning)
        XCTAssertEqual(p.planningDepth, .deep)
        XCTAssertTrue(p.shouldGeneratePlan)
    }

    func test_capstoneAmongDeadlines_isMultiDeadline_notAtomic() {
        // The capstone deliverable joins multi-deadline planning when it shares
        // the capture with other dated deliverables (it is NOT a lone atomic).
        let input = "Prepare my capstone presentation by June 20, finish the report by June 22, and submit slides by June 24."
        let p = PlanningClassifier.classify(rawInput: input)
        XCTAssertEqual(p.inputType, .multiDeadlinePlanning)
        XCTAssertFalse(p.shouldCreateSubtasks)
    }

    func test_projectKeywordDoesNotOverrideMultiDeadlineRouting() {
        // "capstone" is a project-scale keyword, but three explicit deadlines
        // are stronger evidence: one task per deadline, no invented subtasks.
        let input = "I need to finish my portfolio by June 25, apply to 5 jobs by June 18, and prepare my capstone presentation by June 20."
        let p = PlanningClassifier.classify(rawInput: input)
        XCTAssertEqual(p.inputType, .multiDeadlinePlanning)
        XCTAssertFalse(p.shouldCreateSubtasks)
    }

    func test_multiDeadlineReminder_routesToOneItemPerDeadline() {
        let p = PlanningClassifier.classify(rawInput: "remind me to finish my essay by Friday and submit the report by Monday")
        XCTAssertEqual(p.inputType, .multiDeadlinePlanning, "two dated items, not one reminder with an arbitrary date")
    }

    func test_singleDeadlineReminder_staysAReminder() {
        let p = PlanningClassifier.classify(rawInput: "Remind me to submit the visa form by Friday")
        XCTAssertEqual(p.inputType, .reminder)
    }

    func test_recurrenceWithTwoWeekdayMentions_staysRecurring() {
        let p = PlanningClassifier.classify(rawInput: "gym every monday and thursday")
        XCTAssertEqual(p.inputType, .recurringTask, "a habit naming two weekdays is one recurring task, not two deadlines")
    }

    // MARK: - Multi-deadline creation (non-LLM commit path)

    func test_semicolonSeparatedDeadlines_createSeparateDatedTasks() async throws {
        let service = RuleBasedTaskUnderstandingService()
        let items = try await service.parseMany(
            "finish design critique by Tuesday; revise prototype by Thursday; submit the report on Sunday"
        )
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.compactMap(\.dueDate).count, 3, "each task keeps its own deadline")
        XCTAssertEqual(Set(items.compactMap { day(of: $0.dueDate) }).count, 3, "deadlines must not be merged")
    }

    func test_commaSeparatedDeadlines_createOneTaskPerDeadline() async throws {
        let service = RuleBasedTaskUnderstandingService()
        let items = try await service.parseMany(
            "I need to finish my portfolio by June 25, apply to 5 jobs by June 18, and prepare my capstone presentation by June 20."
        )
        XCTAssertEqual(items.count, 3, "three deliverables with three deadlines must become three tasks")
        XCTAssertEqual(items.compactMap { day(of: $0.dueDate) }, [25, 18, 20],
                       "each task keeps ITS OWN deadline, in the order written")
    }

    func test_andJoinedDeadlines_splitWithCorrectDates() async throws {
        let service = RuleBasedTaskUnderstandingService()
        let items = try await service.parseMany(
            "remind me to finish my essay by Friday and submit the report by Monday"
        )
        XCTAssertEqual(items.count, 2)
        // Fri Jun 19 and Mon Jun 15 relative to the audit's fixed Friday — but
        // parseMany uses the live clock, so assert weekday rather than day.
        let weekdays = items.compactMap { $0.dueDate.map { Calendar.current.component(.weekday, from: $0) } }
        XCTAssertEqual(weekdays, [6, 2], "essay → Friday, report → Monday; the pairing the user wrote")
        XCTAssertTrue(items[0].title.localizedCaseInsensitiveContains("essay"))
        XCTAssertTrue(items[1].title.localizedCaseInsensitiveContains("report"))
    }

    func test_ordinaryCommaList_singleDeadline_staysOneTask() async throws {
        let service = RuleBasedTaskUnderstandingService()
        let items = try await service.parseMany("buy milk, eggs, and bread tomorrow")
        XCTAssertEqual(items.count, 1, "a shopping list with ONE deadline is one task, not three")
    }

    func test_leadInClause_keepsTitleDeadlinePairing() async throws {
        let service = RuleBasedTaskUnderstandingService()
        let items = try await service.parseMany(
            "I have three things this week: finish design critique by Tuesday, revise prototype by Thursday, and submit the report on Sunday"
        )
        XCTAssertEqual(items.count, 3)
        let weekdays = items.compactMap { $0.dueDate.map { Calendar.current.component(.weekday, from: $0) } }
        XCTAssertEqual(weekdays, [3, 5, 1], "critique → Tuesday, prototype → Thursday, report → Sunday")
    }

    // MARK: - Refinement: dropped-target safety net (locks current-correct behavior)

    private func makeDecision(
        extracted: [ExtractedPlanningTarget],
        workspaceTargets: [PlanningTarget]?
    ) -> ContextualCaptureDecision {
        ContextualCaptureDecision(
            inputCompleteness: .projectSeed,
            intentType: .createProjectPlan,
            confidence: 0.9,
            isActionable: true,
            needsClarification: false,
            proposedWorkspace: workspaceTargets.map {
                PlanningWorkspace(title: "Plan", targets: $0)
            },
            extractedPlanningTargets: extracted
        )
    }

    func test_missingExtractedTargets_detectsSilentlyDroppedTarget() {
        let extracted = [
            ExtractedPlanningTarget(title: "Portfolio", dueTimeExpression: "June 25", sourceTextSpan: "finish my portfolio by June 25"),
            ExtractedPlanningTarget(title: "Job applications", dueTimeExpression: "June 18", sourceTextSpan: "apply to 5 jobs by June 18"),
            ExtractedPlanningTarget(title: "Capstone presentation", dueTimeExpression: "June 20", sourceTextSpan: "capstone presentation by June 20")
        ]
        // Workspace only planned two of the three.
        let planned = [
            PlanningTarget(title: "Portfolio", dueTimeExpression: "June 25", sourceTextSpan: "finish my portfolio by June 25"),
            PlanningTarget(title: "Capstone presentation", dueTimeExpression: "June 20", sourceTextSpan: "capstone presentation by June 20")
        ]
        let missing = makeDecision(extracted: extracted, workspaceTargets: planned).missingExtractedTargets()
        XCTAssertEqual(missing.map(\.title), ["Job applications"])
    }

    func test_missingExtractedTargets_emptyWhenWorkspaceCoversAll() {
        let extracted = [
            ExtractedPlanningTarget(title: "Report", sourceTextSpan: "report due Friday"),
            ExtractedPlanningTarget(title: "Slides", sourceTextSpan: "slides due Monday")
        ]
        let planned = [
            PlanningTarget(title: "Report", sourceTextSpan: "report due Friday"),
            PlanningTarget(title: "Slides", sourceTextSpan: "slides due Monday")
        ]
        XCTAssertTrue(makeDecision(extracted: extracted, workspaceTargets: planned).missingExtractedTargets().isEmpty)
    }

    func test_missingExtractedTargets_everythingMissingWhenNoWorkspace() {
        let extracted = [ExtractedPlanningTarget(title: "Report")]
        let missing = makeDecision(extracted: extracted, workspaceTargets: nil).missingExtractedTargets()
        XCTAssertEqual(missing.count, 1)
    }

    func test_refinementHistory_carriesForwardAcrossRevisions() {
        let history = [
            PlanRefinementHistoryItem(feedback: "split the report", summaryOfChange: "Split report into two targets"),
            PlanRefinementHistoryItem(feedback: "less intense", summaryOfChange: "Reduced to 2 tasks per target")
        ]
        let workspace = PlanningWorkspace(title: "Plan", targets: [], refinementHistory: history)
        XCTAssertEqual(workspace.revisionNumber, 2)
        XCTAssertEqual(workspace.refinementHistory.map(\.feedback), ["split the report", "less intense"])
    }

    // MARK: - Project context selection

    func test_projectMatcher_prefersExactNameThenFuzzy() {
        let projects = [Project(name: "Q4 Job Hunt", colorToken: "blue"),
                        Project(name: "Moti", colorToken: "red")]

        // Exact, case-insensitive
        XCTAssertEqual(
            ProjectMatcher.match(projectHint: "moti", taskTitle: "Fix widget", rawInput: "fix widget", existingProjects: projects)?.name,
            "Moti"
        )
        // Token overlap: hint "Job Search" → project "Q4 Job Hunt"
        XCTAssertEqual(
            ProjectMatcher.match(projectHint: "Job Search", taskTitle: "Apply to 5 jobs", rawInput: "apply to 5 jobs", existingProjects: projects)?.name,
            "Q4 Job Hunt"
        )
        // No match → nil (caller preserves the hint as a suggestion)
        XCTAssertNil(
            ProjectMatcher.match(projectHint: "Garden", taskTitle: "Water plants", rawInput: "water plants", existingProjects: projects)
        )
    }

    // MARK: - Trajectory: overdue & completed visibility

    private func auditItem(
        _ title: String, project: String?, created: Date, updated: Date? = nil,
        due: Date? = nil, status: WorkItemStatus = .active
    ) -> WorkItem {
        WorkItem(
            rawInput: title, title: title, projectName: project,
            createdAt: created, updatedAt: updated ?? created,
            dueDate: due, workingStartDate: nil, workingEndDate: nil,
            suggestedSessions: [], estimatedEffort: nil, parserConfidence: 1,
            needsReview: false, reviewReason: nil, status: status, parserExplanation: ""
        )
    }

    func test_completedAndOverdueItems_remainVisibleInStrandTimeline() {
        let now = friday
        let dayInterval: TimeInterval = 86_400
        let project = Project(name: "Capstone", colorToken: "blue")
        let completedLongAgo = auditItem(
            "Outline", project: "Capstone",
            created: now.addingTimeInterval(-30 * dayInterval),
            updated: now.addingTimeInterval(-21 * dayInterval),
            due: now.addingTimeInterval(-22 * dayInterval),
            status: .done
        )
        let overdueOpen = auditItem(
            "Final draft", project: "Capstone",
            created: now.addingTimeInterval(-10 * dayInterval),
            due: now.addingTimeInterval(-2 * dayInterval),
            status: .active
        )

        let builder = StrandTimelineBuilder(
            projects: [project],
            workItems: [completedLongAgo, overdueOpen],
            completionLogs: [],
            now: now
        )
        let strands = builder.build()
        XCTAssertEqual(strands.count, 1)

        let events = builder.deriveEvents(for: [completedLongAgo, overdueOpen])
        XCTAssertTrue(
            events.contains { $0.kind == .completed },
            "a finished task must stay in the strand's past as evidence"
        )

        // The overdue open item must read as needing attention, not vanish.
        let strand = strands[0]
        XCTAssertEqual(strand.trajectory.outcome, .slipping,
                       "an open item past its deadline reads as slipping on the trajectory")
    }

    func test_timelineScope_keepsCompletedAndOverdueItems() {
        let now = friday
        let done = auditItem("Done thing", project: nil, created: now, due: now.addingTimeInterval(-86_400), status: .done)
        let overdue = auditItem("Late thing", project: nil, created: now, due: now.addingTimeInterval(-86_400), status: .active)
        let archived = auditItem("Archived thing", project: nil, created: now, status: .archived)

        let visible = WorkItemScope.timeline([done, overdue, archived], now: now)
        XCTAssertTrue(visible.contains { $0.title == "Done thing" }, "completed work stays visible as history")
        XCTAssertTrue(visible.contains { $0.title == "Late thing" }, "overdue work stays visible")
        XCTAssertFalse(visible.contains { $0.title == "Archived thing" })
    }
}
