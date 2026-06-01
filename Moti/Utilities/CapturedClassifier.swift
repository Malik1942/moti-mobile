import Foundation

enum CapturedClassifier {
    static let actionVerbs = [
        "revise", "write", "send", "email", "call", "prep", "prepare", "finish", "submit",
        "apply", "buy", "schedule", "review", "draft", "build", "ship", "post", "read",
        "watch", "organize", "plan", "fix", "update", "add", "remove", "contact",
        "talk", "follow up", "reach out", "ask", "work", "meet", "interview",
        "complete", "start", "make", "create", "study", "upload", "record"
    ]

    static let vagueFillers = ["stuff", "thing", "figure out", "deal with", "handle"]

    static func hasActionVerb(_ input: String) -> Bool {
        let text = input.lowercased()
        return actionVerbs.contains { verb in
            text == verb || text.hasPrefix("\(verb) ") || text.contains(" \(verb) ")
        }
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
