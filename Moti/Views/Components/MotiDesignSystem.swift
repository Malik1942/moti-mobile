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

// MARK: - Swipe delete row

struct MotiSwipeDeleteRow<Content: View>: View {
    let isSwipeOpen: Bool
    var isSuppressed = false
    let onTap: () -> Void
    let onDelete: () -> Void
    let onSwipeOpen: () -> Void
    let onSwipeClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var swipeOffset: CGFloat = 0
    @State private var swipeStartOffset: CGFloat?
    @State private var swipeAxis: SwipeAxis = .undecided

    private let deleteButtonWidth: CGFloat = 96
    private let deleteButtonHeight: CGFloat = 58
    private let deleteGap: CGFloat = 10
    private let deleteTrailingInset: CGFloat = 10
    private let swipeSettleAnimation = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.84, blendDuration: 0.06)
    private let swipePreviewLimit: CGFloat = 24
    private let swipeTriggerThreshold: CGFloat = 36
    private let swipePredictedTriggerThreshold: CGFloat = 92

    private enum SwipeAxis {
        case undecided
        case horizontal
        case vertical
    }

    private var deleteRevealWidth: CGFloat {
        deleteButtonWidth + deleteGap + deleteTrailingInset
    }

    private var revealProgress: CGFloat {
        guard !isSuppressed else { return 0 }
        return min(max(abs(swipeOffset) / deleteRevealWidth, 0), 1)
    }

    private var cardOffsetX: CGFloat {
        isSuppressed ? 0 : swipeOffset
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .zIndex(0)

            content()
                .offset(x: cardOffsetX)
                .contentShape(RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
                .onTapGesture {
                    if swipeOffset != 0 {
                        closeSwipe()
                    } else {
                        onTap()
                    }
                }
                .gesture(swipeGesture)
                .zIndex(1)

            deleteHitTarget
                .zIndex(2)
        }
        .onChange(of: isSwipeOpen) { _, open in
            if !open, swipeOffset != 0 {
                closeSwipe()
            }
        }
        .onChange(of: isSuppressed) { _, suppressed in
            if suppressed, swipeOffset != 0 {
                closeSwipe()
            }
            resetSwipeGestureState()
        }
    }

    private var deleteAction: some View {
        HStack(spacing: 6) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
            Text("Delete")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(width: deleteButtonWidth, height: deleteButtonHeight)
        .background(Color(.systemRed), in: Capsule())
        .shadow(color: Color(.systemRed).opacity(0.14 * revealProgress), radius: 6, x: 0, y: 3)
        .allowsHitTesting(false)
        .opacity(Double(revealProgress))
        .scaleEffect(0.92 + (0.08 * revealProgress), anchor: .center)
        .offset(x: (1 - revealProgress) * 10)
        .padding(.trailing, deleteTrailingInset)
        .padding(.vertical, 9)
        .accessibilityHidden(revealProgress < 0.5)
    }

    private var deleteHitTarget: some View {
        Button(action: onDelete) {
            Capsule()
                .fill(Color.black.opacity(0.001))
                .frame(width: deleteButtonWidth, height: deleteButtonHeight)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .padding(.trailing, deleteTrailingInset)
        .padding(.vertical, 9)
        .allowsHitTesting(revealProgress > 0.85 && !isSuppressed)
        .accessibilityLabel("Delete")
        .accessibilityHidden(revealProgress <= 0.85 || isSuppressed)
    }

    private func closeSwipe() {
        withAnimation(swipeSettleAnimation) {
            swipeOffset = 0
        }
        onSwipeClose()
        resetSwipeGestureState()
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isSuppressed else { return }
                let h = value.translation.width
                let v = value.translation.height

                if swipeStartOffset == nil {
                    swipeStartOffset = swipeOffset
                    swipeAxis = .undecided
                }

                if swipeAxis == .undecided {
                    if abs(h) > abs(v) * 1.2 {
                        swipeAxis = .horizontal
                        if h < 0, !isSwipeOpen {
                            onSwipeOpen()
                        }
                    } else if abs(v) > abs(h) * 1.1 {
                        swipeAxis = .vertical
                    } else {
                        return
                    }
                }

                guard swipeAxis == .horizontal else { return }

                let base = swipeStartOffset ?? swipeOffset
                swipeOffset = previewOffset(startOffset: base, translation: h)
            }
            .onEnded { value in
                guard !isSuppressed else { return }

                guard swipeAxis == .horizontal else {
                    resetSwipeGestureState()
                    return
                }

                let startOffset = swipeStartOffset ?? 0
                let shouldOpen = shouldSettleOpen(
                    startOffset: startOffset,
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width
                )
                withAnimation(swipeSettleAnimation) {
                    swipeOffset = shouldOpen ? -deleteRevealWidth : 0
                }
                if !shouldOpen { onSwipeClose() }
                resetSwipeGestureState()
            }
    }

    private func previewOffset(startOffset: CGFloat, translation: CGFloat) -> CGFloat {
        let isStartingOpen = startOffset <= -deleteRevealWidth * 0.5

        if isStartingOpen {
            if translation > 0 {
                return -deleteRevealWidth + min(translation * 0.55, swipePreviewLimit)
            }
            return -deleteRevealWidth - min(abs(translation) * 0.12, 8)
        }

        if translation < 0 {
            return -min(abs(translation) * 0.55, swipePreviewLimit)
        }

        return min(translation * 0.12, 6)
    }

    private func shouldSettleOpen(startOffset: CGFloat, translation: CGFloat, predictedTranslation: CGFloat) -> Bool {
        let isStartingOpen = startOffset <= -deleteRevealWidth * 0.5

        if isStartingOpen {
            let wantsClose = translation > swipeTriggerThreshold || predictedTranslation > swipePredictedTriggerThreshold
            return !wantsClose
        }

        return translation < -swipeTriggerThreshold || predictedTranslation < -swipePredictedTriggerThreshold
    }

    private func resetSwipeGestureState() {
        swipeStartOffset = nil
        swipeAxis = .undecided
    }
}
