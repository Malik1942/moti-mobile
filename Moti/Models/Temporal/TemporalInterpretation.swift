import Foundation

enum TemporalInterpretation: String, Codable {
    case relativeDuration
    case calendarDate
    case clockTime
    case ambiguous
    case unknown
}
