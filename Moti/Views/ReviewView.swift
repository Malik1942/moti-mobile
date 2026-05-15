import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]

    @State private var selectedWorkItem: WorkItem?
    @State private var workItemPendingDeletion: WorkItem?
    @State private var openSwipeID: UUID?

    private var reviewItems: [WorkItem] {
        // Critical review (needsReview) first, then light review (needsProjectAssignment).
        let critical = workItems.filter(\.needsReview)
        let light = workItems.filter(\.needsProjectAssignment)
        return critical + light
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MotiLayout.cardSpacing) {
                    if reviewItems.isEmpty {
                        EmptyReviewState()
                    } else {
                        reviewList
                    }
                }
                .padding(.horizontal, MotiLayout.pagePadding)
                .padding(.top, MotiLayout.pageTopPadding)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .navigationDestination(item: $selectedWorkItem) { item in
                WorkItemDetailView(item: item)
            }
            .alert("Delete Work Item?", isPresented: deleteWorkItemAlertBinding) {
                Button("Cancel", role: .cancel) { workItemPendingDeletion = nil }
                Button("Delete", role: .destructive) {
                    if let item = workItemPendingDeletion {
                        deleteWorkItem(item)
                    }
                    workItemPendingDeletion = nil
                }
            } message: {
                Text("This will permanently delete this work item. This cannot be undone.")
            }
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
        VStack(spacing: MotiLayout.cardSpacing) {
            ForEach(reviewItems) { item in
                MotiSwipeDeleteRow(
                    isSwipeOpen: openSwipeID == item.id,
                    onTap: { selectedWorkItem = item },
                    onDelete: { workItemPendingDeletion = item },
                    onSwipeOpen: { openSwipeID = item.id },
                    onSwipeClose: { if openSwipeID == item.id { openSwipeID = nil } }
                ) {
                    ReviewItemRow(item: item)
                        .motiCard()
                }
                .contentShape(RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
            }
        }
    }

    private var deleteWorkItemAlertBinding: Binding<Bool> {
        Binding {
            workItemPendingDeletion != nil
        } set: { isPresented in
            if !isPresented { workItemPendingDeletion = nil }
        }
    }

    private func deleteWorkItem(_ item: WorkItem) {
        try? AppleCalendarSyncService.shared.deleteEvent(for: item)
        modelContext.delete(item)
        openSwipeID = nil
        try? modelContext.save()
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
        .motiCard()
    }
}

private struct ReviewItemRow: View {
    let item: WorkItem

    private var isLightReview: Bool { item.needsProjectAssignment }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title.isEmpty ? item.rawInput : item.title)
                    .font(.subheadline.weight(.semibold))
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

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(MotiLayout.cardPadding)
    }
}
