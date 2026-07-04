import Foundation

// Horizon Timeline v2 — the domain's render-ready strand model. Pure,
// Foundation-only. Built from the app's `Strand` value type by an adapter (a
// later, non-domain file); the trajectory *engine* types never reach here — the
// adapter extracts only what Horizon needs. This is what keeps Workstream 1
// pure and the Phase-2 seam explicit.

/// A strand ready for the Horizon snapshot: stable identity + the bucketing
/// inputs + an optional Phase-2 divergence read.
struct HorizonStrand: Equatable, Identifiable {
    /// Stable identity (the `Strand.id`).
    let id: String
    let name: String
    /// Identity color token (stable per future) — never a status scale.
    let colorToken: String
    /// Achievement (a landing) or maintenance (a rhythm), with the dates
    /// bucketing needs. Mirrors `HorizonItem.Kind`.
    let kind: HorizonItem.Kind
    /// The achievement/maintenance classification, surfaced for the row glyph.
    let type: StrandType
    /// **Phase-2 seam.** The engine's divergence read, populated by the adapter
    /// from `TrajectoryProjection`. Always `nil` in Phase 1 (design in, build
    /// nothing) — so a `DivergenceQuietnessProvider` and the row second line can
    /// land later with no change to this file's shape.
    let divergence: HorizonDivergence?

    init(id: String, name: String, colorToken: String, kind: HorizonItem.Kind,
         type: StrandType, divergence: HorizonDivergence? = nil) {
        self.id = id
        self.name = name
        self.colorToken = colorToken
        self.kind = kind
        self.type = type
        self.divergence = divergence
    }

    /// The minimal value bucket assignment consumes (T2).
    var item: HorizonItem { HorizonItem(id: id, kind: kind) }
}

/// **Phase-2 seam.** The engine's divergence read for a strand — the "time
/// actually required at current pace" re-expressed as data. Absent in Phase 1.
///
/// Design in now, build nothing: the adapter will fill `requiredDuration` from
/// the engine (it maps onto `CountdownPayload.requiredDuration`), and
/// `exceedsThreshold` gates the row's amber second line (PRD §6.3). Phase-2's
/// fallback "direction before precision" ("trending later") rides `direction`
/// when precision is not yet trustworthy (PRD §9).
struct HorizonDivergence: Equatable {
    enum Direction: Equatable { case onTrack, trendingLater }
    /// Projected time actually required at the current pace ("needs Xd"). May be
    /// `nil` when the engine cannot produce a trustworthy number.
    let requiredDuration: TimeInterval?
    /// Whether the projection diverges past the display threshold (PRD §6.3).
    let exceedsThreshold: Bool
    /// Coarse direction, used when precision is withheld (PRD §9 Phase-2 gate).
    let direction: Direction
}
