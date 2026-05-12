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
