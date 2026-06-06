//
// WorkspaceProjectDeduplicationTests.swift
//
// Regression tests for the session-scoped project cache introduced in
// QuickCaptureView.confirmWorkspace.
//
// Root cause of the bug: @Query [Project] is a SwiftUI-rendered snapshot that
// does NOT reflect within-task modelContext.insert() calls synchronously.
// Each per-task call to the old resolver methods saw an unchanged snapshot,
// found "no existing project", and inserted a fresh duplicate Project row.
//
// Fix: maintain a [String: String] session cache keyed on the normalised hint.
// First call for a hint creates (and caches) exactly one Project. Every
// subsequent call returns the cached canonical name without touching the DB.
//
// These tests mirror the production closure as a standalone free function so
// the behaviour is verifiable without instantiating the SwiftUI view.
// Any change to the cache logic in QuickCaptureView.confirmWorkspace must be
// reflected here.
//
// Test coverage:
//   1. Within-run dedup: N tasks with same hint → 1 project created
//   2. Case-insensitive dedup: "Job Search" / "job search" / "JOB SEARCH" → 1
//   3. Multiple distinct hints → separate projects with incrementing sortIndex
//   4. sortIndex increments correctly across a batch (not all the same value)
//   5. Second-run reuse: existing project found via ProjectMatcher, no new row
//   6. Second-run: 5 repeated hints against existing project → no duplicate
//   7. Nil / empty / "Uncategorized" hints return nil, create nothing
//

import XCTest
import SwiftData
@testable import Moti

final class WorkspaceProjectDeduplicationTests: XCTestCase {

    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self, WorkItem.self, SessionCheckIn.self,
                 WorkSession.self, ProjectContext.self, ContextNote.self,
                 CompletionLog.self,
            configurations: config
        )
        ctx = ModelContext(container)
    }

    override func tearDownWithError() throws {
        ctx = nil
        container = nil
    }

    // MARK: - Test helper

    /// Mirrors the `resolveProjectName` closure inside
    /// `QuickCaptureView.confirmWorkspace`. Any structural change there should
    /// be reflected here.
    @discardableResult
    private func resolve(
        hint: String?,
        existingProjects: [Project],
        cache: inout [String: String],
        nextIdx: inout Int
    ) -> String? {
        guard let hint = hint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hint.isEmpty,
              hint.localizedCaseInsensitiveCompare("Uncategorized") != .orderedSame
        else { return nil }

        let key = hint.lowercased()
        if let cached = cache[key] { return cached }

        if let matched = ProjectMatcher.match(
            projectHint: hint, taskTitle: "", rawInput: "",
            existingProjects: existingProjects
        ) {
            cache[key] = matched.name
            return matched.name
        }

        let project = Project(
            name: hint,
            colorToken: ProjectCatalog.colorToken(forProjectNamed: hint),
            sortIndex: nextIdx
        )
        ctx.insert(project)
        nextIdx += 1
        cache[key] = project.name
        return project.name
    }

    private func fetchProjects() throws -> [Project] {
        try ctx.fetch(FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.sortIndex)]
        ))
    }

    // MARK: - 1. Within-run dedup

    func test_sameHintFiveTimes_createsExactlyOneProject() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0
        let existing: [Project] = []

        for _ in 0..<5 {
            resolve(hint: "Job Search", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        }

        let projects = try fetchProjects()
        XCTAssertEqual(
            projects.count, 1,
            "Five tasks with the same project hint must create exactly 1 Project row, not 5."
        )
        XCTAssertEqual(projects[0].name, "Job Search")
    }

    // MARK: - 2. Case-insensitive dedup

    func test_caseVariantsOfSameHint_createExactlyOneProject() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0
        let existing: [Project] = []

        resolve(hint: "Job Search", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "job search", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "JOB SEARCH", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)

        XCTAssertEqual(
            (try fetchProjects()).count, 1,
            "Case variants of the same name must deduplicate to a single Project row."
        )
    }

    // MARK: - 3. Multiple distinct hints

    func test_threeDistinctHints_createThreeSeparateProjects() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0
        let existing: [Project] = []

        resolve(hint: "Job Search", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "Portfolio",  existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "Personal",   existingProjects: existing, cache: &cache, nextIdx: &nextIdx)

        let projects = try fetchProjects()
        XCTAssertEqual(projects.count, 3, "Three distinct hints must create three separate projects.")
        XCTAssertEqual(
            Set(projects.map(\.name)),
            ["Job Search", "Portfolio", "Personal"]
        )
    }

    // MARK: - 4. sortIndex stability

    func test_sortIndexIncrements_noDuplicateIndices() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0
        let existing: [Project] = []

        resolve(hint: "Alpha", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "Beta",  existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "Alpha", existingProjects: existing, cache: &cache, nextIdx: &nextIdx) // repeat — must not bump idx
        resolve(hint: "Gamma", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)

        let projects = try fetchProjects()
        XCTAssertEqual(projects.count, 3, "Alpha/Beta/Gamma — 3 unique projects.")
        let indices = projects.compactMap(\.sortIndex)
        XCTAssertEqual(Set(indices).count, indices.count, "sortIndex must be unique across all created projects.")
        XCTAssertEqual(indices.sorted(), [0, 1, 2], "sortIndex must increment: 0, 1, 2 — not all the same value.")
    }

    func test_sortIndexStartsAtOffset_whenExistingProjectsPresent() throws {
        // Simulate existing project at sortIndex 3 → new ones start at 4.
        var cache: [String: String] = [:]
        var nextIdx = 4   // caller sets this from projects.nextSortIndex
        let existing: [Project] = []

        resolve(hint: "New A", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        resolve(hint: "New B", existingProjects: existing, cache: &cache, nextIdx: &nextIdx)

        let projects = try fetchProjects()
        XCTAssertEqual(projects.compactMap(\.sortIndex).sorted(), [4, 5],
                       "New projects must pick up after the existing sort range.")
    }

    // MARK: - 5. Second-run: existing project reused

    func test_secondRun_existingProjectReused_noNewRowCreated() throws {
        // Run 1: "Job Search" created and saved.
        let existing = Project(
            name: "Job Search",
            colorToken: ProjectCatalog.colorToken(forProjectNamed: "Job Search"),
            sortIndex: 0
        )
        ctx.insert(existing)
        try ctx.save()

        // Run 2: new workspace confirmation with the same hint.
        var cache: [String: String] = [:]
        var nextIdx = 1
        let existingProjects = try fetchProjects()   // reflects the saved project

        let resolved = resolve(hint: "Job Search", existingProjects: existingProjects,
                               cache: &cache, nextIdx: &nextIdx)

        XCTAssertEqual(resolved, "Job Search")
        XCTAssertEqual(
            (try fetchProjects()).count, 1,
            "Second run must reuse the existing project — no duplicate created."
        )
    }

    // MARK: - 6. Second-run: multiple tasks, all hits → no new row

    func test_secondRun_fiveTasksHittingExistingProject_noNewRows() throws {
        let existing = Project(name: "Job Search", colorToken: "blue", sortIndex: 0)
        ctx.insert(existing)
        try ctx.save()

        var cache: [String: String] = [:]
        var nextIdx = 1
        let existingProjects = try fetchProjects()

        for _ in 0..<5 {
            resolve(hint: "Job Search", existingProjects: existingProjects,
                    cache: &cache, nextIdx: &nextIdx)
        }

        XCTAssertEqual(
            (try fetchProjects()).count, 1,
            "Five tasks in a second workspace confirmation must all reuse the existing project."
        )
    }

    // MARK: - 7. Guard: nil / empty / Uncategorized

    func test_nilHint_returnsNilCreatesNothing() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0

        let result = resolve(hint: nil, existingProjects: [], cache: &cache, nextIdx: &nextIdx)

        XCTAssertNil(result)
        XCTAssertEqual((try fetchProjects()).count, 0)
    }

    func test_whitespaceOnlyHint_returnsNilCreatesNothing() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0

        let result = resolve(hint: "   \t  ", existingProjects: [], cache: &cache, nextIdx: &nextIdx)

        XCTAssertNil(result)
        XCTAssertEqual((try fetchProjects()).count, 0)
    }

    func test_uncategorizedHint_returnsNilCreatesNothing() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0

        let result = resolve(hint: "Uncategorized", existingProjects: [], cache: &cache, nextIdx: &nextIdx)

        XCTAssertNil(result)
        XCTAssertEqual((try fetchProjects()).count, 0)
    }

    func test_uncategorizedHint_caseVariants_allReturnNilCreateNothing() throws {
        var cache: [String: String] = [:]
        var nextIdx = 0

        for variant in ["Uncategorized", "uncategorized", "UNCATEGORIZED"] {
            let result = resolve(hint: variant, existingProjects: [], cache: &cache, nextIdx: &nextIdx)
            XCTAssertNil(result, "'\(variant)' must return nil and create no project.")
        }
        XCTAssertEqual((try fetchProjects()).count, 0)
    }

    // MARK: - 8. Composite: workspace confirmation scenario

    func test_workspaceConfirmation_twoTargetsSameProject_createOneProject() throws {
        // Simulates a workspace with two planning targets, both tagged "Job Search",
        // each containing two tasks also tagged "Job Search" — 6 resolution calls total
        // (2 targets + 4 tasks). The session cache must prevent 5 duplicate rows.
        var cache: [String: String] = [:]
        var nextIdx = 0
        let existing: [Project] = []

        let hints = [
            "Job Search",   // workspace fallback
            "Job Search",   // target 1
            "Job Search",   // task 1.1
            "Job Search",   // task 1.2
            "Job Search",   // target 2
            "Job Search",   // task 2.1
        ]
        for hint in hints {
            resolve(hint: hint, existingProjects: existing, cache: &cache, nextIdx: &nextIdx)
        }

        let projects = try fetchProjects()
        XCTAssertEqual(
            projects.count, 1,
            "A workspace where every target and task shares the same project hint must produce exactly 1 Project row."
        )
    }
}
