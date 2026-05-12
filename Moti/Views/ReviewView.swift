import SwiftData
import SwiftUI

struct ReviewView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]

    private var reviewItems: [WorkItem] {
        // Critical review (needsReview) first, then light review (needsProjectAssignment).
        let critical = workItems.filter(\.needsReview)
        let light = workItems.filter(\.needsProjectAssignment)
        return critical + light
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if reviewItems.isEmpty {
                        EmptyReviewState()
                    } else {
                        reviewList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .onAppear {
                MotiDebugDataLogger.log(
                    source: "ReviewView.onAppear",
                    projects: projects,
                    workItems: workItems,
                    hasCompletedOnboarding: hasCompletedOnboarding
                )
            }
        }
    }

    private var reviewList: some View {
        VStack(spacing: 0) {
            ForEach(Array(reviewItems.enumerated()), id: \.element.id) { index, item in
                NavigationLink {
                    WorkItemDetailView(item: item)
                } label: {
                    ReviewItemRow(item: item)
                }
                .buttonStyle(.plain)

                if index < reviewItems.count - 1 {
                    Divider()
                        .padding(.leading, 18)
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
    }
}

private struct EmptyReviewState: View {
    var body: some View {
        VStack(spacing: 14) {
            MotiEmptyStateIcon(systemName: "tray")

            VStack(spacing: 6) {
                Text("Nothing needs review.")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Captured work with unclear timing will appear here.")
                    .font(.motiEmptySubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
    }
}

private struct ReviewItemRow: View {
    let item: WorkItem

    private var isLightReview: Bool { item.needsProjectAssignment }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title.isEmpty ? item.rawInput : item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                ProjectPill(project: item.projectName)

                if isLightReview {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.caption)
                        Text(item.lightReviewReason)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(item.reviewReason ?? "Needs timing before it can be placed on the timeline.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange.opacity(0.78))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}
