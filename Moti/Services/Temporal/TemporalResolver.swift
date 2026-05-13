import Foundation

// Orchestrates the three-step temporal resolution pipeline:
//   Step 1: DeterministicPreClassifier  (regex + rules, always runs)
//   Step 2: SemanticContextResolver     (keyword bias, runs when any candidate is below 0.85)
//   Step 3: LLMTiebreaker               (stub SLM, runs per-candidate below 0.70 or ambiguous)
enum TemporalResolver {

    static func resolve(
        input: String,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [TemporalResolution] {
        // Step 1 — Deterministic (returns all non-overlapping matches)
        var candidates = DeterministicPreClassifier.classify(input: input, calendar: calendar, now: now)

        // If no candidates at all, emit a single noSignal sentinel
        if candidates.isEmpty {
            return [.noSignal(for: input)]
        }

        // If every candidate is noSignal, short-circuit
        if candidates.allSatisfy({ $0.resolverPath == .noSignal }) {
            return candidates
        }

        // Step 2 — Semantic context
        // Run when any non-noSignal candidate is unknown/ambiguous OR below 0.85
        let needsSemantic = candidates.contains {
            $0.resolverPath != .noSignal
            && ($0.interpretation == .unknown
                || $0.interpretation == .ambiguous
                || $0.confidence < 0.85)
        }
        if needsSemantic {
            candidates = SemanticContextResolver.resolve(candidates: candidates, input: input)
        }

        // Step 3 — LLM tiebreaker, applied per-candidate
        candidates = candidates.map { candidate in
            guard candidate.resolverPath != .noSignal,
                  candidate.confidence < 0.70 || candidate.interpretation == .ambiguous
            else { return candidate }
            return LLMTiebreaker.resolve(candidates: [candidate], input: input)
        }

        return candidates
    }
}
