//
// StrandTimelineBuilderTests.swift
//
// Covers the adapter that derives a behavioral event stream from existing
// WorkItem / Project / CompletionLog fields (read-only, no task-model change)
// and assembles render-ready Strands.
//
// Product rules under test:
//   • strand = Project (+ one implicit Unassigned strand)
//   • achievement iff a real one-time deadline exists; recurrence → maintenance
//   • recurring completions are counted from CompletionLog (a living habit reads
//     as repeatedly fed, not one done task)
//   • attention order: drifted rises, calm recedes, paused sinks
//   • "why it went quiet" is co-occurrence across the field, never causation
//

import XCTest
@testable import Moti

final class StrandTimelineBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * day) }

    private func item(
        _ title: String,
        project: String?,
        created: Date,
        updated: Date? = nil,
        due: Date? = nil,
        status: WorkItemStatus = .active,
        recurrence: RecurrenceRule = .none
    ) -> WorkItem {
        let wi = WorkItem(
            rawInput: title, title: title, projectName: project,
            createdAt: created, updatedAt: updated ?? created,
            dueDate: due, workingStartDate: nil, workingEndDate: nil,
            suggestedSessions: [], estimatedEffort: nil, parserConfidence: 1,
            needsReview: false, reviewReason: nil, status: status, parserExplanation: ""
        )
        wi.recurrence = recurrence
        return wi
    }

    private func project(_ name: String, color: String = "blue") -> Project {
        Project(name: name, colorToken: color)
    }

    // MARK: - Declared cadence mapping

    func test_recurrenceCadenceDays_mapsEachFrequency() {
        XCTAssertNil(RecurrenceRule(frequency: .none).approximateCadenceDays)
        XCTAssertEqual(RecurrenceRule(frequency: .daily).approximateCadenceDays, 1)
        XCTAssertEqual(RecurrenceRule(frequency: .weekly).approximateCadenceDays, 7)
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekday: 6).approximateCadenceDays, 7)
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, interval: 2).approximateCadenceDays, 14)
        XCTAssertEqual(RecurrenceRule(frequency: .custom, interval: 3).approximateCadenceDays, 3)
        XCTAssertEqual(RecurrenceRule(frequency: .monthly).approximateCadenceDays ?? 0, 30.4, accuracy: 0.01)
    }

    // MARK: - Strand kind inference

    func test_strandWithRealDeadline_isAchievement() {
        let builder = StrandTimelineBuilder(
            projects: [project("Move")],
            workItems: [item("Book movers", project: "Move", created: daysAgo(3), due: daysAgo(-10))],
            completionLogs: [], now: now
        )
        let move = builder.build().first { $0.name == "Move" }
        XCTAssertEqual(move?.kind, .achievement)
        XCTAssertNotNil(move?.deadline)
        XCTAssertFalse(move?.forwardNodes.isEmpty ?? true)
    }

    func test_recurringStrandWithNoOneOffDeadline_isMaintenance() {
        let builder = StrandTimelineBuilder(
            projects: [project("Fitness")],
            workItems: [item("Gym", project: "Fitness", created: daysAgo(2),
                             due: daysAgo(-1), recurrence: RecurrenceRule(frequency: .weekly))],
            completionLogs: [], now: now
        )
        let fitness = builder.build().first { $0.name == "Fitness" }
        XCTAssertEqual(fitness?.kind, .maintenance)
    }

    // MARK: - Unassigned strand

    func test_unassignedItems_formOneImplicitStrand() {
        let builder = StrandTimelineBuilder(
            projects: [project("Work")],
            workItems: [
                item("Ship", project: "Work", created: daysAgo(1)),
                item("Misc", project: nil, created: daysAgo(1))
            ],
            completionLogs: [], now: now
        )
        let strands = builder.build()
        XCTAssertTrue(strands.contains { $0.id == Strand.unassignedID })
    }

    func test_noUnassignedStrand_whenAllItemsHaveProjects() {
        let builder = StrandTimelineBuilder(
            projects: [project("Work")],
            workItems: [item("Ship", project: "Work", created: daysAgo(1))],
            completionLogs: [], now: now
        )
        XCTAssertFalse(builder.build().contains { $0.id == Strand.unassignedID })
    }

    // MARK: - Recurring completions counted from the log

    func test_recurringCompletions_areCountedFromCompletionLog() {
        let gym = item("Gym", project: "Fitness", created: daysAgo(40),
                       due: daysAgo(-2), recurrence: RecurrenceRule(frequency: .weekly))
        let logs = [
            CompletionLog(taskId: gym.id, eventType: .statusChanged, newStatus: .done, timestamp: daysAgo(14)),
            CompletionLog(taskId: gym.id, eventType: .statusChanged, newStatus: .done, timestamp: daysAgo(7)),
            CompletionLog(taskId: gym.id, eventType: .statusChanged, newStatus: .done, timestamp: daysAgo(2))
        ]
        let builder = StrandTimelineBuilder(
            projects: [project("Fitness")], workItems: [gym], completionLogs: logs, now: now
        )
        let fitness = builder.build().first { $0.name == "Fitness" }
        // Last fed 2 days ago on a weekly rhythm → active, and traces show history.
        XCTAssertEqual(fitness?.presence.state, .active)
        XCTAssertFalse(fitness?.lastTraces.isEmpty ?? true)
    }

    // MARK: - Attention ordering

    func test_attentionOrder_driftedRisesAboveActive_pausedSinks() {
        let builder = StrandTimelineBuilder(
            projects: [project("Work"), project("Fitness"), project("Reading")],
            workItems: [
                item("Ship", project: "Work", created: daysAgo(2), updated: daysAgo(1)),
                // Fitness: weekly but silent 30 days → drifted.
                item("Gym", project: "Fitness", created: daysAgo(60), updated: daysAgo(30),
                     status: .done, recurrence: RecurrenceRule(frequency: .weekly)),
                // Reading: also drifted, but paused → should sink below Work.
                item("Book", project: "Reading", created: daysAgo(60), updated: daysAgo(40), status: .done,
                     recurrence: RecurrenceRule(frequency: .weekly))
            ],
            completionLogs: [], now: now,
            pausedStrandIDs: []
        )
        // Mark Reading paused.
        var b = builder
        let readingID = b.projects.first { $0.name == "Reading" }!.id.uuidString
        b.pausedStrandIDs = [readingID]
        let order = b.build().map(\.name)

        XCTAssertEqual(order.first, "Fitness")          // drifted, not paused → top
        XCTAssertLessThan(order.firstIndex(of: "Work")!, order.firstIndex(of: "Reading")!) // paused sinks
    }

    // MARK: - Co-occurrence ("why it went quiet")

    func test_coOccurrence_namesStrandsThatRoseWhileThisFell() {
        let fitness = item("Gym", project: "Fitness", created: daysAgo(30),
                           recurrence: RecurrenceRule(frequency: .weekly))
        let fitnessLogs = [
            CompletionLog(taskId: fitness.id, eventType: .statusChanged, newStatus: .done, timestamp: daysAgo(25)),
            CompletionLog(taskId: fitness.id, eventType: .statusChanged, newStatus: .done, timestamp: daysAgo(20))
        ]
        // Work surged recently (4 events in the last window, none before).
        let work1 = item("Ship A", project: "Work", created: daysAgo(6), updated: daysAgo(5), status: .done)
        let work2 = item("Ship B", project: "Work", created: daysAgo(4), updated: daysAgo(2), status: .done)

        let builder = StrandTimelineBuilder(
            projects: [project("Fitness"), project("Work")],
            workItems: [fitness, work1, work2],
            completionLogs: fitnessLogs, now: now
        )
        let fit = builder.build().first { $0.name == "Fitness" }
        XCTAssertEqual(fit?.presence.state, .drifted)               // silent 20d on weekly horizon 14
        XCTAssertEqual(fit?.coOccurringStrandNames, ["Work"])       // rose while Fitness fell
    }

    func test_activeStrand_hasNoCoOccurrenceNoise() {
        let builder = StrandTimelineBuilder(
            projects: [project("Work"), project("Fitness")],
            workItems: [
                item("Ship", project: "Work", created: daysAgo(2), updated: daysAgo(1), status: .done),
                item("Gym", project: "Fitness", created: daysAgo(2), updated: daysAgo(1), status: .done,
                     recurrence: RecurrenceRule(frequency: .weekly))
            ],
            completionLogs: [], now: now
        )
        let fitness = builder.build().first { $0.name == "Fitness" }
        XCTAssertEqual(fitness?.presence.state, .active)
        XCTAssertTrue(fitness?.coOccurringStrandNames.isEmpty ?? false)
    }
}
