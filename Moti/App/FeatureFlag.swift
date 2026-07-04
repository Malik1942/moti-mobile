import Foundation

// Horizon Timeline v2 — P1. A single, canonical home for feature flags, so keys
// are not hand-duplicated across views (the pattern the older
// `"useTrajectoryTimeline"` string fell into). Each case's raw value IS its
// UserDefaults / @AppStorage key.

enum FeatureFlag: String, CaseIterable {
    /// Horizon: the bucket-based temporal queue as the Timeline tab's root,
    /// demoting the axis view to a reachable Map. **Off by default** — flag off
    /// is the current app, byte-for-byte.
    case horizonTimeline = "featureFlag.horizonTimeline"

    var defaultValue: Bool { false }

    /// Non-view read (defaults to `defaultValue` when unset).
    var isOn: Bool {
        UserDefaults.standard.object(forKey: rawValue) as? Bool ?? defaultValue
    }

    /// Human label for the DEBUG Settings toggle.
    var label: String {
        switch self {
        case .horizonTimeline: return "Horizon Timeline (v2)"
        }
    }
}
