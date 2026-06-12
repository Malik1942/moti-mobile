import Foundation
import os

// MARK: - Coverage snapshot (the load-bearing metric)

/// A live snapshot of how many strands actually have behavioral events to stand
/// on, broken down by effective type. This directly measures the
/// maintenance-starvation risk (PRD §13, strand-definition open question): if a
/// large fraction of *maintenance* strands have zero events, they render
/// Drifted/absent simply because nothing feeds them in real use — which would
/// tell us v1 needs a maintenance "touch" path before it's trustworthy.
///
/// Computed on demand from the current strands; never stored.
struct StrandCoverageSnapshot: Equatable {
    var achievementTotal = 0
    var achievementZeroEvents = 0
    var maintenanceTotal = 0
    var maintenanceZeroEvents = 0

    var total: Int { achievementTotal + maintenanceTotal }
    var zeroEvents: Int { achievementZeroEvents + maintenanceZeroEvents }

    func zeroFraction(for type: String?) -> Double {
        switch type {
        case "achievement": return fraction(achievementZeroEvents, achievementTotal)
        case "maintenance": return fraction(maintenanceZeroEvents, maintenanceTotal)
        default:            return fraction(zeroEvents, total)
        }
    }

    private func fraction(_ n: Int, _ d: Int) -> Double { d == 0 ? 0 : Double(n) / Double(d) }
}

// MARK: - Metric record

/// One timestamped local signal. Holds only ids / types / states — never titles
/// or any other PII, and never leaves the device.
struct LifelineMetricRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case open       // timeline appeared
        case close      // timeline disappeared
        case surface    // a drifted strand was surfaced in "What matters now"
        case outcome    // the user acted on a surfaced/peeked strand
        case peek       // a strand line was tapped
    }

    var id = UUID()
    let kind: Kind
    let timestamp: Date
    var strandID: String?
    var effectiveType: String?
    var presenceState: String?
    /// Free-form, low-cardinality tag: "glance-close" | "tapped" | "make-space"
    /// | "not-this-week" | "lowered" | "ignored".
    var detail: String?
}

// MARK: - Instrumentation store

/// Local-only, on-device instrumentation for the Lifelines Timeline. No backend,
/// no PII off-device. It is a measurement tool (read in the DEBUG Settings panel
/// or via os_log), not a product feature — and it only ever runs while the
/// flagged timeline is on screen, so it costs nothing for normal users.
@MainActor
final class LifelineInstrumentation: ObservableObject {
    static let shared = LifelineInstrumentation()

    private let defaults: UserDefaults
    private let storageKey = "lifelines.metrics.records.v1"
    private let cap = 200
    private let logger = Logger(subsystem: "com.malik.Moti", category: "LifelineMetrics")

    @Published private(set) var records: [LifelineMetricRecord] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Recording

    func record(
        _ kind: LifelineMetricRecord.Kind,
        strandID: String? = nil,
        effectiveType: String? = nil,
        presenceState: String? = nil,
        detail: String? = nil
    ) {
        let entry = LifelineMetricRecord(
            kind: kind, timestamp: .now, strandID: strandID,
            effectiveType: effectiveType, presenceState: presenceState, detail: detail
        )
        records.append(entry)
        if records.count > cap { records.removeFirst(records.count - cap) }
        persist()
        logger.log("\(kind.rawValue, privacy: .public) type=\(effectiveType ?? "-", privacy: .public) state=\(presenceState ?? "-", privacy: .public) detail=\(detail ?? "-", privacy: .public)")
    }

    func clear() {
        records.removeAll()
        persist()
    }

    // MARK: Derived aggregates (for the DEBUG panel)

    var openCount: Int { records.filter { $0.kind == .open }.count }
    var closeCount: Int { records.filter { $0.kind == .close }.count }
    var glanceCloseCount: Int { records.filter { $0.kind == .close && $0.detail == "glance-close" }.count }

    /// Fraction of closes that were a pure glance (no strand tapped) — the
    /// calm-day signal. `nil` until there is at least one close.
    var glanceAndCloseRate: Double? {
        closeCount == 0 ? nil : Double(glanceCloseCount) / Double(closeCount)
    }

    var surfaceCount: Int { records.filter { $0.kind == .surface }.count }

    /// Tally of how surfaced strands resolved.
    /// keys: "make-space" (re-engaged), "not-this-week" (parked), "lowered",
    /// "ignored" (surfaced but closed with no action).
    var surfacedOutcomeTally: [String: Int] {
        var out: [String: Int] = [:]
        for r in records where r.kind == .outcome {
            guard let d = r.detail else { continue }
            out[d, default: 0] += 1
        }
        return out
    }

    /// Live coverage snapshot from the current strands (not stored).
    func coverage(for strands: [Strand]) -> StrandCoverageSnapshot {
        var snap = StrandCoverageSnapshot()
        for strand in strands {
            let zero = strand.eventCount == 0
            switch strand.effectiveType {
            case .achievement:
                snap.achievementTotal += 1
                if zero { snap.achievementZeroEvents += 1 }
            case .maintenance:
                snap.maintenanceTotal += 1
                if zero { snap.maintenanceZeroEvents += 1 }
            }
        }
        return snap
    }

    // MARK: Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([LifelineMetricRecord].self, from: data)
        else { return }
        records = decoded
    }
}
