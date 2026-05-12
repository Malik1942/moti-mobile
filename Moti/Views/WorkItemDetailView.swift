import SwiftData
import SwiftUI

struct WorkItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: WorkItem
    @Query(sort: \Project.createdAt) private var projects: [Project]

    @State private var showingDeleteConfirmation = false
    @State private var showingTimingEditor = false
    @State private var draftWorkingStartDate = Date.now
    @State private var draftWorkingEndDate = Date.now
    @State private var draftDueDate = Date.now
    @State private var draftHasDueDate = true
    @State private var previousWorkingEndDate: Date?
    @State private var previousDueDate: Date?
    @State private var validationMessage: String?
    @State private var isDeleting = false

    var body: some View {
        Form {
            Section("Work Item") {
                TextField("Title", text: $item.title)
                Picker("Project", selection: Binding($item.projectName, replacingNilWith: ProjectCatalog.unassignedLabel)) {
                    Text(ProjectCatalog.unassignedLabel).tag(ProjectCatalog.unassignedLabel)
                    ForEach(projectOptions, id: \.self) { project in
                        Text(project).tag(project)
                    }
                }
                Picker("Status", selection: statusSelection) {
                    ForEach(WorkItemStatus.visibleCases) { status in
                        Text(status.label).tag(status)
                    }
                }
            }

            if shouldShowSuggestedProject {
                Section("Suggested Project") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggested: \(item.suggestedProjectName ?? "")")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("This is not an assigned project until you create it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Create") {
                            createSuggestedProject()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }

            Section("Timing") {
                Button {
                    prepareTimingEditor()
                } label: {
                    timingRow
                }
                .buttonStyle(.plain)

                if let tp = currentTimingProgress {
                    timingProgressRow(tp)
                }
            }

            Section("Original Capture") {
                Text(item.rawInput)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Work Item")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete work item")
            }
        }
        .alert("Delete Work Item?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWorkItem()
            }
        } message: {
            Text("This will remove this work item from your timeline.")
        }
        .sheet(isPresented: $showingTimingEditor) {
            TimingEditorSheet(
                workingStartDate: $draftWorkingStartDate,
                workingEndDate: $draftWorkingEndDate,
                dueDate: $draftDueDate,
                hasDueDate: $draftHasDueDate,
                validationMessage: validationMessage,
                onCancel: { showingTimingEditor = false },
                onClear: clearTiming,
                onSave: saveTiming
            )
            .presentationDetents([.medium, .large])
        }
        .onDisappear {
            guard !isDeleting else { return }
            item.updatedAt = .now
            reconcileReviewState()
            try? AppleCalendarSyncService.shared.syncAfterItemChange(item: item)
            try? modelContext.save()
        }
    }

    private var statusSelection: Binding<WorkItemStatus> {
        Binding<WorkItemStatus>(
            get: {
                if item.needsReview { return .needsReview }
                return WorkItemStatus.visibleCases.contains(item.status) ? item.status : .active
            },
            set: { newStatus in
                item.status = newStatus
                item.needsReview = newStatus == .needsReview
            }
        )
    }

    private var projectOptions: [String] {
        var names = projects.map(\.name)
        if let current = item.projectName, !names.contains(current) {
            names.append(current)
        }
        return names
    }

    private var shouldShowSuggestedProject: Bool {
        guard item.projectName == nil, let suggested = item.suggestedProjectName, !suggested.isEmpty else { return false }
        return !projects.contains { $0.name.localizedCaseInsensitiveCompare(suggested) == .orderedSame }
    }

    private var timingRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Timing")
                    .foregroundStyle(.primary)
                if hasAnyTiming {
                    Text("Working Period: \(workingPeriodLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Due: \(dueDateLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add working period or due date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var currentTimingProgress: (progress: Double, elapsed: Int, total: Int, isEvent: Bool)? {
        guard let start = item.workingStartDate, let end = item.workingEndDate else { return nil }
        let cal = Calendar.current
        let isEvent = cal.isDate(start, inSameDayAs: end)
        let now = Date.now
        let totalSec = end.timeIntervalSince(start)
        guard totalSec > 0 else {
            return (now >= start ? 1.0 : 0.0, now >= start ? 1 : 0, 1, isEvent)
        }
        let progress = min(max(now.timeIntervalSince(start) / totalSec, 0), 1)
        let totalDays = max(1, cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 1)
        let elapsedDays = min(max(cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day ?? 0, 0), totalDays)
        return (progress, elapsedDays, totalDays, isEvent)
    }

    @ViewBuilder
    private func timingProgressRow(_ tp: (progress: Double, elapsed: Int, total: Int, isEvent: Bool)) -> some View {
        if tp.isEvent {
            LabeledContent("Type", value: "Point-in-time event")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Time Progress")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(tp.progress * 100))% elapsed")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tp.progress > 0.85 ? .orange : .secondary)
                }
                ProgressView(value: tp.progress)
                    .tint(tp.progress > 0.85 ? .orange : .indigo)
                Text("\(tp.elapsed) of \(tp.total) days into the working period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var hasAnyTiming: Bool {
        item.dueDate != nil || item.workingStartDate != nil || item.workingEndDate != nil
    }

    private var workingPeriodLabel: String {
        guard let start = item.workingStartDate, let end = item.workingEndDate else {
            return "Not set"
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) -> \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private var dueDateLabel: String {
        item.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "No due marker"
    }

    private func prepareTimingEditor() {
        let calendar = Calendar.current
        let fallbackStart = item.workingStartDate ?? calendar.startOfDay(for: item.createdAt)
        let fallbackEnd = item.workingEndDate ?? item.dueDate ?? fallbackStart

        draftWorkingStartDate = fallbackStart
        draftWorkingEndDate = fallbackEnd
        draftDueDate = item.dueDate ?? endOfDay(for: fallbackEnd)
        draftHasDueDate = item.dueDate != nil
        previousWorkingEndDate = item.workingEndDate
        previousDueDate = item.dueDate
        validationMessage = nil
        showingTimingEditor = true
    }

    private func saveTiming() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draftWorkingStartDate)
        let end = endOfDay(for: draftWorkingEndDate)

        guard start <= end else {
            validationMessage = "Working Start must be before or equal to Working End."
            return
        }

        var dueDate = draftHasDueDate ? draftDueDate : nil
        if
            draftHasDueDate,
            let previousWorkingEndDate,
            let previousDueDate,
            abs(previousDueDate.timeIntervalSince(previousWorkingEndDate)) < 60,
            abs(draftDueDate.timeIntervalSince(previousDueDate)) < 60
        {
            dueDate = end
        }

        if let dueDate, dueDate < end {
            validationMessage = "Due Date should be on or after Working End."
            return
        }

        item.workingStartDate = start
        item.workingEndDate = end
        item.dueDate = dueDate
        item.updatedAt = .now
        reconcileReviewState()
        try? AppleCalendarSyncService.shared.syncAfterItemChange(item: item)
        try? modelContext.save()
        showingTimingEditor = false
    }

    private func clearTiming() {
        item.workingStartDate = nil
        item.workingEndDate = nil
        item.dueDate = nil
        item.updatedAt = .now
        reconcileReviewState()
        try? AppleCalendarSyncService.shared.deleteEvent(for: item)
        try? modelContext.save()
        showingTimingEditor = false
    }

    private func reconcileReviewState() {
        let hasValidPeriod = item.workingStartDate.flatMap { start in
            item.workingEndDate.map { start <= $0 }
        } ?? false
        let hasTimelinePlacement = item.dueDate != nil || hasValidPeriod

        item.needsReview = !hasTimelinePlacement
        item.reviewReason = item.needsReview ? "Missing time information" : nil

        if item.needsReview {
            item.status = .needsReview
        } else if item.status == .needsReview {
            item.status = .active
        }
    }

    private func deleteWorkItem() {
        isDeleting = true
        try? AppleCalendarSyncService.shared.deleteEvent(for: item)
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }

    private func createSuggestedProject() {
        guard let suggested = item.suggestedProjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !suggested.isEmpty else { return }
        if let existingProject = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(suggested) == .orderedSame }) {
            item.projectName = existingProject.name
            item.suggestedProjectName = nil
            return
        }

        modelContext.insert(Project(name: suggested, colorToken: ProjectCatalog.colorToken(forProjectNamed: suggested)))
        item.projectName = suggested
        item.suggestedProjectName = nil
        item.updatedAt = .now
        try? modelContext.save()
    }

    private func endOfDay(for date: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
    }
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0 == ProjectCatalog.unassignedLabel || $0.isEmpty ? nil : $0 }
        )
    }
}

private struct TimingEditorSheet: View {
    @Binding var workingStartDate: Date
    @Binding var workingEndDate: Date
    @Binding var dueDate: Date
    @Binding var hasDueDate: Bool

    let validationMessage: String?
    let onCancel: () -> Void
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Working Start", selection: $workingStartDate, displayedComponents: .date)
                    DatePicker("Working End", selection: $workingEndDate, displayedComponents: .date)
                }

                Section {
                    Toggle("Has Due Date", isOn: $hasDueDate)
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .disabled(!hasDueDate)
                        .foregroundStyle(hasDueDate ? .primary : .secondary)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Clear Timing", role: .destructive, action: onClear)
                }
            }
            .navigationTitle("Edit Timing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}
