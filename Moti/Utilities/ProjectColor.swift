import SwiftUI

extension Color {
    static func project(_ name: String?) -> Color {
        projectToken(ProjectCatalog.color(for: name))
    }

    static func projectToken(_ token: String?) -> Color {
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

extension Date {
    var shortDayLabel: String {
        formatted(.dateTime.weekday(.abbreviated).day())
    }

    var compactTimeLabel: String {
        formatted(date: .omitted, time: .shortened)
    }
}
