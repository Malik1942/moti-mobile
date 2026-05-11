import SwiftUI

struct SettingsView: View {
    @AppStorage("taskUnderstandingMode") private var modeRawValue = TaskUnderstandingMode.foundationModel.rawValue

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Parser") {
                    LabeledContent("Active", value: "\(activeMode.label), \(activeMode.detailLabel)")
                    LabeledContent("Foundation Model", value: foundationStatus.summary)
                    if let fallback = foundationStatus.fallbackSummary, requestedMode == .foundationModel {
                        LabeledContent("Fallback", value: fallback)
                    }

                    Picker("Preferred", selection: mode) {
                        ForEach(TaskUnderstandingMode.allCases) { mode in
                            Text("\(mode.label), \(mode.detailLabel)").tag(mode)
                        }
                    }
                }

                Section("About") {
                    Text("All task data is stored on this device. No network calls in V0.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
