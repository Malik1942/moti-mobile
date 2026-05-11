import Foundation

enum ProjectInferrer {
    static func infer(from input: String) -> String? {
        let text = input.lowercased()
        let mappings: [(String, [String])] = [
            ("Job Search", [
                "job application", "job applications", "application", "applications", "resume",
                "recruiter", "interview", "referral", "linkedin", "cover letter", "hiring",
                "company", "internship", "full-time", "big tech", "role", "roles", "job", "jobs"
            ]),
            ("School", ["assignment", "class", "course", "dis", "paper", "papers", "reading", "research proposal", "homework", "syllabus", "thesis"]),
            ("Portfolio", ["portfolio", "case study", "website", "personal brand", "project page", "design system"]),
            ("Moti", ["moti", "app", "swiftui", "codex", "xcode", "parser", "timeline"]),
            ("Personal", ["cycling", "personal errand", "life admin", "grocery", "groceries", "workout", "gym", "errand", "personal"])
        ]
        return mappings.first { _, keywords in
            keywords.contains { text.contains($0) }
        }?.0
    }
}
