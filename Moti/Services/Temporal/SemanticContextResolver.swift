import Foundation

enum SemanticContextResolver {

    // Adjusts confidence on each candidate using keyword bias from the surrounding sentence.
    // Returns candidates unchanged (same resolverPath) when no bias applies.
    // Sets resolverPath = .semantic on any candidate whose confidence changes.
    static func resolve(candidates: [TemporalResolution], input: String) -> [TemporalResolution] {
        let text = input.lowercased()

        let hasEvent = SemanticBias.eventKeywords.contains { text.contains($0) }
        let hasTask  = SemanticBias.taskKeywords.contains  { text.contains($0) }

        return candidates.map { candidate in
            var delta = 0.0

            switch candidate.interpretation {
            case .calendarDate:
                if hasEvent && !hasTask  { delta = +0.15 }
                if hasEvent && hasTask   { delta = -0.10 }

            case .relativeDuration:
                if hasTask  && !hasEvent { delta = +0.15 }
                if hasEvent && !hasTask  { delta = -0.10 }
                if hasEvent && hasTask   { delta = -0.10 }

            case .clockTime, .ambiguous, .unknown:
                break
            }

            guard delta != 0.0 else { return candidate }
            return candidate.withConfidence(candidate.confidence + delta, resolverPath: .semantic)
        }
    }
}
