import Foundation

/// The **phrasing layer**. It turns already-computed strand presence into the two
/// pieces of language on the Main Timeline — the top synthesized sentence and the
/// single "What matters now" focus. It is deliberately separate from the compute
/// layer: the algorithm decides *what is true* (PRD §8); this only decides *how
/// it is said*. It never inspects events, never recomputes state, never decides
/// which strand has drifted — it reads the result and narrates it.
enum TimelineNarrator {

    // MARK: - Top synthesized sentence

    /// One calm sentence summarizing the week. Names what stayed active and what
    /// drifted; on a healthy week it simply reassures (PRD §6.1, §10).
    static func headline(for strands: [Strand]) -> String {
        let live = strands.filter { !$0.isPaused }
        let active = live.filter { $0.presence.state == .active }.map(\.name)
        let drifted = live.filter { $0.presence.state == .drifted }.map(\.name)

        if strands.isEmpty {
            return "Your futures will appear here as you use Moti."
        }

        var clauses: [String] = []
        if !active.isEmpty {
            clauses.append("\(joined(active)) stayed active")
        }
        if !drifted.isEmpty {
            let verb = drifted.count == 1 ? "drifted" : "drifted"
            clauses.append("\(joined(drifted)) \(verb) before now")
        }

        switch (active.isEmpty, drifted.isEmpty) {
        case (false, false):
            return "This week \(clauses[0]). \(capitalizingFirst(clauses[1]))."
        case (false, true):
            return "This week \(clauses[0]). Everything's still in reach."
        case (true, false):
            return capitalizingFirst("\(clauses[0]).")
        case (true, true):
            // Only quiet/paused strands — a serene week.
            return "A calm week — everything's still in reach."
        }
    }

    // MARK: - "What matters now" focus

    /// The single thing worth a glance, or calm reassurance. v1 surfaces the one
    /// drifted strand (longest-silent first); paused and parked strands are never
    /// surfaced — pausing and "Not this week" are first-class, peaceful choices.
    static func focus(for strands: [Strand], parkedIDs: Set<String> = []) -> TimelineFocus {
        let candidate = strands
            .filter { !$0.isPaused && !parkedIDs.contains($0.id) }
            .filter { $0.presence.state == .drifted }
            .max(by: { ($0.presence.daysSinceLastActivity ?? 0) < ($1.presence.daysSinceLastActivity ?? 0) })

        guard let strand = candidate else {
            return .calm("Everything's still in reach.")
        }

        return .attention(
            strandID: strand.id,
            title: "\(strand.name) has gone quiet",
            detail: driftDetail(for: strand)
        )
    }

    /// Behavioral, non-shaming description of a drifted strand for the card.
    static func driftDetail(for strand: Strand) -> String {
        var parts: [String] = []
        if let days = strand.presence.daysSinceLastActivity {
            parts.append("Quiet for \(days) \(days == 1 ? "day" : "days")")
        } else {
            parts.append("Quiet")
        }
        if let cadence = strand.presence.baselineCadenceDays,
           strand.presence.baselineSource == .recurrence || strand.presence.baselineSource == .history {
            parts.append("usually \(cadenceWord(cadence))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Phrasing helpers

    /// Coarse, human cadence word from a day interval. Vague on purpose — it is a
    /// felt rhythm, not a schedule.
    static func cadenceWord(_ days: Double) -> String {
        switch days {
        case ..<1.5:  return "daily"
        case ..<2.5:  return "every couple days"
        case ..<5.5:  return "every few days"
        case ..<8.5:  return "weekly"
        case ..<18:   return "every couple weeks"
        case ..<45:   return "monthly"
        default:      return "occasionally"
        }
    }

    /// Oxford-style join: "A", "A and B", "A, B, and C".
    static func joined(_ names: [String]) -> String {
        switch names.count {
        case 0:  return ""
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head), and \(names.last!)"
        }
    }

    private static func capitalizingFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: - Trajectory (forward-looking) copy

    /// One forward-looking sentence about where current pace is heading. Directional
    /// only — no day-counts (PRD §6.1 example shows day-counts, but those are v2;
    /// §9.6). Names what's slipping/fading; reassures when all is on track.
    static func trajectoryHeadline(for strands: [Strand]) -> String {
        if strands.isEmpty {
            return "Your futures will appear here as you use Moti."
        }
        let live = strands.filter { !$0.isPaused }
        let slipping = live.filter { $0.trajectory.outcome == .behind }.map(\.name)
        let fading = live.filter { $0.trajectory.outcome == .fading }.map(\.name)

        var clauses: [String] = []
        if !slipping.isEmpty {
            clauses.append("\(joined(slipping)) \(slipping.count == 1 ? "is" : "are") slipping")
        }
        if !fading.isEmpty {
            clauses.append("\(joined(fading)) \(fading.count == 1 ? "is" : "are") fading")
        }

        guard !clauses.isEmpty else {
            return "On current pace, everything's on track."
        }
        return "On current pace: \(oxfordClauses(clauses))."
    }

    /// The single forward-looking focus: the one future heading the wrong way, or
    /// calm reassurance. Behind sorts above fading; paused/parked never surface.
    static func trajectoryFocus(for strands: [Strand], parkedIDs: Set<String> = []) -> TimelineFocus {
        let candidates = strands
            .filter { !$0.isPaused && !parkedIDs.contains($0.id) }
            .filter { $0.trajectory.outcome.needsAttention }

        // Behind (a deadline at risk) outranks fading (a rhythm dimming).
        let chosen = candidates.first { $0.trajectory.outcome == .behind }
            ?? candidates.first { $0.trajectory.outcome == .fading }

        guard let strand = chosen else {
            return .calm("Everything's on track.")
        }

        let title: String
        let detail: String
        if strand.trajectory.outcome == .behind {
            title = "\(strand.name) is slipping"
            detail = "Behind its deadline at the current pace."
        } else {
            title = "\(strand.name) is fading"
            detail = "At the current pace, this fades out."
        }
        return .attention(strandID: strand.id, title: title, detail: detail)
    }

    /// Join already-built clauses with Oxford style ("A", "A and B", "A, B, and C").
    private static func oxfordClauses(_ clauses: [String]) -> String {
        switch clauses.count {
        case 0:  return ""
        case 1:  return clauses[0]
        case 2:  return "\(clauses[0]) and \(clauses[1])"
        default:
            let head = clauses.dropLast().joined(separator: ", ")
            return "\(head), and \(clauses.last!)"
        }
    }

    // MARK: - Peek sheet copy

    /// Achievement current-state line, in behavioral terms (PRD §6.2):
    /// "Moving toward deadline · 4 done, 2 deferred". Counts completed actions
    /// whether or not they carry a date (P2).
    static func achievementStatus(for strand: Strand) -> String {
        let done = strand.completedActionCount
        var lead = "In progress"
        if strand.deadline != nil { lead = strand.isPaused ? "Paused before deadline" : "Moving toward deadline" }
        var tail: [String] = []
        if done > 0 { tail.append("\(done) done") }
        if strand.deferredCount > 0 { tail.append("\(strand.deferredCount) deferred") }
        return tail.isEmpty ? lead : "\(lead) · \(tail.joined(separator: ", "))"
    }

    /// Maintenance rhythm line (PRD §6.2): "Usually weekly · quiet for 18 days".
    static func maintenanceRhythm(for strand: Strand) -> String {
        var parts: [String] = []
        if let cadence = strand.presence.baselineCadenceDays,
           strand.presence.baselineSource == .recurrence || strand.presence.baselineSource == .history {
            parts.append("Usually \(cadenceWord(cadence))")
        }
        if let days = strand.presence.daysSinceLastActivity {
            switch strand.presence.state {
            case .drifted, .quiet: parts.append("quiet for \(days) \(days == 1 ? "day" : "days")")
            case .active:          parts.append(days == 0 ? "tended today" : "last tended \(days) \(days == 1 ? "day" : "days") ago")
            }
        } else {
            parts.append("no rhythm yet")
        }
        return capitalizingFirst(parts.joined(separator: " · "))
    }

    /// "Why it went quiet" — co-occurrence, never causation, never "crowded out"
    /// (PRD §6.2). Returns nil when there is nothing honest to say.
    static func whyQuiet(for strand: Strand) -> String? {
        guard strand.presence.state != .active,
              !strand.coOccurringStrandNames.isEmpty else { return nil }
        return "It faded as \(joined(strand.coOccurringStrandNames)) rose during the same weeks."
    }

    /// The why-quiet line, with a **non-causal fallback** when no co-occurring
    /// rise can be honestly computed (P2). Never fabricates a cause.
    static func whyQuietOrFallback(for strand: Strand) -> String? {
        if let why = whyQuiet(for: strand) { return why }
        switch strand.presence.state {
        case .drifted: return "It's been quiet a while."
        case .quiet:   return "It's been slowing lately."
        case .active:  return nil
        }
    }

    /// Achievement **milestone-health** as one natural-language line — the
    /// trajectory read for the Peek (PRD §6.2). Directional, non-shaming, no
    /// day-counts (§9.6).
    static func milestoneHealth(for strand: Strand) -> String {
        switch strand.trajectory.outcome {
        case .onTime:
            return strand.completedActionCount >= max(strand.totalActionCount, 1)
                ? "Done — every step complete."
                : "On track for the pace you set."
        case .behind:
            return "Behind the pace you set — but the deadline's still in view."
        case .sustained:
            return "Holding a steady rhythm."
        case .fading:
            return "Slipping off the pace — it's starting to fade."
        }
    }
}

/// The Main Timeline's single bottom focus: either calm reassurance or the one
/// strand worth attention. Attention carries only computed identity + phrased
/// copy — the card supplies the reversible actions.
enum TimelineFocus: Equatable {
    case calm(String)
    case attention(strandID: String, title: String, detail: String)
}
