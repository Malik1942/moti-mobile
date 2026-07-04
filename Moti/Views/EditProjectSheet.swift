import SwiftData
import SwiftUI

struct EditProjectSheet: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \WorkItem.createdAt) private var workItems: [WorkItem]

    @State private var name: String
    @State private var colorToken: String
    @State private var errorMessage: String?

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _colorToken = State(initialValue: project.colorToken)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Project name", text: $name)
                        .onChange(of: name) { _, _ in errorMessage = nil }

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
            .navigationTitle("Edit Project")
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

        let nameChanged = trimmedName.localizedCaseInsensitiveCompare(project.name) != .orderedSame
        if nameChanged {
            let isDuplicate = projects.contains {
                $0.id != project.id &&
                $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
            }
            guard !isDuplicate else {
                errorMessage = "A project with this name already exists."
                return
            }

            // Linked items follow the rename automatically via the `project`
            // relationship. Adopt any legacy string-linked stragglers first so
            // the rename can't orphan them.
            for item in workItems where item.project == nil && item.projectName == project.name {
                item.assignProject(project)
                item.updatedAt = .now
            }
            // TODO: update Apple Calendar name when sync is active (non-blocking)
        }

        project.name = trimmedName
        project.colorToken = colorToken
        // TODO: update Apple Calendar color when sync is active (non-blocking)
        try? modelContext.save()
        dismiss()
    }

    private func colorDot(for token: String) -> some View {
        Circle()
            .fill(Color.projectToken(token))
            .frame(width: 11, height: 11)
    }
}
