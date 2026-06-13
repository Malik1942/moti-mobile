# Moti Intelligence / Timeline / Trajectory QA Audit — June 12, 2026

Scope: Smart Capture understanding, temporal parsing, multi-deadline planning,
project context injection, refinement loop, timeline generation, trajectory
display. Method: code-path audit + executable probes (deterministic layers run
against product-level inputs with a fixed reference date of Fri Jun 12 2026)
+ full test-suite runs. LLM (Gemini) output quality itself was not exercised —
findings about the LLM path are based on its prompt/validation contract, which
is testable; the deterministic layers around it are where the confirmed bugs
live.

Regression suite added: `MotiTests/IntelligenceAuditTests.swift` (23 tests —
15 lock current-correct behavior, 8 encode confirmed bugs via `XCTExpectFailure`).
Full suite: 222 tests, 0 failures.

---

## 1. Overall assessment

### What works
- **Multi-date extraction (prompt layer).** `TemporalResolver` extracts ALL
  non-overlapping date expressions: "portfolio by June 25, jobs by June 18,
  capstone by June 20" → 3 correct calendar dates. Named months, spelled
  durations ("in two weeks"), strict "next Friday" all correct.
- **Stage-1 anti-overplanning core.** Clear atomic tasks ("Submit the final
  PDF by Friday") never trigger plans/subtasks. Vague input asks one question.
  Weekday multi-deadline lists route to one-task-per-deadline.
- **LLM prompt contract.** The Gemini/FM system prompt has strong multi-target
  rules (extract every target, never drop later deadlines, equal counts
  enforced), anti-overplanning examples, and a refinement contract. A
  validate-and-retry safety net (`missingExtractedTargets()`) catches dropped
  targets and escalates to a user clarification if a retry still drops them.
- **Trajectory foundations.** Overdue open work reads `.slipping` with a
  distinct downward projection; completed work stays in the past as evidence
  (no auto-hide); curves are behavior-derived from real events, never
  fabricated; lanes sort by attention. DEBUG seeding cannot leak to release.

### What is fragile
- **Two divergent temporal systems.** `TemporalResolver` (informs the LLM) and
  `DateResolver` (assigns the actual `WorkItem.dueDate` at commit) disagree on
  "next Friday", spelled durations, "this weekend". What the user is shown in
  the plan preview is not what gets saved.
- **Closed keyword lists.** 30 action verbs, ~20 project-scale keywords.
  "Pay rent", "Clean the garage", "Renew my passport" → unnecessary
  clarification; "capstone"/"launch" anywhere overrides multi-deadline routing.
- **Rule-based fallback chain is silent.** Gemini/proxy/FM failures degrade to
  rule-based with no UI indication; fallback planning collapses any input to
  ONE generic target ("Define the next concrete milestone") with only the
  first time signal.
- **Refinement plumbing.** `refinePlan` "recover original input" expression is
  dead code (both branches return the live text field); clarification rounds
  have no upper bound.

### What is broken (confirmed by probes)
1. "by next Friday" saved a week early (commit path).
2. Comma-separated multi-deadline input collapses to one task in the default
   (non-LLM) path — 2 of 3 deadlines silently dropped.
3. "by the end of the month", "in two weeks" (spelled), "next month",
   "before graduation" → task created undated and shunted to review even when
   the deadline was explicit.
4. Everyday-verb tasks misrouted to clarification.
5. Multi-deadline + project keyword → deep multi-phase plan with subtasks
   (over-planning, against the classifier's own contract).

### Vision match
The architecture matches the product vision (two-stage gate, multi-target
planning, presence/trajectory instead of a static list). The gap is in the
deterministic seams: by default (`foundationModel` mode, which silently falls
back to rule-based wherever Apple Intelligence is unavailable) the experience
is the weakest path — single-date-collapse, closed verb lists, no LLM. The v2
trajectory timeline is still behind a default-off flag, so the shipped
timeline is the legacy card list.

---

## 2. Top issues by severity

| # | Severity | Issue | Where |
|---|----------|-------|-------|
| 1 | Blocker | "by next Friday" resolves to THIS Friday at commit (a week early, silently wrong deadline) while the prompt layer says next week | `DateResolver.resolveBeforeAfter` (Moti/Utilities/DateResolver.swift:249-268) |
| 2 | High | Comma multi-deadline input → 1 task, later deadlines dropped (default-mode path) | `CaptureSegmenter.segments` (Moti/Services/TaskUnderstandingService.swift:36-58) + `DateResolver` first-match-only |
| 3 | High | LLM-preserved time expressions unparseable at commit ("end of the month", spelled durations, "next month") → undated review tasks | `DateResolver` missing patterns; spelled numbers only in `DeterministicPreClassifier` |
| 4 | High | Everyday verbs (pay/clean/renew/book/cancel...) → "unclear" → unnecessary clarification | `CapturedClassifier.actionVerbs` (Moti/Utilities/CapturedClassifier.swift:4-10) |
| 5 | High | Silent degradation: Gemini/proxy/FM errors fall back to rule-based with no user-visible signal; fallback planning emits ONE generic target with first time signal only | `GeminiContextualCaptureService.analyze` catch; `fallbackWorkspaceDecision` (ContextualCaptureAgentService.swift:290-333) |
| 6 | Medium | Project-scale keyword (rule 3) outranks multi-deadline (rule 8): 3-deadline list mentioning "capstone" → deep plan with subtasks | `PlanningClassifier.classify` rule order (PlanningClassifier.swift:56-152) |
| 7 | Medium | `refinePlan` original-input recovery is dead code — always uses live text field | QuickCaptureView.swift:563 |
| 8 | Medium | No cap on clarification rounds (potential question loop) | QuickCaptureView `answerClarification` |
| 9 | Medium | Reminder rule (7) swallows multi-deadline reminders → one task, arbitrary date wins (weekday array order, not first mention) | PlanningClassifier rule order + DateResolver |
| 10 | Medium | Trajectory: 6-strand hard cap, silently truncated; one deadline per strand on main field (intermediate milestones only in Peek) | TrajectoryTimelineView.swift:72; StrandTimelineBuilder.swift:193 |
| 11 | Medium | "this week" resolves to NEXT Friday when today is Friday | DeterministicPreClassifier/DateResolver `nextWeekday` (0→7 wrap) |
| 12 | Medium | TemporalResolver blind to "this weekend" (DateResolver supports it) → prompt may re-ask for known timeline | DeterministicPreClassifier |
| 13 | Low | Title hygiene: "TestFlight ready by", "Finish my portfolio , apply to 5 jobs ,", trailing "on" | `removingDatePhrases` / `normalizedTitle` |
| 14 | Low | Task completed after deadline projects a confident upward "completed" arc (reads as recovered, not late) | TrajectoryProjector outcome mapping |
| 15 | Low | Orphan projects if user dismisses after project creation but before plan confirm | QuickCaptureView confirmWorkspace |

---

## 3. Failed-input examples (probe evidence, ref date Fri Jun 12 2026)

| Input | Expected | Actual | Verdict |
|---|---|---|---|
| "TestFlight ready by next Friday" (from Wed Jun 10) | due Fri Jun 19 | prompt layer: Jun 19; **saved: Jun 12** | FAIL (Blocker) |
| "I need to finish my portfolio by June 25, apply to 5 jobs by June 18, and prepare my capstone presentation by June 20." (non-LLM path) | 3 tasks, 3 dates | 1 task "Finish my portfolio , apply to 5 jobs , and prepare my capstone presentation", due Jun 25 only | FAIL (High) |
| same input (Stage-1 routing) | multiDeadlinePlanning, no subtasks | complexPlanning **deep**, subtasks=true ("capstone" keyword) | FAIL (Medium) |
| "Pay rent by the end of the month" | atomic task, due Jun 30 | "unclear" → clarification question; date unparseable | FAIL (High) |
| "Finish the draft in two weeks" | task due Jun 26 | task undated → review "Missing time information" (works with digits "in 2 weeks") | FAIL (High) |
| "remind me to finish my essay by Friday and submit the report by Monday" | 2 reminders | 1 task, due **Monday** (weekday array order wins, not first mention) | FAIL (Medium) |
| "Renew my passport before graduation" | task, no date, no interrogation | "unclear" → clarification | FAIL (Medium) |
| "Clean the garage this weekend" | atomic, weekend window | "unclear" → clarification (verb missing; weekend invisible to classifier/prompt) | FAIL (Medium) |
| fallback plan for app-launch input (3 deadlines known) | 3 targets | clarifying question, then ONE generic target "Define the next concrete milestone" w/ first signal | FAIL (High, no-LLM mode) |
| "I have three things this week: ... by Tuesday, ... by Thursday, ... on Sunday." | multiDeadline, all dates | PASS at classifier+resolver layers (LLM path) | PASS |
| "finish critique by Tuesday; revise prototype by Thursday; submit report on Sunday" (semicolons, non-LLM) | 3 dated tasks | 3 dated tasks (title nit: "Submit the report on") | PASS |
| "I'm overwhelmed and need to finish this in 10 days" | no heavy plan | atomic task due Jun 22, no plan | PASS (title "Finish this" is vague but acceptable) |

---

## 4. Root cause analysis

1. **Two temporal resolvers with different grammars.** `DeterministicPreClassifier`
   (new, multi-match, spelled numbers, strict-next weekdays) feeds the prompt;
   `DateResolver` (old, first-match-only, digit-only, loose-next) writes the
   database. Every expression supported by one but not the other produces
   either silent wrong dates or "Missing time information" on input the user
   considers fully specified. The commit path re-parses LLM `timeExpression`
   strings through the OLD resolver.
2. **Closed keyword lists as language understanding.** Verb list (30 entries),
   project-scale list, recurrence list. Anything outside = vague/unclear.
3. **Rule ordering in `PlanningClassifier`** encodes priority by accident:
   refinement > explicit > project-scale > recurrence > note > status >
   reminder > multi-deadline. Multi-deadline evidence (≥2 anchors) is
   strictly stronger than a scope keyword or a "remind me" prefix, but it is
   checked later.
4. **Segmentation is lexical (newline/semicolon), not semantic.** Natural
   comma/"and" lists never split on the non-LLM path.
5. **Fallbacks prioritize never-failing over fidelity.** Every error path
   lands in rule-based output that looks like a successful result; no
   degradation signal reaches the user or logs.
6. **View-layer refinement state** relies on the live `input` field rather
   than workspace-carried state (`refinementHistory.first.map { _ in input }`
   is `input` in both branches).

---

## 5. Recommended implementation plan (small steps, in order)

**Step 1 — Unify temporal parsing (fixes #1, #3, #11)**
Make `DateResolver.resolveTemporal` delegate date *detection* to
`DeterministicPreClassifier` (single grammar), keeping DateResolver's
working-range/clock-time enrichment. Port: strict "next <weekday>", spelled
numbers, end-of-month, "next month", weekend, mid-month. Acceptance: the
`test_KNOWNBUG_commitPath_*` wrappers in `IntelligenceAuditTests` trip
("expected failure didn't occur") and get deleted.

**Step 2 — Multi-deadline correctness in Stage 1 + segmentation (fixes #2, #6, #9)**
(a) In `PlanningClassifier`, check `deadlineAnchorCount >= 2` BEFORE
project-scale and reminder rules (a reminder with two anchors is two
reminders). (b) Teach `CaptureSegmenter` to split comma/"and" clauses when
each clause carries its own date anchor. Acceptance:
`test_KNOWNBUG_projectKeywordOverridesMultiDeadlineRouting` and
`test_KNOWNBUG_commaSeparatedDeadlines_collapseIntoOneTask` wrappers deleted.

**Step 3 — Understanding breadth (fixes #4)**
Replace/extend `actionVerbs` with NLTagger lexical-class checks (verb POS at
sentence start) plus the expanded list; keep the closed list as fast path.
Acceptance: `test_KNOWNBUG_everydayVerbs_misclassifiedAsUnclear` wrapper deleted.

**Step 4 — Honest degradation + fallback planning fidelity (fixes #5)**
Log and surface ("Generated without full intelligence — retry?") when the
Gemini/FM path fell back; make `fallbackWorkspaceDecision` emit one target per
extracted time signal (the signals are already in `context.timeSignals`)
instead of one generic target.

**Step 5 — Refinement loop hardening (fixes #7, #8)**
Store `originalCaptureText` on `PlanningWorkspace` at first generation and use
it in `refinePlan`; add `clarificationRound` to `SmartCaptureContext` and stop
asking after 2 rounds (proceed with stated assumptions instead).

**Step 6 — Timeline/trajectory clarity (fixes #10, #14)**
Overflow chip when >6 strands ("+3 more"); render intermediate forward-node
ticks (already computed, capped 6) on the main field, not just in Peek;
distinct "finished late" treatment (or narrator phrase) for post-deadline
completions. No redesign required — all data already exists.

**Step 7 — Tests (done in this audit + follow-ups)**
`IntelligenceAuditTests.swift` added (23 tests). Follow-ups when fixing:
convert each KNOWNBUG wrapper into a plain assertion; add an integration test
that round-trips PlannedTask.timeExpression → created WorkItem.dueDate for
every expression class the prompt layer supports.

---

## 6. Test inventory added by this audit

Locked-in current-correct behavior (plain tests):
- 3-deadline extraction, 2-weekday extraction, date+clock coexistence
- spelled durations + strict next-Friday at the temporal layer
- atomic inputs never plan; emotional-pressure input never plans
- weekday multi-deadline routing (one task per deadline, no subtasks)
- semicolon-separated input → 3 dated tasks
- `missingExtractedTargets()` drop detection (3 cases)
- refinement history carry-forward
- ProjectMatcher exact/fuzzy/no-match
- StrandTimeline: completed stays as evidence; overdue reads `.slipping`
- WorkItemScope.timeline keeps done+overdue, hides archived

Known bugs encoded as `XCTExpectFailure` (delete wrapper when fixed):
- ~~commit-path "next Friday" disagreement~~ — FIXED in Step 1 (temporal unification)
- ~~commit-path spelled durations~~ — FIXED in Step 1
- ~~commit-path end-of-month~~ — FIXED in Step 1
- ~~temporal layer blind to "this weekend"~~ — FIXED in Step 1
- ~~everyday verbs → unclear~~ — FIXED in Step 3
- ~~project keyword overrides multi-deadline routing~~ — FIXED in Step 2
- ~~comma multi-deadline collapse~~ — FIXED in Step 2

### Step 3 status (completed 2026-06-12)
Understanding breadth for everyday action verbs:
- `CapturedClassifier.actionVerbs` expanded with everyday actions (renew, pay,
  clean, book, cancel, print, pack, register, deposit, reschedule, …) — the
  reliable, environment-independent fast path.
- Structural lead-in detection: the word after a personal-intent lead-in
  ("I need to ___", "have to ___", "please ___", "remember to ___") is treated
  as the action, so verbs Moti has never seen are still recognized
  ("I need to winterize the cabin" → task) — deterministic, no POS model.
- Guardrails: a `nonActionVerbs` set (think, feel, want, wonder, …) plus
  structural stop words keep reflective ("Think about my future"), emotional
  ("I feel overwhelmed about graduation"), and vague ("visa stuff") inputs out
  of the task path; project-scale wording ("Launch my app…") still routes to a
  plan, never a lone atomic task.
- **NLTagger was evaluated and rejected**: its `.lexicalClass`/`.lemma` schemes
  return `OtherWord`/nil for every token in the simulator and CI (POS model
  not bundled), confirmed against a plain declarative sentence. A deterministic
  lexicon + structural strategy is reliable across simulator, CI, and device;
  NLTagger would have made classification environment-dependent.
- Nuance (unchanged, pre-existing): "Prepare my capstone presentation by
  June 20" entered ALONE still routes to planning because "capstone" is a
  project-scale keyword. The firm requirement — it joins multi-deadline
  planning when entered with other dated deliverables — is met and tested.
  Revisiting the project-scale keyword list is out of Step 3's scope.

### Gemini schema 400 fix (completed 2026-06-12)
Live QA found a release-blocker: `GeminiContextualCaptureService.responseSchema`
nested arrays three deep (targets → phases → tasks) with in-array enums and
`maxItems`, which `gemini-2.5-flash` rejected with HTTP 400 "schema produces a
constraint that has too many states for serving" — so **every** Smart Capture
call silently fell back to deterministic.
- **Flattened the schema**: the workspace is now two sibling flat arrays —
  `planTargets` (metadata) and `planTasks` (each links to its target via
  `targetTitle`, grouped by `phaseTitle`). No array nested in an array; no
  in-array enums; no `maxItems`. Top-level enums kept (not multiplied).
- **Local reconstruction**: `GeminiContextualCaptureService.reconstructWorkspace`
  rebuilds the nested PlanningWorkspace/Target/Phase/Task models from the flat
  arrays, so internal models, validation/retry, and fallback honesty are
  unchanged. Orphan tasks synthesize a target (nothing dropped); conflicts are
  no longer model-emitted (rarely used; minor, noted limitation).
- **Live verified** (real Gemini): "Plan my app launch before next Friday",
  the 3-deadline prototype input, and "make this less intense" all return
  `source=fullLLM`, **0 HTTP 400s**, real multi-phase plans; refinement reduced
  8→4 tasks while preserving the goal + deadline.
- **Regression guard**: `MotiTests/GeminiSchemaTests.swift` asserts the schema
  stays flat (object-array depth ≤ 1, no `maxItems`) and that flat→nested
  reconstruction is correct — CI-safe (no network), so this can't silently
  regress. Full suite: 269 tests, 0 failures.

### Step 5 status — refinement-loop hardening (completed 2026-06-12)
- **Stable original capture text.** Fixed the dead-code recovery in
  `refinePlan` (it read the live `input` field; `refinementHistory.first.map { _ in input } ?? input`
  resolved to `input` either way). QuickCaptureView now snapshots
  `originalCaptureText` once at submit, and refinement/clarification resolve it
  via the testable `RefinementOriginalText.resolve(stored:liveInput:)` — the
  snapshot wins over a since-edited live field.
- **Clarification cap (2).** `SmartCaptureContext.clarificationRound` +
  `maxClarificationRounds = 2` + `clarificationBudgetExhausted`. The view counts
  answered rounds; at the cap the rule-based service proceeds
  (`proceedWithoutClarification`) instead of asking, recording the assumption in
  the existing `PlanningWorkspace.assumptions`; the prompt builder tells the LLM
  to stop asking and record guesses.
- **Refinement preserves, never restarts.** The deterministic path gained
  `refinementEchoDecision`: when a `planRefinement` is present it preserves the
  previous workspace verbatim (targets, deadlines, assumptions) and records the
  change request in `refinementHistory`, rather than asking a generic "what's the
  goal?" question. The LLM refinement prompt already preserved original input,
  targets, deadlines, assumptions, and history and instructed "Preserve all
  existing PlanningTargets … not as a new raw task" — locked by tests now.
- Intelligence source (Step 4) is preserved/honest through refinement.
- Tests: `MotiTests/RefinementLoopTests.swift` (11) — stable original text,
  prompt preservation, the cap (below/at), post-cap assumptions, and
  deterministic refinement preserving the plan. No timeline/trajectory/capture
  UI changes; the marker is still not surfaced in UI.

### Step 4 status — fallback honesty only (completed 2026-06-12)
The refinement-loop half of Step 4 is intentionally NOT started yet.
- New `IntelligenceSource` marker on `ContextualCaptureDecision`: `.fullLLM`,
  `.onDevice`, `.deterministic`, `.clarificationNeeded`. Each tier stamps its
  own result at the `analyze` boundary; fallback results pass through with the
  lower tier's stamp, so a rule-based result can never masquerade as the LLM.
  A clarification/asking result self-marks `.clarificationNeeded` regardless of
  engine (honest — it isn't a finished plan). Default is `.deterministic` so an
  unstamped decision never over-claims AI.
- Silent-degradation points addressed: Gemini catch (#5), FM catch, and the
  generic fallback workspace. `fallbackWorkspaceDecision` now preserves
  structure — it segments a multi-deadline capture into one target per
  deliverable, each keeping its own deadline, instead of collapsing to a single
  "Define the next concrete milestone" stub. Assumption copy softened (calm,
  never implies failure).
- Internal-only for now: the marker drives a DEBUG console log in
  QuickCaptureView (`[Capture source] …`) and exposes a calm `displayLabel`
  hook for a future subtle badge. No user-facing UI, no warnings, no timeline
  changes — per scope.
- Tests: `MotiTests/FallbackHonestyTests.swift` (11) — Gemini/proxy failure
  preserving the fallback marker (URLProtocol-stubbed outage), rule-based
  stamping `.deterministic`/`.clarificationNeeded`, the deterministic fallback
  preserving every deadline, and normal deterministic task creation unchanged.
- Remaining for the later refinement-loop step: dead-code original-input
  recovery in `refinePlan`, unbounded clarification rounds, and surfacing the
  marker in a subtle user-facing way if desired.

### Step 2 status (completed 2026-06-12)
Multi-deadline understanding and segmentation:
- `PlanningClassifier`: the multi-deadline rule now runs BEFORE project-scale
  wording and the reminder rule (recurrence/note/status still outrank it —
  "gym every monday and thursday" stays one habit; past-tense status reports
  never spawn tasks). Anchor counting delegates to the unified grammar via
  the new `TemporalAnchors` helper.
- `CaptureSegmenter`: comma/"and" clauses split into separate captures when
  at least two clauses carry their own date anchor; anchor-less lead-ins glue
  forward, anchor-less tails glue backward, and ordinary comma text with one
  deadline never splits.
- `DateResolver.unifiedDateDetection`: prefers the candidate the user marked
  with a deadline cue ("by Tuesday") over an incidental earlier reference
  ("this week: …").
Verified: the portfolio/jobs/capstone sentence → 3 tasks with Jun 25/18/20;
the two-deadline reminder → essay→Friday + report→Monday.

### Step 1 status (completed 2026-06-12)
`DateResolver.resolve` now delegates date detection to
`DeterministicPreClassifier` (the prompt layer's grammar) for confident
(≥0.85) deterministic candidates, with legacy patterns as fallback. The
unified grammar also gained: end-of-month ("by the end of the month",
"end of June"), bare "next month" (end of that month), "this weekend"
(Sunday end-of-day), and a fix so "this week" on a Friday stays today.
`test_promptLayerAndCommitPath_neverDisagree` locks the contract across
ten expression classes.
