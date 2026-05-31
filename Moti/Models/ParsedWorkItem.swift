import Foundation

struct ParsedWorkItem: Equatable {
    var rawInput: String
    var title: String
    var projectGuess: String?
    var temporalIntent: WorkItemTemporalIntent
    var dueDate: Date?
    var workingStartDate: Date?
    var workingEndDate: Date?
    var suggestedSessions: [SuggestedSession]
    var estimatedEffort: Int?
    var parserConfidence: Double
    var needsReview: Bool
    var reviewReason: String?
    var parserExplanation: String
}

enum WorkItemTemporalIntent: String, Codable, Equatable {
    case deadline
    case workingPeriod
    case event
    case periodWithDeadline
    case openEndedAfter
    case noTime
    case unknown
}

struct SuggestedSession: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var startTime: Date?
    var endTime: Date?
    var reason: String
    var source: String

    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date? = nil,
        endTime: Date? = nil,
        reason: String,
        source: String = "parser"
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.reason = reason
        self.source = source
    }
}

// MARK: - Deduplication

extension ParsedWorkItem {
    /// Compact key used to detect duplicate parses.
    ///
    /// Two parses with the same signature describe the same work item and
    /// should not both be inserted. Dates are rounded to the nearest minute so
    /// two parses of the same capture (one with microsecond-level drift) still
    /// collide.
    var dedupSignature: String {
        let normalizedTitle = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let project = (projectGuess ?? "").lowercased()
        let dueKey   = ParsedWorkItem.minuteKey(dueDate)
        let startKey = ParsedWorkItem.minuteKey(workingStartDate)
        let endKey   = ParsedWorkItem.minuteKey(workingEndDate)
        return "\(normalizedTitle)|\(project)|\(dueKey)|\(startKey)|\(endKey)|\(temporalIntent.rawValue)"
    }

    private static func minuteKey(_ date: Date?) -> String {
        guard let date else { return "-" }
        return String(Int(date.timeIntervalSinceReferenceDate / 60))
    }
}

// MARK: - Temporal-variant collapsing

extension ParsedWorkItem {
    /// The title reduced to its core action by stripping temporal phrases. This
    /// is the key that recognizes "same task, expressed with different temporal
    /// richness" — e.g. "Finish video filming" and "Finish video filming before
    /// 3:45" both reduce to "finish video filming".
    var coreTitleKey: String {
        DateResolver.removingDatePhrases(from: title)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How much extracted timing this parse carries. A due date is the strongest
    /// signal; working-period bounds add weight. Used to keep the richer twin.
    var timingRichness: Int {
        (dueDate != nil ? 2 : 0)
            + (workingStartDate != nil ? 1 : 0)
            + (workingEndDate != nil ? 1 : 0)
    }

    /// Whether `self` and `other` are the *same task* expressed with different
    /// temporal richness (one is a stricter/temporal variant of the other), so
    /// they must collapse into one. Distinct tasks that merely share a title but
    /// carry *conflicting concrete timings* (e.g. "call mom today" vs "call mom
    /// tomorrow") are NOT variants and stay separate.
    func isTemporalVariant(of other: ParsedWorkItem) -> Bool {
        // Projects must be compatible (equal, or at least one unassigned).
        let p1 = (projectGuess ?? "").lowercased()
        let p2 = (other.projectGuess ?? "").lowercased()
        guard p1.isEmpty || p2.isEmpty || p1 == p2 else { return false }

        // Same core action, or one core is a stricter superset of the other.
        let a = coreTitleKey
        let b = other.coreTitleKey
        guard !a.isEmpty, !b.isEmpty else { return false }
        guard a == b || a.contains(b) || b.contains(a) else { return false }

        return ParsedWorkItem.timingsCompatible(self, other)
    }

    /// Compatible = no conflicting concrete anchors. A missing date is always
    /// compatible (the weak twin). Two present-but-different due dates (or
    /// start windows) more than a minute apart signal genuinely distinct tasks.
    private static func timingsCompatible(_ a: ParsedWorkItem, _ b: ParsedWorkItem) -> Bool {
        if let da = a.dueDate, let db = b.dueDate, abs(da.timeIntervalSince(db)) >= 60 {
            return false
        }
        if let sa = a.workingStartDate, let sb = b.workingStartDate, abs(sa.timeIntervalSince(sb)) >= 60 {
            return false
        }
        return true
    }

    /// Merge a temporal variant into `self`, keeping the richer task: prefer the
    /// twin with extracted timing, take the cleanest (temporal-stripped) title,
    /// and let a placeable twin rescue the other from needs-review.
    func mergingVariant(_ other: ParsedWorkItem) -> ParsedWorkItem {
        let selfRicher = timingRichness >= other.timingRichness
        let base = selfRicher ? self : other
        let weak = selfRicher ? other : self

        var merged = base
        merged.title = ParsedWorkItem.cleanerTitle(base.title, weak.title)
        if !base.needsReview || !weak.needsReview {
            merged.needsReview = false
            merged.reviewReason = nil
        }
        merged.parserConfidence = Swift.max(base.parserConfidence, weak.parserConfidence)
        return merged
    }

    /// Picks the title that best reads as the clean core action — preferring one
    /// that already carries no temporal residue, then the shorter of the two.
    static func cleanerTitle(_ a: String, _ b: String) -> String {
        func isClean(_ t: String) -> Bool {
            let stripped = DateResolver.removingDatePhrases(from: t)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(stripped) == .orderedSame
        }
        switch (isClean(a), isClean(b)) {
        case (true, false): return a
        case (false, true): return b
        default:            return a.count <= b.count ? a : b
        }
    }
}

extension Array where Element == ParsedWorkItem {
    /// Drops content-duplicate items while preserving the original order. Used
    /// as a final guard before inserting work items into SwiftData so that any
    /// upstream parser glitch (FM returning the same item twice, user typing a
    /// duplicate line, segmenter over-splitting) never produces duplicate work.
    func deduplicatedByContent() -> [ParsedWorkItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.dedupSignature).inserted }
    }

    /// Stronger guard for model output: first drops exact content-duplicates,
    /// then collapses *temporal variants* of the same task into one richer item.
    ///
    /// This is what stops a single capture like "finish video filming before
    /// 3:45 today" from becoming two tasks ("finish video filming" + "finish
    /// video filming before 3:45"): the temporal phrase enriches one task, it
    /// never spawns a second. Order is preserved; the surviving item keeps the
    /// extracted timing and the clean, temporal-stripped title.
    func deduplicatedMergingVariants() -> [ParsedWorkItem] {
        var result: [ParsedWorkItem] = []
        for item in deduplicatedByContent() {
            if let idx = result.firstIndex(where: { $0.isTemporalVariant(of: item) }) {
                result[idx] = result[idx].mergingVariant(item)
            } else {
                result.append(item)
            }
        }
        return result
    }
}
