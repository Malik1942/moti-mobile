import Foundation

/// Shared date-anchor detection for the classification/segmentation layer.
///
/// Both `PlanningClassifier` (deciding whether an input is multi-deadline) and
/// `CaptureSegmenter` (deciding whether a comma/"and" clause is its own task)
/// need to ask "how many independent date expressions does this text carry?".
/// Answering through `DeterministicPreClassifier` keeps that judgment on the
/// same single grammar the prompt layer and `DateResolver` already share —
/// an expression counts as an anchor exactly when it would also resolve to a
/// real due date downstream.
enum TemporalAnchors {

    /// Number of confident, date-bearing temporal expressions in `text`.
    /// Clock-only times ("at 7pm") and low-confidence numeric forms don't
    /// count — they wouldn't produce a due date on their own.
    static func count(in text: String, calendar: Calendar = .current, now: Date = .now) -> Int {
        resolutions(in: text, calendar: calendar, now: now).count
    }

    /// True when the text contains at least one confident date anchor.
    static func containsAnchor(in text: String, calendar: Calendar = .current, now: Date = .now) -> Bool {
        count(in: text, calendar: calendar, now: now) >= 1
    }

    private static func resolutions(in text: String, calendar: Calendar, now: Date) -> [TemporalResolution] {
        DeterministicPreClassifier.classify(input: text, calendar: calendar, now: now)
            .filter {
                $0.resolverPath == .deterministic
                    && $0.confidence >= 0.85
                    && $0.resolvedDate != nil
            }
    }
}
