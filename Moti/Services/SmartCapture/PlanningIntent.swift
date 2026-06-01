import Foundation

/// How strongly a capture expresses a desire for Moti to *plan* — distinct from
/// task scale. Combined with scale/recurrence by `PlanningClassifier` to choose
/// a `PlanningDepth`.
///
///   - `none`     — no planning desire ("buy milk tomorrow").
///   - `mild`     — time pressure but no planning verb ("finish this before Friday").
///   - `explicit` — a genuine ask to plan/structure/organize/break down/map out
///                  ("help me plan this out", "make a timeline for this").
enum PlanningIntent: String, Equatable {
    case none
    case mild
    case explicit
}

/// Semantic planning-intent detection. Deliberately more than keyword equality:
/// it matches planning *words by token* (so "planning", "planned", "plans" all
/// count, while "plant"/"planet" do not) plus a set of multi-word planning
/// phrases. This is what keeps planning-intent detection from being brittle
/// while still preserving the anti-overplanning default for plain captures.
enum PlanningIntentDetector {

    static func detect(_ rawInput: String) -> PlanningIntent {
        let lower = rawInput.lowercased()
        let tokens = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if hasExplicitSignal(lower, tokens: tokens) { return .explicit }
        if hasMildSignal(lower) { return .mild }
        return .none
    }

    // MARK: - Explicit planning desire

    /// Whole-word planning signals. Matched against tokens (not substrings) so
    /// "plan" fires on "plan/plans/planning/planned" but never on "plant",
    /// "plane", or "planet", and "organize" never fires on "organic".
    private static let explicitWords: Set<String> = [
        "plan", "plans", "planning", "planned", "replan", "replanning", "planner",
        "organize", "organise", "organizing", "organising", "organized", "organised",
        "structure", "structuring", "structured", "restructure", "restructuring",
        "roadmap", "outline", "outlining", "sequence", "sequencing",
        "prioritize", "prioritise", "strategize", "strategise"
    ]

    /// Multi-word planning phrases (substring match is fine — these are unambiguous).
    private static let explicitPhrases: [String] = [
        "plan out", "plan this out", "plan it out", "make a plan", "come up with a plan",
        "map out", "map this out", "map it out", "lay out", "schedule out",
        "break down", "break it down", "break this down", "breakdown", "break into",
        "step by step", "into steps", "game plan",
        "make a timeline", "build a timeline", "create a timeline", "draw up a timeline",
        "a timeline for", "timeline for",
        "into a routine", "make this a routine", "create a routine", "build a routine",
        "split this", "split it up",
        "help me plan", "help me structure", "help me organize", "help me organise",
        "help me map", "help me break", "help me figure out", "help me lay out",
        "help me sort", "help me sequence", "figure out a plan"
    ]

    /// Verbs that turn a "timeline" mention into a planning artifact rather than a
    /// reference to the app's Timeline tab ("add to timeline" ≠ "make a timeline").
    private static let timelinePlanningVerbs: Set<String> = [
        "make", "build", "create", "map", "draw", "plan", "planning", "sketch",
        "need", "want", "lay", "design", "structure", "organize", "organise"
    ]

    private static func hasExplicitSignal(_ lower: String, tokens: Set<String>) -> Bool {
        if !tokens.isDisjoint(with: explicitWords) { return true }
        if explicitPhrases.contains(where: { lower.contains($0) }) { return true }
        if tokens.contains("timeline"), !tokens.isDisjoint(with: timelinePlanningVerbs) { return true }
        return false
    }

    // MARK: - Mild (time pressure, no planning verb)

    /// Deadline-pressure phrasing — a single task that's time-bound but not a
    /// planning request. Note bare relatives like "tomorrow"/"tonight" are NOT
    /// here: "buy milk tomorrow" stays `none`, while "finish this before Friday"
    /// reads as `mild`.
    private static func hasMildSignal(_ lower: String) -> Bool {
        let pressure = [
            "before ", " by ", "due ", "deadline", "no later than",
            "by end of", "by the end of", "before end of", "asap", "time-sensitive"
        ]
        return pressure.contains { lower.contains($0) }
    }
}
