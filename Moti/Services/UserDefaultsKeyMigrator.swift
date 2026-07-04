import Foundation

/// One-time, idempotent migration of renamed `UserDefaults` keys.
///
/// The v2.1 vocabulary cleanup renamed the legacy `useLifelineTimeline` flag and
/// the `lifelines.*Strand*` preference keys. Renaming a persisted key would
/// otherwise silently orphan the stored value (a user who enabled the trajectory
/// timeline, or paused/parked strands, would lose that state). This copies each
/// legacy key's value to its canonical name and removes the old key.
///
/// Idempotent by construction: once migrated the legacy keys are gone, so every
/// subsequent launch is a no-op. Never clobbers a value already present under
/// the new key. Modeled on `ProjectRelationshipMigrator`.
enum UserDefaultsKeyMigrator {
    /// `(legacy, canonical)` key pairs. The copy goes through
    /// `object(forKey:)` / `set(_:forKey:)`, which are type-agnostic — so
    /// `Bool` (the flag), `[String]` (paused/lowered IDs), and `[String: String]`
    /// (parked/spaced week maps) all migrate without per-type handling.
    private static let renames: [(old: String, new: String)] = [
        ("useLifelineTimeline",        "useTrajectoryTimeline"),
        ("lifelines.pausedStrandIDs",  "strand.pausedIDs"),
        ("lifelines.loweredStrandIDs", "strand.loweredIDs"),
        ("lifelines.parkedStrandWeek", "strand.parkedWeek"),
        ("lifelines.spacedStrandWeek", "strand.spacedWeek"),
    ]

    static func run(_ defaults: UserDefaults = .standard) {
        var migrated = 0
        for (old, new) in renames {
            // Nothing stored under the legacy key → nothing to migrate.
            guard let value = defaults.object(forKey: old) else { continue }
            // Don't overwrite a value already written under the canonical key.
            if defaults.object(forKey: new) == nil {
                defaults.set(value, forKey: new)
            }
            defaults.removeObject(forKey: old)
            migrated += 1
        }
        #if DEBUG
        if migrated > 0 {
            print("[Migration] Migrated \(migrated) legacy UserDefaults key(s) to canonical names.")
        }
        #endif
    }
}
