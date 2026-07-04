import SwiftData
import SwiftUI

struct StartSessionSheet: View {
    let workItem: WorkItem
    let onStarted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var selectedDuration: SessionDuration = .oneHour
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    workItemContext
                    durationPicker
                    checkpointPreview
                }
                .padding(24)
                .padding(.bottom, 8)
            }
            .background(Color.motiGroupedBackground)
            .navigationTitle("Timeline Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startButton
            }
        }
    }

    // MARK: - Sub-views

    private var workItemContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session for")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(workItem.title.isEmpty ? workItem.rawInput : workItem.title)
                .font(.headline)
            if let project = workItem.projectName {
                ProjectPill(project: project)
            }
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session length")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                ForEach(SessionDuration.allCases) { duration in
                    Button {
                        withAnimation(.snappy) { selectedDuration = duration }
                    } label: {
                        Text(duration.label)
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(selectedDuration == duration ? .white : .motiAccent)
                            .background(
                                selectedDuration == duration ? Color.motiAccent : Color.motiAccent.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var checkpointPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline checkpoints")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(previewCheckpoints, id: \.self) { progress in
                    let triggerDate = Date.now.addingTimeInterval(selectedDuration.seconds * progress)
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.motiAccent.opacity(0.30))
                            .frame(width: 7, height: 7)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.motiAccent)
                            .frame(width: 30, alignment: .leading)
                        Text(triggerDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(relativeLabel(for: triggerDate))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var startButton: some View {
        Button {
            Task { await startSession() }
        } label: {
            Group {
                if isStarting {
                    ProgressView().tint(.white)
                } else {
                    Text("Start Session")
                }
            }
        }
        .buttonStyle(MotiPrimaryButtonStyle(isFullWidth: true, height: 48))
        .frame(maxWidth: MotiLayout.prominentControlMaxWidth)
        .frame(maxWidth: .infinity)
        .disabled(isStarting)
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(.bar)
    }

    // MARK: - Helpers

    /// Checkpoints for the previewed session — same central policy the scheduler
    /// uses, so the preview always matches what actually fires.
    private var previewCheckpoints: [Double] {
        CheckpointPolicy.checkpoints(
            duration: selectedDuration.seconds,
            isRecurring: workItem.isRecurring
        )
    }

    private func relativeLabel(for date: Date) -> String {
        let mins = Int(date.timeIntervalSince(.now) / 60)
        if mins < 60 { return "in \(mins)m" }
        let h = mins / 60, m = mins % 60
        return m > 0 ? "in \(h)h \(m)m" : "in \(h)h"
    }

    // MARK: - Actions

    private func startSession() async {
        isStarting = true
        defer { isStarting = false }

        _ = await TimelineCheckpointScheduler.shared.requestAuthorizationIfNeeded()

        let now     = Date.now
        let session = WorkSession(
            workItemID:      workItem.id,
            startTime:       now,
            expectedEndTime: now.addingTimeInterval(selectedDuration.seconds),
            isRecurring:     workItem.isRecurring
        )
        modelContext.insert(session)
        try? modelContext.save()

        await TimelineCheckpointScheduler.shared.scheduleCheckpoints(for: session)

        #if DEBUG
        print("[Checkpoints] Session started: \(session.id) (\(selectedDuration.label))")
        #endif

        onStarted()
        dismiss()
    }
}

// MARK: - Session Duration

enum SessionDuration: CaseIterable, Identifiable {
    case thirtyMinutes, oneHour, ninetyMinutes, twoHours, threeHours

    var id: Self { self }

    var label: String {
        switch self {
        case .thirtyMinutes:  "30m"
        case .oneHour:        "1h"
        case .ninetyMinutes:  "1.5h"
        case .twoHours:       "2h"
        case .threeHours:     "3h"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .thirtyMinutes:  1800
        case .oneHour:        3600
        case .ninetyMinutes:  5400
        case .twoHours:       7200
        case .threeHours:    10800
        }
    }
}
