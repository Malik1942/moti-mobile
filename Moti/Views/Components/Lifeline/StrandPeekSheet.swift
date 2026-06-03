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
                if strand.effectiveType == .achievement {
                    achievementBody
                } else {
                    maintenanceBody
                }
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

    private var achievementBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(TimelineNarrator.achievementStatus(for: strand))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if strand.forwardNodes.isEmpty {
                Text("No steps mapped yet. Open in Projects to lay out the path.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForwardNodesView(nodes: strand.forwardNodes, color: color)
            }

            HStack(spacing: 10) {
                primaryButton("Open in Projects") {
                    onOpenInProjects(strand.id)
                    dismiss()
                }
                secondaryButton(strand.isPaused ? "Resume" : "Mark as paused") {
                    prefs.setPaused(!strand.isPaused, for: strand.id)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Maintenance

    private var maintenanceBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(TimelineNarrator.maintenanceRhythm(for: strand))
                .font(.system(size: 15, weight: .medium))

            lastTraces

            if let why = TimelineNarrator.whyQuiet(for: strand) {
                Text(why)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            reEntry
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
                Text("No traces yet — this one's just beginning.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(strand.lastTraces) { trace in
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

    private var reEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gentle re-entry")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                primaryButton("Make space this week") {
                    prefs.makeSpaceThisWeek(strand.id); dismiss()
                }
                secondaryButton("Not this week") {
                    prefs.parkForThisWeek(strand.id); dismiss()
                }
            }
            Button {
                prefs.setLowered(!prefs.isLowered(strand.id), for: strand.id); dismiss()
            } label: {
                Text(prefs.isLowered(strand.id) ? "Restore priority" : "Lower priority")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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

    private static let traceDate: DateFormatter = {
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
                let step = n > 1 ? w / CGFloat(n - 1) : 0
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.25))
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                        nodeMark(node)
                            .position(x: n > 1 ? CGFloat(idx) * step + 4 - (idx == n - 1 ? 8 : 0) : 4,
                                      y: proxy.size.height / 2)
                    }
                }
            }
            .frame(height: 18)

            // Step labels beneath, in order — names only, no checkboxes.
            HStack(alignment: .top, spacing: 6) {
                ForEach(nodes) { node in
                    Text(node.title)
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
}
