import Foundation

/// Lightweight, reversible per-strand UI preferences, kept entirely outside the
/// Projects task model (PRD: do not modify the task model). These hold the
/// user's *attention* choices — pausing a strand, parking it for the week,
/// lowering its priority — without ever touching their tasks.
///
/// Everything here is reversible by design (PRD §7: "All reversible. These
/// execute the user's choice; they never make the choice.").
///
/// Backed by `UserDefaults` so it is trivial, synchronous, and needs no schema
/// migration. Keyed by stable strand id.
@MainActor
final class StrandPreferenceStore: ObservableObject {
    static let shared = StrandPreferenceStore()

    private let defaults: UserDefaults
    private let pausedKey = "lifelines.pausedStrandIDs"
    private let loweredKey = "lifelines.loweredStrandIDs"
    /// Maps strand id → ISO week string it was parked in ("Not this week").
    private let parkedKey = "lifelines.parkedStrandWeek"

    /// Bumped on every mutation so SwiftUI views observing the store refresh.
    @Published private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Paused (deliberate set-down — dashed + label on the axis)

    func isPaused(_ strandID: String) -> Bool {
        pausedIDs.contains(strandID)
    }

    func setPaused(_ paused: Bool, for strandID: String) {
        var ids = pausedIDs
        if paused { ids.insert(strandID) } else { ids.remove(strandID) }
        defaults.set(Array(ids), forKey: pausedKey)
        bump()
    }

    // MARK: Lowered priority (recedes further; still present)

    func isLowered(_ strandID: String) -> Bool {
        loweredIDs.contains(strandID)
    }

    func setLowered(_ lowered: Bool, for strandID: String) {
        var ids = loweredIDs
        if lowered { ids.insert(strandID) } else { ids.remove(strandID) }
        defaults.set(Array(ids), forKey: loweredKey)
        bump()
    }

    // MARK: "Not this week" (peaceful park for the current week, auto-expires)

    /// True when the strand was parked during the current ISO week.
    func isParkedThisWeek(_ strandID: String, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let stored = parkedMap[strandID] else { return false }
        return stored == Self.weekKey(for: now, calendar: calendar)
    }

    func parkForThisWeek(_ strandID: String, now: Date = .now, calendar: Calendar = .current) {
        var map = parkedMap
        map[strandID] = Self.weekKey(for: now, calendar: calendar)
        defaults.set(map, forKey: parkedKey)
        bump()
    }

    func unpark(_ strandID: String) {
        var map = parkedMap
        map.removeValue(forKey: strandID)
        defaults.set(map, forKey: parkedKey)
        bump()
    }

    // MARK: - Internals

    private var pausedIDs: Set<String> { Set(defaults.stringArray(forKey: pausedKey) ?? []) }
    private var loweredIDs: Set<String> { Set(defaults.stringArray(forKey: loweredKey) ?? []) }
    private var parkedMap: [String: String] { (defaults.dictionary(forKey: parkedKey) as? [String: String]) ?? [:] }

    private func bump() { revision &+= 1 }

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }
}
