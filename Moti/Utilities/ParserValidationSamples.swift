import Foundation

enum ParserValidationSamples {
    static let examples = [
        "I want to apply 3 big tech roles between 5.20 and 6.5",
        "Apply to jobs from May 20 to June 5",
        "Work on portfolio from Monday to Wednesday and submit by Friday",
        "Finish 5 job applications before 5.15",
        "Interview with Matt next Thursday 10AM",
        "I need to finish 5 job applications before 5.15",
        "I need to submit 5 job application before 5.15",
        "I need to have an interview with Matt next Thursday 10AM",
        "Read papers for research proposal, no deadline yet",
        "Reach out to recruiters over the weekend"
    ]

    static let expectedNotes = [
        "I want to apply 3 big tech roles between 5.20 and 6.5": "Title Apply to 3 big tech roles, Job Search, temporalIntent working_period, workingStartDate May 20, workingEndDate June 5, due June 5 at 23:59 or nil, needsReview false.",
        "Apply to jobs from May 20 to June 5": "Title Apply to jobs, Job Search, temporalIntent working_period, workingStartDate May 20, workingEndDate June 5, needsReview false.",
        "Work on portfolio from Monday to Wednesday and submit by Friday": "Title Work on portfolio, Portfolio, temporalIntent period_with_deadline, working period Monday to Wednesday, due Friday at 23:59, needsReview false.",
        "Finish 5 job applications before 5.15": "TemporalIntent deadline, due May 15 at 23:59, working period from createdAt to dueDate, needsReview false.",
        "Interview with Matt next Thursday 10AM": "TemporalIntent event, due next Thursday at 10:00, working period from createdAt to dueDate, needsReview false.",
        "I need to finish 5 job applications before 5.15": "Title Finish 5 job applications, Job Search, due May 15 at 23:59, working period from createdAt to dueDate, needsReview false.",
        "I need to submit 5 job application before 5.15": "Title Submit 5 job applications, Job Search, due May 15 at 23:59, needsReview false.",
        "I need to have an interview with Matt next Thursday 10AM": "Title Interview with Matt, Job Search, due next Thursday at 10:00, needsReview false.",
        "Read papers for research proposal, no deadline yet": "Title Read papers for research proposal, School, no due date, needsReview true.",
        "Reach out to recruiters over the weekend": "Title Reach out to recruiters, Job Search, working period Saturday to Sunday, due Sunday at 23:59, needsReview false."
    ]

    static func run(using service: any TaskUnderstandingService = FoundationModelsTaskUnderstandingService(fallback: RuleBasedTaskUnderstandingService())) async -> [ParserValidationResult] {
        var results: [ParserValidationResult] = []
        for input in examples {
            do {
                let parsed = try await service.parse(input)
                results.append(ParserValidationResult(input: input, parsed: parsed, errorDescription: nil))
            } catch {
                results.append(ParserValidationResult(input: input, parsed: nil, errorDescription: error.localizedDescription))
            }
        }
        return results
    }
}

struct ParserValidationResult {
    let input: String
    let parsed: ParsedWorkItem?
    let errorDescription: String?
}
