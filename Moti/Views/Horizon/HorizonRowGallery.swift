import SwiftUI

// Horizon Timeline v2 — a static gallery of every row state, used for visual
// validation (T7 side-by-side check + T6 token verification at Dynamic Type XL
// and in dark mode). Unreferenced by the running app; harmless when the flag is
// off. Fixed `now` so renders are deterministic.

struct HorizonRowGallery: View {
    var now: Date = Date(timeIntervalSince1970: 1_781_000_000) // fixed instant

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        c.firstWeekday = 2
        return c
    }

    private let day: TimeInterval = 86_400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(.today)
            achievement("Ship TestFlight build", .overdue(overdueDays: 2,
                        countdown: CountdownPayload(daysRemaining: -2, dueDate: now.addingTimeInterval(-2 * day))))
            hairline
            maintenance("Weekly long run", .feedOverdue(rhythm: rhythm(feedByOffset: -7, gap: 7, since: 14, approaching: true)))
            hairline
            achievement("Portfolio rebuild", .dueIn(bucket: .today,
                        countdown: CountdownPayload(daysRemaining: 0, dueDate: now)))
            hairline
            HorizonFoldRow(count: 3, reason: .onCourse)

            header(.restOfThisWeek)
            achievement("Grant application", .dueIn(bucket: .restOfThisWeek,
                        countdown: CountdownPayload(daysRemaining: 4, dueDate: now.addingTimeInterval(4 * day))))
            hairline
            maintenance("Sourdough starter", .feedBy(bucket: .restOfThisWeek,
                        rhythm: rhythm(feedByOffset: 1, gap: 7, since: 6, approaching: true)))
            hairline
            maintenance("Water the ferns", .feedBy(bucket: .restOfThisWeek,
                        rhythm: rhythm(feedByOffset: 3, gap: 7, since: 4, approaching: false)))

            header(.later)
            achievement("Someday novel", .achievementNoDueDate)
            hairline
            HorizonFoldRow(count: 5, reason: .collapsedBucket)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HorizonTheme.surface)
    }

    // MARK: - Builders

    private func achievement(_ name: String, _ placement: BucketPlacement) -> some View {
        AchievementRow(name: name, placement: placement)
    }
    private func maintenance(_ name: String, _ placement: BucketPlacement) -> some View {
        MaintenanceRow(name: name, placement: placement, now: now, calendar: calendar)
    }
    private func rhythm(feedByOffset: Double, gap: Double, since: Int, approaching: Bool) -> MaintenanceRhythm {
        MaintenanceRhythm(lastFed: now.addingTimeInterval(-Double(since) * day),
                          typicalGap: gap * day,
                          nextFeedBy: now.addingTimeInterval(feedByOffset * day),
                          daysSinceLastFed: since,
                          daysUntilFeedBy: Int(feedByOffset),
                          isApproaching: approaching)
    }
    private func header(_ bucket: TimeBucket) -> some View {
        Text(HorizonCopy.bucketTitle(bucket).uppercased())
            .font(HorizonTheme.bucketHeaderStyle)
            .tracking(HorizonTheme.bucketHeaderTracking)
            .foregroundStyle(HorizonTheme.tertiaryLabel)
            .padding(.leading, HorizonTheme.leadingInset)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }
    private var hairline: some View {
        HorizonTheme.hairline
            .frame(height: HorizonTheme.hairlineWidth)
            .padding(.leading, HorizonTheme.leadingInset)
    }
}

#if DEBUG
#Preview("Rows — light") { HorizonRowGallery().background(HorizonTheme.background) }
#Preview("Rows — dark") { HorizonRowGallery().background(Color.black).environment(\.colorScheme, .dark) }
#Preview("Rows — XL") { HorizonRowGallery().environment(\.dynamicTypeSize, .xxxLarge) }
#endif
