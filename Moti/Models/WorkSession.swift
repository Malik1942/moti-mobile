import Foundation
import SwiftData

// MARK: - Session State

enum SessionState: String, Codable, CaseIterable {
    case good
    case normal
    case bad

    var label: String {
        switch self {
        case .good:   "Good"
        case .normal: "Normal"
        case .bad:    "Bad"
        }
    }

    var emoji: String {
        switch self {
        case .good:   "🙂"
        case .normal: "😐"
        case .bad:    "☹️"
        }
    }
}

// MARK: - Session Check-In
//
// A single pace pulse — "how is this going?" — recorded either from a
// `WorkSession` focus block OR from a `WorkItem` progress checkpoint
// notification / manual task pulse. One model serves both roles to avoid a
// duplicate type:
//
//   • `session` set, `workItemID == nil`     → focus-block checkpoint
//   • `session == nil`, `workItemID` set      → task progress check-in
//
// `checkpointID` is the deduplication key (matches the originating
// notification's identifier, e.g. `moti-progress-<uuid>-25`) so repeated
// notification taps don't create duplicate rows.

@Model final class SessionCheckIn {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var progress: Double
    var stateRawValue: String

    /// Set when this pulse came from a `WorkSession` focus block.
    var session: WorkSession?

    /// Set when this pulse came from a `WorkItem` checkpoint or a manual
    /// check-in on the task detail screen.
    var workItemID: UUID?

    /// Optional free-text context ("What changed?").
    var note: String?

    /// Stable identifier of the originating event — used to dedup
    /// repeated taps of the same notification. `nil` for manual pulses.
    var checkpointID: String?

    var state: SessionState {
        get { SessionState(rawValue: stateRawValue) ?? .normal }
        set { stateRawValue = newValue.rawValue }
    }

    /// Focus-block init kept for backward compatibility with existing call
    /// sites (`SessionCheckIn(progress:state:)`).
    init(progress: Double, state: SessionState) {
        self.id            = UUID()
        self.timestamp     = .now
        self.progress      = progress
        self.stateRawValue = state.rawValue
    }

    /// Task-scoped init — used by checkpoint notifications and manual pulses.
    init(
        workItemID: UUID,
        progress: Double,
        state: SessionState,
        note: String? = nil,
        checkpointID: String? = nil
    ) {
        self.id            = UUID()
        self.timestamp     = .now
        self.progress      = progress
        self.stateRawValue = state.rawValue
        self.workItemID    = workItemID
        self.note          = note?.isEmpty == true ? nil : note
        self.checkpointID  = checkpointID
    }
}

// MARK: - Work Session

@Model final class WorkSession {
    @Attribute(.unique) var id: UUID
    var workItemID: UUID
    var startTime: Date
    var expectedEndTime: Date
    /// All checkpoint progress fractions this session tracks — e.g. [0.25, 0.5, 0.75, 0.9].
    var checkpointProgress: [Double]
    /// Subset of checkpointProgress that have already fired (responded or dismissed).
    var firedCheckpoints: [Double]
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SessionCheckIn.session)
    var checkIns: [SessionCheckIn] = []

    var duration: TimeInterval {
        expectedEndTime.timeIntervalSince(startTime)
    }

    var currentProgress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0, Date.now.timeIntervalSince(startTime) / duration))
    }

    var remainingLabel: String {
        let remaining = max(0, expectedEndTime.timeIntervalSince(.now))
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "\(minutes)m left" }
        let hours = minutes / 60
        let mins  = minutes % 60
        return mins > 0 ? "\(hours)h \(mins)m left" : "\(hours)h left"
    }

    init(workItemID: UUID, startTime: Date, expectedEndTime: Date) {
        self.id                 = UUID()
        self.workItemID         = workItemID
        self.startTime          = startTime
        self.expectedEndTime    = expectedEndTime
        self.checkpointProgress = [0.25, 0.5, 0.75, 0.9]
        self.firedCheckpoints   = []
        self.isActive           = true
        self.createdAt          = .now
    }
}
