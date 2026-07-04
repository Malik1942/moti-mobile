import SwiftUI

struct MultiWeekTimelineHeroView: View {
    let workItems: [WorkItem]
    let projects: [Project]
    let selectedProject: String
    var horizonDays = 30
    var horizonLabel: String?

    @AppStorage("timelineTaskSort") private var timelineTaskSortRawValue = TimelineTaskSort.projectPriority.rawValue
    @State private var selectedItem: WorkItem?

    private let labelWidth: CGFloat = 90
    private let plotDividerWidth: CGFloat = 1
    private let plotLeadingGap: CGFloat = 8
    private let axisHeight: CGFloat = 42
    private let projectHeaderHeight: CGFloat = 20
    private let rowHeight: CGFloat = 62
    private let selectedRowHeight: CGFloat = 62
    private let laneGap: CGFloat = 8
    private let minimumPlotHeight: CGFloat = 278
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
            .sorted(by: areItemsInDisplayOrder)
    }

    private var taskSort: TimelineTaskSort {
        TimelineTaskSort(rawValue: timelineTaskSortRawValue) ?? .projectPriority
    }

    private func areItemsInDisplayOrder(_ lhs: WorkItem, _ rhs: WorkItem) -> Bool {
        switch taskSort {
        case .projectPriority:
            let lhsProject = projectPriorityKey(for: lhs)
            let rhsProject = projectPriorityKey(for: rhs)
            if lhsProject.rank != rhsProject.rank {
                return lhsProject.rank < rhsProject.rank
            }
            if lhsProject.name != rhsProject.name {
                return lhsProject.name.localizedCaseInsensitiveCompare(rhsProject.name) == .orderedAscending
            }
            return isEarlierByTime(lhs, than: rhs)
        case .time:
            return isEarlierByTime(lhs, than: rhs)
        }
    }

    private func projectPriorityKey(for item: WorkItem) -> (rank: Int, name: String) {
        let name = item.displayProject
        if let index = projects.firstIndex(where: { $0.name == name }) {
            return (index, name)
        }
        if name == ProjectCatalog.unassignedLabel {
            return (projects.count + 1, name)
        }
        return (projects.count, name)
    }

    private func isEarlierByTime(_ lhs: WorkItem, than rhs: WorkItem) -> Bool {
        let lhsDate = timelineDateKey(for: lhs)
        let rhsDate = timelineDateKey(for: rhs)
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func timelineDateKey(for item: WorkItem) -> Date {
        item.dueDate ?? item.workingEndDate ?? item.workingStartDate ?? .distantFuture
    }

    private var lanes: [TimelineLane] {
        if selectedProject == ProjectCatalog.allProjectsLabel {
            let grouped = Dictionary(grouping: visibleItems, by: { $0.displayProject })
            var orderedLaneNames = projects.map(\.name)
            for name in grouped.keys.sorted() where !orderedLaneNames.contains(name) {
                orderedLaneNames.append(name)
            }
            return orderedLaneNames.compactMap { project in
                guard let items = grouped[project], !items.isEmpty else { return nil }
                let runtimeProject = projects.first { $0.name == project }
                return TimelineLane(
                    id: project,
                    title: project,
                    projectName: project == ProjectCatalog.unassignedLabel ? nil : project,
                    colorToken: runtimeProject?.colorToken,
                    items: items,
                    mode: .project
                )
            }
        }

        let items = visibleItems.filter { $0.projectName == selectedProject }
        guard !items.isEmpty else { return [] }
        let runtimeProject = projects.first { $0.name == selectedProject }
        return [TimelineLane(
            id: selectedProject,
            title: selectedProject,
            projectName: selectedProject,
            colorToken: runtimeProject?.colorToken,
            items: items,
            mode: .project
        )]
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
        VStack(alignment: .leading, spacing: 14) {
            header

            if visibleItems.isEmpty {
                emptyTimelineWindow
            } else {
                timelineMetricGrid
                timelineDigestList
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.motiSurface,
            in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous)
                .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(horizonTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(horizonLabel ?? "\(horizonDays)d", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.motiQuietFill, in: Capsule())
        }
    }

    private var horizonTitle: String {
        if horizonDays <= 7 { return "Next Week" }
        if horizonDays <= 31 { return "Next Month" }
        if horizonDays <= 92 { return "Next 3 Months" }
        if horizonDays <= 183 { return "Next 6 Months" }
        return "Next Year"
    }

    private var dateRangeText: String {
        "\(startDate.formatted(.dateTime.month(.abbreviated).day())) to \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var headerDetail: String {
        guard !visibleItems.isEmpty else { return dateRangeText }
        return "\(dateRangeText) · \(visibleItems.count) \(visibleItems.count == 1 ? "item" : "items")"
    }

    private var dueInWindowCount: Int {
        visibleItems.filter { item in
            guard let dueDate = item.dueDate else { return false }
            return dueDate <= endDate
        }.count
    }

    private var overdueCount: Int {
        visibleItems.filter { $0.timeState() == .overdue }.count
    }

    private var visibleProjectCount: Int {
        Set(visibleItems.map(\.displayProject)).count
    }

    private var timelineMetricGrid: some View {
        HStack(spacing: 10) {
            timelineMetricCell(value: "\(visibleItems.count)", label: "Scheduled")
            timelineMetricCell(value: "\(dueInWindowCount)", label: "Due")
            timelineMetricCell(
                value: overdueCount > 0 ? "\(overdueCount)" : "\(visibleProjectCount)",
                label: overdueCount > 0 ? "Late" : "Projects",
                tint: overdueCount > 0 ? MotiTheme.today : .primary
            )
        }
    }

    private func timelineMetricCell(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.motiElevatedSurface,
            in: RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous)
                .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
        }
    }

    private var emptyTimelineWindow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.motiAccent)
                .frame(width: 42, height: 42)
                .background(Color.motiAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("No timed work here.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Add a date or work window to place a task on the timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.motiQuietFill, in: RoundedRectangle(cornerRadius: MotiLayout.compactSurfaceRadius, style: .continuous))
    }

    private var timelineDigestList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    selectedItem = item
                } label: {
                    timelineDigestRow(for: item)
                }
                .buttonStyle(.plain)

                if index < visibleItems.count - 1 {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
        .background(
            Color.motiElevatedSurface,
            in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius - 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MotiLayout.cardRadius - 6, style: .continuous)
                .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
        }
    }

    private func timelineDigestRow(for item: WorkItem) -> some View {
        let color = itemColor(item)

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.10))
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(rowBadgeText(for: item))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(rowBadgeTint(for: item))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(rowBadgeTint(for: item).opacity(0.10), in: Capsule())
                }

                HStack(spacing: 6) {
                    Text(item.displayProject)
                        .lineLimit(1)
                    Text("·")
                    Text(itemTimelineDetail(for: item))
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                timelineDigestProgress(for: item, tint: color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func timelineDigestProgress(for item: WorkItem, tint: Color) -> some View {
        GeometryReader { proxy in
            let progress = elapsedProgress(for: item) ?? 0
            let fillWidth = max(progress > 0 ? 8 : 0, proxy.size.width * progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 3)

                if fillWidth > 0 {
                    Capsule()
                        .fill(tint.opacity(0.56))
                        .frame(width: fillWidth, height: 3)
                }
            }
        }
        .frame(height: 3)
    }

    private var timelineChart: some View {
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
                    .fill(Color.secondary.opacity(0.08))
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
                        .font(.caption.weight(.medium))
                        .lineLimit(lane.mode == .project ? 1 : 2)
                        .foregroundStyle(.secondary)
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
            // Top horizontal rule.
            Rectangle()
                .fill(.secondary.opacity(0.08))
                .frame(width: timelineWidth, height: 1)
                .offset(y: plotTop)

            // Row separator lines.
            ForEach(0...horizontalLineCount, id: \.self) { index in
                let y = plotTop + min(CGFloat(index) * rowHeight, plotHeight)
                Rectangle()
                    .fill(Color.secondary.opacity(index == 0 ? 0.10 : 0.055))
                    .frame(width: timelineWidth, height: 1)
                    .offset(y: y)
            }

            // Vertical tick lines.
            ForEach(axisTicks, id: \.self) { day in
                let x = xPosition(forDayOffset: day, timelineWidth: timelineWidth)
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 1, height: plotHeight)
                    .offset(x: x, y: plotTop)
            }

            // Date axis labels.
            ForEach(axisTicks, id: \.self) { day in
                let date = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
                let x = xPosition(forDayOffset: day, timelineWidth: timelineWidth)
                Text(axisLabel(for: date))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: min(max(x - 10, 0), timelineWidth - 52), y: 4)
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
                .fill(.secondary.opacity(0.065))
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
        let progress = elapsedProgress(for: item)

        return Button {
            selectedItem = item
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .truncationMode(.tail)
                    .frame(width: titleWidth, alignment: .leading)
                    .offset(x: titleX)

                Text(itemTimelineDetail(for: item))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(width: titleWidth, alignment: .leading)
                    .offset(x: titleX)

                ZStack(alignment: .topLeading) {
                    if isEvent {
                        Circle()
                            .fill(color.opacity(0.22))
                            .overlay {
                                Circle()
                                    .stroke(color.opacity(0.52), lineWidth: 1)
                            }
                            .frame(width: frame.width, height: frame.width)
                            .offset(x: frame.x, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(color.opacity(0.30), lineWidth: 1)
                            }
                            .frame(width: frame.width, height: 20)
                            .offset(x: frame.x)

                        if let progress, progress > 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color.opacity(0.38))
                                .frame(width: max(7, frame.width * progress), height: 20)
                                .offset(x: frame.x)
                                .clipped()
                        }

                        if let dueX = dueX(for: item, timelineWidth: timelineWidth),
                           timelineWidth >= 18 {
                            deadlineMarker(for: item)
                                .offset(x: min(max(dueX - 8, 0), timelineWidth - 16), y: 1)
                        }
                    }
                }
                .frame(width: timelineWidth, height: 20, alignment: .topLeading)
                .clipped()
            }
            .frame(width: timelineWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    private func deadlineMarker(for item: WorkItem) -> some View {
        Circle()
            .fill(Color.motiSurface)
            .frame(width: 16, height: 16)
            .overlay {
                Circle().stroke(itemColor(item).opacity(0.58), lineWidth: 2)
            }
            .accessibilityLabel("Due date")
    }

    private func todayLine(timelineWidth: CGFloat, height: CGFloat) -> some View {
        let x = dateX(.now, timelineWidth: timelineWidth)
        let plotHeight = max(0, height - axisHeight)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(MotiTheme.today.opacity(0.36))
                .frame(width: 1.5, height: plotHeight)
                .offset(x: x, y: axisHeight)
            Text("Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MotiTheme.today.opacity(0.72))
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

    private func elapsedProgress(for item: WorkItem) -> CGFloat? {
        guard case let .period(start, end)? = renderKind(for: item) else { return nil }
        let lowerBound = min(start, end)
        let upperBound = max(start, end)
        let totalMinutes = upperBound.timeIntervalSince(lowerBound) / 60
        guard totalMinutes > 0 else { return nil }

        let elapsedMinutes = Date.now.timeIntervalSince(lowerBound) / 60
        let progress = min(max(elapsedMinutes / totalMinutes, 0), 1)
        return CGFloat(progress)
    }

    private func accessibilityLabel(for item: WorkItem) -> String {
        if let progress = elapsedProgress(for: item) {
            return "\(item.title), \(Int((progress * 100).rounded())) percent time elapsed"
        }
        return "\(item.title), event"
    }

    private func barFrame(for item: WorkItem, timelineWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        switch renderKind(for: item) {
        case .event(let at):
            let x = dateX(at, timelineWidth: timelineWidth)
            let eventWidth: CGFloat = 16
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

    private func itemTimelineDetail(for item: WorkItem) -> String {
        if item.timeState() == .overdue {
            return "Overdue"
        }

        if isEventItem(item) {
            if let dueDate = item.dueDate {
                return pointDateLabel(dueDate)
            }
            if let start = item.workingStartDate {
                return pointDateLabel(start)
            }
        }

        if let dueDate = item.dueDate {
            return "Due \(relativeDateLabel(dueDate))"
        }

        if let endDate = item.workingEndDate {
            return "Ends \(relativeDateLabel(endDate))"
        }

        return item.status.label
    }

    private func rowBadgeText(for item: WorkItem) -> String {
        if item.timeState() == .overdue {
            return "Late"
        }

        let date = item.dueDate ?? item.workingEndDate ?? item.workingStartDate
        guard let date else { return item.status.label }

        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func rowBadgeTint(for item: WorkItem) -> Color {
        if item.timeState() == .overdue {
            return MotiTheme.today
        }

        let date = item.dueDate ?? item.workingEndDate ?? item.workingStartDate
        guard let date else { return .secondary }

        if calendar.isDateInToday(date) {
            return .primary
        }
        return .secondary
    }

    private func relativeDateLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func pointDateLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow at \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
