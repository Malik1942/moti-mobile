import SwiftUI

/// Compact floating card that appears over the current UI when a timeline
/// checkpoint fires while the app is foregrounded.
///
/// Design intent: quiet pulse from the system, not a demand.
/// - One-tap mood response (no typing required)
/// - Dismissible via the × button
/// - Auto-dismisses after 8 seconds of inactivity
/// - Animates in/out from below using the parent's transition
struct CheckpointFloatingCard: View {
    let event:     CheckpointCoordinator.CheckpointEvent
    let onRespond: (ProgressState) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            moodButtons
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 18, x: 0, y: 4)
        .padding(.horizontal, 16)
        // Restart the 8-second timer whenever a new event arrives.
        .task(id: event.id) {
            try? await Task.sleep(for: .seconds(8))
            onDismiss()
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Int(event.progress * 100))% checkpoint")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.motiAccent)
                Text("How's the session progressing?")
                    .font(.subheadline.weight(.medium))
            }
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var moodButtons: some View {
        HStack(spacing: 8) {
            ForEach(ProgressState.allCases, id: \.self) { state in
                Button {
                    onRespond(state)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.glyph)
                            .font(.system(size: 13, weight: .thin))
                        Text(state.label)
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
                    .background(
                        Color(.secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
