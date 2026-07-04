import Foundation

// Horizon Timeline v2 — sample snapshots for previews and the T12 state sweep.
// Deterministic (fixed `now`/calendar). Not shown by the running app.

enum HorizonSnapshotPreviewData {

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        c.firstWeekday = 2
        return c
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!
    private static let day: TimeInterval = 86_400

    // MARK: Strand builders

    static func ach(_ id: String, _ name: String, dueOffset: Double?) -> HorizonStrand {
        HorizonStrand(id: id, name: name, colorToken: "blue",
                      kind: .achievement(due: dueOffset.map { now.addingTimeInterval($0 * day) }),
                      type: .achievement)
    }
    static func maint(_ id: String, _ name: String, lastFedOffset: Double, gap: Double) -> HorizonStrand {
        HorizonStrand(id: id, name: name, colorToken: "green",
                      kind: .maintenance(lastFed: now.addingTimeInterval(lastFedOffset * day), typicalGap: gap * day),
                      type: .maintenance)
    }
    static func maintNoRhythm(_ id: String, _ name: String) -> HorizonStrand {
        HorizonStrand(id: id, name: name, colorToken: "green",
                      kind: .maintenance(lastFed: nil, typicalGap: nil), type: .maintenance)
    }

    private static func snapshot(_ active: [HorizonStrand], _ completed: [HorizonCompletion] = []) -> HorizonSnapshot {
        HorizonSnapshotBuilder.makeSnapshot(active: active, completed: completed, now: now, calendar: calendar)
    }

    // MARK: States

    static func mixed() -> HorizonSnapshot {
        snapshot([
            ach("overdue", "Ship TestFlight build", dueOffset: -2),   // today, pinned
            maint("longrun", "Weekly long run", lastFedOffset: -14, gap: 7), // today, pinned
            ach("portfolio", "Portfolio rebuild", dueOffset: 0),      // today, folds
            ach("read", "Read 30 pages", dueOffset: 0),               // today, folds
            ach("inbox", "Inbox zero", dueOffset: 0),                 // today, folds
            maint("ferns", "Water the ferns", lastFedOffset: -6, gap: 7), // tomorrow, loud
            ach("call", "Call the dentist", dueOffset: 1),            // tomorrow, folds
            ach("grant", "Grant application", dueOffset: 3),          // week, folds
            ach("taxes", "Quarterly taxes", dueOffset: 4),            // week, folds
            ach("m1", "Conference talk", dueOffset: 12),              // rest of month
            ach("m2", "Renew passport", dueOffset: 13),               // rest of month
            ach("novel", "Someday novel", dueOffset: nil),            // later
            maintNoRhythm("meditate", "Meditation (new)"),            // later
            ach("far", "Sabbatical plan", dueOffset: 60),             // later
        ], [
            HorizonCompletion(id: "c1", name: "Launch v1.0", colorToken: "purple",
                              completedAt: now.addingTimeInterval(-3 * day), origin: now.addingTimeInterval(-118 * day)),
            HorizonCompletion(id: "c2", name: "Half marathon", colorToken: "indigo",
                              completedAt: now.addingTimeInterval(-30 * day), origin: now.addingTimeInterval(-200 * day)),
        ])
    }

    static func empty() -> HorizonSnapshot { snapshot([]) }

    static func onlyMaintenance() -> HorizonSnapshot {
        snapshot([
            maint("longrun", "Weekly long run", lastFedOffset: -14, gap: 7),   // today, overdue
            maint("ferns", "Water the ferns", lastFedOffset: -6, gap: 7),      // tomorrow, approaching
            maint("dishes", "Kitchen reset", lastFedOffset: -4, gap: 7),       // week, quiet
            maint("plants", "Water the pothos", lastFedOffset: -3, gap: 14),   // week/later, quiet
            maintNoRhythm("meditate", "Meditation (new)"),                     // later
        ])
    }

    static func onlyAchievement() -> HorizonSnapshot {
        snapshot([
            ach("overdue", "Ship TestFlight build", dueOffset: -1),  // today, pinned
            ach("portfolio", "Portfolio rebuild", dueOffset: 0),     // today, folds
            ach("call", "Call the dentist", dueOffset: 1),           // tomorrow
            ach("grant", "Grant application", dueOffset: 4),         // week
            ach("m1", "Conference talk", dueOffset: 12),             // month
            ach("novel", "Someday novel", dueOffset: nil),           // later
        ])
    }

    static func overduePileUp() -> HorizonSnapshot {
        snapshot([
            ach("o1", "Ship TestFlight build", dueOffset: -5),
            ach("o2", "Submit grant", dueOffset: -3),
            ach("o3", "Reply to landlord", dueOffset: -2),
            ach("o4", "File reimbursement", dueOffset: -1),
            maint("o5", "Weekly long run", lastFedOffset: -21, gap: 7),
            maint("o6", "Call parents", lastFedOffset: -18, gap: 7),
        ])
    }
}
