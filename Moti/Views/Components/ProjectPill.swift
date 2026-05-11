import SwiftUI

struct ProjectPill: View {
    let project: String?
    var isSelected = false

    var body: some View {
        Text(project ?? "Uncategorized")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : Color.project(project))
            .background(isSelected ? Color.project(project) : Color.project(project).opacity(0.12), in: Capsule())
    }
}
