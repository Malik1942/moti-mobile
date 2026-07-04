import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]

    @State private var showingAddProject = false
    @State private var projectPendingDeletion: Project?
    @State private var selectedProject: Project?

    // Drag-to-reorder state
    @State private var localOrder: [UUID] = []
    @State private var draggedID: UUID? = nil
    @State private var dragTranslation: CGFloat = 0
    @State private var absorbedOffset: CGFloat = 0
    @State private var cardHeights: [UUID: CGFloat] = [:]
    @State private var prevGestureTranslation: CGFloat = 0
    @State private var lastSwapTime: Date = .distantPast

    // Swipe-to-delete: tracks which card is currently swiped open
    @State private var openSwipeID: UUID? = nil

    private let reorderSwapThresholdRatio: CGFloat = 0.72
    private let reorderSwapCooldown: TimeInterval = 0.22
    private let reorderSwapAnimation = Animation.spring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.05)

    private var persistedOrderedProjects: [Project] {
        projects.motiOrdered
    }

    private var orderedProjects: [Project] {
        guard !localOrder.isEmpty else { return persistedOrderedProjects }
        let byID = Dictionary(uniqueKeysWithValues: persistedOrderedProjects.map { ($0.id, $0) })
        let ordered = localOrder.compactMap { byID[$0] }
        let missing = persistedOrderedProjects.filter { !localOrder.contains($0.id) }
        return ordered + missing
    }

    var body: some View {
        NavigationStack {
            Group {
                if orderedProjects.isEmpty {
                    emptyProjectsState
                } else {
                    projectScrollView
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddProject = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add project")
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectSheet()
            }
            .navigationDestination(item: $selectedProject) { project in
                ProjectDetailView(project: project)
            }
            .alert("Delete Project?", isPresented: deleteProjectAlertBinding) {
                Button("Cancel", role: .cancel) { projectPendingDeletion = nil }
                Button("Delete", role: .destructive) {
                    if let project = projectPendingDeletion { deleteProject(project) }
                    projectPendingDeletion = nil
                }
            } message: {
                Text("This will delete the project. Work items in this project will be moved to Unassigned.")
            }
            .onAppear {
                normalizeProjectOrderIfNeeded()
                syncLocalOrderIfNeeded()
            }
            .onChange(of: projects.count) { _, _ in
                syncLocalOrderIfNeeded()
            }
        }
    }

    private var projectScrollView: some View {
        ScrollView {
            LazyVStack(spacing: MotiLayout.cardSpacing) {
                ForEach(orderedProjects) { project in
                    let items = workItems.filter { $0.belongsTo(project) && !$0.needsReview }
                    ProjectCardRow(
                        project: project,
                        items: items,
                        isDragging: draggedID == project.id,
                        isReordering: draggedID != nil,
                        dragTranslation: draggedID == project.id ? dragTranslation : 0,
                        isSwipeOpen: openSwipeID == project.id,
                        onTap: { selectedProject = project },
                        onDelete: { projectPendingDeletion = project },
                        onSwipeOpen: { openSwipeID = project.id },
                        onSwipeClose: { if openSwipeID == project.id { openSwipeID = nil } }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CardHeightPreferenceKey.self,
                                value: [project.id: geo.size.height]
                            )
                        }
                    )
                    .gesture(reorderGesture(for: project))
                    .zIndex(draggedID == project.id ? 1 : 0)
                }
            }
            .padding(.horizontal, MotiLayout.pagePadding)
            .padding(.top, MotiLayout.pageTopPadding)
            .padding(.bottom, MotiLayout.pageBottomPadding)
        }
        .background(Color.motiGroupedBackground)
        .onPreferenceChange(CardHeightPreferenceKey.self) { cardHeights = $0 }
    }

    private func reorderGesture(for project: Project) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if draggedID != project.id {
                        draggedID = project.id
                        dragTranslation = 0
                        absorbedOffset = 0
                        prevGestureTranslation = 0
                        lastSwapTime = .distantPast
                        openSwipeID = nil
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if localOrder.isEmpty {
                            localOrder = orderedProjects.map(\.id)
                        }
                    }
                    updateDrag(drag.translation.height, for: project.id)
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, _) = value {
                    finalizeDrag()
                } else {
                    draggedID = nil
                    dragTranslation = 0
                    absorbedOffset = 0
                    prevGestureTranslation = 0
                    lastSwapTime = .distantPast
                }
            }
    }

    private func updateDrag(_ gestureTranslation: CGFloat, for id: UUID) {
        let rawOffset = gestureTranslation - absorbedOffset
        dragTranslation = rawOffset

        // Direction of movement this frame: positive = downward, negative = upward
        let direction = gestureTranslation - prevGestureTranslation
        prevGestureTranslation = gestureTranslation

        // Cooldown: ignore swap evaluations briefly after a swap to prevent oscillation.
        let now = Date()
        guard now.timeIntervalSince(lastSwapTime) > reorderSwapCooldown else { return }

        // Direction == 0 means no movement this frame; skip
        guard direction != 0 else { return }

        guard let currentIdx = localOrder.firstIndex(of: id) else { return }
        let spacing = MotiLayout.cardSpacing

        if direction < 0, currentIdx > 0 {
            // Moving upward — only check swap with previous card
            let prevID = localOrder[currentIdx - 1]
            let prevH = cardHeights[prevID] ?? 80
            if rawOffset < -swapThreshold(for: prevH, spacing: spacing) {
                withAnimation(reorderSwapAnimation) {
                    localOrder.swapAt(currentIdx, currentIdx - 1)
                }
                absorbedOffset -= prevH + spacing
                dragTranslation = gestureTranslation - absorbedOffset
                lastSwapTime = now
            }
        } else if direction > 0, let idx = localOrder.firstIndex(of: id), idx < localOrder.count - 1 {
            // Moving downward — only check swap with next card
            let nextID = localOrder[idx + 1]
            let nextH = cardHeights[nextID] ?? 80
            if rawOffset > swapThreshold(for: nextH, spacing: spacing) {
                withAnimation(reorderSwapAnimation) {
                    localOrder.swapAt(idx, idx + 1)
                }
                absorbedOffset += nextH + spacing
                dragTranslation = gestureTranslation - absorbedOffset
                lastSwapTime = now
            }
        }
    }

    private func swapThreshold(for neighborHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        neighborHeight * reorderSwapThresholdRatio + spacing
    }

    private func finalizeDrag() {
        guard draggedID != nil else { return }
        let byID = Dictionary(uniqueKeysWithValues: persistedOrderedProjects.map { ($0.id, $0) })
        let reordered = localOrder.compactMap { byID[$0] }
        for (index, p) in reordered.enumerated() { p.sortIndex = index }
        try? modelContext.save()
        SoundManager.shared.play(.reorganized)   // magnetic settle after reorder
        withAnimation(reorderSwapAnimation) {
            draggedID = nil
            dragTranslation = 0
            absorbedOffset = 0
            prevGestureTranslation = 0
            lastSwapTime = .distantPast
        }
    }

    private var deleteProjectAlertBinding: Binding<Bool> {
        Binding {
            projectPendingDeletion != nil
        } set: { isPresented in
            if !isPresented { projectPendingDeletion = nil }
        }
    }

    private var emptyProjectsState: some View {
        VStack(alignment: .leading, spacing: MotiLayout.emptyStateSpacing) {
            MotiEmptyStateIcon(systemName: "square.grid.2x2")
            Text("Add your first project.")
                .font(.motiEmptyTitle)
            Text("Projects help Moti organize work across your timeline.")
                .font(.motiEmptySubtitle)
                .foregroundStyle(.secondary)
            Button {
                showingAddProject = true
            } label: {
                Label("Add Project", systemImage: "square.grid.2x2")
            }
            .buttonStyle(MotiPrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.motiGroupedBackground)
    }

    private func normalizeProjectOrderIfNeeded() {
        var changed = false
        for (index, project) in persistedOrderedProjects.enumerated() where project.sortIndex == nil {
            project.sortIndex = index
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    private func syncLocalOrderIfNeeded() {
        let ids = persistedOrderedProjects.map(\.id)
        if localOrder != ids { localOrder = ids }
    }

    private func deleteProject(_ project: Project) {
        let remainingProjects = projects.filter { $0.id != project.id }.motiOrdered
        for item in workItems where item.belongsTo(project) {
            item.assignProject(nil)
            item.updatedAt = .now
            try? AppleCalendarSyncService.shared.syncAfterItemChange(item: item, projects: remainingProjects)
        }
        modelContext.delete(project)
        for (index, p) in remainingProjects.enumerated() { p.sortIndex = index }
        localOrder = remainingProjects.map(\.id)
        try? modelContext.save()
    }
}

// MARK: - Preference Key

private struct CardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Card row with swipe-to-delete

private struct ProjectCardRow: View {
    let project: Project
    let items: [WorkItem]
    let isDragging: Bool
    let isReordering: Bool
    let dragTranslation: CGFloat
    let isSwipeOpen: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onSwipeOpen: () -> Void
    let onSwipeClose: () -> Void

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

    private var revealProgress: CGFloat {
        guard !isReordering else { return 0 }
        return min(max(abs(swipeOffset) / deleteRevealWidth, 0), 1)
    }

    private var cardOffsetX: CGFloat {
        isReordering ? 0 : swipeOffset
    }

    private var deleteRevealWidth: CGFloat {
        deleteButtonWidth + deleteGap + deleteTrailingInset
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .zIndex(0)

            // Project card — slides left on swipe to reveal delete behind it
            ProjectSummaryRow(project: project, items: items)
                .padding(MotiLayout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .motiCard()
                .clipShape(RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
                .offset(x: cardOffsetX, y: isDragging ? dragTranslation : 0)
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
        // When another card is swiped open, close this one
        .onChange(of: isSwipeOpen) { _, open in
            if !open, swipeOffset != 0 {
                closeSwipe()
            }
        }
        // Close and suppress swipe actions while any project is being reordered.
        .onChange(of: isReordering) { _, reordering in
            if reordering, swipeOffset != 0 {
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
        .allowsHitTesting(revealProgress > 0.85 && !isReordering)
        .accessibilityLabel("Delete project")
        .accessibilityHidden(revealProgress <= 0.85 || isReordering)
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
                guard !isReordering else { return }
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
                guard !isReordering else { return }

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

// MARK: - Summary row content

private struct ProjectSummaryRow: View {
    let project: Project
    let items: [WorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProjectPill(project: project.name, colorToken: project.colorToken)
                Spacer()
                Text("\(items.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let nextDeadline = items.compactMap(\.dueDate).sorted().first {
                Label(nextDeadline.formatted(date: .abbreviated, time: .shortened), systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No scheduled work yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            workloadBar(count: items.count)
        }
    }

    private func workloadBar(count: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.06))
                Capsule().fill(Color.projectToken(project.colorToken).opacity(0.45))
                    .frame(width: min(proxy.size.width, CGFloat(count) / 8 * proxy.size.width))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Project detail

private struct ProjectDetailView: View {
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @AppStorage("taskUnderstandingMode") private var modeRawValue = TaskUnderstandingMode.foundationModel.rawValue
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]
    @State private var showingEdit = false
    @State private var selectedWorkItem: WorkItem?
    @State private var workItemPendingDeletion: WorkItem?
    @State private var openWorkItemSwipeID: UUID?
    @State private var showingHistory = false
    @State private var showingReplan = false
    @State private var replanSeedText = ""
    @State private var replanDetent: PresentationDetent = .large

    private var isLLMMode: Bool {
        (TaskUnderstandingMode(rawValue: modeRawValue) ?? .foundationModel) == .llm
    }

    /// All items for this project — every status, including completed and
    /// archived. Nothing is filtered out by date; grouping happens via buckets
    /// so a passed deadline can never hide a task.
    private var allProjectItems: [WorkItem] {
        workItems.filter { $0.belongsTo(project) }
    }

    var body: some View {
        let buckets = ProjectTaskBuckets(items: allProjectItems)
        let pulse = ProjectPulse(items: allProjectItems, buckets: buckets)
        let historyCount = buckets.completed.count + buckets.skipped.count + buckets.archived.count

        return List {
            headerSection

            Section("Project Pulse") {
                ProjectPulseView(pulse: pulse)
            }

            if allProjectItems.isEmpty {
                Section { Text("No work items yet.").foregroundStyle(.secondary) }
            }

            if !buckets.needsAttention.isEmpty {
                itemsSection("Needs Attention", items: buckets.needsAttention, overdueActions: true)
            }
            if !buckets.currentFocus.isEmpty {
                itemsSection("Current Focus", items: buckets.currentFocus)
            }
            if !buckets.upcoming.isEmpty {
                itemsSection("Upcoming", items: buckets.upcoming)
            }

            if historyCount > 0 {
                Section {
                    DisclosureGroup(isExpanded: $showingHistory) {
                        ForEach(buckets.completed) { historyRow(for: $0) }
                        ForEach(buckets.skipped)   { historyRow(for: $0) }
                        ForEach(buckets.archived)  { historyRow(for: $0) }
                    } label: {
                        Text("History (\(historyCount))")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        // The custom tab bar sits above the system safe area, so the List's own
        // bottom inset isn't enough — add explicit clearance.
        .contentMargins(.bottom, MotiLayout.pageBottomPadding, for: .scrollContent)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showingEdit) {
            EditProjectSheet(project: project)
        }
        .sheet(isPresented: $showingReplan) {
            QuickCaptureView(initialText: replanSeedText, selectedDetent: $replanDetent)
                .presentationDetents([.medium, .large], selection: $replanDetent)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            Button {
                showingEdit = true
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.projectToken(project.colorToken))
                        .frame(width: 12, height: 12)
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func itemsSection(_ title: String, items: [WorkItem], overdueActions: Bool = false) -> some View {
        Section(title) {
            ForEach(items) { item in
                MotiSwipeDeleteRow(
                    isSwipeOpen: openWorkItemSwipeID == item.id,
                    onTap: { selectedWorkItem = item },
                    onDelete: { workItemPendingDeletion = item },
                    onSwipeOpen: { openWorkItemSwipeID = item.id },
                    onSwipeClose: { if openWorkItemSwipeID == item.id { openWorkItemSwipeID = nil } }
                ) {
                    ProjectWorkItemRow(item: item, colorToken: project.colorToken)
                        .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .contextMenu { rowActions(for: item, includeReplan: overdueActions) }
            }
        }
    }

    /// Read-mostly history rows: tap to open, no swipe gesture, but the same
    /// quick actions via context menu (e.g. un-skip by marking done).
    private func historyRow(for item: WorkItem) -> some View {
        Button { selectedWorkItem = item } label: {
            ProjectWorkItemRow(item: item, colorToken: project.colorToken)
        }
        .buttonStyle(.plain)
        .contextMenu { rowActions(for: item, includeReplan: false) }
    }

    @ViewBuilder
    private func rowActions(for item: WorkItem, includeReplan: Bool) -> some View {
        if item.status != .done {
            Button { markDone(item) } label: { Label("Mark Done", systemImage: "checkmark.circle") }
        }
        Button { selectedWorkItem = item } label: { Label("Reschedule", systemImage: "calendar") }
        if item.status != .skipped {
            Button { skip(item) } label: { Label("Skip", systemImage: "minus.circle") }
        }
        if includeReplan && isLLMMode {
            Button { replan(item) } label: { Label("Replan with AI", systemImage: "wand.and.stars") }
        }
        Divider()
        Button(role: .destructive) { workItemPendingDeletion = item } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Overdue / quick actions

    private func markDone(_ item: WorkItem) {
        // Recurring items roll forward and stay active; non-recurring items
        // complete normally. Centralized so every surface agrees.
        WorkItemCompletion.complete(item, in: modelContext)
        SoundManager.shared.play(.completed)
    }

    private func skip(_ item: WorkItem) {
        item.status = .skipped
        item.needsReview = false
        item.updatedAt = .now
        try? modelContext.save()
    }

    /// Seeds the capture sheet with a replan prompt for this item. Only offered
    /// in LLM mode (the Smart Capture planning flow lives there).
    private func replan(_ item: WorkItem) {
        let due = item.dueDate.map { " (was due \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
        replanSeedText = "Replan \"\(item.title)\" for \(project.name)\(due). It's overdue — give me a realistic new plan."
        showingReplan = true
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
        openWorkItemSwipeID = nil
        try? modelContext.save()
    }
}

// MARK: - Project Pulse view

private struct ProjectPulseView: View {
    let pulse: ProjectPulse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(pulse.statusLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(pulse.completed)/\(pulse.total) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                pulseChip(value: pulse.active, label: "Active", tint: .motiAccent)
                pulseChip(value: pulse.overdue, label: "Overdue", tint: pulse.overdue > 0 ? .orange : .secondary)
                pulseChip(value: pulse.upcoming, label: "Upcoming", tint: .secondary)
            }

            if let next = pulse.nextDeadline {
                Label("Next due \(next.formatted(date: .abbreviated, time: .omitted))", systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let last = pulse.lastActivity {
                Text("Last activity \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch pulse.statusLabel {
        case "Needs attention": .orange
        case "Complete":        .green
        case "In progress":     .motiAccent
        default:                .secondary
        }
    }

    private func pulseChip(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous))
    }
}

private struct ProjectWorkItemRow: View {
    let item: WorkItem
    let colorToken: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.projectToken(colorToken))
                .frame(width: 4)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Spacer()
                    let state = item.timeState()
                    Text(state.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stateColor(state))
                }

                Text(timingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var timingSummary: String {
        let period: String
        if let start = item.workingStartDate, let end = item.workingEndDate {
            period = "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        } else {
            period = "Needs timing"
        }

        if let dueDate = item.dueDate {
            return "\(period) · Due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
        }
        return period
    }

    private func stateColor(_ state: WorkItemTimeState) -> Color {
        switch state {
        case .overdue:     .orange
        case .completed:   .green
        case .active:      .motiAccent
        case .needsReview: .orange
        case .upcoming, .skipped, .archived: .secondary
        }
    }
}
