import Foundation

/// Resolves the best-matching existing `Project` for a parsed work item.
///
/// Matching strategy (highest-confidence first; stops at the first match):
///   1. **Exact** case-insensitive match of the parser's project hint against
///      an existing project name.
///   2. **Substring** match in either direction — e.g. parser hint "Portfolio"
///      matches an existing project "My Portfolio", or hint "Aura App" matches
///      project "Aura".
///   3. **Token overlap** — splits the task title + raw input into words,
///      lower-cases them, drops short/stop words, and stems trailing 's'.
///      Scores each project by how many of its name tokens appear in the
///      task's tokens; returns the highest-scoring project when score > 0.
///
/// All modes (Foundation Model, rule-based, Smart Capture) call this from the
/// view layer after parsing, so a parser that returns a slightly-off hint
/// (e.g. "Job Search" when the user actually named their project "Q4 Job Hunt")
/// still lands the work item in the right place.
enum ProjectMatcher {

    /// Finds the best-matching existing project, or `nil` if no candidate scores.
    ///
    /// - Parameters:
    ///   - projectHint: Whatever the parser inferred — e.g. `ParsedWorkItem.projectGuess`
    ///     or `ContextualCaptureDecision.inferredProjectName`. May be nil.
    ///   - taskTitle: Normalized work-item title. Used for token overlap matching.
    ///   - rawInput: The original capture text. Used for token overlap matching.
    ///   - existingProjects: The user's current projects.
    static func match(
        projectHint: String?,
        taskTitle: String,
        rawInput: String,
        existingProjects: [Project]
    ) -> Project? {
        guard !existingProjects.isEmpty else { return nil }

        // 1. Exact (case-insensitive) match against the hint.
        if let hint = normalize(projectHint), !hint.isEmpty {
            if let exact = existingProjects.first(where: {
                $0.name.localizedCaseInsensitiveCompare(hint) == .orderedSame
            }) {
                return exact
            }

            // 2. Substring containment (either direction).
            //    "Portfolio" matches "My Portfolio".
            //    "Aura App" matches "Aura".
            let loweredHint = hint.lowercased()
            for project in existingProjects {
                let loweredName = project.name.lowercased()
                if loweredName.count >= 3,
                   loweredHint.count >= 3,
                   (loweredName.contains(loweredHint) || loweredHint.contains(loweredName)) {
                    return project
                }
            }
        }

        // 3. Token overlap on (title + rawInput) vs project name tokens.
        let taskTokens = stemmedTokens(in: "\(taskTitle) \(rawInput)")
        guard !taskTokens.isEmpty else { return nil }

        var bestScore = 0
        var bestProject: Project?
        for project in existingProjects {
            let projectTokens = stemmedTokens(in: project.name)
            let overlap = projectTokens.intersection(taskTokens).count
            if overlap > bestScore {
                bestScore = overlap
                bestProject = project
            }
        }
        return bestScore > 0 ? bestProject : nil
    }

    // MARK: - Private helpers

    private static func normalize(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if trimmed.localizedCaseInsensitiveCompare("Uncategorized") == .orderedSame {
            return nil
        }
        return trimmed
    }

    /// Tokenizes a string: lowercases, strips punctuation, drops words < 3 chars
    /// and common English stop words, and stems trailing 's' on words ≥ 4 chars
    /// so "jobs" matches "job".
    private static func stemmedTokens(in string: String) -> Set<String> {
        var tokens: Set<String> = []
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        for piece in string.lowercased().components(separatedBy: separators) {
            let trimmed = piece.trimmingCharacters(in: separators)
            guard trimmed.count >= 3, !stopWords.contains(trimmed) else { continue }
            tokens.insert(stem(trimmed))
        }
        return tokens
    }

    private static func stem(_ word: String) -> String {
        guard word.count >= 4, word.hasSuffix("s") else { return word }
        return String(word.dropLast())
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "this", "that",
        "have", "has", "are", "was", "but", "not", "you", "your",
        "our", "their", "them", "they", "his", "her", "its",
        "all", "any", "out", "off", "via", "per", "ish",
        "yet", "now", "just", "more", "less", "very", "much"
    ]
}
