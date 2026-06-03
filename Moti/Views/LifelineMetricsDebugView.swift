#if DEBUG
import SwiftData
import SwiftUI

/// DEBUG-only read-out for the Lifelines instrumentation (PRD §9). Local data
/// only — nothing here leaves the device. Surfaces the gating signals so the
/// redesign can be made *learnable on real data*: glance-and-close rate,
/// surfaced-strand outcomes, and the load-bearing **coverage** metric (fraction
/// of strands with zero events by effective type — the maintenance-feeding risk).
struct LifelineMetricsDebugView: View {
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query private var completionLogs: [CompletionLog]

    @ObservedObject private var metrics = LifelineInstrumentation.shared
    @ObservedObject private var prefs = StrandPreferenceStore.shared
    @ObservedObject private var overrides = LifelineTypeOverrideStore.shared

    private var strands: [Strand] {
        let pausedIDs = Set((projects.map { $0.id.uuidString } + [Strand.unassignedID])
            .filter { prefs.isPaused($0) })
        return StrandTimelineBuilder(
            projects: projects,
            workItems: WorkItemScope.timeline(workItems),
            completionLogs: completionLogs,
            pausedStrandIDs: pausedIDs,
            typeOverrides: overrides.overrides
        ).build()
    }

    var body: some View {
        List {
            coverageSection
            engagementSection
            overrideSection
            recordsSection
            Section {
                Button("Clear metrics", role: .destructive) { metrics.clear() }
                Button("Clear type overrides") { overrides.clearAll() }
            }
        }
        .navigationTitle("Lifelines Metrics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Coverage (the maintenance-feeding metric)

    private var coverageSection: some View {
        let snap = metrics.coverage(for: strands)
        return Section {
            row("Strands total", "\(snap.total)")
            row("Zero-event · all", percent(snap.zeroFraction(for: nil), snap.zeroEvents, snap.total))
            row("Zero-event · achievement", percent(snap.zeroFraction(for: "achievement"), snap.achievementZeroEvents, snap.achievementTotal))
            row("Zero-event · maintenance", percent(snap.zeroFraction(for: "maintenance"), snap.maintenanceZeroEvents, snap.maintenanceTotal))
        } header: {
            Text("Coverage (live)")
        } footer: {
            Text("High zero-event maintenance coverage = strands rendering drifted/absent only because nothing feeds them. This gates whether v1 needs a maintenance touch path.")
        }
    }

    // MARK: Engagement

    private var engagementSection: some View {
        Section("Engagement") {
            row("Opens", "\(metrics.openCount)")
            row("Closes", "\(metrics.closeCount)")
            row("Glance-and-close", metrics.glanceAndCloseRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            row("Drift surfaced", "\(metrics.surfaceCount)")
            let tally = metrics.surfacedOutcomeTally
            row("→ re-engaged (make space)", "\(tally["make-space"] ?? 0)")
            row("→ parked (not this week)", "\(tally["not-this-week"] ?? 0)")
            row("→ lowered", "\(tally["lowered"] ?? 0)")
            row("→ ignored", "\(tally["ignored"] ?? 0)")
        }
    }

    // MARK: Type override ladder (DEBUG exercise; no production user flow)

    private var overrideSection: some View {
        Section {
            ForEach(strands, id: \.id) { strand in
                overrideRow(strand)
            }
        } header: {
            Text("Type ladder")
        } footer: {
            Text("DEBUG override map only — no user entry point ships. effectiveType = userOverrideType ?? computedType.")
        }
    }

    @ViewBuilder
    private func overrideRow(_ strand: Strand) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(strand.name).font(.subheadline)
                Text("computed: \(strand.computedType.rawValue) · effective: \(strand.effectiveType.rawValue)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Auto (computed)") { overrides.setOverride(nil, for: strand.id) }
                Button("Force achievement") { overrides.setOverride(.achievement, for: strand.id) }
                Button("Force maintenance") { overrides.setOverride(.maintenance, for: strand.id) }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(strand.userOverrideType == nil ? Color.secondary : Color.indigo)
            }
        }
    }

    // MARK: Recent records

    private var recordsSection: some View {
        Section("Recent events (\(metrics.records.count))") {
            ForEach(Array(metrics.records.suffix(30).reversed()), id: \.id) { r in
                HStack {
                    Text(r.kind.rawValue)
                        .font(.caption.weight(.semibold))
                        .frame(width: 64, alignment: .leading)
                    Text([r.effectiveType, r.presenceState, r.detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(r.timestamp, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }

    private func percent(_ fraction: Double, _ n: Int, _ d: Int) -> String {
        d == 0 ? "—" : "\(Int((fraction * 100).rounded()))% (\(n)/\(d))"
    }
}
#endif
