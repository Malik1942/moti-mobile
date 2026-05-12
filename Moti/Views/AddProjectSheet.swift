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

                    Menu {
                        ForEach(ProjectCatalog.colorTokens, id: \.self) { token in
                            Button {
                                colorToken = token
                            } label: {
                                HStack {
                                    colorDot(for: token)
                                    Text(token.capitalized)
                                    if token == colorToken {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Color")
                                .foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 7) {
                                colorDot(for: colorToken)
                                Text(colorToken.capitalized)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

        modelContext.insert(Project(name: trimmedName, colorToken: colorToken, sortIndex: projects.nextSortIndex))
        try? modelContext.save()
        dismiss()
    }

    private func colorDot(for token: String) -> some View {
        Circle()
            .fill(Color.projectToken(token))
            .frame(width: 11, height: 11)
    }
}
