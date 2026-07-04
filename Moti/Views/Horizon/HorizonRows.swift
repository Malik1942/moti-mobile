import SwiftUI

// Horizon Timeline v2 — T7. Row components (PRD §6.3). Built on one scaffold so
// every row shares the spacing rhythm, the baseline-aligned glyph, and the
// optional second-line slot. The second line is reserved as a *pattern* (an
// optional row below the primary line), so when Phase 2 adds a divergence line
// to achievement rows it slots in exactly where maintenance rhythm copy already
// sits — the primary line never shifts.

// MARK: - Scaffold

/// The shared row skeleton: baseline-aligned type glyph · name · trailing, with
/// an optional second line under the name. Reads to VoiceOver as one element.
struct HorizonRowScaffold<Trailing: View>: View {
    let type: StrandType
    let name: String
    var glyphAccent: Bool = false
    var secondLine: String? = nil
    var secondLineAccent: Bool = false
    /// One combined VoiceOver phrase, e.g. "Portfolio rebuild, 4 days left".
    var accessibilityLabel: String
    @ViewBuilder var trailing: () -> Trailing

    private var secondLineInset: CGFloat { HorizonTheme.glyphSize + HorizonTheme.glyphToNameGap }

    var body: some View {
        VStack(alignment: .leading, spacing: HorizonTheme.secondLineGap) {
            HStack(alignment: .firstTextBaseline, spacing: HorizonTheme.glyphToNameGap) {
                HorizonGlyph(type: type,
                             color: glyphAccent ? HorizonTheme.divergenceAccent : HorizonTheme.secondaryLabel)
                    // optically drop the glyph onto the name's baseline
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + HorizonTheme.glyphSize * 0.30 }

                Text(name)
                    .font(HorizonTheme.nameStyle)
                    .foregroundStyle(HorizonTheme.primaryLabel)
                    .lineLimit(1)

                Spacer(minLength: 12)

                trailing()
            }

            if let secondLine {
                Text(secondLine)
                    .font(HorizonTheme.secondaryStyle)
                    .foregroundStyle(secondLineAccent ? HorizonTheme.divergenceAccent : HorizonTheme.secondaryLabel)
                    .lineLimit(1)
                    .padding(.leading, secondLineInset)
            }
        }
        .padding(.vertical, HorizonTheme.rowVerticalPadding)
        .padding(.leading, HorizonTheme.leadingInset)
        .padding(.trailing, HorizonTheme.trailingInset)
        .frame(maxWidth: .infinity, minHeight: HorizonTheme.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Achievement

/// A landing: name + right-aligned countdown numeral (PRD §6.3). On-track rows
/// are single-line; overdue rows tint amber and pin (handled by the section).
struct AchievementRow: View {
    let name: String
    let placement: BucketPlacement

    var body: some View {
        switch placement {
        case let .dueIn(_, countdown):
            HorizonRowScaffold(type: .achievement, name: name,
                               accessibilityLabel: "\(name), \(spokenLeft(countdown.daysRemaining))") {
                countdownText(HorizonCopy.daysLeft(countdown.daysRemaining), accent: false)
            }
        case let .overdue(overdueDays, _):
            HorizonRowScaffold(type: .achievement, name: name, glyphAccent: true,
                               accessibilityLabel: "\(name), \(overdueDays) days over") {
                countdownText(HorizonCopy.daysOver(overdueDays), accent: true)
            }
        case .achievementNoDueDate:
            HorizonRowScaffold(type: .achievement, name: name,
                               accessibilityLabel: name) { EmptyView() }
        default:
            EmptyView() // not an achievement placement
        }
    }

    private func spokenLeft(_ n: Int) -> String {
        n <= 0 ? "due today" : "\(n) day\(n == 1 ? "" : "s") left"
    }
}

// MARK: - Maintenance

/// A rhythm: name + feed-by phrase, with a rhythm baseline second line when the
/// gap is approaching or exceeded (PRD §6.3). Never uses the word "due".
struct MaintenanceRow: View {
    let name: String
    let placement: BucketPlacement
    var now: Date = Date()
    var calendar: Calendar = .current

    var body: some View {
        switch placement {
        case let .feedBy(_, rhythm):
            let feed = HorizonCopy.feedBy(rhythm.nextFeedBy, now: now, calendar: calendar)
            HorizonRowScaffold(
                type: .maintenance, name: name,
                secondLine: rhythm.isApproaching
                    ? HorizonCopy.rhythm(daysSinceLastFed: rhythm.daysSinceLastFed, typicalGap: rhythm.typicalGap)
                    : nil,
                accessibilityLabel: "\(name), \(feed)"
            ) {
                countdownText(feed, accent: false)
            }
        case let .feedOverdue(rhythm):
            HorizonRowScaffold(
                type: .maintenance, name: name, glyphAccent: true,
                secondLine: HorizonCopy.usualRhythm(typicalGap: rhythm.typicalGap),
                accessibilityLabel: "\(name), \(HorizonCopy.daysSinceLast(rhythm.daysSinceLastFed))"
            ) {
                countdownText(HorizonCopy.daysSinceLast(rhythm.daysSinceLastFed), accent: true)
            }
        case .maintenanceNoRhythm:
            HorizonRowScaffold(type: .maintenance, name: name,
                               accessibilityLabel: name) { EmptyView() }
        default:
            EmptyView() // not a maintenance placement
        }
    }
}

// MARK: - Fold / count row

/// The collapsed row (PRD §6.4). Serves both roles: a near-bucket on-course fold
/// ("▸ 3 more on course") and a far-bucket collapsed count ("▸ 5 futures"); the
/// `FoldSummary.reason` chooses the copy. Quiet by design — tertiary chevron,
/// secondary text.
struct HorizonFoldRow: View {
    let summary: FoldSummary

    private var text: String {
        switch summary.reason {
        case .onCourse: return HorizonCopy.onCourse(summary.count)
        case .collapsedBucket: return HorizonCopy.collapsedCount(summary.count)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.forward")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(HorizonTheme.tertiaryLabel)
            Text(text)
                .font(HorizonTheme.foldStyle)
                .foregroundStyle(HorizonTheme.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.vertical, HorizonTheme.rowVerticalPadding)
        .padding(.leading, HorizonTheme.leadingInset)
        .padding(.trailing, HorizonTheme.trailingInset)
        .frame(maxWidth: .infinity, minHeight: HorizonTheme.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Dispatcher

/// Renders a domain `HorizonRow` as the right concrete row.
struct HorizonStrandRow: View {
    let row: HorizonRow
    var now: Date = Date()
    var calendar: Calendar = .current

    var body: some View {
        switch row.placement {
        case .dueIn, .overdue, .achievementNoDueDate:
            AchievementRow(name: row.name, placement: row.placement)
        case .feedBy, .feedOverdue, .maintenanceNoRhythm:
            MaintenanceRow(name: row.name, placement: row.placement, now: now, calendar: calendar)
        }
    }
}

// MARK: - Shared trailing

/// The right-aligned countdown / feed-by text. Rounded monospaced digits so
/// numerals don't jitter (PRD §7.1); amber only for divergence/overdue signals.
@ViewBuilder
private func countdownText(_ text: String, accent: Bool) -> some View {
    Text(text)
        .font(HorizonTheme.countdownStyle)
        .foregroundStyle(accent ? HorizonTheme.divergenceAccent : HorizonTheme.primaryLabel)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
}
