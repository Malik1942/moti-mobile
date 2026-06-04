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

        // Keep visual QA deterministic even after interacting with the sample
        // build in prior simulator runs.
        UserDefaults.standard.removeObject(forKey: "lifelines.parkedStrandWeek")
        UserDefaults.standard.removeObject(forKey: "lifelines.spacedStrandWeek")
        UserDefaults.standard.removeObject(forKey: "lifelines.loweredStrandIDs")

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

        // A representative spread — one of each trajectory outcome — so the
        // grammar reads calm-by-default (two healthy, two needing a voice, one
        // paused), not "everything is slipping."

        // Move — achievement, ON-TIME: well ahead of pace (50% done, 25% of time).
        _ = project("Move", "purple")
        item("Book movers", project: "Move", created: daysAgo(10), updated: daysAgo(6), status: .done)
        item("Pack kitchen", project: "Move", created: daysAgo(9), updated: daysAgo(2), status: .done)
        item("Change address", project: "Move", created: daysAgo(8), due: daysAhead(18))
        item("Move day", project: "Move", created: daysAgo(10), due: daysAhead(30))

        // Launch — achievement, BEHIND: little progress, most of the time gone.
        _ = project("Launch", "blue")
        item("Spec", project: "Launch", created: daysAgo(40), updated: daysAgo(34), status: .done)
        item("Build core", project: "Launch", created: daysAgo(38), due: daysAhead(6))
        item("Beta", project: "Launch", created: daysAgo(38), due: daysAhead(8))
        item("Polish", project: "Launch", created: daysAgo(38), due: daysAhead(9))
        item("Ship", project: "Launch", created: daysAgo(40), due: daysAhead(10))

        // Parents — maintenance, SUSTAINED: weekly, fed 2 days ago.
        _ = project("Parents", "green")
        let call = item("Call home", project: "Parents", created: daysAgo(60),
                        due: daysAhead(5), recurrence: RecurrenceRule(frequency: .weekly))
        completion(call, daysAgo(23)); completion(call, daysAgo(16))
        completion(call, daysAgo(9)); completion(call, daysAgo(2))

        // Fitness — maintenance, FADING: weekly rhythm, silent for 24 days.
        _ = project("Fitness", "orange")
        let gym = item("Gym", project: "Fitness", created: daysAgo(70),
                       due: daysAhead(1), recurrence: RecurrenceRule(frequency: .weekly))
        completion(gym, daysAgo(52)); completion(gym, daysAgo(45))
        completion(gym, daysAgo(38)); completion(gym, daysAgo(24))

        // Reading — PAUSED (deliberate set-down, dashed + label).
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
