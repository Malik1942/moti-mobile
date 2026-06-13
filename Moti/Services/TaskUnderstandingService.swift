import SwiftUI

protocol TaskUnderstandingService {
    func parse(_ input: String) async throws -> ParsedWorkItem
    func parseMany(_ input: String) async throws -> [ParsedWorkItem]
}

extension TaskUnderstandingService {
    func parseMany(_ input: String) async throws -> [ParsedWorkItem] {
        [try await parse(input)]
    }
}

enum TaskUnderstandingError: LocalizedError {
    case foundationModelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .foundationModelUnavailable(let reason):
            "Foundation Model parsing is unavailable: \(reason)"
        }
    }
}

private struct TaskUnderstandingServiceKey: EnvironmentKey {
    static let defaultValue: any TaskUnderstandingService = RuleBasedTaskUnderstandingService()
}

extension EnvironmentValues {
    var taskUnderstandingService: any TaskUnderstandingService {
        get { self[TaskUnderstandingServiceKey.self] }
        set { self[TaskUnderstandingServiceKey.self] = newValue }
    }
}

enum CaptureSegmenter {
    static func segments(from input: String) -> [String] {
        let lineSegments = input
            .components(separatedBy: .newlines)
            .flatMap { line in
                line.components(separatedBy: ";")
            }
            .map(cleanSegment)
            .filter { !$0.isEmpty }

        guard lineSegments.count > 1 else {
            // Single line/clause group: a natural sentence may still list
            // several deliverables, each with its own deadline. Split on
            // comma/"and" boundaries ONLY when at least two clauses carry
            // their own date anchor — ordinary comma text ("buy milk, eggs,
            // and bread tomorrow") stays one capture.
            let single = lineSegments.first ?? cleanSegment(input)
            guard !single.isEmpty else { return [] }
            let clauses = deadlineClauses(from: single)
            return clauses.count > 1 ? clauses : [single]
        }
        return lineSegments
    }

    /// Splits a sentence into per-deadline clauses, or returns [] when the
    /// input isn't a multi-deadline list.
    ///
    /// Algorithm: split on comma / "and" boundaries; a fragment that carries
    /// no date anchor is glued to the NEXT fragment (lead-ins like "I have
    /// three things:" or shared objects like "prepare slides and"), and a
    /// trailing anchor-less fragment is glued to the previous one. Splitting
    /// happens only when at least two resulting clauses each own an anchor,
    /// so the title→deadline pairing the user wrote is preserved.
    private static func deadlineClauses(from text: String) -> [String] {
        // Cheap gate first: clause analysis only matters for multi-anchor input.
        guard TemporalAnchors.count(in: text) >= 2 else { return [] }

        let pattern = #"\s*,\s*(?:and\s+)?|\s+and\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }

        let ns = text as NSString
        var fragments: [String] = []
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let fragment = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if !fragment.trimmingCharacters(in: .whitespaces).isEmpty { fragments.append(fragment) }
            cursor = NSMaxRange(match.range)
        }
        let tail = ns.substring(from: cursor)
        if !tail.trimmingCharacters(in: .whitespaces).isEmpty { fragments.append(tail) }

        guard fragments.count > 1 else { return [] }

        var clauses: [String] = []
        var pending = ""
        for fragment in fragments {
            pending = pending.isEmpty ? fragment : "\(pending) and \(fragment)"
            if TemporalAnchors.containsAnchor(in: fragment) {
                clauses.append(pending)
                pending = ""
            }
        }
        if !pending.isEmpty {
            // Trailing fragment without its own deadline belongs to the last clause.
            if clauses.isEmpty { return [] }
            clauses[clauses.count - 1] += " and \(pending)"
        }

        let cleaned = clauses.map(cleanSegment).filter { !$0.isEmpty }
        return cleaned.count >= 2 ? cleaned : []
    }

    private static func cleanSegment(_ value: String) -> String {
        var segment = value.trimmingCharacters(in: .whitespacesAndNewlines)
        segment = segment.replacingOccurrences(
            of: #"^\s*(?:[-•*]|\d+[\.)])\s*"#,
            with: "",
            options: .regularExpression
        )
        return segment.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    }
}
