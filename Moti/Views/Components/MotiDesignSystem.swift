import SwiftUI

// MARK: - Empty-state icon container

/// Consistent icon container used in empty states across Projects, Review, and any future screens.
/// 64 pt square, soft indigo background, 18 pt corner radius.
struct MotiEmptyStateIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.indigo)
            .frame(width: 64, height: 64)
            .background(
                .indigo.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

// MARK: - Typography tokens

extension Font {
    /// Button label font used on all primary and secondary pill buttons.
    static let motiButtonLabel = Font.subheadline.weight(.semibold)
    /// Empty-state headline (icon screens like Projects, Review).
    static let motiEmptyTitle = Font.title2.weight(.semibold)
    /// Empty-state supporting text.
    static let motiEmptySubtitle = Font.subheadline
}

// MARK: - Layout tokens

enum MotiLayout {
    /// Corner radius for floating content cards (empty-state cards, review list card).
    static let cardRadius: CGFloat = 16
    /// Standard horizontal padding for page-level content.
    static let pagePadding: CGFloat = 16
    /// Padding inside content cards.
    static let cardPadding: CGFloat = 20
    /// Vertical spacing between empty-state elements.
    static let emptyStateSpacing: CGFloat = 12
}
