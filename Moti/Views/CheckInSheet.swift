import SwiftUI

/// Lightweight pace pulse sheet for the Timeline Check-in flow.
///
/// Presented either from a `moti-progress-*` notification tap (via
/// `TaskCheckInCoordinator`) or manually from the work-item detail screen.
/// Designed as a *project pulse, not a form* — three large mood buttons, an
/// optional one-line note, and a `Bad`-only follow-up offering a re-plan
/// shortcut.
struct CheckInSheet: View {

    /// Short label for the work item being checked in on — purely informational
    /// (used as a subtitle chip). Pass `nil` to omit.
    let taskTitle: String?

    /// Progress fraction (0…1) the check-in is anchored to. Shown in the chip
    /// for context. `nil` for manual pulses where no checkpoint is implied.
    let progress: Double?

    /// Persist the check-in. Called once when the user taps a pace button (or
    /// after a `Bad` selection if they want to attach a note before deciding
    /// what to do next).
    let onSave: (SessionState, String) -> Void

    /// Bad-only follow-up: user wants to revise the plan now.
    let onReplan: () -> Void

    /// Bad-only follow-up: dismiss without re-planning ("Later").
    let onLater: () -> Void

    /// Top-right × dismiss without recording anything.
    let onCancel: () -> Void

    @State private var selection: SessionState?
    @State private var note: String = ""
    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    paceButtons
                    noteField
                    if selection == .bad {
                        replanRow
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.18), value: selection)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss")
                }
                ToolbarItem(placement: .principal) {
                    if let chip = chipLabel {
                        Text(chip)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How is your pace right now?")
                .font(.title3.weight(.semibold))
            Text("This helps Moti understand whether the timeline still feels realistic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var paceButtons: some View {
        HStack(spacing: 10) {
            ForEach(SessionState.allCases, id: \.self) { state in
                paceButton(state)
            }
        }
    }

    private func paceButton(_ state: SessionState) -> some View {
        let isSelected = selection == state
        let tint: Color = {
            switch state {
            case .good:   return .green
            case .normal: return .indigo
            case .bad:    return .orange
            }
        }()

        return Button {
            paceTapped(state)
        } label: {
            VStack(spacing: 8) {
                Text(state.emoji)
                    .font(.title2)
                Text(state.label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isSelected ? tint : .primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.14) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.55) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("What changed?", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($noteFieldFocused)
                .submitLabel(.done)
            Text("Optional context — helps the timeline learn.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var replanRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Want to adjust the plan?")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Button {
                    persistIfNeeded(state: .bad)
                    onReplan()
                } label: {
                    Text("Re-plan")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    persistIfNeeded(state: .bad)
                    onLater()
                } label: {
                    Text("Later")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.primary)
                        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chipLabel: String? {
        if let progress {
            return "\(Int(progress * 100))% checkpoint"
        }
        return taskTitle.map { _ in "Pulse" }
    }

    // MARK: - Behavior

    /// Tap a pace button. For `.good`/`.normal` we save and dismiss right away
    /// — quick pulse, done. For `.bad` we hold the selection so the user can
    /// add context and choose Re-plan vs. Later from the follow-up row.
    private func paceTapped(_ state: SessionState) {
        if selection == state {
            // Toggle off to allow correction before saving.
            selection = nil
            return
        }
        selection = state
        switch state {
        case .good, .normal:
            onSave(state, note)
        case .bad:
            // Don't auto-save; wait for the user to choose Re-plan / Later so
            // they can attach a note. Persistence happens on that tap.
            break
        }
    }

    /// Used by the Bad follow-up buttons to save once on the way out.
    private func persistIfNeeded(state: SessionState) {
        onSave(state, note)
    }
}
