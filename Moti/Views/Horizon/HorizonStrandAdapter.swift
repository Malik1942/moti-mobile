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
    /// - Maintenance → last activity as "last fed", and a typical gap chosen in
    ///   priority order (P3): the strand's **declared** cadence when it recurs;
    ///   else the PRD §11-exact derivation (`HorizonRhythm.typicalGap`, median of
    ///   the last 5 inter-event gaps, ≥3 events) over the strand's recent dated
    ///   traces — `lastTraces` is already capped at the 5 most recent events;
    ///   else the app's derived presence baseline. `nil` means no derivable
    ///   rhythm (the strand falls to Later with no feed-by copy).
    init(from strand: Strand) {
        let kind: HorizonItem.Kind
        switch strand.effectiveType {
        case .achievement:
            kind = .achievement(due: strand.deadline)
        case .maintenance:
            kind = .maintenance(lastFed: strand.presence.lastActivity,
                                typicalGap: Self.typicalGap(for: strand))
        }
        self.init(id: strand.id,
                  name: strand.name,
                  colorToken: strand.colorToken,
                  kind: kind,
                  type: strand.effectiveType,
                  divergence: nil) // Phase-2 seam
    }

    private static func typicalGap(for strand: Strand) -> TimeInterval? {
        if let declared = strand.recurrenceCadenceDays {
            return declared * 86_400
        }
        if let derived = HorizonRhythm.typicalGap(events: strand.lastTraces.map(\.date)) {
            return derived
        }
        return strand.presence.baselineCadenceDays.map { $0 * 86_400 }
    }
}
