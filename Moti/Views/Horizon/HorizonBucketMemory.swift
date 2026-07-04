import Combine
import Foundation

// Horizon Timeline v2 — T15 support. Remembers which bucket each strand sat in
// last time, so the next snapshot can tell which strands moved *toward* Now and
// animate them in ("time visibly pushes things toward you"). Persisted so the
// diff survives a background/relaunch.

final class HorizonBucketMemory: ObservableObject {
    private let defaults: UserDefaults
    private let key = "horizon.lastBuckets.v1"
    private var lastByStrand: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastByStrand = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    /// Strand ids that sit in a strictly nearer bucket than last recorded.
    /// Empty on the very first open (nothing to compare against — we don't
    /// animate the whole first paint). Brand-new strands are *not* treated as
    /// migrations (they appeared, they didn't move).
    func migratedIDs(in snapshot: HorizonSnapshot) -> Set<String> {
        guard !lastByStrand.isEmpty else { return [] }
        var migrated: Set<String> = []
        for section in snapshot.sections {
            let ordinal = section.bucket.ordinal
            for id in section.allStrandIDs {
                if let previous = lastByStrand[id], ordinal < previous {
                    migrated.insert(id)
                }
            }
        }
        return migrated
    }

    /// Persist the current snapshot's strand→bucket ordinals for next time.
    func record(_ snapshot: HorizonSnapshot) {
        var map: [String: Int] = [:]
        for section in snapshot.sections {
            let ordinal = section.bucket.ordinal
            for id in section.allStrandIDs { map[id] = ordinal }
        }
        lastByStrand = map
        defaults.set(map, forKey: key)
    }
}
