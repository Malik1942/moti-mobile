import SwiftData
import SwiftUI

struct OnboardingView: View {
    var isReplay = false
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt) private var existingProjects: [Project]

    @State private var page = 0
    @State private var selectedProjects = Set<String>()
    @State private var customProjectName = ""
    @State private var customProjects: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingPageView(
                        systemImage: "calendar.badge.clock",
                        title: "Plan work by timeline, not to-do list.",
                        bodyText: "Moti turns quick captures into project timelines, showing when work starts, when it ends, and what is coming due."
                    )
                    .tag(0)

                    capturePage
                        .tag(1)

                    projectsPage
                        .tag(2)

                    OnboardingPageView(
                        systemImage: "tray",
                        title: "Review only what needs clarity.",
                        bodyText: "Items with clear timing go directly to your timeline. If Moti cannot find usable time information, the item goes to Review."
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                footer
            }
            .background(Color.motiGroupedBackground)
            .navigationTitle("Welcome to Moti")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var capturePage: some View {
        OnboardingPageContainer(systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Capture naturally.")
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Type or speak what you need to work on. Moti uses on-device intelligence when available to summarize it, infer the project, detect timing, and place it on your timeline.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("\"I need to finish 5 job applications before 5.15\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("Finish 5 job applications")
                        .font(.headline)
                    ProjectPill(project: "Job Search")
                    Label("Due May 15", systemImage: "flag.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.motiSurface, in: RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MotiLayout.cardRadius, style: .continuous)
                        .strokeBorder(MotiTheme.subtleStroke, lineWidth: 0.5)
                }
            }
        }
    }

    private var projectsPage: some View {
        OnboardingPageContainer(systemImage: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set up your projects.")
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Projects help Moti organize work across your timeline. Start with one or add more later.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Project Manually")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("Project name", text: $customProjectName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            addCustomProject()
                        }
                        .buttonStyle(.bordered)
                        .disabled(customProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !customProjects.isEmpty {
                    FlowPillGroup(items: customProjects) { project in
                        ProjectTemplateChip(
                            project: project,
                            isSelected: true,
                            action: { removeCustomProject(project) }
                        )
                    }
                }

                Text("Suggested Templates")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(ProjectCatalog.suggestedTemplates, id: \.self) { project in
                        ProjectTemplateChip(
                            project: project,
                            isSelected: selectedProjects.contains(project)
                        ) {
                            toggleProject(project)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if page < 3 {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    completeOnboarding(createProjects: true)
                }
            } label: {
                Text(page == 3 ? "Start Planning" : "Continue")
            }
            .buttonStyle(MotiPrimaryButtonStyle(isFullWidth: true, height: 48))
            .frame(maxWidth: MotiLayout.prominentControlMaxWidth)

            Button(isReplay ? "Done" : "Skip") {
                completeOnboarding(createProjects: false)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(height: 34)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(.bar)
    }

    private func toggleProject(_ project: String) {
        if selectedProjects.contains(project) {
            selectedProjects.remove(project)
        } else {
            selectedProjects.insert(project)
        }
    }

    private func addCustomProject() {
        let trimmedName = customProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !customProjects.contains(where: { $0.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) else { return }
        customProjects.append(trimmedName)
        customProjectName = ""
    }

    private func removeCustomProject(_ project: String) {
        customProjects.removeAll { $0 == project }
    }

    private func completeOnboarding(createProjects: Bool) {
        if createProjects {
            let names = Array(selectedProjects).sorted() + customProjects
            var existingNames = Set(existingProjects.map { $0.name.lowercased() })
            var nextSortIndex = existingProjects.nextSortIndex
            for name in names where !existingNames.contains(name.lowercased()) {
                modelContext.insert(Project(
                    name: name,
                    colorToken: ProjectCatalog.colorToken(forProjectNamed: name),
                    sortIndex: nextSortIndex
                ))
                existingNames.insert(name.lowercased())
                nextSortIndex += 1
            }
            try? modelContext.save()
        }

        // First-run only: ask for notification permission so Timeline Checkpoints
        // can nudge during focused sessions. Requesting here means Moti shows up
        // in iOS Settings → Notifications from day one, rather than only after the
        // user happens to start their first session. Replays skip this.
        if !isReplay {
            Task { _ = await TimelineCheckpointScheduler.shared.requestAuthorizationIfNeeded() }
        }

        onComplete()
    }
}

private struct ProjectTemplateChip: View {
    let project: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(project)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.project(project) : Color.motiQuietFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? .clear : Color.project(project).opacity(0.18), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FlowPillGroup<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

private struct OnboardingPageView: View {
    let systemImage: String
    let title: String
    let bodyText: String

    var body: some View {
        OnboardingPageContainer(systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.title.weight(.semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OnboardingPageContainer<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.motiAccent)
                    .frame(width: 72, height: 72)
                    .background(Color.motiAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                content

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}
