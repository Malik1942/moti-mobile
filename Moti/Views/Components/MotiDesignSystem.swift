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
    /// Corner radius for floating content cards (empty-state cards, project cards, review cards).
    static let cardRadius: CGFloat = 16
    /// Standard horizontal padding for page-level content.
    static let pagePadding: CGFloat = 16
    /// Gap between the navigation title and the first content card on every main tab.
    static let titleToContentSpacing: CGFloat = 24
    static let pageTopPadding: CGFloat = titleToContentSpacing
    /// Vertical spacing between content sections / cards within a page.
    static let sectionSpacing: CGFloat = 18
    /// Vertical gap between individual stacked cards (projects, review items).
    static let cardSpacing: CGFloat = 12
    /// Padding inside content cards.
    static let cardPadding: CGFloat = 16
    /// Vertical spacing between empty-state elements.
    static let emptyStateSpacing: CGFloat = 12
    /// Extra bottom scroll clearance so content isn't hidden behind the custom tab bar.
    static let pageBottomPadding: CGFloat = 32
}

// MARK: - Card container style

/// Shared card surface used by Project cards, Review cards, and Timeline content cards.
/// Applies a white background, system corner radius, and a soft drop shadow.
struct MotiCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func motiCard() -> some View {
        modifier(MotiCardModifier())
    }
}
