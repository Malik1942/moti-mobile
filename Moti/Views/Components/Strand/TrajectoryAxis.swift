import CoreGraphics
import Foundation

/// Pure vertical time→y mapping for the trajectory view (PRD §4–§6.1): `Now`
/// near the top, a **bounded** recent past above it, the future expanding
/// **downward**. Near-future is near-linear; the far-future is **compressed** so
/// distant deadlines stay reachable on one scroll without the view becoming a
/// Gantt-length scroll (the layout fork you chose).
///
/// Kept UI-free so the geometry can be reasoned about and tested.
struct TrajectoryAxis: Equatable {
    var now: Date
    /// Bounded recent-past window drawn above Now (feedback only).
    var pastDays: Double = 14
    /// Linear region below Now, where committed near-term plans live.
    var nearDays: Double = 30
    /// Points per day in the past + near-future linear region.
    var pointsPerDay: CGFloat = 7
    /// Points-per-day multiplier applied beyond `nearDays` (compression).
    var farCompression: CGFloat = 0.32
    var topPadding: CGFloat = 28
    var bottomPadding: CGFloat = 40

    /// Height of the bounded past band above Now.
    var pastHeight: CGFloat { CGFloat(pastDays) * pointsPerDay }

    /// y of the fixed Now band.
    var nowY: CGFloat { topPadding + pastHeight }

    /// Map a signed day offset from Now to a y coordinate. Past (negative) is
    /// clamped to the bounded window; the future compresses beyond `nearDays`.
    func y(daysFromNow d: Double) -> CGFloat {
        if d <= 0 {
            return nowY + CGFloat(max(d, -pastDays)) * pointsPerDay
        } else if d <= nearDays {
            return nowY + CGFloat(d) * pointsPerDay
        } else {
            let near = CGFloat(nearDays) * pointsPerDay
            let far = CGFloat(d - nearDays) * pointsPerDay * farCompression
            return nowY + near + far
        }
    }

    func y(date: Date, calendar: Calendar = .current) -> CGFloat {
        y(daysFromNow: date.timeIntervalSince(now) / 86_400)
    }

    /// Total content height needed to draw out to `horizonDays` of future.
    func contentHeight(horizonDays: Double) -> CGFloat {
        y(daysFromNow: max(horizonDays, nearDays)) + bottomPadding
    }
}
