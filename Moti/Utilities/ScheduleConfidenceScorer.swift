import Foundation

enum ScheduleConfidenceScorer {
    static func score(for item: WorkItem, allItems: [WorkItem], now: Date) -> Int {
        var score = 85
        let isDone = item.status == .done

        if item.needsReview {
            score -= 30
        }

        if let dueDate = item.dueDate, !isDone {
            let secondsUntilDue = dueDate.timeIntervalSince(now)
            if secondsUntilDue < 0 {
                score -= 40
            } else if secondsUntilDue <= 86_400 {
                score -= 25
            } else if secondsUntilDue <= 259_200 {
                score -= 15
            }
        }

        if let start = item.workingStartDate, let end = item.workingEndDate {
            let days = end.timeIntervalSince(start) / 86_400
            if days > 14 {
                score -= 5
            }
            if days < 2, (item.estimatedEffort ?? 0) >= 120 {
                score -= 15
            }
        }

        if activeCount(for: item.projectName, in: allItems) > 5 {
            score -= 10
        }

        if (item.estimatedEffort ?? 0) >= 180 {
            score -= 15
        }

        // Parser confidence is an internal support signal; the UI presents only the final schedule score.
        if item.parserConfidence < 0.60 {
            score -= 10
        }

        if let completionRate = previousMonthCompletionRate(in: allItems, now: now) {
            if completionRate > 0.75 {
                score += 5
            } else if completionRate < 0.40 {
                score -= 10
            }
        }

        if completedSimilarDifficultyRecently(to: item, in: allItems, now: now) {
            score += 5
        }

        return min(100, max(0, score))
    }

    private static func activeCount(for projectName: String?, in items: [WorkItem]) -> Int {
        items.filter { item in
            item.projectName == projectName &&
                !item.needsReview &&
                item.status != .done &&
                item.status != .archived
        }.count
    }

    private static func previousMonthCompletionRate(in items: [WorkItem], now: Date) -> Double? {
        let calendar = Calendar.current
        guard let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
        let recent = items.filter { $0.createdAt >= monthAgo || $0.updatedAt >= monthAgo }
        guard recent.count >= 3 else { return nil }
        let completed = recent.filter { $0.status == .done }.count
        return Double(completed) / Double(recent.count)
    }

    private static func completedSimilarDifficultyRecently(to item: WorkItem, in items: [WorkItem], now: Date) -> Bool {
        guard let effort = item.estimatedEffort else { return false }
        let calendar = Calendar.current
        guard let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return false }
        return items.contains { candidate in
            candidate.id != item.id &&
                candidate.status == .done &&
                candidate.updatedAt >= monthAgo &&
                (candidate.estimatedEffort ?? 0) >= max(60, effort - 30)
        }
    }
}
