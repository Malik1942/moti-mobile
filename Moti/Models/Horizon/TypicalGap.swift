import Foundation

// Horizon Timeline v2 — T3. Deriving a maintenance strand's typical feeding
// cadence from its event history (PRD §11 fallback). Pure, Foundation-only.

enum HorizonRhythm {

    /// The typical gap between a maintenance strand's events, or `nil` when there
    /// is not enough signal to place a feed-by (PRD §11).
    ///
    /// Definition (PRD §11): **median of the last 5 inter-event gaps, requiring
    /// at least 3 events, else `nil`.** Non-positive gaps — identical timestamps
    /// (bulk-created events) or out-of-order clock skew — are dropped, since a
    /// zero/negative interval is not a real cadence; if none remain the result is
    /// `nil`. Events are sorted first, so input order does not matter.
    ///
    /// Note: this is the *derivation fallback*. The integration layer prefers a
    /// strand's **declared** cadence (`RecurrenceRule` / `recurrenceCadenceDays`)
    /// when it recurs, and only falls back to this when there is no declared
    /// rhythm. This differs deliberately from the existing `StrandPresence`
    /// baseline (≥2 events / median-of-all-gaps): the PRD wants a higher evidence
    /// bar (≥3 events) and a recency window (last 5) for the feed-by placement.
    static func typicalGap(events: [Date]) -> TimeInterval? {
        let sorted = events.sorted()
        guard sorted.count >= 3 else { return nil }

        var gaps: [TimeInterval] = []
        for i in 1..<sorted.count {
            let gap = sorted[i].timeIntervalSince(sorted[i - 1])
            if gap > 0 { gaps.append(gap) } // drop identical timestamps / skew
        }
        guard !gaps.isEmpty else { return nil }

        return median(Array(gaps.suffix(5))) // the 5 most-recent real gaps
    }

    /// Median of a non-empty list. Even counts average the two middle values.
    static func median(_ values: [TimeInterval]) -> TimeInterval {
        precondition(!values.isEmpty)
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
