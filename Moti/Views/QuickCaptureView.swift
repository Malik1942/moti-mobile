import SwiftData
import SwiftUI

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskUnderstandingService) private var parser
    @FocusState private var isInputFocused: Bool

    @State private var input = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tell Moti what you need to work on.")
                    .font(.title2.weight(.semibold))
                TextField("Tell Moti what you need to work on...", text: $input, axis: .vertical)
                    .font(.title3)
                    .lineLimit(4...8)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .focused($isInputFocused)
                    .submitLabel(.done)
                    .onSubmit { submit() }

                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Placing it on your timeline...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add to Timeline")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                    } label: {
                        Image(systemName: "mic")
                    }
                    .disabled(true)
                    .accessibilityLabel("Voice capture placeholder")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .task { isInputFocused = true }
        }
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let parsed = try await parser.parse(text)
                try await MainActor.run {
                    let item = WorkItem(parsed: parsed)
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
                        dueDate=\(parsed.dueDate?.description ?? "nil")
                        workingStartDate=\(parsed.workingStartDate?.description ?? "nil")
                        workingEndDate=\(parsed.workingEndDate?.description ?? "nil")
                        needsReview=\(parsed.needsReview)
                        parserConfidence=\(parsed.parserConfidence)
                        """
                    )
                    #endif
                    modelContext.insert(item)
                    try modelContext.save()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "I could not parse that yet."
                    isLoading = false
                }
                return
            }
        }
    }
}
