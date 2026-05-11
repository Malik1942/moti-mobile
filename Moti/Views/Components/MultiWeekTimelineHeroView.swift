import SwiftUI

struct MultiWeekTimelineHeroView: View {
    let workItems: [WorkItem]
    let selectedProject: String
    var horizonDays = 28

    @State private var selectedItem: WorkItem?

    private let labelWidth: CGFloat = 104
    private let healthWidth: CGFloat = 46
    private let axisHeight: CGFloat = 46
    private let projectHeaderHeight: CGFloat = 26
    private let rowHeight: CGFloat = 38
    private let selectedRowHeight: CGFloat = 46
    private let laneGap: CGFloat = 8
    private let calendar = Calendar.current

    private var startDate: Date {
        calendar.startOfDay(for: .now)
    }

    private var endDate: Date {
        calendar.date(byAdding: .day, value: horizonDays, to: startDate) ?? startDate
    }

    private var visibleItems: [WorkItem] {
        workItems
            .filter { !$0.needsReview }
            .filter { $0.status != .done && $0.status != .archived }
            .filter { item in
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
            let grouped = Dictionary(grouping: visibleItems, by: { $0.projectName ?? "Uncategorized" })
            let orderedProjects = ProjectCatalog.defaultProjects + ["Uncategorized"]
            return orderedProjects.map { project in
                TimelineLane(
                    id: project,
                    title: project,
                    projectName: project == "Uncategorized" ? nil : project,
                    items: grouped[project] ?? [],
                    mode: .project
                )
            }
        }

        let items = visibleItems.filter { $0.projectName == selectedProject }
        if items.isEmpty {
            return [
                TimelineLane(id: "empty-scheduled", title: "Scheduled work", projectName: selectedProject, items: [], mode: .workItem),
                TimelineLane(id: "empty-deadlines", title: "Deadlines", projectName: selectedProject, items: [], mode: .workItem),
                TimelineLane(id: "empty-window", title: "Planning window", projectName: selectedProject, items: [], mode: .workItem)
            ]
        }

        return items.map { item in
            TimelineLane(id: item.id.uuidString, title: item.title, projectName: item.projectName, items: [item], mode: .workItem)
        }
    }

    private var contentHeight: CGFloat {
        axisHeight + lanes.reduce(CGFloat.zero) { $0 + laneHeight(for: $1) }
    }

    private var weekTickDays: [Int] {
        Array(stride(from: 0, to: horizonDays, by: 7))
    }

    private var weekCount: Int {
        max(1, Int(ceil(Double(horizonDays) / 7.0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GeometryReader { proxy in
                let timelineWidth = max(1, proxy.size.width - labelWidth - healthWidth)
                ZStack(alignment: .topLeading) {
                    axisAndGrid(timelineWidth: timelineWidth, height: contentHeight)
                    laneStack(timelineWidth: timelineWidth)
                    todayLine(timelineWidth: timelineWidth, height: contentHeight)
                }
                .frame(height: contentHeight, alignment: .topLeading)
            }
            .frame(height: max(470, contentHeight))
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Continuous work map")
                    .font(.headline)
                Text("\(startDate.formatted(.dateTime.month(.abbreviated).day())) - \(endDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(horizonDays)d horizon", systemImage: "arrow.left.and.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.background.opacity(0.7), in: Capsule())
        }
    }

    private func axisAndGrid(timelineWidth: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<weekCount, id: \.self) { week in
                Rectangle()
                    .fill(Color.secondary.opacity(week.isMultiple(of: 2) ? 0.035 : 0.015))
                    .frame(width: timelineWidth / CGFloat(weekCount), height: height - 24)
                    .offset(x: labelWidth + CGFloat(week) * (timelineWidth / CGFloat(weekCount)), y: 22)
            }

            Rectangle()
                .fill(.secondary.opacity(0.12))
                .frame(height: 1)
                .offset(x: labelWidth, y: axisHeight - 16)

            ForEach(weekTickDays, id: \.self) { day in
                let x = labelWidth + xPosition(forDayOffset: day, timelineWidth: timelineWidth)
                Rectangle()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: 1, height: height - 24)
                    .offset(x: x, y: 20)
            }

            ForEach(weekTickDays, id: \.self) { day in
                let date = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
                let x = labelWidth + xPosition(forDayOffset: day, timelineWidth: timelineWidth)
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.background.opacity(0.78), in: Capsule())
                .foregroundStyle(.secondary)
                .fixedSize()
                .offset(x: min(max(x - 10, labelWidth), labelWidth + timelineWidth - 52), y: 2)
            }
        }
    }

    private func laneStack(timelineWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: axisHeight)
            ForEach(lanes) { lane in
                laneView(lane, timelineWidth: timelineWidth)
                    .frame(height: laneHeight(for: lane), alignment: .topLeading)
            }
        }
    }

    private func laneView(_ lane: TimelineLane, timelineWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.secondary.opacity(0.10))
                .frame(height: 1)
                .offset(x: labelWidth)

            laneLabel(lane)
                .frame(width: labelWidth - 8, alignment: .leading)
                .offset(y: lane.mode == .project ? 6 : 10)

            if lane.items.isEmpty {
                emptyLaneLine(for: lane, timelineWidth: timelineWidth)
            } else {
                ForEach(Array(lane.items.enumerated()), id: \.element.id) { index, item in
                    workBar(for: item, timelineWidth: timelineWidth)
                        .offset(y: barYOffset(for: lane, index: index))
                }
                scheduleBadge(for: lane)
                    .offset(x: labelWidth + timelineWidth + 8, y: lane.mode == .project ? 2 : 6)
            }
        }
    }

    private func laneLabel(_ lane: TimelineLane) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.project(lane.projectName))
                .frame(width: 8, height: 8)
            Text(lane.title)
                .font(.caption.weight(.semibold))
                .lineLimit(lane.mode == .project ? 1 : 2)
                .foregroundStyle(.primary)
        }
    }

    private func emptyLaneLine(for lane: TimelineLane, timelineWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.project(lane.projectName).opacity(0.16))
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: timelineWidth, height: 20, alignment: .leading)
        .offset(x: labelWidth, y: lane.mode == .project ? projectHeaderHeight : 12)
    }

    private func workBar(for item: WorkItem, timelineWidth: CGFloat) -> some View {
        let frame = barFrame(for: item, timelineWidth: timelineWidth)
        let color = Color.project(item.projectName)

        return Button {
            selectedItem = item
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color.opacity(0.30))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(color.opacity(0.70), lineWidth: 1)
                    }

                if frame.width > 58 {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .padding(.leading, 8)
                        .padding(.trailing, 24)
                }

                if let dueX = dueX(for: item, timelineWidth: timelineWidth) {
                    deadlineMarker(for: item)
                        .offset(x: dueX - frame.x - 9)
                }
            }
            .frame(width: frame.width, height: 26)
        }
        .buttonStyle(.plain)
        .offset(x: labelWidth + frame.x)
        .accessibilityLabel("\(item.title), working period")
    }

    private func deadlineMarker(for item: WorkItem) -> some View {
        Image(systemName: "flag.fill")
            .font(.caption2)
            .foregroundStyle(Color.project(item.projectName))
            .padding(4)
            .background(.background, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.project(item.projectName).opacity(0.35), lineWidth: 1)
            }
            .accessibilityLabel("Due date")
    }

    private func scheduleBadge(for lane: TimelineLane) -> some View {
        let score = laneScheduleScore(lane)
        return ScheduleConfidenceBadge(score: score)
    }

    private func todayLine(timelineWidth: CGFloat, height: CGFloat) -> some View {
        let x = labelWidth + dateX(.now, timelineWidth: timelineWidth)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.red.opacity(0.75))
                .frame(width: 2, height: height - 18)
                .offset(x: x, y: 18)
            Text("Today")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .fixedSize()
                .offset(x: min(max(x - 15, labelWidth), labelWidth + timelineWidth - 34), y: 28)
        }
    }

    private func laneHeight(for lane: TimelineLane) -> CGFloat {
        switch lane.mode {
        case .project:
            return projectHeaderHeight + CGFloat(max(lane.items.count, 1)) * rowHeight + laneGap
        case .workItem:
            return selectedRowHeight + laneGap
        }
    }

    private func barYOffset(for lane: TimelineLane, index: Int) -> CGFloat {
        switch lane.mode {
        case .project:
            projectHeaderHeight + CGFloat(index) * rowHeight + 4
        case .workItem:
            10
        }
    }

    private func displayRange(for item: WorkItem) -> (start: Date, end: Date)? {
        if let start = item.workingStartDate, let end = item.workingEndDate {
            return (start, end)
        }
        if let due = item.dueDate {
            return (item.createdAt, due)
        }
        return nil
    }

    private func barFrame(for item: WorkItem, timelineWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        guard let range = displayRange(for: item) else { return (0, 0) }
        let clampedStart = min(max(range.start, startDate), endDate)
        let clampedEnd = min(max(range.end, startDate), endDate)
        let x = dateX(clampedStart, timelineWidth: timelineWidth)
        let endX = dateX(clampedEnd, timelineWidth: timelineWidth)
        return (x, max(24, endX - x))
    }

    private func dueX(for item: WorkItem, timelineWidth: CGFloat) -> CGFloat? {
        guard let dueDate = item.dueDate, dueDate >= startDate, dueDate <= endDate else { return nil }
        return dateX(dueDate, timelineWidth: timelineWidth)
    }

    private func dateX(_ date: Date, timelineWidth: CGFloat) -> CGFloat {
        let clamped = min(max(date, startDate), endDate)
        let total = max(1, endDate.timeIntervalSince(startDate))
        let progress = clamped.timeIntervalSince(startDate) / total
        return timelineWidth * progress
    }

    private func xPosition(forDayOffset day: Int, timelineWidth: CGFloat) -> CGFloat {
        timelineWidth * (CGFloat(day) / CGFloat(max(horizonDays, 1)))
    }

    private func laneScheduleScore(_ lane: TimelineLane) -> Int {
        guard !lane.items.isEmpty else { return 85 }
        let scores = lane.items.map {
            ScheduleConfidenceScorer.score(for: $0, allItems: workItems, now: .now)
        }
        return scores.reduce(0, +) / max(scores.count, 1)
    }
}

private enum TimelineLaneMode {
    case project
    case workItem
}

private struct TimelineLane: Identifiable {
    let id: String
    let title: String
    let projectName: String?
    let items: [WorkItem]
    let mode: TimelineLaneMode
}

private struct TimelineItemSheet: View {
    let item: WorkItem

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkItemCard(item: item)
                }
                Section("Timeline") {
                    if let start = item.workingStartDate, let end = item.workingEndDate {
                        LabeledContent("Working Period", value: "\(start.formatted(date: .abbreviated, time: .shortened)) - \(end.formatted(date: .abbreviated, time: .shortened))")
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
                        WorkItemDetailView(item: item)
                    }
                }
            }
            .navigationTitle("Timeline Detail")
        }
    }
}

private struct ScheduleConfidenceBadge: View {
    let score: Int

    private var color: Color {
        if score >= 75 { return .green }
        if score >= 45 { return .yellow }
        return .red
    }

    var body: some View {
        Text("\(score)%")
            .font(.caption2.weight(.bold))
            .foregroundStyle(score >= 45 && score < 75 ? .black.opacity(0.72) : color)
            .minimumScaleFactor(0.75)
            .lineLimit(1)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.16), in: Circle())
            .overlay {
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 1)
            }
            .accessibilityLabel("Schedule confidence \(score) percent")
    }
}
