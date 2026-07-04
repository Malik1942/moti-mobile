import Foundation
import Combine

// Horizon Timeline v2 — fold expansion state (PRD §6.4 / P1.4). Which folds the
// user has opened. Persisted per calendar day and reset daily: a new day opens
// fully folded again, so visual density returns to problem density each morning.

final class HorizonFoldStore: ObservableObject {
    @Published private var expanded: Set<String>

    private let defaults: UserDefaults
    private let stamp: String
    private let expandedKey = "horizon.folds.expanded.v1"
    private let dayKey = "horizon.folds.day.v1"

    init(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.stamp = Self.dayStamp(now, calendar)

        if defaults.string(forKey: dayKey) == stamp {
            expanded = Set(defaults.stringArray(forKey: expandedKey) ?? [])
        } else {
            // New day (or first run) → start fully folded and reset storage.
            expanded = []
            defaults.set(stamp, forKey: dayKey)
            defaults.removeObject(forKey: expandedKey)
        }
    }

    func isExpanded(_ id: String) -> Bool { expanded.contains(id) }

    func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        defaults.set(Array(expanded), forKey: expandedKey)
        defaults.set(stamp, forKey: dayKey)
    }

    /// A stable per-day key (locale-independent).
    static func dayStamp(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
