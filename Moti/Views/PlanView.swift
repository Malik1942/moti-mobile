import SwiftData
import SwiftUI

/// The Plan tab — Moti's execution surface (PRD: "What exactly should happen
/// next?"). The one place that holds *all* work: the review inbox pinned on
/// top, then everything else grouped by time state. Supersedes the Review tab;
/// its inbox lives on as the first section here.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]

    @State private var selectedWorkItem: WorkItem?
    @State private var workItemPendingDeletion: WorkItem?
    @State private var openSwipeID: UUID?
    @State private var showingAllCompleted = false

    private static let completedPreviewCount = 5
    private static let completedMaxCount = 20

    // MARK: - Buckets

    /// Review inbox: critical (needs timing) first, then light (needs project).
    private var reviewItems: [WorkItem] {
        workItems.filter(\.needsReview) + workItems.filter(\.needsProjectAssignment)
    }

    private var overdueItems: [WorkItem] { WorkItemScope.overdue(workItems) }
    private var activeItems: [WorkItem] { WorkItemScope.activeQueue(workItems) }
    private var upcomingItems: [WorkItem] { WorkItemScope.upcoming(workItems) }
    private var completedItems: [WorkItem] { WorkItemScope.recentlyCompleted(workItems) }

    private var visibleCompleted: [WorkItem] {
        Array(completedItems.prefix(showingAllCompleted ? Self.completedMaxCount : Self.completedPreviewCount))
    }

    private var hasAnyContent: Bool {
        !(reviewItems.isEmpty && overdueItems.isEmpty && activeItems.isEmpty
          && upcomingItems.isEmpty && completedItems.isEmpty)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MotiLayout.sectionSpacing) {
                    if hasAnyContent {
                        if !reviewItems.isEmpty {
                            reviewSection
                        }
                        workSection("Overdue", items: overdueItems)
                        workSection("Active Now", items: activeItems)
                        workSection("Upcoming", items: upcomingItems)
                        completedSection
                    } else {
                        EmptyPlanState()
                    }
                }
                .padding(.horizontal, MotiLayout.pagePadding)
                .padding(.top, MotiLayout.pageTopPadding)
                .padding(.bottom, 32)
            }
            .background(Color.motiGroupedBackground)
            .navigationTitle("Plan")
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
        }
    }

    // MARK: - Sections

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: MotiLayout.cardSpacing) {
            sectionHeader("Needs Review", count: reviewItems.count)
            ForEach(reviewItems) { item in
                deletableRow(item) {
                    ReviewItemRow(item: item)
                        .motiCard()
                }
            }
        }
    }

    @ViewBuilder
    private func workSection(_ title: String, items: [WorkItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MotiLayout.cardSpacing) {
                sectionHeader(title, count: items.count)
                ForEach(items) { item in
                    deletableRow(item) {
                        WorkItemCard(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completedItems.isEmpty {
            VStack(alignment: .leading, spacing: MotiLayout.cardSpacing) {
                sectionHeader("Recently Done", count: completedItems.count)
                ForEach(visibleCompleted) { item in
                    deletableRow(item) {
                        WorkItemCard(item: item)
                            .opacity(0.72)
                    }
                }
                if completedItems.count > Self.completedPreviewCount {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            showingAllCompleted.toggle()
                        }
                    } label: {
                        Text(showingAllCompleted ? "Show fewer" : "Show all")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.motiAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.motiQuietFill, in: Capsule())
            Spacer()
        }
    }

    private func deletableRow<Content: View>(
        _ item: WorkItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let rowContent = content()
        return MotiSwipeDeleteRow(
            isSwipeOpen: openSwipeID == item.id,
            onTap: { selectedWorkItem = item },
            onDelete: { workItemPendingDeletion = item },
            onSwipeOpen: { openSwipeID = item.id },
            onSwipeClose: { if openSwipeID == item.id { openSwipeID = nil } }
        ) {
            rowContent
        }
        .contentShape(RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
    }

    // MARK: - Deletion

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

// MARK: - Review inbox row

struct ReviewItemRow: View {
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

// MARK: - Empty state

private struct EmptyPlanState: View {
    var body: some View {
        VStack(spacing: 14) {
            MotiEmptyStateIcon(systemName: "checklist")

            VStack(spacing: 6) {
                Text("Nothing planned yet.")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Captured work lands here, grouped by what needs attention now.")
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
