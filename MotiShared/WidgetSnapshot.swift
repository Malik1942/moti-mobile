import Foundation
import SwiftUI

// MARK: - Snapshot models (Codable, no SwiftData dependency)

struct ProjectWidgetSnapshot: Codable {
    var generatedAt: Date
    var projects: [ProjectWidgetData]

    static let appGroupID = "group.com.malik.Moti"
    static let snapshotFilename = "widget_snapshot.json"

    static func readFromAppGroup() -> ProjectWidgetSnapshot? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let url = container.appendingPathComponent(snapshotFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectWidgetSnapshot.self, from: data)
    }
}

struct ProjectWidgetData: Codable, Identifiable {
    var id: UUID
    var name: String
    var colorToken: String
    var activeCount: Int
    var items: [WidgetWorkItemData]
}

struct WidgetWorkItemData: Codable, Identifiable {
    var id: UUID
    var title: String
    var statusRawValue: String
    var dueDate: Date?
    var workingStartDate: Date?
    var workingEndDate: Date?
    var isEvent: Bool

    // elapsed / total using minutes for precision; clamped 0-100
    func progressPercentage(asOf now: Date = .now) -> Int? {
        guard !isEvent, let start = workingStartDate, let end = workingEndDate else { return nil }
        let totalMinutes = end.timeIntervalSince(start) / 60
        guard totalMinutes > 0 else { return nil }
        let elapsedMinutes = now.timeIntervalSince(start) / 60
        let pct = (elapsedMinutes / totalMinutes) * 100
        return min(max(Int(pct.rounded()), 0), 100)
    }

    var hasTiming: Bool { workingStartDate != nil && workingEndDate != nil && !isEvent }
}

// MARK: - Ranking

/// Returns items sorted by relevance for widget display.
/// 1. Currently active (working period contains now)
/// 2. Upcoming soonest
/// 3. Has due date soonest
/// 4. Everything else
func widgetRankedItems(_ items: [WidgetWorkItemData], now: Date, maxCount: Int) -> [WidgetWorkItemData] {
    let visible = items.filter { $0.statusRawValue != "done" && $0.statusRawValue != "archived" }
    let scored = visible.map { ($0, widgetRelevanceScore($0, now: now)) }
    return scored.sorted { $0.1 < $1.1 }.prefix(maxCount).map(\.0)
}

private func widgetRelevanceScore(_ item: WidgetWorkItemData, now: Date) -> Double {
    if let start = item.workingStartDate, let end = item.workingEndDate, start <= now, now <= end {
        // active now: score by how far through (near end = more urgent, shown first)
        let progress = now.timeIntervalSince(start) / max(end.timeIntervalSince(start), 1)
        return progress
    }
    if let start = item.workingStartDate, start > now {
        return 2 + start.timeIntervalSince(now) / 86400
    }
    if let due = item.dueDate {
        return 100 + max(due.timeIntervalSince(now), 0) / 86400
    }
    return 1000
}

// MARK: - Color

extension Color {
    static func widgetProjectColor(token: String) -> Color {
        switch token {
        case "blue": .blue
        case "green": .green
        case "purple": .purple
        case "indigo": .indigo
        case "orange": .orange
        default: .gray
        }
    }
}
