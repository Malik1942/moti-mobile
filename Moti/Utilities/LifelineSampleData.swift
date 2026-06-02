#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only sample data for visually verifying the Lifelines Timeline against
/// the PRD's visual grammar. Never compiled into release builds, and only runs
/// when the app is launched with `-MotiSeedLifelines YES`.
///
/// It deliberately exercises every state: active (reaching, filled), quiet
/// (just-reaching, hollow), drifted (empty Now-slot), and paused (dashed) — plus
/// an achievement strand (deadline + forward nodes), a maintenance strand with a
/// co-occurring riser, and a calm/active majority so the screen reads serene.
enum LifelineSampleData {
    @MainActor
    static func seedIfRequested(into context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "MotiSeedLifelines") else { return }

        // Only seed an empty store, so relaunches stay stable.
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard existing.isEmpty else { return }

        let now = Date()
        func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
        func daysAhead(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

        func project(_ name: String, _ color: String) -> Project {
            let p = Project(name: name, colorToken: color)
            context.insert(p)
            return p
        }

        @discardableResult
        func item(
            _ title: String, project: String,
            created: Date, updated: Date? = nil, due: Date? = nil,
            status: WorkItemStatus = .active, recurrence: RecurrenceRule = .none
        ) -> WorkItem {
            let wi = WorkItem(
                rawInput: title, title: title, projectName: project,
                createdAt: created, updatedAt: updated ?? created,
                dueDate: due, workingStartDate: nil, workingEndDate: nil,
                suggestedSessions: [], estimatedEffort: nil, parserConfidence: 1,
                needsReview: false, reviewReason: nil, status: status, parserExplanation: ""
            )
            wi.recurrence = recurrence
            context.insert(wi)
            return wi
        }

        func completion(_ item: WorkItem, _ date: Date) {
            context.insert(CompletionLog(
                taskId: item.id, eventType: .statusChanged, newStatus: .done, timestamp: date
            ))
        }

        // Work — achievement, active. Real deadline + forward steps.
        _ = project("Work", "blue")
        item("Ship release notes", project: "Work", created: daysAgo(10), updated: daysAgo(1), status: .done)
        item("Fix onboarding bug", project: "Work", created: daysAgo(6), updated: daysAgo(2), status: .done)
        item("Review PRs", project: "Work", created: daysAgo(3), updated: daysAgo(1))
        item("Launch v2", project: "Work", created: daysAgo(20), due: daysAhead(12))
        item("QA pass", project: "Work", created: daysAgo(4), due: daysAhead(5))

        // Move — achievement, active, closing in on a deadline.
        _ = project("Move", "purple")
        item("Book movers", project: "Move", created: daysAgo(8), updated: daysAgo(3), status: .done)
        item("Pack kitchen", project: "Move", created: daysAgo(5), due: daysAhead(3))
        item("Change address", project: "Move", created: daysAgo(5), due: daysAhead(7))
        item("Move day", project: "Move", created: daysAgo(15), due: daysAhead(10))

        // Fitness — maintenance, drifted (weekly, last fed 22 days ago).
        _ = project("Fitness", "orange")
        let gym = item("Gym", project: "Fitness", created: daysAgo(70),
                       due: daysAhead(1), recurrence: RecurrenceRule(frequency: .weekly))
        completion(gym, daysAgo(50)); completion(gym, daysAgo(43)); completion(gym, daysAgo(36))
        completion(gym, daysAgo(29)); completion(gym, daysAgo(22))

        // Parents — maintenance, quiet (weekly-ish, ~9 days since).
        _ = project("Parents", "green")
        let call = item("Call home", project: "Parents", created: daysAgo(60),
                        due: daysAhead(1), recurrence: RecurrenceRule(frequency: .weekly))
        completion(call, daysAgo(30)); completion(call, daysAgo(23))
        completion(call, daysAgo(16)); completion(call, daysAgo(9))

        // Friends — maintenance, drifted longest (→ "What matters now").
        _ = project("Friends", "indigo")
        let friends = item("See friends", project: "Friends", created: daysAgo(80),
                           due: daysAhead(1), recurrence: RecurrenceRule(frequency: .weekly))
        completion(friends, daysAgo(60)); completion(friends, daysAgo(48)); completion(friends, daysAgo(34))

        // Reading — paused (deliberate set-down, dashed + label).
        let reading = project("Reading", "gray")
        item("Read 20 pages", project: "Reading", created: daysAgo(40), updated: daysAgo(35),
             due: daysAhead(1), recurrence: RecurrenceRule(frequency: .daily))

        try? context.save()
        StrandPreferenceStore.shared.setPaused(true, for: reading.id.uuidString)

        // Turn the redesign on and skip onboarding for the verification run.
        UserDefaults.standard.set(true, forKey: "useLifelineTimeline")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}
#endif
