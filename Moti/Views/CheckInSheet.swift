import SwiftUI

/// Pace-pulse sheet for the Timeline Check-in flow.
///
/// Presented either from a `moti-progress-*` notification tap (via
/// `TaskCheckInCoordinator`) or manually from the work-item detail screen.
/// Design intent: reflective, emotionally safe, fast to answer, non-gamified.
/// Hierarchy — headline → explanation → state cards → note → helper text.
struct CheckInSheet: View {

    /// Short label for the work item being checked in on — purely informational
    /// (used as a subtitle chip). Pass `nil` to omit.
    let taskTitle: String?

    /// Progress fraction (0…1) the check-in is anchored to. Shown in the chip
    /// for context. `nil` for manual pulses where no checkpoint is implied.
    let progress: Double?

    /// Persist the check-in. Called once when the user taps a state button (or
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
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 24)
                    stateButtons
                        .padding(.bottom, 20)
                    noteField
                        .padding(.bottom, 4)
                    noteHint
                        .padding(.bottom, 20)
                    if selection == .bad {
                        replanRow
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.20), value: selection)
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
        .presentationDetents([.fraction(0.60), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How is your pace right now?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text("This helps Moti understand whether the timeline still feels realistic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - State selection buttons

    private var stateButtons: some View {
        HStack(spacing: 10) {
            ForEach(SessionState.allCases, id: \.self) { state in
                stateButton(state)
            }
        }
    }

    private func stateButton(_ state: SessionState) -> some View {
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
            VStack(spacing: 10) {
                Image(systemName: state.glyph)
                    .font(.system(size: 22, weight: .thin))
                    .foregroundStyle(isSelected ? tint : Color(.secondaryLabel))
                Text(state.label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isSelected ? tint : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected
                        ? tint.opacity(0.10)
                        : Color(.secondarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? tint.opacity(0.38)
                            : Color(.separator).opacity(0.55),
                        lineWidth: 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(state.label)\(isSelected ? ", selected" : "")")
    }

    // MARK: - Note field

    private var noteField: some View {
        TextField("Add a note… (optional)", text: $note, axis: .vertical)
            .lineLimit(1...4)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Color(.secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .focused($noteFieldFocused)
            .submitLabel(.done)
    }

    private var noteHint: some View {
        Text("Optional — helps the timeline learn from your rhythm.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
    }

    // MARK: - Bad follow-up row

    private var replanRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Want to adjust the plan?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("You can revise the timeline now or come back to it later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    persistIfNeeded(state: .bad)
                    onReplan()
                } label: {
                    Text("Re-plan now")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    persistIfNeeded(state: .bad)
                    onLater()
                } label: {
                    Text("Later")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.primary)
                        .background(
                            Color(.secondarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            Color.orange.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.75)
        )
    }

    // MARK: - Chip label

    private var chipLabel: String? {
        if let progress {
            return "\(Int(progress * 100))% checkpoint"
        }
        return taskTitle.map { _ in "Pulse" }
    }

    // MARK: - Behavior

    /// Tap a state button. `.good`/`.normal` auto-save and dismiss.
    /// `.bad` holds selection for the follow-up row.
    private func paceTapped(_ state: SessionState) {
        if selection == state {
            // Allow de-selection for correction before saving.
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

    /// Used by the Bad follow-up buttons to save exactly once on the way out.
    private func persistIfNeeded(state: SessionState) {
        onSave(state, note)
    }
}
