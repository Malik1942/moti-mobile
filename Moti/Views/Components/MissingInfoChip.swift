import SwiftUI

struct MissingInfoChip: View {
    let type: MissingInfoType

    var body: some View {
        Text(type.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.motiAccent.opacity(0.10), in: Capsule())
            .foregroundStyle(.motiAccent)
    }
}
