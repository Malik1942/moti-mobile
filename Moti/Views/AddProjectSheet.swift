import SwiftData
import SwiftUI

struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt) private var projects: [Project]

    @State private var name = ""
    @State private var colorToken = "indigo"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Project name", text: $name)
                    Picker("Color", selection: $colorToken) {
                        ForEach(ProjectCatalog.colorTokens, id: \.self) { token in
                            HStack {
                                Circle()
                                    .fill(color(for: token))
                                    .frame(width: 12, height: 12)
                                Text(token.capitalized)
                            }
                            .tag(token)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Project name is required."
            return
        }
        guard !projects.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            errorMessage = "A project with that name already exists."
            return
        }

        modelContext.insert(Project(name: trimmedName, colorToken: colorToken))
        try? modelContext.save()
        dismiss()
    }

    private func color(for token: String) -> Color {
        switch token {
        case "blue": .blue
        case "green": .green
        case "purple": .purple
        case "orange": .orange
        case "gray": .gray
        default: .indigo
        }
    }
}
