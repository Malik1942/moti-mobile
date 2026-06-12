import SwiftUI

/// **Screen 2 — the Peek sheet.** Presented as a sheet *over* the timeline (the
/// other lines stay faintly visible behind it — this is not a page navigation,
/// so cross-future context is preserved; PRD §6.2). Its content is
/// type-dependent: achievement and maintenance futures are different kinds of
/// thing and never share one generic checklist.
struct StrandPeekSheet: View {
    let strand: Strand
    /// Switches to the Projects tab (the Timeline previews the path; Projects is
    /// where execution happens).
    var onOpenInProjects: (String) -> Void = { _ in }

    @ObservedObject private var prefs = StrandPreferenceStore.shared
    @Environment(\.dismiss) private var dismiss

    private var color: Color { .projectToken(strand.colorToken) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                insightBlock
                visualBlock
                actionBlock
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Translucent so the timeline reads faintly behind — context preserved.
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Header (identity + state)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(strand.name)
                    .font(.system(size: 20, weight: .semibold))
                Text(stateWord)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var stateWord: String {
        if strand.isPaused { return "Paused" }
        switch strand.presence.state {
        case .active:  return "Active"
        case .quiet:   return "Quiet"
        case .drifted: return "Drifted"
        }
    }

    // MARK: - Achievement

    @ViewBuilder
    private var insightBlock: some View {
        if strand.effectiveType == .achievement {
            insightBlock(
                title: achievementPaceState,
                detail: achievementTimeExplanation
            )
        } else {
            insightBlock(
                title: maintenanceProjectionState,
                detail: maintenanceTimeExplanation
            )
        }
    }

    private func insightBlock(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Milestone health (PRD §6.2): a continuous **felt texture** of whether the
    /// line is tracking its expected pace, plus one natural-language line. The
    /// detail lives here in the Peek, never on the main axis (§8 detail-vs-load).
    private var milestoneProgress: some View {
        let progress = strand.trajectory.progressFraction ?? 0
        // Where you'd "expect" to be = progress / pace (time elapsed). The gap
        // between fill and this tick is the felt read; no numbers shown.
        let expected: Double = {
            guard let pace = strand.trajectory.paceRatio, pace > 0, pace.isFinite else { return progress }
            return min(1, max(0, progress / pace))
        }()
        return VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.5)).frame(height: 6)
                    Capsule().fill(color.opacity(0.85))
                        .frame(width: max(4, geo.size.width * progress), height: 6)
                    // expected-pace marker
                    Rectangle().fill(.secondary)
                        .frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * expected - 0.75, y: -3)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Milestone health: \(TimelineNarrator.milestoneHealth(for: strand))")
    }

    // MARK: - Visual block

    @ViewBuilder
    private var visualBlock: some View {
        if strand.effectiveType == .achievement {
            achievementVisual
        } else {
            maintenanceVisual
        }
    }

    private var achievementVisual: some View {
        VStack(alignment: .leading, spacing: 18) {
            evidenceSummary(achievementEvidenceSummary)

            Text("Progress")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            milestoneProgress

            if strand.forwardNodes.isEmpty {
                Text("No steps mapped yet. Open in Projects to lay out the path.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForwardNodesView(nodes: strand.forwardNodes, color: color)
            }
        }
    }

    private var maintenanceVisual: some View {
        VStack(alignment: .leading, spacing: 18) {
            evidenceSummary(maintenanceEvidenceSummary)
            lastTraces
        }
    }

    private func evidenceSummary(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Evidence")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lastTraces: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last traces")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if strand.lastTraces.isEmpty {
                // Never an empty "No tasks" state — show the shape of a beginning.
                Text("No traces yet. This strand is just getting started.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(strand.lastTraces.prefix(3))) { trace in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(trace.kind == .deferred ? Color.secondary.opacity(0.5) : color.opacity(0.8))
                            .frame(width: 6, height: 6)
                        Text(Self.traceDate.string(from: trace.date))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(trace.label)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if strand.effectiveType == .achievement {
                HStack(spacing: 10) {
                    primaryButton("Open in Projects") {
                        onOpenInProjects(strand.id)
                        dismiss()
                    }
                    secondaryButton("Not this week") {
                        prefs.parkForThisWeek(strand.id)
                        dismiss()
                    }
                }
                textAction("Mark as paused") {
                    prefs.setPaused(true, for: strand.id)
                    dismiss()
                }
            } else {
                HStack(spacing: 10) {
                    primaryButton("Make space this week") {
                        prefs.makeSpaceThisWeek(strand.id)
                        dismiss()
                    }
                    secondaryButton("Not this week") {
                        prefs.parkForThisWeek(strand.id)
                        dismiss()
                    }
                }
                textAction("Lower priority") {
                    prefs.setLowered(true, for: strand.id)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Buttons

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .background(Color.indigo, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.indigo)
                .background(Color.indigo.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func textAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time and evidence copy

    private var achievementPaceState: String {
        switch strand.trajectory.outcome {
        case .onTrack: return "On pace"
        case .slipping: return "Slipping"
        case .stalled: return "Stalled"
        case .completed: return "Complete"
        case .sustained, .quiet, .fading: return "In progress"
        }
    }

    private var achievementTimeExplanation: String {
        let target = strand.deadline.map { "Target: \(Self.mediumDate.string(from: $0))." } ?? "No target date yet."
        return "\(target) \(achievementProjectionSentence)"
    }

    private var achievementProjectionSentence: String {
        switch strand.trajectory.outcome {
        case .onTrack:
            return "At the current pace, the projection reaches the target."
        case .slipping:
            return "Projected after target at the current pace."
        case .stalled:
            return "Stalled — no recent movement toward the target."
        case .completed:
            return "Every step is complete."
        case .sustained, .quiet, .fading:
            return "Tracking the current pace."
        }
    }

    private var achievementEvidenceSummary: String {
        var parts = ["\(strand.completedActionCount)/\(max(strand.totalActionCount, 1)) actions complete"]
        if strand.deferredCount > 0 { parts.append("\(strand.deferredCount) deferred") }
        parts.append(lastActivityPhrase)
        return parts.joined(separator: " · ")
    }

    private var maintenanceProjectionState: String {
        if hasNoHistory { return "Just getting started" }
        switch strand.trajectory.outcome {
        case .sustained: return "Sustained"
        case .quiet: return "Weakening"
        case .fading: return "Fading"
        case .onTrack, .completed: return "Sustained"
        case .slipping, .stalled: return "Weakening"
        }
    }

    private var maintenanceTimeExplanation: String {
        if hasNoHistory {
            return "Once this has a few real traces, Moti can show whether it is building rhythm or fading."
        }

        var parts: [String] = []
        if let cadence = strand.presence.baselineCadenceDays,
           strand.presence.baselineSource == .recurrence || strand.presence.baselineSource == .history {
            parts.append("Usual rhythm: \(TimelineNarrator.cadenceWord(cadence)).")
        }
        if let days = strand.presence.daysSinceLastActivity {
            parts.append(days == 0 ? "Last trace: today." : "Quiet for \(days) \(days == 1 ? "day" : "days").")
        }
        parts.append(maintenanceProjectionSentence)
        return parts.joined(separator: " ")
    }

    private var maintenanceProjectionSentence: String {
        switch strand.trajectory.outcome {
        case .sustained:
            return "Projection: sustained."
        case .quiet:
            return "Projection: weakening."
        case .fading:
            return "Projection: fading."
        case .onTrack, .completed:
            return "Projection: sustained."
        case .slipping, .stalled:
            return "Projection: weakening."
        }
    }

    private var maintenanceEvidenceSummary: String {
        if hasNoHistory { return "No traces yet. This strand is just getting started." }
        var parts: [String] = []
        parts.append(lastTracePhrase)
        if let days = strand.presence.daysSinceLastActivity {
            parts.append(days == 0 ? "quiet duration: none" : "quiet duration: \(days) \(days == 1 ? "day" : "days")")
        }
        parts.append("\(strand.eventCount) \(strand.eventCount == 1 ? "trace" : "traces") recorded")
        return parts.joined(separator: " · ")
    }

    private var lastActivityPhrase: String {
        guard let date = strand.presence.lastActivity ?? strand.lastTraces.first?.date else {
            return "no activity yet"
        }
        return "last activity \(Self.mediumDate.string(from: date))"
    }

    private var lastTracePhrase: String {
        guard let date = strand.lastTraces.first?.date ?? strand.presence.lastActivity else {
            return "last trace: none"
        }
        return "last trace: \(Self.mediumDate.string(from: date))"
    }

    private var hasNoHistory: Bool {
        strand.eventCount == 0
            && strand.lastTraces.isEmpty
            && strand.presence.daysSinceLastActivity == nil
            && strand.presence.baselineSource == .none
    }

    private static let traceDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}

/// Forward steps drawn as points the line passes through toward a deadline
/// marker — a journey, not a checklist (PRD §6.2). Reached points are filled;
/// upcoming points are hollow; the deadline is a distinct flag.
private struct ForwardNodesView: View {
    let nodes: [StrandForwardNode]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let w = proxy.size.width
                let n = max(nodes.count, 1)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.25))
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                        nodeMark(node)
                            .position(x: xPosition(for: node, index: idx, count: n, width: w),
                                      y: proxy.size.height / 2)
                    }
                }
            }
            .frame(height: 18)

            // Time-positioned step labels beneath, in order — no checkboxes.
            HStack(alignment: .top, spacing: 6) {
                ForEach(nodes) { node in
                    Text(label(for: node))
                        .font(.system(size: 11))
                        .foregroundStyle(node.isReached ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Path: " + nodes.map { "\($0.title)\($0.isReached ? " done" : "")" }.joined(separator: ", "))
    }

    private func xPosition(for node: StrandForwardNode, index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard let date = node.date,
              let first = nodes.compactMap(\.date).min(),
              let last = nodes.compactMap(\.date).max(),
              last > first
        else {
            let step = count > 1 ? width / CGFloat(count - 1) : 0
            return count > 1 ? CGFloat(index) * step + 4 - (index == count - 1 ? 8 : 0) : 4
        }
        let fraction = min(1, max(0, date.timeIntervalSince(first) / last.timeIntervalSince(first)))
        return 4 + (width - 12) * CGFloat(fraction)
    }

    private func label(for node: StrandForwardNode) -> String {
        guard let date = node.date else { return node.title }
        return "\(Self.nodeDate.string(from: date))\n\(node.title)"
    }

    @ViewBuilder
    private func nodeMark(_ node: StrandForwardNode) -> some View {
        if node.isDeadline {
            Image(systemName: "flag.fill")
                .font(.system(size: 12))
                .foregroundStyle(color)
        } else if node.isReached {
            Circle().fill(color).frame(width: 10, height: 10)
        } else {
            Circle().stroke(color.opacity(0.7), lineWidth: 1.6).frame(width: 10, height: 10)
        }
    }

    private static let nodeDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
