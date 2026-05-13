import SwiftUI

protocol TaskUnderstandingService {
    // Primary parse — accepts pre-resolved temporal context.
    // Pass an empty array to fall back to internal DateResolver (deprecated path, kept for tests).
    func parse(_ input: String, temporalResolutions: [TemporalResolution]) async throws -> ParsedWorkItem

    // Multi-item parse. Default resolves temporal per segment via TemporalResolver.
    func parseMany(_ input: String) async throws -> [ParsedWorkItem]
}

extension TaskUnderstandingService {
    // Convenience: resolve temporal then delegate to the primary signature.
    func parse(_ input: String) async throws -> ParsedWorkItem {
        let resolutions = TemporalResolver.resolve(input: input)
        return try await parse(input, temporalResolutions: resolutions)
    }

    // Default multi-item: segment → resolve per segment → parse.
    func parseMany(_ input: String) async throws -> [ParsedWorkItem] {
        let segments = CaptureSegmenter.segments(from: input)
        let effective = segments.isEmpty ? [input] : segments
        var results: [ParsedWorkItem] = []
        for segment in effective {
            let resolutions = TemporalResolver.resolve(input: segment)
            results.append(try await parse(segment, temporalResolutions: resolutions))
        }
        return results
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

        return lineSegments.isEmpty ? [cleanSegment(input)].filter { !$0.isEmpty } : lineSegments
    }

    private static func cleanSegment(_ value: String) -> String {
        var segment = value.trimmingCharacters(in: .whitespacesAndNewlines)
        segment = segment.replacingOccurrences(
            of: #"^\s*(?:[-•*]|\d+[\.)])\s*"#,
            with: "",
            options: .regularExpression
        )
        return segment.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
