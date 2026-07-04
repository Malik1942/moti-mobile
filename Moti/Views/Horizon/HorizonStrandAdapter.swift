import Foundation

// Horizon Timeline v2 — the domain ↔ app seam. Maps the app's render-ready
// `Strand` value type into the domain's `HorizonStrand`, extracting only what
// Horizon needs. The trajectory *engine* types (`TrajectoryProjection`, etc.)
// deliberately do NOT cross this boundary in Phase 1 — the divergence read
// (`HorizonDivergence`) is left nil until Phase 2, when this adapter fills it.

extension HorizonStrand {
    /// Build a Horizon strand from an app `Strand`.
    ///
    /// - Achievement → its `deadline` (optional; nil = no landing set).
    /// - Maintenance → last activity as "last fed", and a typical gap taken from
    ///   the strand's **declared** cadence when it recurs, else the app's derived
    ///   presence baseline. Both are already in days; nil means no derivable
    ///   rhythm (the strand falls to Later with no feed-by copy).
    init(from strand: Strand) {
        let kind: HorizonItem.Kind
        switch strand.effectiveType {
        case .achievement:
            kind = .achievement(due: strand.deadline)
        case .maintenance:
            let cadenceDays = strand.recurrenceCadenceDays ?? strand.presence.baselineCadenceDays
            kind = .maintenance(lastFed: strand.presence.lastActivity,
                                typicalGap: cadenceDays.map { $0 * 86_400 })
        }
        self.init(id: strand.id,
                  name: strand.name,
                  colorToken: strand.colorToken,
                  kind: kind,
                  type: strand.effectiveType,
                  divergence: nil) // Phase-2 seam
    }
}
