import SwiftUI

struct MultiWeekTimelineHeroView: View {
    let workItems: [WorkItem]
    let projects: [Project]
    let selectedProject: String
    var horizonDays = 30

    @State private var selectedItem: WorkItem?

    private let labelWidth: CGFloat = 104
    private let plotDividerWidth: CGFloat = 1
    private let plotLeadingGap: CGFloat = 8
    private let axisHeight: CGFloat = 46
    private let projectHeaderHeight: CGFloat = 26
    private let rowHeight: CGFloat = 54
    private let selectedRowHeight: CGFloat = 58
    private let laneGap: CGFloat = 8
    private let minimumPlotHeight: CGFloat = 470
    private let calendar = Calendar.current

    private var startDate: Date {
        calendar.startOfDay(for: .now)
    }

    private var endDate: Date {
        calendar.date(byAdding: .day, value: horizonDays, to: startDate) ?? startDate
    }

    // 2W fills the available plot width exactly (no scroll).
    // Longer horizons use day-based widths so the coordinate system stays readable.
    private func plotContentWidth(availableWidth: CGFloat) -> CGFloat {
        switch horizonDays {
        case ...14:
            return availableWidth
        case ...60:
            return max(availableWidth, CGFloat(horizonDays) * 14)
        default:
            return max(availableWidth, CGFloat(horizonDays) * 8)
        }
    }

    private var visibleItems: [WorkItem] {
        workItems
            .filter { !$0.needsReview }
            // The gantt is the forward planner: it plots actionable work, not
            // archived items or completed history (completed work stays visible
            // in the Timeline's "Completed" card and in Project History).
            .filter { $0.status != .done && $0.status != .archived }
            .filter { item in
                // A passed deadline must never hide a task. Overdue work is kept
                // unconditionally and clamps to the "today" line on render.
                if item.timeState() == .overdue { return true }
                guard let range = displayRange(for: item) else { return false }
                return range.end >= startDate && range.start <= endDate
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.dueDate ?? lhs.workingEndDate ?? .distantFuture
                let rhsDate = rhs.dueDate ?? rhs.workingEndDate ?? .distantFuture
                return lhsDate < rhsDate
            }
    }

    private var lanes: [TimelineLane] {
        if selectedProject == ProjectCatalog.allProjectsLabel {
            let grouped = Dictionary(grouping: visibleItems, by: { $0.displayProject })
            var orderedLaneNames = projects.map(\.name)
            for name in grouped.keys.sorted() where !orderedLaneNames.contains(name) {
                orderedLaneNames.append(name)
            }
            return orderedLaneNames.map { project in
                let runtimeProject = projects.first { $0.name == project }
                return TimelineLane(
                    id: project,
                    title: project,
                    projectName: project == ProjectCatalog.unassignedLabel ? nil : project,
                    colorToken: runtimeProject?.colorToken,
                    items: grouped[project] ?? [],
                    mode: .project
                )
            }
        }

        let items = visibleItems.filter { $0.projectName == selectedProject }
        if items.isEmpty {
            let runtimeProject = projects.first { $0.name == selectedProject }
            return [TimelineLane(
                id: selectedProject,
                title: selectedProject,
                projectName: selectedProject,
                colorToken: runtimeProject?.colorToken,
                items: [],
                mode: .project
            )]
        }
        return items.map { item in
            TimelineLane(
                id: item.id.uuidString,
                title: item.title,
                projectName: item.projectName,
                colorToken: colorToken(for: item.projectName),
                items: [item],
                mode: .workItem
            )
        }
    }

    private var contentHeight: CGFloat {
        axisHeight + lanes.reduce(CGFloat.zero) { $0 + laneHeight(for: $1) }
    }

    // Background band ticks (visual shading only).
    private var tickInterval: Int { horizonDays > 60 ? 14 : 7 }
    private var weekCount: Int { max(1, Int(ceil(Double(horizonDays) / Double(tickInterval)))) }

    // Axis label positions:
    // 2W: 3 labels (start / mid / end).
    // Month: 4 evenly spaced day-level dates.
    // Quarter: true calendar month boundaries (Jun 1, Jul 1, Aug 1) so bars align
    //   with the correct calendar month rather than an arbitrary 30-day offset.
    private var axisTicks: [Int] {
        if horizonDays <= 14 {
            return [0, 7, 14]
        } else if horizonDays <= 60 {
            let step = horizonDays / 3
            return [0, step, step * 2, horizonDays]
        } else {
            var ticks = [0]
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
            while cursor < endDate {
                let days = calendar.dateComponents([.day], from: startDate, to: cursor).day ?? 0
                if days > 0 { ticks.append(days) }
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
            }
            return ticks
        }
    }

    private func axisLabel(for date: Date) -> String {
        if horizonDays > 60 {
            return date.formatted(.dateTime.month(.abbreviated))
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GeometryReader { proxy in
                let availableForPlot = max(1, proxy.size.width - labelWidth - plotDividerWidth - plotLeadingGap)
                let plotWidth = plotContentWidth(availableWidth: availableForPlot)
                let plotHeight = max(minimumPlotHeight, contentHeight)

                HStack(spacing: 0) {
                    // Fixed left column — project names always visible.
                    fixedLabelColumn
                        .frame(width: labelWidth, height: plotHeight, alignment: .topLeading)
                        .clipped()

                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: plotDividerWidth, height: plotHeight)

                    Color.clear
                        .frame(width: plotLeadingGap, height: plotHeight)

                    // 2W: fixed, no scroll — full 14-day overview fits on screen.
                    // Month/Quarter: controlled horizontal scroll with an explicit leading anchor.
                    if horizonDays <= 14 {
                        plotZStack(plotWidth: plotWidth, canvasWidth: plotWidth, plotHeight: plotHeight)
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                plotZStack(plotWidth: plotWidth, canvasWidth: plotWidth, plotHeight: plotHeight)
                                    .id("timeline-start")
                            }
                            .onAppear {
                                scrollProxy.scrollTo("timeline-start", anchor: .leading)
                            }
                            .onChange(of: horizonDays) {
                                scrollProxy.scrollTo("timeline-start", anchor: .leading)
                            }
                        }
                    }
                }
                .frame(height: plotHeight)
            }
            .frame(height: max(minimumPlotHeight, contentHeight))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 540, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.13), .cyan.opacity(0.08), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.indigo.opacity(0.18))
        }
        .sheet(item: $selectedItem) { item in
            TimelineItemSheet(item: item)
                .presentationDetents([.medium])
        }
    }

    // canvasWidth = explicit scroll-content width (plotWidth for 2W, plotWidth+16 for scroll).
    private func plotZStack(plotWidth: CGFloat, canvasWidth: CGFloat, plotHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Size anchor — tells the ZStack (and therefore the ScrollView) the canvas width.
            Color.clear.frame(width: canvasWidth, height: plotHeight)
            axisAndGrid(timelineWidth: plotWidth, height: plotHeight)
            todayLine(timelineWidth: plotWidth, height: plotHeight)
            laneStack(timelineWidth: plotWidth)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("\(startDate.formatted(.dateTime.month(.abbreviated).day())) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Label("\(horizonDays)d", systemImage: "arrow.left.and.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.background.opacity(0.7), in: Capsule())
        }
    }

    // MARK: - Fixed left column

    private var fixedLabelColumn: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: axisHeight)
            ForEach(lanes) { lane in
                HStack(spacing: 6) {
                    Circle()
                        .fill(laneColor(lane))
                        .frame(width: 8, height: 8)
                    Text(lane.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(lane.mode == .project ? 1 : 2)
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: labelWidth - 8, alignment: .leading)
                .frame(height: laneHeight(for: lane), alignment: .topLeading)
                .offset(y: lane.mode == .project ? 6 : 10)
            }
        }
    }

    // MARK: - Plot content

    private func axisAndGrid(timelineWidth: CGFloat, height: CGFloat) -> some View {
        let plotTop = axisHeight
        let plotHeight = max(0, height - axisHeight)
        let horizontalLineCount = max(1, Int(ceil(plotHeight / rowHeight)))

        return ZStack(alignment: .topLeading) {
            // Alternating background bands.
            ForEach(0..<weekCount, id: \.self) { week in
                Rectangle()
                    .fill(Color.secondary.opacity(week.isMultiple(of: 2) ? 0.035 : 0.015))
                    .frame(width: timelineWidth / CGFloat(weekCount), height: plotHeight)
                    .offset(x: CGFloat(week) * (timelineWidth / CGFloat(weekCount)), y: plotTop)
            }

            // Top horizontal rule.
            Rectangle()
                .fill(.secondary.opacity(0.12))
                .frame(width: timelineWidth, height: 1)
                .offset(y: plotTop)

            // Row separator lines.
            ForEach(0...horizontalLineCount, id: \.self) { index in
                let y = plotTop + min(CGFloat(index) * rowHeight, plotHeight)
                Rectangle()
                    .fill(Color.secondary.opacity(index == 0 ? 0.16 : 0.08))
                    .frame(width: timelineWidth, height: 1)
                    .offset(y: y)
            }

            // Vertical tick lines.
            ForEach(axisTicks, id: \.self) { day in
                let x = xPosition(forDayOffset: day, timelineWidth: timelineWidth)
                Rectangle()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: 1, height: plotHeight)
                    .offset(x: x, y: plotTop)
            }

            // Date axis labels.
            ForEach(axisTicks, id: \.self) { day in
                let date = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
                let x = xPosition(forDayOffset: day, timelineWidth: timelineWidth)
                Text(axisLabel(for: date))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.background.opacity(0.78), in: Capsule())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: min(max(x - 10, 0), timelineWidth - 52), y: 2)
            }
        }
    }

    private func laneStack(timelineWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: axisHeight)
            ForEach(lanes) { lane in
                laneContent(lane, timelineWidth: timelineWidth)
                    .frame(height: laneHeight(for: lane), alignment: .topLeading)
            }
        }
    }

    private func laneContent(_ lane: TimelineLane, timelineWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Lane separator line.
            Rectangle()
                .fill(.secondary.opacity(0.10))
                .frame(width: timelineWidth, height: 1)

            if lane.items.isEmpty {
                emptyLaneLine(for: lane, timelineWidth: timelineWidth)
            } else {
                ForEach(Array(lane.items.enumerated()), id: \.element.id) { index, item in
                    workBar(for: item, timelineWidth: timelineWidth)
                        .offset(y: barYOffset(for: lane, index: index))
                }
            }
        }
    }

    private func emptyLaneLine(for lane: TimelineLane, timelineWidth: CGFloat) -> some View {
        Rectangle()
            .fill(laneColor(lane).opacity(0.16))
            .frame(width: timelineWidth, height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(y: lane.mode == .project ? projectHeaderHeight : 12)
    }

    private func workBar(for item: WorkItem, timelineWidth: CGFloat) -> some View {
        let frame = barFrame(for: item, timelineWidth: timelineWidth)
        let color = itemColor(item)
        let isEvent = isEventItem(item)
        let titleWidth = titleWidth(for: frame, timelineWidth: timelineWidth)
        let titleX = readableTextX(for: frame.x, width: titleWidth, timelineWidth: timelineWidth)
        let progressWidth: CGFloat = 38
        let progressX = readableTextX(for: frame.x, width: progressWidth, timelineWidth: timelineWidth)

        return Button {
            selectedItem = item
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .truncationMode(.tail)
                    .frame(width: titleWidth, alignment: .leading)
                    .offset(x: titleX)

                ZStack(alignment: .topLeading) {
                    if isEvent {
                        Circle()
                            .fill(color.opacity(0.30))
                            .overlay {
                                Circle()
                                    .stroke(color.opacity(0.70), lineWidth: 1.2)
                            }
                            .frame(width: frame.width, height: frame.width)
                            .offset(x: frame.x, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.28))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(color.opacity(0.65), lineWidth: 1)
                            }
                            .frame(width: frame.width, height: 20)
                            .offset(x: frame.x)

                        if let dueX = dueX(for: item, timelineWidth: timelineWidth),
                           timelineWidth >= 18 {
                            deadlineMarker(for: item)
                                .offset(x: min(max(dueX - 9, 0), timelineWidth - 18))
                        }
                    }
                }
                .frame(width: timelineWidth, height: 20, alignment: .topLeading)
                .clipped()

                if !isEvent, let progress = elapsedPercentLabel(for: item) {
                    Text(progress)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: progressWidth, alignment: .leading)
                        .offset(x: progressX)
                }
            }
            .frame(width: timelineWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    private func deadlineMarker(for item: WorkItem) -> some View {
        Image(systemName: "flag.fill")
            .font(.caption2)
            .foregroundStyle(itemColor(item))
            .padding(4)
            .background(.background, in: Circle())
            .overlay {
                Circle().stroke(itemColor(item).opacity(0.35), lineWidth: 1)
            }
            .accessibilityLabel("Due date")
    }

    private func todayLine(timelineWidth: CGFloat, height: CGFloat) -> some View {
        let x = dateX(.now, timelineWidth: timelineWidth)
        let plotHeight = max(0, height - axisHeight)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.red.opacity(0.38))
                .frame(width: 1, height: plotHeight)
                .offset(x: x, y: axisHeight)
            Text("Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red.opacity(0.72))
                .fixedSize()
                .offset(x: min(max(x - 15, 0), timelineWidth - 34), y: axisHeight - 16)
        }
    }

    // MARK: - Layout helpers

    private func laneHeight(for lane: TimelineLane) -> CGFloat {
        switch lane.mode {
        case .project:  return projectHeaderHeight + CGFloat(max(lane.items.count, 1)) * rowHeight + laneGap
        case .workItem: return selectedRowHeight + laneGap
        }
    }

    private func barYOffset(for lane: TimelineLane, index: Int) -> CGFloat {
        switch lane.mode {
        case .project:  return projectHeaderHeight + CGFloat(index) * rowHeight + 6
        case .workItem: return 8
        }
    }

    private func titleWidth(for frame: (x: CGFloat, width: CGFloat), timelineWidth: CGFloat) -> CGFloat {
        let remainingWidth = max(0, timelineWidth - frame.x)
        return min(max(44, remainingWidth), min(220, timelineWidth))
    }

    private func readableTextX(for proposedX: CGFloat, width: CGFloat, timelineWidth: CGFloat) -> CGFloat {
        let todayX = dateX(.now, timelineWidth: timelineWidth)
        let adjustedX = abs(proposedX - todayX) < 14 ? proposedX + 10 : proposedX
        return min(max(0, adjustedX), max(0, timelineWidth - width))
    }

    private func isEventItem(_ item: WorkItem) -> Bool {
        if case .event? = renderKind(for: item) {
            return true
        }
        return false
    }

    private func elapsedPercentLabel(for item: WorkItem) -> String? {
        guard case let .period(start, end)? = renderKind(for: item) else { return nil }
        let lowerBound = min(start, end)
        let upperBound = max(start, end)
        let totalMinutes = upperBound.timeIntervalSince(lowerBound) / 60
        guard totalMinutes > 0 else { return nil }

        let elapsedMinutes = Date.now.timeIntervalSince(lowerBound) / 60
        let progress = min(max(elapsedMinutes / totalMinutes, 0), 1)
        return "\(Int((progress * 100).rounded()))%"
    }

    private func accessibilityLabel(for item: WorkItem) -> String {
        if let progress = elapsedPercentLabel(for: item) {
            return "\(item.title), \(progress) time elapsed"
        }
        return "\(item.title), event"
    }

    private func barFrame(for item: WorkItem, timelineWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        switch renderKind(for: item) {
        case .event(let at):
            let x = dateX(at, timelineWidth: timelineWidth)
            let eventWidth: CGFloat = 14
            return (min(max(0, x - (eventWidth / 2)), max(0, timelineWidth - eventWidth)), eventWidth)
        case .period(let start, let end):
            let lowerBound = min(start, end)
            let upperBound = max(start, end)
            let visibleStart = max(lowerBound, startDate)
            let visibleEnd = min(upperBound, endDate)
            guard visibleEnd >= visibleStart else { return (0, 0) }

            let startX = dateX(visibleStart, timelineWidth: timelineWidth)
            let endX = dateX(visibleEnd, timelineWidth: timelineWidth)
            let x = min(max(0, startX), timelineWidth)
            let rawWidth = max(18, endX - startX)
            return (x, min(rawWidth, max(0, timelineWidth - x)))
        case nil:
            return (0, 0)
        }
    }

    private func dueX(for item: WorkItem, timelineWidth: CGFloat) -> CGFloat? {
        guard let dueDate = item.dueDate,
              dueDate >= startDate,
              dueDate <= endDate
        else { return nil }
        return dateX(dueDate, timelineWidth: timelineWidth)
    }

    // MARK: - Render kind

    // Inferred from stored date fields since temporalIntent is not persisted to WorkItem.
    // Same-day working period = point event. Multi-day or deadline-only = period bar.
    private enum TimelineRenderKind {
        case event(at: Date)
        case period(start: Date, end: Date)
    }

    private func renderKind(for item: WorkItem) -> TimelineRenderKind? {
        if let s = item.workingStartDate, let e = item.workingEndDate {
            if calendar.isDate(s, inSameDayAs: e) {
                // Same-day working period → point event; prefer dueDate for exact time.
                return .event(at: item.dueDate ?? s)
            }
            return .period(start: s, end: e)
        }
        // Deadline-only: period from today midnight to due date.
        if let due = item.dueDate {
            return .period(start: startDate, end: due)
        }
        return nil
    }

    // Used for visibleItems filtering and the empty-lane guard.
    private func displayRange(for item: WorkItem) -> (start: Date, end: Date)? {
        switch renderKind(for: item) {
        case .event(let at):
            let s = calendar.startOfDay(for: at)
            let e = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: at) ?? at
            return (s, e)
        case .period(let s, let e):
            return (min(s, e), max(s, e))
        case nil:
            return nil
        }
    }

    private func dateX(_ date: Date, timelineWidth: CGFloat) -> CGFloat {
        let clamped = min(max(date, startDate), endDate)
        let total = max(1, endDate.timeIntervalSince(startDate))
        return timelineWidth * (clamped.timeIntervalSince(startDate) / total)
    }

    private func xPosition(forDayOffset day: Int, timelineWidth: CGFloat) -> CGFloat {
        timelineWidth * (CGFloat(day) / CGFloat(max(horizonDays, 1)))
    }

    private func colorToken(for projectName: String?) -> String? {
        guard let projectName else { return nil }
        return projects.first { $0.name == projectName }?.colorToken
    }

    private func laneColor(_ lane: TimelineLane) -> Color {
        Color.projectToken(lane.colorToken ?? ProjectCatalog.color(for: lane.projectName))
    }

    private func itemColor(_ item: WorkItem) -> Color {
        Color.projectToken(colorToken(for: item.projectName) ?? ProjectCatalog.color(for: item.projectName))
    }
}

// MARK: - Supporting types

private enum TimelineLaneMode { case project, workItem }

private struct TimelineLane: Identifiable {
    let id: String
    let title: String
    let projectName: String?
    let colorToken: String?
    let items: [WorkItem]
    let mode: TimelineLaneMode
}

private struct TimelineItemSheet: View {
    let item: WorkItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkItemCard(item: item)
                }
                Section("Timeline") {
                    if let start = item.workingStartDate, let end = item.workingEndDate {
                        LabeledContent("Working Period", value: "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))")
                    }
                    if let due = item.dueDate {
                        LabeledContent("Due", value: due.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Raw Input") {
                    Text(item.rawInput)
                        .foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Edit") {
                        WorkItemDetailView(showsDeleteAction: false, item: item)
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .navigationTitle("Timeline Detail")
            .alert("Delete Work Item?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteWorkItem()
                }
            } message: {
                Text("This will permanently delete this work item. This cannot be undone.")
            }
        }
    }

    private func deleteWorkItem() {
        try? AppleCalendarSyncService.shared.deleteEvent(for: item)
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
