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
            .foregroundStyle(isSelected ? .white : color)
            .background(isSelected ? color : color.opacity(0.12), in: Capsule())
    }
}
