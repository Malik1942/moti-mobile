import SwiftUI
import UIKit

extension Color {
    static func project(_ name: String?) -> Color {
        projectToken(ProjectCatalog.color(for: name))
    }

    static func projectToken(_ token: String?) -> Color {
        switch token {
        case "blue": Color(uiColor: .systemBlue)
        case "green": Color(uiColor: .systemGreen)
        case "purple": Color(uiColor: .systemPurple)
        case "indigo": Color(uiColor: .systemIndigo)
        case "orange": Color(uiColor: .systemBrown)
        default: Color(uiColor: .systemGray)
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
