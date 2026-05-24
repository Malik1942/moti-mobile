import SwiftData
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkItem.createdAt) private var workItems: [WorkItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \CompletionLog.timestamp) private var completionLogs: [CompletionLog]

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("taskUnderstandingMode") private var modeRawValue = TaskUnderstandingMode.foundationModel.rawValue
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false
    @AppStorage("calendarSyncProvider") private var calendarSyncProviderRawValue = CalendarSyncProvider.appleCalendar.rawValue
    @AppStorage("calendarSyncMode") private var calendarSyncModeRawValue = CalendarSyncMode.event.rawValue
    @AppStorage(WorkItemNotificationScheduler.dueRemindersKey)   private var dueRemindersEnabled = true
    @AppStorage(WorkItemNotificationScheduler.progressChecksKey) private var progressChecksEnabled = true
    @AppStorage(SoundManager.enabledKey) private var soundEffectsEnabled = true

    @State private var calendarStatus = AppleCalendarSyncStatus.off
    @State private var showingGoogleComingSoon = false
    @State private var showingOnboarding = false
    @State private var showingResetLocalDataConfirmation = false

    // Smart Capture API key (Gemini) — Settings UI for the Keychain-backed key.
    @State private var apiKeyDraft: String = ""
    @State private var apiKeyConfigured: Bool = SmartCaptureKeyStore.hasKeychainKey
    @State private var apiKeySaveFeedback: String?

    // Timeline Checkpoint notification authorization state.
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var mode: Binding<TaskUnderstandingMode> {
        Binding {
            TaskUnderstandingMode(rawValue: modeRawValue) ?? .foundationModel
        } set: {
            modeRawValue = $0.rawValue
        }
    }

    private var requestedMode: TaskUnderstandingMode {
        TaskUnderstandingMode(rawValue: modeRawValue) ?? .foundationModel
    }

    private var activeMode: TaskUnderstandingMode {
        TaskUnderstandingServiceFactory.resolvedMode(for: requestedMode)
    }

    private var foundationStatus: FoundationModelAvailabilityStatus {
        FoundationModelRuntime.status
    }

    private var calendarSyncMode: Binding<CalendarSyncMode> {
        Binding {
            CalendarSyncMode(rawValue: calendarSyncModeRawValue) ?? .event
        } set: {
            calendarSyncModeRawValue = $0.rawValue
        }
    }

    private var calendarSyncProvider: CalendarSyncProvider {
        CalendarSyncProvider(rawValue: calendarSyncProviderRawValue) ?? .appleCalendar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Intelligence") {
                    Picker("Active", selection: mode) {
                        ForEach(TaskUnderstandingMode.releaseOptions) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    if let description = requestedMode.modeDescription {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Foundation Model", value: foundationStatus.summary)
                    if let fallback = foundationStatus.fallbackSummary, requestedMode == .foundationModel {
                        LabeledContent("Fallback", value: fallback)
                    }
                }

                // Smart Capture API key entry — only relevant in LLM mode.
                // Stored in iOS Keychain; never embedded in the app binary.
                if requestedMode == .llm {
                    smartCaptureAPISection
                }

                Section("Calendar Sync") {
                    Toggle("Auto-sync to Calendar", isOn: calendarSyncToggle)

                    Picker("Calendar Provider", selection: Binding(
                        get: { calendarSyncProvider },
                        set: { provider in
                            if provider == .googleCalendar {
                                showingGoogleComingSoon = true
                                calendarSyncProviderRawValue = CalendarSyncProvider.appleCalendar.rawValue
                            } else {
                                calendarSyncProviderRawValue = provider.rawValue
                            }
                        }
                    )) {
                        Text("Apple Calendar").tag(CalendarSyncProvider.appleCalendar)
                        Text("Google Calendar, Coming Soon")
                            .foregroundStyle(.secondary)
                            .tag(CalendarSyncProvider.googleCalendar)
                    }

                    Picker("Sync Work Items As", selection: calendarSyncMode) {
                        ForEach(CalendarSyncMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    LabeledContent("Sync Status", value: calendarStatusLabel)

                    Text("Scheduled work items are mirrored to Apple Calendar by project. Each project gets its own calendar with a matching name and color. Moti remains the source of truth.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Google Calendar sync is planned for a later version.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                notificationsSection

                Section("Sound") {
                    Toggle("Sound effects", isOn: $soundEffectsEnabled)
                    Text("Soft, occasional cues at key moments — capturing a thought, understanding intent, finishing a task. Quiet by design; respects your silent switch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Moti keeps your work data on this device and uses on-device intelligence to turn natural language captures into project timelines.")
                        .foregroundStyle(.secondary)

                    Button("View Onboarding") {
                        showingOnboarding = true
                    }
                }

                Section("Advanced") {
                    Button("Reset Local Data", role: .destructive) {
                        showingResetLocalDataConfirmation = true
                    }
                    Text("Clears local work items and projects on this device after confirmation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .contentMargins(.bottom, 72, for: .scrollContent)
            .navigationTitle("Settings")
            .onAppear {
                if modeRawValue == TaskUnderstandingMode.mockSLM.rawValue {
                    modeRawValue = FoundationModelRuntime.status.isAvailable
                        ? TaskUnderstandingMode.foundationModel.rawValue
                        : TaskUnderstandingMode.ruleBased.rawValue
                }
                refreshCalendarStatus()
                Task { await refreshNotificationStatus() }
            }
            .alert("Google Calendar Coming Later", isPresented: $showingGoogleComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Google Calendar sync is planned for a later version. Apple Calendar is available now.")
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(isReplay: true) {
                    showingOnboarding = false
                }
            }
            .alert("Reset Local Data?", isPresented: $showingResetLocalDataConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetLocalData()
                }
            } message: {
                Text("This will delete all projects, work items, and onboarding state on this device. This cannot be undone.")
            }
        }
    }

    private var calendarSyncToggle: Binding<Bool> {
        Binding {
            calendarSyncEnabled
        } set: { isEnabled in
            if isEnabled {
                Task {
                    let granted = await AppleCalendarSyncService.shared.requestAccess()
                    await MainActor.run {
                        calendarSyncEnabled = granted
                        calendarSyncProviderRawValue = CalendarSyncProvider.appleCalendar.rawValue
                        if granted {
                            let mode = CalendarSyncMode(rawValue: calendarSyncModeRawValue) ?? .event
                            try? AppleCalendarSyncService.shared.syncExistingScheduledItems(
                                workItems: workItems,
                                projects: projects,
                                mode: mode
                            )
                            try? modelContext.save()
                        }
                        refreshCalendarStatus()
                    }
                }
            } else {
                calendarSyncEnabled = false
                refreshCalendarStatus()
            }
        }
    }

    private var calendarStatusLabel: String {
        guard calendarSyncEnabled else { return AppleCalendarSyncStatus.off.label }
        return calendarStatus.label
    }

    // MARK: - Notifications section

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            LabeledContent("Status", value: notificationStatusLabel)

            switch notificationStatus {
            case .notDetermined:
                Button("Enable Notifications") {
                    Task {
                        _ = await TimelineCheckpointScheduler.shared.requestAuthorizationIfNeeded()
                        await refreshNotificationStatus()
                        await WorkItemNotificationScheduler.shared.reconcile(workItems: workItems)
                    }
                }
            case .denied:
                Button("Open iOS Settings") { openSystemSettings() }
            case .authorized, .provisional, .ephemeral:
                EmptyView()
            @unknown default:
                EmptyView()
            }

            Toggle("Due date reminders", isOn: dueRemindersBinding)
            Text("A heads-up the morning a task is due, and again about an hour before.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Progress check-ins", isOn: progressChecksBinding)
            Text("Gentle nudges at 25%, 50%, 75%, and 90% of a scheduled task's working period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var dueRemindersBinding: Binding<Bool> {
        Binding {
            dueRemindersEnabled
        } set: { newValue in
            dueRemindersEnabled = newValue
            Task { await WorkItemNotificationScheduler.shared.reconcile(workItems: workItems) }
        }
    }

    private var progressChecksBinding: Binding<Bool> {
        Binding {
            progressChecksEnabled
        } set: { newValue in
            progressChecksEnabled = newValue
            Task { await WorkItemNotificationScheduler.shared.reconcile(workItems: workItems) }
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized:    return "On"
        case .provisional:   return "Quiet delivery"
        case .ephemeral:     return "Limited"
        case .denied:        return "Off (enable in iOS Settings)"
        case .notDetermined: return "Not enabled yet"
        @unknown default:    return "Unknown"
        }
    }

    private func refreshNotificationStatus() async {
        let status = await TimelineCheckpointScheduler.shared.authorizationStatus()
        await MainActor.run { notificationStatus = status }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func refreshCalendarStatus() {
        calendarStatus = calendarSyncProvider == .appleCalendar
            ? AppleCalendarSyncService.shared.syncStatus
            : .unavailable

        if calendarSyncEnabled, calendarStatus != .connected {
            calendarSyncEnabled = false
        }
    }

    // MARK: - Smart Capture API section

    @ViewBuilder
    private var smartCaptureAPISection: some View {
        Section("Smart Capture API") {
            SecureField(
                apiKeyConfigured ? "Replace stored key" : "Paste your Gemini API key",
                text: $apiKeyDraft
            )
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit(saveAPIKey)

            HStack {
                Button("Save") { saveAPIKey() }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if apiKeyConfigured {
                    Button("Clear", role: .destructive) { clearAPIKey() }
                }
            }

            LabeledContent("Status", value: apiKeyStatusLabel)

            if let feedback = apiKeySaveFeedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Used by Smart Capture in LLM mode. Stored in the iOS Keychain on this device. Requests go only to generativelanguage.googleapis.com (Google Gemini).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeyStatusLabel: String {
        if SmartCaptureKeyStore.isProxyConfigured {
            return "Routed through proxy"
        }
        if apiKeyConfigured { return "Configured" }
        #if DEBUG
        if DevSecrets.geminiAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return "Using DEBUG fallback"
        }
        #endif
        return "Not configured"
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ok = SmartCaptureKeyStore.setKey(trimmed)
        if ok {
            apiKeyDraft = ""
            apiKeyConfigured = SmartCaptureKeyStore.hasKeychainKey
            apiKeySaveFeedback = "Key saved to Keychain."
        } else {
            apiKeySaveFeedback = "Could not save key to Keychain."
        }
    }

    private func clearAPIKey() {
        _ = SmartCaptureKeyStore.clear()
        apiKeyDraft = ""
        apiKeyConfigured = SmartCaptureKeyStore.hasKeychainKey
        apiKeySaveFeedback = "Key cleared."
    }

    private func resetLocalData() {
        for workItem in workItems {
            try? AppleCalendarSyncService.shared.deleteEvent(for: workItem)
            modelContext.delete(workItem)
        }
        for project in projects {
            modelContext.delete(project)
        }
        for completionLog in completionLogs {
            modelContext.delete(completionLog)
        }
        hasCompletedOnboarding = false
        modeRawValue = TaskUnderstandingMode.foundationModel.rawValue
        calendarSyncEnabled = false
        try? modelContext.save()
    }
}
