import Foundation

enum TemporalInterpretation: String, Codable, Equatable {
    case relativeDuration
    case calendarDate
    case clockTime
    case ambiguous
    case unknown
}
