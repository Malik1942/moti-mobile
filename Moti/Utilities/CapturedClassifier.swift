import Foundation

enum CapturedClassifier {
    /// Fast-path imperative action verbs. A capture whose action is one of
    /// these is actionable without any further analysis. Kept as an explicit
    /// list (not POS tagging) because it's fully deterministic and identical
    /// across simulator, CI, and device — `NLTagger`'s `.lexicalClass` scheme
    /// returns `OtherWord` for every token in the test/CI environment (the POS
    /// model isn't bundled), so it can't be a reliable signal here.
    static let actionVerbs = [
        // Original set
        "revise", "write", "send", "email", "call", "prep", "prepare", "finish", "submit",
        "apply", "buy", "schedule", "review", "draft", "build", "ship", "post", "read",
        "watch", "organize", "plan", "fix", "update", "add", "remove", "contact",
        "talk", "follow up", "reach out", "ask", "work", "meet", "interview",
        "complete", "start", "make", "create", "study", "upload", "record",
        // Everyday actions — common in personal capture, previously unrecognized
        "renew", "pay", "clean", "book", "cancel", "print", "pack", "mail", "file",
        "sign", "register", "enroll", "deposit", "withdraw", "transfer", "return",
        "replace", "repair", "refill", "install", "download", "order", "reserve",
        "confirm", "reschedule", "water", "wash", "feed", "walk", "vote", "donate",
        "attend", "join", "scan", "charge", "restart", "publish", "deploy", "rename",
        "delete", "archive", "cook", "bake", "fetch", "fill", "wrap", "drop", "move",
        "set up", "sign up", "back up", "pick up", "drop off", "check in", "check out",
        "clean up", "fill out", "fill in"
    ]

    /// Cognition / emotion / stative verbs that do NOT make an atomic task on
    /// their own. Used by the structural detector so "I need to think about my
    /// future" or "I want to feel less stressed" stay reflective, not concrete
    /// tasks. Deliberately NOT in `actionVerbs`, so a bare "Think about X" never
    /// fast-paths to actionable either.
    static let nonActionVerbs: Set<String> = [
        "think", "consider", "ponder", "reflect", "wonder", "dream", "imagine",
        "brainstorm", "feel", "want", "wish", "hope", "love", "hate", "like",
        "miss", "fear", "worry", "believe", "know", "guess", "suppose", "assume",
        "doubt", "realize", "understand", "prefer", "enjoy", "regret", "remember",
        "be", "am", "is", "are", "was", "were", "seem", "become"
    ]

    /// Personal-intent lead-ins. The word that FOLLOWS one of these is, in
    /// English, almost always the action verb — "I need to <verb>", "have to
    /// <verb>", "please <verb>". This is what lets Moti recognize an action
    /// whose verb isn't in `actionVerbs`, deterministically and without a POS
    /// model. Order longest-first so "i need to" wins over a bare "need to".
    static let intentLeadIns = [
        "i need to ", "i have to ", "i would like to ", "i want to ", "i should ",
        "i must ", "i gotta ", "i've got to ", "i have got to ",
        "need to ", "have to ", "want to ", "got to ", "gotta ",
        "please ", "remember to ", "make sure to ", "don't forget to ", "dont forget to "
    ]

    /// Words that can sit right after a lead-in but are never the action verb
    /// (so "I need to the dentist" — a fragment — isn't misread as a verb).
    private static let structuralStopWords: Set<String> = [
        "the", "a", "an", "my", "your", "our", "their", "his", "her", "its",
        "this", "that", "these", "those", "it", "them", "some", "any", "more",
        "about", "of", "for", "to", "and", "or", "be"
    ]

    static let vagueFillers = ["stuff", "thing", "figure out", "deal with", "handle"]

    /// True when the capture expresses a concrete action — either a known
    /// imperative verb (fast path) or a verb implied by a personal-intent
    /// lead-in (structural path). Cognition/emotion verbs and vague fillers
    /// never qualify, so reflective or emotional statements aren't actions.
    static func hasActionVerb(_ input: String) -> Bool {
        let text = input.lowercased()
        if matchesVerbList(text) { return true }
        if let word = wordAfterLeadIn(text), isLikelyActionWord(word) { return true }
        return false
    }

    private static func matchesVerbList(_ text: String) -> Bool {
        actionVerbs.contains { verb in
            text == verb || text.hasPrefix("\(verb) ") || text.contains(" \(verb) ")
        }
    }

    /// The first word following a personal-intent lead-in, or nil if the input
    /// doesn't start that way.
    private static func wordAfterLeadIn(_ text: String) -> String? {
        for lead in intentLeadIns {
            guard let range = text.range(of: lead) else { continue }
            // Only honor a lead-in at the very start, or right after a clause
            // boundary — avoids matching "have to" inside "I don't have to ask".
            let prefix = text[text.startIndex..<range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            guard prefix.isEmpty || prefix.hasSuffix(",") || prefix.hasSuffix(":") else { continue }
            let rest = text[range.upperBound...]
            guard let first = rest.split(whereSeparator: { $0 == " " }).first else { return nil }
            return String(first).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?'\""))
        }
        return nil
    }

    /// A post-lead-in word counts as an action unless it's a cognition/emotion
    /// verb, a vague filler, or a structural stop word.
    private static func isLikelyActionWord(_ word: String) -> Bool {
        let w = word.lowercased()
        guard !w.isEmpty else { return false }
        if nonActionVerbs.contains(w) { return false }
        if structuralStopWords.contains(w) { return false }
        if vagueFillers.contains(where: { w == $0 || $0.contains(w) }) { return false }
        return true
    }

    static func isVeryVague(_ input: String) -> Bool {
        let text = input.lowercased()
        return vagueFillers.contains { text.contains($0) }
    }

    static func hasPersonWithoutContext(_ input: String) -> Bool {
        let words = input.split(separator: " ")
        guard words.count >= 2 else { return false }
        return words.enumerated().contains { index, word in
            index > 0 && word.first?.isUppercase == true
        }
    }

    static func shouldCapture(input: String, hasDate: Bool, hasVerb: Bool) -> Bool {
        let wordCount = input.split(separator: " ").count
        return (wordCount < 4 && !hasDate) || !hasVerb || isVeryVague(input)
    }
}
