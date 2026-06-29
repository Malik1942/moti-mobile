import SwiftUI

struct ProjectPill: View {
    let project: String?
    var isSelected = false
    var colorToken: String?

    var body: some View {
        let color = Color.projectToken(colorToken ?? ProjectCatalog.color(for: project))

        Text(project ?? ProjectCatalog.unassignedLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? color : Color.motiQuietFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? .clear : color.opacity(0.20), lineWidth: 0.5)
            }
    }
}
