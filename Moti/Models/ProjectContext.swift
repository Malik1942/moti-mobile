import Foundation
import SwiftData

// MARK: - ProjectContext

@Model
final class ProjectContext {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var goal: String?
    var audience: String?
    var deadlineExpression: String?
    var keyReferences: [String]
    var constraints: [String]
    var successCriteria: [String]
    var openQuestions: [String]
    var userPreferences: [String]
    var sourceNotes: [String]
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ContextNote.projectContext)
    var notes: [ContextNote] = []

    var summary: String {
        var parts: [String] = []
        if let goal = goal, !goal.isEmpty {
            parts.append("Goal: \(goal).")
        }
        if let audience = audience, !audience.isEmpty {
            parts.append("Audience: \(audience).")
        }
        if let deadline = deadlineExpression, !deadline.isEmpty {
            parts.append("Deadline: \(deadline).")
        }
        if !keyReferences.isEmpty {
            parts.append("References: \(keyReferences.joined(separator: ", ")).")
        }
        if !constraints.isEmpty {
            parts.append("Constraints: \(constraints.joined(separator: ", ")).")
        }
        if !successCriteria.isEmpty {
            parts.append("Success Criteria: \(successCriteria.joined(separator: ", ")).")
        }
        if !openQuestions.isEmpty {
            parts.append("Open Questions: \(openQuestions.joined(separator: ", ")).")
        }
        if !userPreferences.isEmpty {
            parts.append("Preferences: \(userPreferences.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    init(projectId: UUID) {
        self.id = UUID()
        self.projectId = projectId
        self.goal = nil
        self.audience = nil
        self.deadlineExpression = nil
        self.keyReferences = []
        self.constraints = []
        self.successCriteria = []
        self.openQuestions = []
        self.userPreferences = []
        self.sourceNotes = []
        self.createdAt = .now
        self.updatedAt = .now
    }

    func merge(_ extracted: ExtractedProjectContext, sourceInput: String) {
        // Goal
        if let extractedGoal = extracted.goal {
            if goal == nil {
                goal = extractedGoal
            } else if goal != extractedGoal {
                let alternative = "Alternative goal: \(extractedGoal)"
                if !openQuestions.contains(alternative) {
                    openQuestions.append(alternative)
                }
            }
        }

        // Audience
        if let extractedAudience = extracted.audience {
            if audience == nil {
                audience = extractedAudience
            }
        }

        // Deadline
        if let extractedDeadline = extracted.deadlineExpression {
            if deadlineExpression == nil {
                deadlineExpression = extractedDeadline
            }
        }

        // Append unique items to arrays
        for item in extracted.keyReferences where !keyReferences.contains(item) {
            keyReferences.append(item)
        }
        for item in extracted.constraints where !constraints.contains(item) {
            constraints.append(item)
        }
        for item in extracted.successCriteria where !successCriteria.contains(item) {
            successCriteria.append(item)
        }
        for item in extracted.openQuestions where !openQuestions.contains(item) {
            openQuestions.append(item)
        }
        for item in extracted.userPreferences where !userPreferences.contains(item) {
            userPreferences.append(item)
        }
        for item in extracted.notes where !sourceNotes.contains(item) {
            sourceNotes.append(item)
        }

        sourceNotes.append(sourceInput)
        updatedAt = .now
    }
}

// MARK: - ContextNote

@Model
final class ContextNote {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var content: String
    var categoryRawValue: String
    var sourceInput: String
    var createdAt: Date
    var projectContext: ProjectContext?

    var category: ContextCategory {
        get {
            ContextCategory(rawValue: categoryRawValue) ?? .generalNote
        }
        set {
            categoryRawValue = newValue.rawValue
        }
    }

    init(projectId: UUID, content: String, category: ContextCategory, sourceInput: String) {
        self.id = UUID()
        self.projectId = projectId
        self.content = content
        self.categoryRawValue = category.rawValue
        self.sourceInput = sourceInput
        self.createdAt = .now
    }
}

// MARK: - Project Context Coordinator

/// Single place where project context is persisted to SwiftData.
///
/// Smart Capture (and future planning features) produce `ExtractedProjectContext`
/// values. `ContextualCaptureAgentService` itself never writes to SwiftData — it
/// only returns structured decisions. This coordinator performs the actual
/// persistence, and is only ever invoked from the view layer after the user
/// has confirmed the change.
///
/// Persistence rules:
/// - A project has at most one `ProjectContext` (no duplicates).
/// - `ContextNote` records are append-only — existing notes are never deleted.
/// - Structured summary fields are merged carefully and never blindly erased.
enum ProjectContextCoordinator {

    /// Returns the existing `ProjectContext` for a project, or creates and inserts
    /// a fresh one. Never creates a duplicate for a project that already has one.
    @discardableResult
    static func findOrCreateContext(
        for projectId: UUID,
        in modelContext: ModelContext
    ) -> ProjectContext {
        let descriptor = FetchDescriptor<ProjectContext>(
            predicate: #Predicate { $0.projectId == projectId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let created = ProjectContext(projectId: projectId)
        modelContext.insert(created)
        return created
    }

    /// Persists extracted context for a project. Call only after user confirmation.
    ///
    /// - Appends one `ContextNote` per extracted item (append-only history).
    /// - Merges structured summary fields without erasing existing values.
    @discardableResult
    static func saveExtractedContext(
        _ extracted: ExtractedProjectContext,
        to projectId: UUID,
        sourceInput: String,
        in modelContext: ModelContext
    ) -> ProjectContext {
        let projectContext = findOrCreateContext(for: projectId, in: modelContext)

        // Append-only context notes — one record per extracted item.
        for note in makeContextNotes(from: extracted, projectId: projectId, sourceInput: sourceInput) {
            note.projectContext = projectContext
            projectContext.notes.append(note)
            modelContext.insert(note)
        }

        // Careful merge of structured summary fields (existing values preserved).
        projectContext.merge(extracted, sourceInput: sourceInput)

        try? modelContext.save()
        return projectContext
    }

    /// Builds append-only `ContextNote` records from an extracted context payload.
    private static func makeContextNotes(
        from extracted: ExtractedProjectContext,
        projectId: UUID,
        sourceInput: String
    ) -> [ContextNote] {
        var notes: [ContextNote] = []

        func add(_ content: String?, _ category: ContextCategory) {
            guard let content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            notes.append(
                ContextNote(projectId: projectId, content: content, category: category, sourceInput: sourceInput)
            )
        }
        func addAll(_ contents: [String], _ category: ContextCategory) {
            for content in contents { add(content, category) }
        }

        add(extracted.goal, .goal)
        add(extracted.audience, .audience)
        add(extracted.deadlineExpression, .deadline)
        addAll(extracted.keyReferences, .reference)
        addAll(extracted.constraints, .constraint)
        addAll(extracted.successCriteria, .successCriteria)
        addAll(extracted.openQuestions, .openQuestion)
        addAll(extracted.userPreferences, .preference)
        addAll(extracted.notes, .generalNote)

        return notes
    }
}
