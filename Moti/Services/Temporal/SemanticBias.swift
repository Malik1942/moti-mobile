import Foundation

enum SemanticBias {
    static let eventKeywords: [String] = [
        "party", "birthday", "wedding", "meeting", "flight",
        "dinner", "lunch", "breakfast", "concert", "show",
        "appointment", "interview", "reservation", "anniversary",
        "ceremony", "graduation", "coffee", "drinks"
    ]

    static let taskKeywords: [String] = [
        "submit", "finish", "send", "complete", "deliver",
        "review", "ship", "publish", "post", "draft",
        "write", "build", "fix", "prepare", "edit"
    ]

    static let currencySignals: [String] = [
        "$", "€", "£", "¥", "usd", "eur", "gbp",
        "price", "cost", "fee", "amount"
    ]

    static let quantitySignals: [String] = [
        " kg", " lb", " oz", " ml", " gb", " mb", " tb", "%",
        " pounds", " ounces", " km", " mi ", " miles", " kilometers"
    ]

    static let versionSignals: [String] = [
        "version ", "ver.", "ios ", "macos ", "swift ", "python ", " v."
    ]
}
