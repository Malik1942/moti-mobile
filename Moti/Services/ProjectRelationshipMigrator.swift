import Foundation
import SwiftData

/// One-way backfill from the legacy `WorkItem.legacyProjectName` string link
/// to the `WorkItem.project` relationship.
///
/// Runs on every launch and is idempotent: it only touches items that have a
/// legacy name but no relationship, links them to the matching project, and
/// clears the legacy string. Items whose legacy name matches no existing
/// project keep the string (it still drives display via `projectName`) and are
/// re-checked next launch — e.g. after the user creates that project.
enum ProjectRelationshipMigrator {
    static func run(in context: ModelContext) {
        guard
            let items = try? context.fetch(FetchDescriptor<WorkItem>()),
            let projects = try? context.fetch(FetchDescriptor<Project>()),
            !projects.isEmpty
        else { return }

        var linkedCount = 0
        for item in items {
            guard item.project == nil,
                  let legacyName = item.legacyProjectName, !legacyName.isEmpty
            else { continue }

            // Exact match first; case-insensitive as a fallback (safe because
            // EditProjectSheet rejects case-insensitive duplicate names).
            let match = projects.first { $0.name == legacyName }
                ?? projects.first { $0.name.localizedCaseInsensitiveCompare(legacyName) == .orderedSame }

            if let match {
                item.assignProject(match)
                linkedCount += 1
            }
        }

        if linkedCount > 0 {
            try? context.save()
            #if DEBUG
            print("[Migration] Linked \(linkedCount) work item(s) to project relationships.")
            #endif
        }
    }
}
