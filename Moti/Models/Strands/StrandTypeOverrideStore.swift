#if DEBUG
import Foundation

/// DEBUG-only manual type overrides, keyed by strand id. There is **no user
/// entry point** — this exists so the type ladder (`Strand.userOverrideType` /
/// `effectiveType`) is exercisable while dogfooding, and so a later phase can add
/// real user override without reworking the shape.
///
/// Crucially, overrides live here (UserDefaults), never as SwiftData model
/// fields, and strands are recomputed every render. So when v2 wants to record a
/// `computedTypeAtOverride` audit value (what the algorithm thought at the moment
/// the user overrode), it can store a richer value type under this same key with
/// **no data migration**. Do not add that field now.
@MainActor
final class StrandTypeOverrideStore: ObservableObject {
    static let shared = StrandTypeOverrideStore()

    private let defaults: UserDefaults
    private let key = "trajectory.debug.typeOverrides.v1"

    @Published private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Current override map (strand id → forced type).
    var overrides: [String: StrandType] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: String] else { return [:] }
        return raw.reduce(into: [:]) { acc, pair in
            if let t = StrandType(rawValue: pair.value) { acc[pair.key] = t }
        }
    }

    func setOverride(_ type: StrandType?, for strandID: String) {
        var raw = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        if let type { raw[strandID] = type.rawValue } else { raw.removeValue(forKey: strandID) }
        defaults.set(raw, forKey: key)
        revision &+= 1
    }

    func clearAll() {
        defaults.removeObject(forKey: key)
        revision &+= 1
    }
}
#endif
