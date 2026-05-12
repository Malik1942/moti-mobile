import Foundation

struct MockSLMTaskUnderstandingService: TaskUnderstandingService {
    private let base = RuleBasedTaskUnderstandingService()

    func parseMany(_ input: String) async throws -> [ParsedWorkItem] {
        let delay = UInt64.random(in: 300_000_000...800_000_000)
        try await Task.sleep(nanoseconds: delay)
        var parsedItems = try await base.parseMany(input)
        for index in parsedItems.indices {
            applyMockBehavior(input: parsedItems[index].rawInput, parsed: &parsedItems[index])
        }
        return parsedItems
    }

    func parse(_ input: String) async throws -> ParsedWorkItem {
        // This intentionally simulates imperfect local-model behavior for V1.
        // It is not a real SLM and does not run inference.
        let parsedItems = try await parseMany(input)
        if let first = parsedItems.first {
            return first
        }
        var fallback = try await base.parse(input)
        applyMockBehavior(input: input, parsed: &fallback)
        return fallback
    }

    private func applyMockBehavior(input: String, parsed: inout ParsedWorkItem) {
        parsed.parserConfidence = min(parsed.parserConfidence, 0.80)

        if input.range(of: #"\b\d+\s+to\s+\d+\b"#, options: .regularExpression) != nil {
            parsed.parserConfidence = max(0.0, parsed.parserConfidence - 0.15)
            parsed.title = input.replacingOccurrences(of: #"\b(\d+)\s+to\s+\d+\b"#, with: "$1", options: .regularExpression)
            parsed.title = DateResolver.removingDatePhrases(from: parsed.title)
            parsed.reviewReason = parsed.reviewReason ?? "Scope may need review"
        }
    }
}
