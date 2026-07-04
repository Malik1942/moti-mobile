import Foundation

// Horizon Timeline v2 — T5. The snapshot assembler (PRD §6). One pure,
// deterministic function: active strands + completions + now → an ordered,
// render-ready snapshot. No UI, no strings, no engine types. Recompute is an
// app-foreground trigger (T14); the function itself is a pure projection of its
// inputs, so the same inputs always yield the same snapshot.

/// A completed future for the Past region (PRD §6.5). Built by the adapter from
/// a completed `Strand` + its surviving origin date. Completion is a state,
/// never a deletion — the data layer keeps these.
struct HorizonCompletion: Equatable, Identifiable {
    let id: String
    let name: String
    let colorToken: String
    let completedAt: Date
    /// Strand origin ("began Mar 2 · 118 days").
    let origin: Date
}

/// One visible strand row (PRD §6.3). Carries the raw placement data its view
/// needs; the view does the formatting.
struct HorizonRow: Equatable, Identifiable {
    let strandID: String
    let name: String
    let colorToken: String
    let type: StrandType
    let placement: BucketPlacement
    var id: String { strandID }
    var isPinnedToTodayTop: Bool { placement.isPinnedToTodayTop }
}

/// The folded remainder of a bucket (PRD §6.4). In near buckets it is the
/// on-track strands ("▸ N more on course"); in far buckets it is the whole
/// bucket collapsed to a count row.
struct FoldSummary: Equatable {
    enum Reason: Equatable {
        /// Near bucket: on-track strands folded away.
        case onCourse
        /// Far bucket (rest of month / later): the whole bucket collapsed.
        case collapsedBucket
    }
    /// The folded rows, in stable render order — revealed when the fold is
    /// expanded (T9). Carrying the rows (not just IDs) lets the screen render
    /// them on tap without re-deriving.
    let rows: [HorizonRow]
    let reason: Reason
    var count: Int { rows.count }
    var strandIDs: [String] { rows.map(\.strandID) }
}

/// One rendered bucket. `rows` are the surfaced (loud) strands, pinned overdue
/// first; `fold` is the collapsed remainder, if any.
struct BucketSection: Equatable, Identifiable {
    let bucket: TimeBucket
    let rows: [HorizonRow]
    let fold: FoldSummary?
    var id: TimeBucket { bucket }
    /// Today rendered with nothing in it → the view shows "Nothing needs you
    /// today." (PRD §7.3). Only Today is ever emitted empty.
    var isEmpty: Bool { rows.isEmpty && fold == nil }
    /// Total strands in this bucket (surfaced + folded) — shown in the header.
    var strandCount: Int { rows.count + (fold?.count ?? 0) }
    /// Every strand id in this bucket, surfaced or folded (for migration diffing).
    var allStrandIDs: [String] { rows.map(\.strandID) + (fold?.strandIDs ?? []) }
}

/// The Past region (PRD §6.5): completed futures, reverse-chronological.
struct PastSection: Equatable {
    let entries: [PastEntry]
    var isEmpty: Bool { entries.isEmpty }
}

struct PastEntry: Equatable, Identifiable {
    let strandID: String
    let name: String
    let colorToken: String
    let completedAt: Date
    let origin: Date
    var id: String { strandID }
}

/// The whole Horizon surface for one instant: ordered bucket sections (Today
/// first, always present) + the Past region.
struct HorizonSnapshot: Equatable {
    let sections: [BucketSection]
    let past: PastSection
    /// The instant this snapshot was computed from.
    let now: Date
}

enum HorizonSnapshotBuilder {

    /// Near buckets surface loud rows and fold the on-track remainder (PRD §6.4).
    static let nearBuckets: [TimeBucket] = [.today, .tomorrow, .restOfThisWeek, .nextWeek]
    /// Far buckets collapse entirely to a count row by default (PRD §6.1, §6.4).
    static let farBuckets: [TimeBucket] = [.restOfThisMonth, .later]

    /// Assemble the ordered, deterministic Horizon snapshot (PRD §6).
    ///
    /// - Today always renders (empty → the view's voice line). Other near buckets
    ///   render only when non-empty; far buckets render only when non-empty and
    ///   always as a single collapsed count.
    /// - Within a near bucket, overdue rows pin to the top, then the remaining
    ///   loud rows by soonest action; on-track strands fold into "N on course".
    /// - `quietness` is injected (T4) — the snapshot never learns which provider
    ///   is live, so Phase-2 divergence drops in with no change here.
    static func makeSnapshot(active: [HorizonStrand],
                             completed: [HorizonCompletion],
                             now: Date,
                             calendar: Calendar = .current,
                             quietness: QuietnessProvider = CalmQuietnessProvider()) -> HorizonSnapshot {
        let windows = HorizonBuckets.windows(now: now, calendar: calendar)

        let placed = active.map { strand -> Placed in
            let placement = BucketAssigner.assign(strand.item, windows: windows, now: now, calendar: calendar)
            return Placed(strand: strand, placement: placement, quiet: quietness.isQuiet(strand, placement: placement))
        }

        var byBucket: [TimeBucket: [Placed]] = [:]
        for item in placed { byBucket[item.placement.bucket, default: []].append(item) }

        var sections: [BucketSection] = []

        for bucket in nearBuckets {
            let items = byBucket[bucket] ?? []
            if items.isEmpty {
                if bucket == .today { sections.append(BucketSection(bucket: .today, rows: [], fold: nil)) }
                continue
            }
            let loud = items.filter { !$0.quiet }.sorted(by: Self.rowOrder)
            let quiet = items.filter { $0.quiet }.sorted(by: Self.rowOrder)
            let fold = quiet.isEmpty ? nil
                : FoldSummary(rows: quiet.map(Self.row), reason: .onCourse)
            sections.append(BucketSection(bucket: bucket, rows: loud.map(Self.row), fold: fold))
        }

        for bucket in farBuckets {
            let items = (byBucket[bucket] ?? []).sorted(by: Self.rowOrder)
            guard !items.isEmpty else { continue }
            let fold = FoldSummary(rows: items.map(Self.row), reason: .collapsedBucket)
            sections.append(BucketSection(bucket: bucket, rows: [], fold: fold))
        }

        let entries = completed
            .sorted { $0.completedAt != $1.completedAt ? $0.completedAt > $1.completedAt : $0.id < $1.id }
            .map { PastEntry(strandID: $0.id, name: $0.name, colorToken: $0.colorToken,
                             completedAt: $0.completedAt, origin: $0.origin) }

        return HorizonSnapshot(sections: sections, past: PastSection(entries: entries), now: now)
    }

    // MARK: - Internals

    private struct Placed {
        let strand: HorizonStrand
        let placement: BucketPlacement
        let quiet: Bool
    }

    /// The date a placement acts on — for ordering rows soonest-first.
    private static func actionDate(_ placement: BucketPlacement) -> Date {
        switch placement {
        case let .dueIn(_, countdown), let .overdue(_, countdown): return countdown.dueDate
        case let .feedBy(_, rhythm), let .feedOverdue(rhythm): return rhythm.nextFeedBy
        case .achievementNoDueDate, .maintenanceNoRhythm: return .distantFuture
        }
    }

    /// Pinned overdue first, then soonest action, then stable by id.
    private static func rowOrder(_ a: Placed, _ b: Placed) -> Bool {
        if a.placement.isPinnedToTodayTop != b.placement.isPinnedToTodayTop {
            return a.placement.isPinnedToTodayTop
        }
        let da = actionDate(a.placement), db = actionDate(b.placement)
        if da != db { return da < db }
        return a.strand.id < b.strand.id
    }

    private static func row(_ placed: Placed) -> HorizonRow {
        HorizonRow(strandID: placed.strand.id, name: placed.strand.name,
                   colorToken: placed.strand.colorToken, type: placed.strand.type,
                   placement: placed.placement)
    }
}
