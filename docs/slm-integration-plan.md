# Moti SLM Integration Plan

## Current State

Moti now has three task understanding modes behind `TaskUnderstandingService`:

- **Foundation Model, On-device**: preferred mode when Apple Foundation Models are available on the current device and OS.
- **Rule-based, Fallback**: deterministic local parsing for projects, due dates, working periods, effort hints, review state, and parser confidence.
- **Mock SLM, Debug Only**: a simulation layer around the rule-based parser. It adds latency and imperfect behavior so the app can exercise model-like UX without claiming real model inference.

There are still no network calls, backend dependencies, or bundled Core ML models. Foundation Models runs on-device and is gated by runtime availability.

If Foundation Models are unavailable, Moti clearly reports that state in Settings and uses the rule-based fallback.

## Foundation Models Behavior

`FoundationModelsTaskUnderstandingService` conforms to:

```swift
func parse(_ input: String) async throws -> ParsedWorkItem
```

The service:

- checks `SystemLanguageModel.default.availability`
- creates a `LanguageModelSession`
- requests structured output from the on-device model
- asks the model to summarize title/project/time text, not to invent final `Date` objects
- resolves date text in Swift with `DateResolver`
- falls back to the rule-based parser when Foundation Models cannot run

Review routing is intentionally product-driven:

- usable time information means the item should usually go to the Timeline
- parser confidence alone does not force Review
- unclear project can become Uncategorized
- Review is reserved for items that cannot be placed on the timeline

## Mock SLM Behavior

`MockSLMTaskUnderstandingService` conforms to `TaskUnderstandingService`, but it is not a real language model. It:

- waits briefly to simulate inference latency
- caps parser confidence
- degrades some range inputs

The mock exists to test parser swapping and uncertainty handling, not to claim model intelligence.

## Parser Output Contract

Every parser should return structured `ParsedWorkItem` values with:

- `rawInput`
- `title`
- `projectGuess`
- `dueDate`
- `workingStartDate`
- `workingEndDate`
- `estimatedEffort`
- `parserConfidence`
- `needsReview`
- `reviewReason`
- `parserExplanation`

## Mapping Into WorkItem

`QuickCaptureView` should continue to call only the `TaskUnderstandingService` environment value. Parsed output maps into `WorkItem` through `WorkItem.init(parsed:)`.

Views should not import or instantiate `FoundationModelsTaskUnderstandingService`, `RuleBasedTaskUnderstandingService`, or `MockSLMTaskUnderstandingService`.

## UI Boundary

The main UI should show schedule-planning concepts:

- project
- working period
- due date
- needs review
- schedule confidence

The UI should not foreground parser internals such as raw parser confidence, parser explanation, token-level reasoning, model prompts, or inference diagnostics. Those can live in debug tooling or developer-only surfaces.

## Validation Samples

Use `ParserValidationSamples` to run quick parser checks for:

- I need to finish 5 job applications before 5.15
- I need to submit 5 job application before 5.15
- I need to have an interview with Matt next Thursday 10AM
- Work on portfolio from Monday to Wednesday and submit by Friday
- Read papers for research proposal, no deadline yet
- Reach out to recruiters over the weekend
