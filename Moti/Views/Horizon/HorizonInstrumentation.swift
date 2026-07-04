import Combine
import Foundation

// Horizon Timeline v2 — T13. Local-only event logging for the dogfooding
// protocol (PRD §10). No network; events persist in UserDefaults (capped) and
// are exportable as plain text. Mirrors the existing TrajectoryInstrumentation.

struct HorizonEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case horizonOpen            // Horizon surface appeared
        case scanSessionLength      // foreground→background delta while visible (seconds in detail)
        case bucketExpand           // a fold/bucket was expanded (bucket in detail)
        case mapOpen                // the axis Map was opened
        case pastOpen               // the Past region was revealed
    }
    let id: UUID
    let kind: Kind
    let timestamp: Date
    /// Kind-specific payload: bucket raw value, or a duration in seconds.
    let detail: String?
}

final class HorizonInstrumentation: ObservableObject {
    static let shared = HorizonInstrumentation()

    @Published private(set) var events: [HorizonEvent] = []

    private let defaults: UserDefaults
    private let storageKey = "horizon.events.v1"
    private let cap = 1000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([HorizonEvent].self, from: data) {
            events = decoded
        }
    }

    func record(_ kind: HorizonEvent.Kind, detail: String? = nil,
                id: UUID = UUID(), at timestamp: Date = Date()) {
        events.append(HorizonEvent(id: id, kind: kind, timestamp: timestamp, detail: detail))
        if events.count > cap { events.removeFirst(events.count - cap) }
        persist()
    }

    func reset() {
        events = []
        defaults.removeObject(forKey: storageKey)
    }

    /// A copy-pasteable log (most recent last) for the dogfooding debug view.
    func exportText() -> String {
        let iso = ISO8601DateFormatter()
        return events.map { e in
            let d = e.detail.map { " \($0)" } ?? ""
            return "\(iso.string(from: e.timestamp)) \(e.kind.rawValue)\(d)"
        }.joined(separator: "\n")
    }

    /// Count of a given event kind — for at-a-glance dogfooding checks.
    func count(_ kind: HorizonEvent.Kind) -> Int {
        events.lazy.filter { $0.kind == kind }.count
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
