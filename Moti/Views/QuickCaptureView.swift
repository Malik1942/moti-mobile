import SwiftData
import SwiftUI

struct QuickCaptureView: View {
    let startWithVoice: Bool
    @Binding var selectedDetent: PresentationDetent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskUnderstandingService) private var parser
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @FocusState private var isInputFocused: Bool

    @StateObject private var speechService = SpeechTranscriptionService()
    @State private var input = ""
    @State private var inputBeforeRecording = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAutoStartVoice = false
    @State private var isInVoiceMode: Bool

    init(startWithVoice: Bool = false, selectedDetent: Binding<PresentationDetent>) {
        self.startWithVoice = startWithVoice
        self._selectedDetent = selectedDetent
        self._isInVoiceMode = State(initialValue: startWithVoice)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isInVoiceMode {
                    voiceBody
                } else {
                    textBody
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .navigationTitle(isInVoiceMode ? "Voice Capture" : "Add to Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navBarToolbar }
            .task {
                if startWithVoice {
                    guard !didAutoStartVoice else { return }
                    didAutoStartVoice = true
                    await startVoiceCapture()
                } else {
                    isInputFocused = true
                }
            }
            .onChange(of: speechService.transcript) { _, transcript in
                applyTranscript(transcript)
            }
            .onDisappear {
                speechService.stopTranscription()
            }
        }
    }

    // MARK: - Toolbar builders

    @ToolbarContentBuilder
    private var navBarToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                speechService.stopTranscription()
                dismiss()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Submit") { submit() }
                .font(.motiButtonLabel)
                .disabled(submitDisabled)
        }
    }

    private var submitDisabled: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isLoading
            || speechService.isRecording
    }

    // MARK: - Voice layout (compact / medium detent)

    private var voiceBody: some View {
        VStack(spacing: 20) {
            Spacer()

            recordingStatusRow

            if !input.isEmpty {
                Text(input)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button { toggleVoiceCapture() } label: {
                ZStack {
                    Circle()
                        .fill(speechService.isRecording ? .red.opacity(0.10) : .indigo.opacity(0.10))
                        .frame(width: 80, height: 80)
                    Image(systemName: speechService.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(speechService.isRecording ? .red : .indigo)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            voiceActionRow

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Placing it on your timeline…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var recordingStatusRow: some View {
        if speechService.isRecording {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("Listening…")
                    .font(.callout.weight(.semibold))
            }
        } else if input.isEmpty {
            Text("Tap the mic to start speaking.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Transcript ready.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var voiceActionRow: some View {
        HStack {
            if !input.isEmpty {
                Button("Clear & Re-record") { clearAndReRecord() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Type instead") { switchToTextMode() }
                .font(.subheadline)
                .foregroundStyle(.indigo)
        }
    }

    // MARK: - Text layout (tap-plus, folded or expanded)
    //
    // The bottomActionRow sits after a Spacer so it is always anchored to the bottom
    // of the available content area. When the keyboard is open the sheet content area
    // shrinks above the keyboard, keeping the row visible. When the keyboard is
    // dismissed the row sits at the sheet bottom. Neither state hides the mic button.

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Tell Moti what you need to work on…", text: $input, axis: .vertical)
                .font(.body)
                .lineLimit(4...10)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($isInputFocused)
                // Return key inserts a newline. Submit is in the nav bar.

            if speechService.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Listening…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear & Re-record") { clearAndReRecord() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Placing it on your timeline…")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Spacer()

            textModeActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
    }

    // Persistent mic row for text mode.
    // Visible in both folded (.medium) and expanded (.large) detents,
    // and regardless of whether the keyboard is showing.
    private var textModeActionBar: some View {
        HStack(spacing: 14) {
            Button {
                isInputFocused = false
                toggleVoiceCapture()
            } label: {
                ZStack {
                    Circle()
                        .fill((speechService.isRecording ? Color.red : Color.indigo).opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: speechService.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(speechService.isRecording ? .red : .indigo)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel(speechService.isRecording ? "Stop recording" : "Start voice capture")

            Spacer()
        }
        .padding(.bottom, 8)
    }

    // MARK: - Mode switching

    private func switchToTextMode() {
        speechService.stopTranscription()
        isInVoiceMode = false
        selectedDetent = .large
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isInputFocused = true
        }
    }

    // MARK: - Voice capture actions

    private func clearAndReRecord() {
        input = ""
        inputBeforeRecording = ""
        speechService.stopTranscription()
        Task { await startVoiceCapture() }
    }

    private func toggleVoiceCapture() {
        if speechService.isRecording {
            speechService.stopTranscription()
            return
        }
        Task { await startVoiceCapture() }
    }

    private func startVoiceCapture() async {
        guard !speechService.isRecording, !isLoading else { return }
        inputBeforeRecording = input.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        do {
            try await speechService.startTranscription()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func applyTranscript(_ transcript: String) {
        let spokenText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }
        input = inputBeforeRecording.isEmpty ? spokenText : "\(inputBeforeRecording) \(spokenText)"
    }

    // MARK: - Submit

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        speechService.stopTranscription()
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let parsed = try await parser.parse(text)
                try await MainActor.run {
                    let item = WorkItem(parsed: parsed)
                    applyProjectMapping(from: parsed, to: item)
                    if parsed.needsReview {
                        item.status = .needsReview
                    }
                    #if DEBUG
                    print(
                        """
                        QuickCapture parsed:
                        input=\(parsed.rawInput)
                        title=\(parsed.title)
                        project=\(parsed.projectGuess ?? "nil")
                        savedProject=\(item.projectName ?? "nil")
                        suggestedProject=\(item.suggestedProjectName ?? "nil")
                        dueDate=\(parsed.dueDate?.description ?? "nil")
                        workingStartDate=\(parsed.workingStartDate?.description ?? "nil")
                        workingEndDate=\(parsed.workingEndDate?.description ?? "nil")
                        needsReview=\(parsed.needsReview)
                        parserConfidence=\(parsed.parserConfidence)
                        """
                    )
                    #endif
                    modelContext.insert(item)
                    try? AppleCalendarSyncService.shared.syncAfterItemChange(item: item)
                    try modelContext.save()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "I could not parse that yet."
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Project mapping

    private func applyProjectMapping(from parsed: ParsedWorkItem, to item: WorkItem) {
        guard let inferredProject = parsed.projectGuess?.trimmingCharacters(in: .whitespacesAndNewlines),
              !inferredProject.isEmpty,
              inferredProject.localizedCaseInsensitiveCompare("Uncategorized") != .orderedSame
        else {
            item.projectName = nil
            item.suggestedProjectName = nil
            return
        }

        if let matchedProject = projects.first(where: {
            $0.name.localizedCaseInsensitiveCompare(inferredProject) == .orderedSame
        }) {
            item.projectName = matchedProject.name
            item.suggestedProjectName = nil
        } else {
            item.projectName = nil
            item.suggestedProjectName = ProjectCatalog.normalizedTemplateName(inferredProject) ?? inferredProject
        }
    }
}
