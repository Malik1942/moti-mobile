import Foundation

// V1 stub: returns the highest-confidence candidate with a small random confidence
// jitter and resolverPath = .llmTiebreaker. When Foundation Models is integrated,
// this becomes the real SLM call using the prompt structure below.
enum LLMTiebreaker {

    static func resolve(candidates: [TemporalResolution], input: String) -> TemporalResolution {
        guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else {
            return .noSignal(for: input)
        }

        let jitter = Double.random(in: -0.05...0.05)
        let adjusted = min(max(best.confidence + jitter, 0.0), 1.0)

        #if DEBUG
        print("[LLMTiebreaker] invoked for: \"\(input.prefix(60))\" — best=\(best.interpretation.rawValue) conf=\(String(format: "%.2f", best.confidence))")
        #endif

        return best.withConfidence(adjusted, resolverPath: .llmTiebreaker)
    }

    // Prompt template kept here for when the real SLM is wired in.
    // The response is expected as JSON: { interpretation, selectedCandidateIndex, reasoning }
    static func prompt(for input: String, candidates: [TemporalResolution]) -> String {
        let candidateLines = candidates.enumerated().map { i, c in
            "- \(c.interpretation.rawValue): \(c.originalText), confidence \(String(format: "%.2f", c.confidence))"
        }.joined(separator: "\n")

        return """
        You are a temporal classification assistant. The user input is:
        "\(input)"

        A deterministic layer found these candidates:
        \(candidateLines)

        Pick the most likely interpretation. If neither makes sense, respond with "unknown".

        Respond as JSON only:
        {
          "interpretation": "calendarDate | relativeDuration | clockTime | unknown",
          "selectedCandidateIndex": 0,
          "reasoning": "short explanation, one sentence"
        }
        """
    }
}
