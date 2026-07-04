import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Horizon Timeline v2 — T8 + T9. The scrolling, bucket-sectioned surface
// (PRD §6). Sticky material section headers with counts; the viewport opens at
// Today; on-track strands fold into a single "on course" row that expands with a
// spring; far buckets collapse to a count row. Reads a pre-assembled
// HorizonSnapshot (built from live data by a later adapter, T14).

// MARK: - Sticky bucket header (T8)

/// A sticky section header on thin material so content scrolls under it
/// (PRD §7.1). Shows the bucket title + strand count; tapping toggles the fold.
struct HorizonSectionHeader: View {
    let title: String
    let count: Int
    var onTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(HorizonTheme.bucketHeaderStyle)
                .tracking(HorizonTheme.bucketHeaderTracking)
                .foregroundStyle(HorizonTheme.tertiaryLabel)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)")
                    .font(HorizonTheme.bucketHeaderStyle.monospacedDigit())
                    .foregroundStyle(HorizonTheme.tertiaryLabel)
            }
        }
        .padding(.horizontal, HorizonTheme.leadingInset)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Screen (T9)

struct HorizonView: View {
    let snapshot: HorizonSnapshot
    var now: Date = Date()
    var calendar: Calendar = .current

    @StateObject private var folds: HorizonFoldStore
    @State private var armedForPastReveal = false
    @State private var didRevealPast = false

    /// `false` renders a non-lazy static list (used by ImageRenderer snapshots,
    /// which don't lay out ScrollView/LazyVStack content). The running app uses
    /// the default scrolling list with sticky headers.
    private let scrolls: Bool

    init(snapshot: HorizonSnapshot, now: Date = Date(), calendar: Calendar = .current,
         folds: HorizonFoldStore = HorizonFoldStore(), scrolls: Bool = true) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        self.scrolls = scrolls
        _folds = StateObject(wrappedValue: folds)
    }

    var body: some View {
        if scrolls {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        pastSection // above Today — up is past (PRD §2, §6.5)
                        ForEach(snapshot.sections) { section in
                            Section {
                                sectionContent(section)
                            } header: {
                                header(section)
                            }
                        }
                    }
                }
                .background(HorizonTheme.background)
                .onAppear {
                    // Open at Today, no animation on first paint (PRD §6, P0.2);
                    // Past sits above, revealed by scrolling up.
                    proxy.scrollTo(TimeBucket.today, anchor: .top)
                    DispatchQueue.main.async { armedForPastReveal = true }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                pastSection
                ForEach(snapshot.sections) { section in
                    header(section)
                    sectionContent(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HorizonTheme.background)
        }
    }

    // MARK: Past (PRD §6.5)

    @ViewBuilder
    private var pastSection: some View {
        if !snapshot.past.isEmpty {
            let year = calendar.component(.year, from: snapshot.past.entries.first?.completedAt ?? now)
            Section {
                ForEach(Array(snapshot.past.entries.enumerated()), id: \.element.id) { index, entry in
                    HorizonPastRow(entry: entry, calendar: calendar)
                    if index < snapshot.past.entries.count - 1 { hairline }
                }
            } header: {
                HorizonSectionHeader(title: HorizonCopy.pastHeader(year: year, count: snapshot.past.entries.count),
                                     count: 0)
                    .onAppear(perform: revealPast)
            }
        }
    }

    private func revealPast() {
        // Suppress the launch-layout pass; only fire once the user actually
        // scrolls up into Past.
        guard armedForPastReveal, !didRevealPast else { return }
        didRevealPast = true
        #if canImport(UIKit)
        if HorizonTheme.motionEnabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        #endif
        HorizonInstrumentation.shared.record(.pastOpen)
    }

    private func header(_ section: BucketSection) -> some View {
        HorizonSectionHeader(title: HorizonCopy.bucketTitle(section.bucket),
                             count: section.strandCount) {
            if section.fold != nil { toggleFold(section.bucket) }
        }
        .id(section.bucket)
    }

    // MARK: Section body

    @ViewBuilder
    private func sectionContent(_ section: BucketSection) -> some View {
        if section.isEmpty {
            // Empty Today → the voice line (PRD §7.3). Other empty buckets never
            // reach here (the snapshot omits them).
            Text(HorizonCopy.nothingToday)
                .font(HorizonTheme.secondaryStyle)
                .foregroundStyle(HorizonTheme.secondaryLabel)
                .padding(.horizontal, HorizonTheme.leadingInset)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                HorizonStrandRow(row: row, now: now, calendar: calendar)
                if index < section.rows.count - 1 || section.fold != nil { hairline }
            }

            if let fold = section.fold {
                if folds.isExpanded(section.bucket.rawValue) {
                    ForEach(Array(fold.rows.enumerated()), id: \.element.id) { index, row in
                        HorizonStrandRow(row: row, now: now, calendar: calendar)
                        if index < fold.rows.count - 1 { hairline }
                    }
                    .transition(.opacity)
                } else {
                    HorizonFoldRow(summary: fold)
                        .onTapGesture { toggleFold(section.bucket) }
                        .transition(.opacity)
                }
            }
        }
    }

    private var hairline: some View {
        HorizonTheme.hairline
            .frame(height: HorizonTheme.hairlineWidth)
            .padding(.leading, HorizonTheme.leadingInset)
    }

    private func toggleFold(_ bucket: TimeBucket) {
        let willExpand = !folds.isExpanded(bucket.rawValue)
        withAnimation(HorizonTheme.motionEnabled ? HorizonTheme.settleSpring : nil) {
            folds.toggle(bucket.rawValue)
        }
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged() // PRD §7.2: .selection on fold toggle
        #endif
        if willExpand {
            HorizonInstrumentation.shared.record(.bucketExpand, detail: bucket.rawValue)
        }
    }
}

#if DEBUG
#Preview("Horizon") {
    HorizonView(snapshot: HorizonSnapshotPreviewData.mixed(),
                now: HorizonSnapshotPreviewData.now,
                calendar: HorizonSnapshotPreviewData.calendar)
}
#endif
