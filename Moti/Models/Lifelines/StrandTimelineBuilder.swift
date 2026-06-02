import Foundation

// MARK: - Declared cadence

extension RecurrenceRule {
    /// The rule's declared rhythm expressed in days, for use as a presence
    /// baseline. Coarse on purpose — it is a *prior*, not a schedule.
    var approximateCadenceDays: Double? {
        let n = Double(max(1, interval))
        switch frequency {
        case .none:     return nil
        case .daily:    return 1
        case .weekdays: return 7.0 / 5.0          // ~1.4 — five touches a week
        case .weekly:   return weekday != nil ? 7 : 7 * n
        case .monthly:  return 30.4 * n
        case .custom:   return n                   // "every N days"
        }
    }
}

// MARK: - Builder

/// The adapter between the live model layer (`WorkItem` / `Project` /
/// `CompletionLog`) and the pure presence computer. It derives a behavioral
/// event stream from existing fields **read-only** — no new logging, no task
/// model change (per the v1 decision) — then hands events to
/// `StrandPresenceComputer` and assembles render-ready `Strand` values.
///
/// Everything here is "what is true." It computes co-occurrence but never phrases
/// it; the model/copy layer narrates the result.
struct StrandTimelineBuilder {
    let projects: [Project]
    let workItems: [WorkItem]
    let completionLogs: [CompletionLog]
    var now: Date = .now
    var calendar: Calendar = .current
    var policy: PresencePolicy = .default
    /// Paused strand ids (deliberate set-down).
    var pausedStrandIDs: Set<String> = []

    /// Build every strand, most-attention-needed first, then calm strands receding.
    func build() -> [Strand] {
        var strands: [Strand] = []

        for project in projects.motiOrdered {
            let items = workItems.filter { $0.projectName == project.name }
            strands.append(makeStrand(
                id: project.id.uuidString,
                name: project.name,
                colorToken: project.colorToken,
                items: items
            ))
        }

        // Unassigned items collapse into one implicit strand (only if non-empty).
        let unassigned = workItems.filter { ($0.projectName ?? "").isEmpty }
        if !unassigned.isEmpty {
            strands.append(makeStrand(
                id: Strand.unassignedID,
                name: ProjectCatalog.unassignedLabel,
                colorToken: ProjectCatalog.color(for: nil),
                items: unassigned
            ))
        }

        // Co-occurrence needs the whole field: which strands rose while others fell.
        let eventsByStrand = Dictionary(uniqueKeysWithValues: strands.map { strand in
            (strand.id, deriveEvents(for: workItemsForStrand(strand, in: strands)))
        })
        strands = strands.map { strand in
            attachCoOccurrence(to: strand, eventsByStrand: eventsByStrand)
        }

        return strands.sorted(by: attentionOrder)
    }

    // MARK: - Per-strand assembly

    private func makeStrand(id: String, name: String, colorToken: String, items: [WorkItem]) -> Strand {
        let events = deriveEvents(for: items)
        let cadence = declaredCadenceDays(for: items)
        let presence = StrandPresenceComputer.presence(
            events: events,
            recurrenceCadenceDays: cadence,
            now: now,
            policy: policy
        )
        let kind = inferKind(for: items)

        return Strand(
            id: id,
            name: name,
            colorToken: colorToken,
            kind: kind,
            presence: presence,
            isPaused: pausedStrandIDs.contains(id),
            recurrenceCadenceDays: cadence,
            openCount: items.filter { $0.status != .done && $0.status != .archived }.count,
            deferredCount: items.filter { $0.status == .deferred || $0.status == .skipped }.count,
            deadline: deadline(for: items),
            forwardNodes: forwardNodes(for: items),
            lastTraces: lastTraces(for: items),
            coOccurringStrandNames: [] // filled in a second pass with the full field
        )
    }

    // MARK: - Event derivation (read-only, from existing fields)

    /// Turn a strand's items into a behavioral event stream. Each item
    /// contributes its `created` mark plus whatever terminal/contact mark its
    /// current state implies. Recurring completions are read from `CompletionLog`.
    func deriveEvents(for items: [WorkItem]) -> [StrandEvent] {
        var events: [StrandEvent] = []
        let logByTask = Dictionary(grouping: completionLogs, by: \.taskId)

        for item in items {
            events.append(StrandEvent(kind: .created, date: item.createdAt))

            switch item.status {
            case .done:
                events.append(StrandEvent(kind: .completed, date: item.updatedAt))
            case .deferred, .skipped:
                events.append(StrandEvent(kind: .deferred, date: item.updatedAt))
            default:
                // A later edit/progress that isn't a terminal state is a touch.
                if item.updatedAt.timeIntervalSince(item.createdAt) > 60 {
                    events.append(StrandEvent(kind: .touched, date: item.updatedAt))
                }
            }

            // Recurring habits log each completed occurrence — count them all so a
            // living habit reads as repeatedly fed, not a single done task.
            for log in logByTask[item.id] ?? [] where log.newStatus == .done {
                events.append(StrandEvent(kind: .completed, date: log.timestamp))
            }
        }
        return events
    }

    // MARK: - Cadence & kind

    /// The strand's dominant declared rhythm: the *shortest* cadence among its
    /// recurring items (the most demanding heartbeat sets the bar).
    private func declaredCadenceDays(for items: [WorkItem]) -> Double? {
        items.compactMap { $0.isRecurring ? $0.recurrence.approximateCadenceDays : nil }.min()
    }

    /// Achievement iff the strand carries a real one-time deadline — a
    /// non-recurring dated item. Recurring due dates are rhythm, not deadlines.
    private func inferKind(for items: [WorkItem]) -> StrandKind {
        let hasRealDeadline = items.contains { !$0.isRecurring && $0.dueDate != nil }
        return hasRealDeadline ? .achievement : .maintenance
    }

    // MARK: - Achievement detail

    private func deadline(for items: [WorkItem]) -> Date? {
        items.filter { !$0.isRecurring }.compactMap(\.dueDate).max()
    }

    /// Upcoming steps as points toward the deadline marker (PRD: not a checklist).
    private func forwardNodes(for items: [WorkItem]) -> [StrandForwardNode] {
        let dated = items
            .filter { !$0.isRecurring && $0.dueDate != nil && $0.status != .archived }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        guard !dated.isEmpty else { return [] }

        let lastDue = dated.last?.dueDate
        return dated.prefix(6).map { item in
            StrandForwardNode(
                id: item.id,
                title: item.title,
                date: item.dueDate,
                isDeadline: item.dueDate == lastDue,
                isReached: item.status == .done || (item.dueDate.map { $0 < now } ?? false)
            )
        }
    }

    // MARK: - Maintenance detail

    /// Recent dated history — the shape of absence, never checkboxes.
    private func lastTraces(for items: [WorkItem]) -> [StrandTrace] {
        var traces: [StrandTrace] = []
        let logByTask = Dictionary(grouping: completionLogs, by: \.taskId)

        for item in items {
            switch item.status {
            case .done:
                traces.append(StrandTrace(id: item.id, label: item.title, date: item.updatedAt, kind: .completed))
            case .deferred, .skipped:
                traces.append(StrandTrace(id: item.id, label: "Skipped · \(item.title)", date: item.updatedAt, kind: .deferred))
            default:
                let date = item.updatedAt.timeIntervalSince(item.createdAt) > 60 ? item.updatedAt : item.createdAt
                traces.append(StrandTrace(id: item.id, label: item.title, date: date, kind: .touched))
            }
            for log in logByTask[item.id] ?? [] where log.newStatus == .done {
                traces.append(StrandTrace(id: UUID(), label: item.title, date: log.timestamp, kind: .completed))
            }
        }

        return traces
            .filter { $0.date <= now }
            .sorted { $0.date > $1.date }
            .reduce(into: [StrandTrace]()) { acc, t in
                if acc.count < 5 { acc.append(t) }
            }
    }

    // MARK: - Co-occurrence ("why it went quiet")

    /// Names of strands that rose while `strand` fell, in the same recent window.
    /// Co-occurrence only — never causation (PRD §6.2). Computed across the field.
    private func attachCoOccurrence(to strand: Strand, eventsByStrand: [String: [StrandEvent]]) -> Strand {
        // Only meaningful for a strand that has actually quietened.
        guard strand.presence.state != .active else { return strand }

        let windowDays = max(7.0, (strand.presence.baselineCadenceDays ?? 7) * policy.driftMultiplier)
        let recentStart = now.addingTimeInterval(-windowDays * 86_400)
        let priorStart = now.addingTimeInterval(-2 * windowDays * 86_400)

        func count(_ events: [StrandEvent], from: Date, to: Date) -> Int {
            events.filter { $0.date >= from && $0.date < to }.count
        }

        let myEvents = eventsByStrand[strand.id] ?? []
        let myRecent = count(myEvents, from: recentStart, to: now)
        let myPrior = count(myEvents, from: priorStart, to: recentStart)
        guard myRecent < myPrior else { return strand } // it must have actually fallen

        let risers = eventsByStrand
            .filter { $0.key != strand.id }
            .compactMap { id, events -> (String, Int)? in
                let recent = count(events, from: recentStart, to: now)
                let prior = count(events, from: priorStart, to: recentStart)
                let rise = recent - prior
                guard rise > 0 else { return nil }
                return (id, rise)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .compactMap { id, _ in nameForStrand(id: id) }

        return Strand(
            id: strand.id, name: strand.name, colorToken: strand.colorToken,
            kind: strand.kind, presence: strand.presence, isPaused: strand.isPaused,
            recurrenceCadenceDays: strand.recurrenceCadenceDays, openCount: strand.openCount,
            deferredCount: strand.deferredCount, deadline: strand.deadline,
            forwardNodes: strand.forwardNodes, lastTraces: strand.lastTraces,
            coOccurringStrandNames: Array(risers)
        )
    }

    // MARK: - Ordering

    /// Attention order: the exception rises, calm strands recede (PRD §5, §10).
    /// Drifted (and not paused) first, then quiet, then active; paused sinks.
    private func attentionOrder(_ a: Strand, _ b: Strand) -> Bool {
        func rank(_ s: Strand) -> Int {
            if s.isPaused { return 4 }
            switch s.presence.state {
            case .drifted: return 0
            case .quiet:   return 1
            case .active:  return 2
            }
        }
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb }
        // Within a tier, the longer-silent strand sorts first.
        return (a.presence.daysSinceLastActivity ?? -1) > (b.presence.daysSinceLastActivity ?? -1)
    }

    // MARK: - Lookup helpers

    private func nameForStrand(id: String) -> String? {
        if id == Strand.unassignedID { return ProjectCatalog.unassignedLabel }
        return projects.first { $0.id.uuidString == id }?.name
    }

    private func workItemsForStrand(_ strand: Strand, in strands: [Strand]) -> [WorkItem] {
        if strand.id == Strand.unassignedID {
            return workItems.filter { ($0.projectName ?? "").isEmpty }
        }
        guard let project = projects.first(where: { $0.id.uuidString == strand.id }) else { return [] }
        return workItems.filter { $0.projectName == project.name }
    }
}
