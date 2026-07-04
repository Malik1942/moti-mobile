# Moti Timeline Redesign v2.1

## Summary

Moti Timeline is a behavior-shaped trajectory view.

It does not show a task list.  
It does not show a calendar.  
It does not assume the user will complete everything they planned.

Instead, each project is drawn as a silk strand across time. The strand shows how that project has been fed by actual behavior, where key moments happened, and where the current trajectory is heading.

The Timeline answers one question:

> Based on what I am actually doing, where are my projects heading?

The visual direction is inspired by stock charts:

- Horizontal time axis
- Selectable time scale
- Continuous project trajectories
- Key moments along the path
- Recent behavior and projected future in one view

Unlike a stock chart, Moti is not visualizing price.

It is visualizing future momentum, slippage, fading, and continuity.

---

# Core Product Belief

Most planning tools assume:

> If it is scheduled, it will happen.

Moti assumes something more realistic:

> The future is shaped by actual behavior, not by intention alone.

A calendar shows the future you planned.

Moti shows the future your behavior is making likely.

This is the core differentiation from Calendar, Things, Linear, and traditional project tools.

---

# Why The Previous Vertical Direction Changes

The previous vertical future-scroll direction used:

- Bounded past above Now
- Future expanding downward
- Project strands as vertical lines

That direction was conceptually interesting, but introduced two major issues:

### 1. Time became harder to read

Vertical timelines are not the dominant mental model for mobile time-based visualizations.

### 2. The visual language became abstract

Users saw lines.

They did not clearly see:

- Time
- Deadlines
- Key moments
- Trajectory differences

Most time-heavy mobile visualizations still use horizontal time:

- Stocks
- Health
- Activity
- Steps
- Sleep
- Heart Rate

Therefore v3 returns to a more intuitive mapping:

> Horizontal = Time  
> Vertical = Projects

---

# Product Architecture

Moti contains three surfaces.

| Surface | Question | Role |
|----------|----------|----------|
| Timeline | Where is each project heading? | Primary trajectory view |
| Peek | Why is it heading there? | Context overlay |
| Plan | What exactly should happen next? | Scheduling and execution |

Timeline remains the primary surface.

However Timeline is not the execution surface.

Tasks, schedules, and detailed planning belong inside Plan and Projects.

Timeline only visualizes:

- Trajectories
- Momentum
- Deadlines
- Key moments
- Future projections
- Behavioral signals

---

# Main Visual Model

## Each Project Is A Silk Strand

Every project appears as a horizontal trajectory strand.

A strand is not:

- A progress bar
- A checklist
- A task lane

A strand is a visual trace of a project's future trajectory.

Each strand can reveal:

- Recent activity
- Quiet periods
- Key moments
- Feedback points
- Deadline pressure
- Future projection
- Fading or slippage

## Project Lanes

Projects are stacked vertically.

Each lane contains:

- Project name
- Identity color
- Current state
- Continuous trajectory
- Sparse markers

Blank space between lanes is intentional.

The goal is calm legibility rather than information density.

Default visible count:

- 4–6 projects

Additional projects collapse into a secondary view.

---

# Time Structure

## Horizontal Time Axis

Time flows left → right.

### Left

Recent behavioral evidence.

### Center

Now.

### Right

Projected future.

The principle is:

> Past is evidence. Future is projection.

## Time Scale Selector

Top-level segmented control.

text 1W   1M   3M   6M   1Y 

This changes:

- Amount of past shown
- Planning horizon
- Future projection distance

This is not merely a zoom control.

It is a planning horizon selector.

| Scale | Past | Future | Purpose |
|---------|---------|---------|---------|
| 1W | Recent days | Next days | Immediate correction |
| 1M | Recent weeks | Next weeks | Default planning |
| 3M | Recent month | Next months | Project trajectory |
| 6M | Recent months | Longer horizon | Strategic planning |
| 1Y | Recent quarter | Year outlook | Long-term direction |

## Shared Time Axis

All projects share one axis.

This allows users to see:

- Simultaneous activity
- Overlapping futures
- Clustered deadlines
- Resource contention

Timeline is not only about individual projects.

It is also about relationships between futures.

---

# Visual Grammar

## Color

Color represents project identity only.

Color must never mean:

- Good
- Bad
- Urgent
- Healthy
- Risky

Same project = same color everywhere.

## Actual vs Projection

Every strand contains two regions.

### Actual

- Solid
- Strong
- High confidence

### Projection

- Dashed or fading
- Lower confidence
- More uncertain with distance

The transition must be immediately visible.

## Depth

Depth communicates certainty.

Near Now:

- Higher contrast
- Stronger opacity

Far future:

- Softer
- Lighter
- More uncertain

This should create a future field rather than a flat chart.

## Shape

A strand should not be a straight line.

Shape carries meaning.

| Shape | Meaning |
|---------|---------|
| Stable continuation | Sustained |
| Flattening | Fading |
| Overshoots target | Slipping |
| Dissolving | Losing support |
| Dashed continuation | Forecasted path |

Visual variation must always map to real behavioral signals.

## Thickness

Thickness can communicate support.

Examples:

- Strong recent behavior → thicker
- Weak support → thinner
- Fading maintenance → thinning projection

Thickness should never communicate priority.

## Key Moments

Markers represent significant moments.

Examples:

- Milestone
- Review
- Feedback
- Deferral
- Deadline
- Projected finish
- Pause

Guideline:

Maximum 1–3 markers per visible project.

Timeline must never become a task list.

---

# Marker System

Every marker answers:

> What happened?  
> Or what is expected to happen?

## Marker Types

| Marker | Meaning |
|----------|----------|
| Filled dot | Actual event |
| Hollow dot | Projected outcome |
| Tick | Future commitment |
| Diamond | Deadline |
| Gap | Quiet period |
| Break | Pause |

## Deadline Marker

Deadlines must be visible without opening details.

Users should visually understand:

- Target date
- Projected finish
- Relative relationship

The geometry should reveal slippage before text does.

---

# Future Bands

Future bands provide temporal structure.

Examples:

text RECENT NOW NEAR FUTURE MID FUTURE LATER 

or

text MAY NOW JUNE JULY LATER 

Bands should:

- Be subtle
- Provide orientation
- Avoid becoming a calendar grid

---

# Timeline Screen

## Header

Timeline title.

Time-scale selector.

Forward-looking summary:

> On current pace, Launch is slipping while Fitness is fading.

## Main Field

Shared horizontal time axis.

Project lanes.

Trajectory strands.

Markers.

Deadlines.

Future projections.

## Bottom Insight Card

One prioritized recommendation.

Example:

> Launch is slipping.

> Consider creating space this week.

---

# Achievement Projects

Achievement projects contain:

- Goal
- Deadline
- Finish condition

Possible states:

- On Track
- Slipping
- Stalled
- Completed
- Paused

Slippage must be visible geometrically.

Not merely through labels.

---

# Maintenance Projects

Maintenance projects do not have finish lines.

Possible states:

- Sustained
- Quiet
- Fading
- Paused

Fading should look different from lateness.

The visual should communicate:

> Losing support

rather than

> Overdue

---

# Peek Sheet

Tapping a strand opens a contextual overlay.

Users remain anchored to the Timeline.

## Shared Structure

1. Project header
2. Current state
3. Explanation
4. Focused visualization
5. Evidence
6. Actions

## Achievement Peek

Shows:

- Deadline
- Pace
- Projection
- Supporting evidence

Actions:

- Open in Projects
- Not this week
- Mark as paused

## Maintenance Peek

Shows:

- Rhythm
- Last trace
- Quiet duration
- Projection

Actions:

- Make space this week
- Not this week
- Lower priority

---

# Computation Model

The model does not determine project state.

The computation layer does.

## Computed States

Achievement:

- On Track
- Slipping
- Stalled
- Completed

Maintenance:

- Sustained
- Quiet
- Fading
- Paused

The language model only translates structure into language.

## AI Role

AI is not the trajectory engine.

The computation layer determines project state, trajectory outcome, and visual structure.

AI may only be used for:

1. Top summary phrasing
   Translate computed states into a short forward-looking sentence.

2. Peek explanation compression
   Turn computed evidence into readable, behavioral language.

3. Co-occurrence explanation
   Describe which projects rose while another went quiet.
   This must be framed as co-occurrence, never causation.

4. Marker and pattern summarization
   Summarize sparse key moments when there are too many raw events to show directly.

5. Later personalization
   Suggest project type or rhythm defaults from observed behavior, but user correction and rule-based learning remain the source of truth.

AI must never:

- Determine whether a project is slipping, fading, sustained, or on track.
- Invent urgency.
- Infer life consequences.
- Say one project caused another to fail.
- Replace deterministic computation.

## Foundation Model Use

When the device and OS support Apple Foundation Models, Moti may use the on-device model for the allowed AI roles above regardless of the user's capture intelligence mode.

Foundation Models must receive computed trajectory facts as input, not raw authority over state. The response should be treated as phrasing or compression only, and deterministic fallback copy must remain available when Foundation Models are unavailable or return unusable output.

The current intelligence mode may still control capture and planning flows. Timeline phrasing support is a separate opportunistic enhancement gated by `FoundationModelRuntime.status.isAvailable`.

---

# V1 Projection Logic

V1 is directional.

Not predictive.

Achievement:

- Progress pace vs remaining time

Maintenance:

- Feeding frequency vs baseline rhythm

Outputs:

- On Track
- Slipping
- Fading
- Sustained

Avoid false precision.

Never claim:

> Two weeks late.

Instead:

> Projected after target.

---

# Interaction Model

## Tap Strand

Open Peek.

## Tap Marker

Explain the moment.

## Change Time Scale

Adjust planning horizon.

Maintain visual continuity around Now.

---

# Language Principles

Use behavioral language.

Preferred:

- On current pace
- Slipping
- Fading
- Sustained
- Quiet
- Projected after target
- Losing support

Avoid:

- Lazy
- Failed
- Neglecting
- Should
- Must

Good:

> Fitness is fading at the current rhythm.

Bad:

> You are neglecting Fitness.

---

# Visual Acceptance Criteria

A successful design should allow users to immediately identify:

1. Time direction
2. Project identity
3. Actual vs projected trajectory
4. Deadline locations
5. Slipping projects
6. Fading projects
7. Future uncertainty
8. What deserves attention now

The visualization should feel like a future field.

Not:

- A dashboard
- A calendar
- A Gantt chart
- A task list

---

# Product Acceptance Criteria

Within five seconds users should answer:

- What is moving?
- What is fading?
- What is slipping?
- Which deadline matters?
- Which future needs attention now?

Without opening individual tasks.

Without reading every label.

The shape should communicate before the text does.

---

# Build Roadmap

## V1

- Horizontal trajectory field
- Project lanes
- Shared time axis
- Time scale selector
- Actual vs projected segments
- Key moments
- Deadlines
- What Matters Now card
- Peek sheet

## V1.5

- Better marker aggregation
- Richer labels
- Improved transitions
- Marker interactions
- Maintenance rhythm visualizations

## V2

- User override learning
- Better trajectory estimation
- More accurate projected dates
- Future contention layer
- Cross-project relationship modeling

---

# Non-Negotiables

- Timeline shows trajectories, not tasks.
- Time is horizontal.
- Projects are stacked vertically.
- Color means identity only.
- Due dates must remain visible.
- Projection must differ from actual behavior.
- Fading must differ from slipping.
- Past is evidence.
- Future is projection.
- Planning belongs to Plan and Projects.
- Moti predicts from behavior, not intention.
- The experience should feel like a future field rather than an analytics dashboard.

---

# Canonical Vocabulary

> **Status: ADOPTED — executed in the v2.1 cleanup.** This section is the single source of truth for Moti's naming. It was produced from an exhaustive inventory of the codebase + docs (every symbol, filename, folder, persisted key, PRD line, and user-facing string). All renames in the "Rename Map" below have been applied; "Lifeline" is fully eliminated from the code. The four sign-off decisions were confirmed: (1) the Good/Normal/Bad value is **`ProgressState`**; (2) the 5 persisted keys were renamed **with** a one-time idempotent `UserDefaultsKeyMigrator` (read-old → write-new → clear-old, covered by tests); (3) `StrandTypeOverrideStore`; (4) the view-component folder is **`Views/Components/Strand`**. `SessionCheckIn` (a `@Model`) remains deferred (store-migration-sensitive).

## The concept model

Three timeline concepts, kept strictly distinct:

| Term | Meaning | Role | User-facing? |
|---|---|---|---|
| **Strand** | A future the user cares about — one project drawn across time. The **entity**. | The noun everything else attaches to. | Yes — the user-facing noun. |
| **Trajectory** | The **computed projection** of a strand: where its behavior says it is heading (on-time, slipping, fading, sustained). Output of the trajectory engine. | A *property of* a Strand, never a synonym for it. | Indirectly (via outcome words). |
| **Trajectory engine** | The pure compute subsystem that turns behavior into a Trajectory (`TrajectoryProjector`, `TrajectoryProjection`, `TrajectoryOutcome`, `TrajectoryPolicy`). | Compute only — no UI, no entity state. | No. |
| **Timeline** | The **surface** that renders strands and their trajectories (PRD three-surface model: Timeline / Peek / Plan). | Surface name. Stays "Timeline". | Yes. |
| **Lifeline** | **ELIMINATED.** Dead legacy name for the pre-v2 vertical design. Every occurrence resolves to Strand, Trajectory, or Timeline. | — | Never again. |

Key invariant confirmed by the inventory: **Strand** (entity) and **Trajectory** (projection) are already used cleanly and are never swapped. `StrandPresence` (the entity's present-moment truth) and `TrajectoryProjection` (the forward read) are correctly separated. The only polluted term is **Lifeline**.

## Rename Map — Lifeline elimination

All remaining `Lifeline`-named symbols (verified: 6 types + 1 sample-data enum), with the concept each actually names:

| Current symbol | Names… | → Canonical | File |
|---|---|---|---|
| `LifelineView` (View) | renders one **strand** row | `StrandView` | `LifelineView.swift` → `StrandView.swift` |
| `LifelineGeometry` | render geometry for a **strand** | `StrandGeometry` | `LifelineGeometry.swift` → `StrandGeometry.swift` |
| `LifelineMetrics` (layout consts) | **strand** row layout constants | `StrandLayout` | (in `StrandView.swift`) |
| `LifelineSampleData` | seeds sample **strands** | `StrandSampleData` | `LifelineSampleData.swift` → `StrandSampleData.swift` |
| `LifelineTypeOverrideStore` | overrides `StrandType` (an **entity** attribute) | `StrandTypeOverrideStore` | file renamed to match |
| `LifelineInstrumentation` | metrics for the **trajectory** timeline feature | `TrajectoryInstrumentation` | file renamed to match |
| `LifelineMetricRecord` | a **trajectory** metrics record | `TrajectoryMetricRecord` | (in `TrajectoryInstrumentation.swift`) |

`StrandCoverageSnapshot` (already Strand-named, lives in the instrumentation file) **keeps its name** — it measures strand-type coverage.

### Folder renames (in-place; not a taxonomy move)

| Current folder | → Canonical | Note |
|---|---|---|
| `Moti/Models/Lifelines/` | `Moti/Models/Strands/` | Holds the Strand entity types **and** the trajectory engine (`TrajectoryProjector`). |
| `Moti/Views/Components/Lifeline/` | `Moti/Views/Components/Strand/` | Also holds `TrajectoryAxis` + `TimelineNarrator` — acceptable as the strand-timeline component folder. |

Both keep the type-vs-feature taxonomy exactly as-is (Models stays Models, Views stays Views). The feature-first restructure is explicitly a **separate, later pass**.

### Feature flag

| Current | → Canonical |
|---|---|
| `@AppStorage("useLifelineTimeline")` (3 sites: `MotiApp`, `SettingsView`, `StrandSampleData`) | `useTrajectoryTimeline` |

The user-facing toggle label is already "Use Trajectory Timeline" — the flag name was the last "Lifeline" leak behind it.

## Persisted keys — the one place migration is required

Renaming a `UserDefaults` **string key** silently orphans stored values. These 8 keys embed the legacy name. Split by risk:

| Current key | → Canonical | Migrate? |
|---|---|---|
| `useLifelineTimeline` | `useTrajectoryTimeline` | **Yes** — real user state (a TestFlight user who enabled the v2 timeline would silently revert to off). |
| `lifelines.pausedStrandIDs` | `strand.pausedIDs` | **Yes** — user's paused strands. |
| `lifelines.loweredStrandIDs` | `strand.loweredIDs` | **Yes** — user's de-emphasized strands. |
| `lifelines.parkedStrandWeek` | `strand.parkedWeek` | **Yes** — user preference. |
| `lifelines.spacedStrandWeek` | `strand.spacedWeek` | **Yes** — user preference. |
| `lifelines.metrics.records.v1` | `trajectory.metrics.records.v1` | No — DEBUG instrumentation, disposable. |
| `lifelines.debug.typeOverrides.v1` | `trajectory.debug.typeOverrides.v1` | No — DEBUG only. |
| `MotiSeedLifelines` (launch arg) | `MotiSeedStrands` | No — DEBUG seed trigger. |

**Decision required:** the 5 "Yes" keys need a one-time idempotent `UserDefaults` migration (read old → write new → remove old), mirroring `ProjectRelationshipMigrator`. This is the only migration code Phase 2 introduces. Alternative (zero-risk, lower-purity): keep the legacy key *strings* and rename only the Swift identifiers — "Lifeline" then survives invisibly in string literals. **Recommended: migrate the 5 keys** so the term is truly gone.

## Check-in family — three distinct meanings

The inventory confirmed three separate concepts hiding under overlapping "check-in" language. Canonical split:

| Concept | Scope | Canonical name | Symbols (KEEP) |
|---|---|---|---|
| **Checkpoint** | Session-scoped mid-session progress prompt | "Checkpoint" | `CheckpointCoordinator`, `CheckpointEvent`, `TimelineCheckpointScheduler`, `CheckpointPolicy`, `CheckpointFloatingCard`, `WorkSession.checkpointProgress` / `.firedCheckpoints` |
| **Check-in** | Task-scoped, notification-driven progress prompt | "Check-in" | `TaskCheckInCoordinator`, `TaskCheckInCoordinator.Request`, `CheckInSheet` |
| **Progress value** | The shared Good / Normal / Bad response | **`ProgressState`** (see below) | currently `SessionState` |

**Open naming choice (the one genuinely open decision): the Good/Normal/Bad value.** Currently `enum SessionState` — misleading, because it is used equally by session checkpoints *and* task check-ins *and* manual pulses, not sessions only.
- **Recommended: `ProgressState`.** Verified **migration-free**: it is a plain `enum` (not a `@Model`); it is persisted only as its raw strings (`"good"`/`"normal"`/`"bad"`) in `SessionCheckIn.stateRawValue`, so the type name is never stored. Rename is ~16 in-memory reference substitutions, zero persistence risk.
- Alternatives if you dislike ProgressState: `PaceState`, `ProgressPulse`.

## Deferred (out of scope for this rename pass)

- **`SessionCheckIn` (`@Model`)** stores *both* checkpoint and check-in responses (disambiguated by whether `session` or `workItemID` is set). Its name leans "check-in" and is arguably a muddle, but it is a **SwiftData `@Model`** — renaming the class changes the persisted entity name and needs a store migration. **Keep `SessionCheckIn` for now**; revisit with the model layer.
- **Doc bug to fix during the pass (not a rename):** `MotiApp.swift:90` — the comment "Drives the Timeline Check-in sheet for task progress checkpoints" sits above the *session checkpoint* scheduler, not the check-in coordinator. Correct it to describe the checkpoint floating card while touching that file.
- **`docs/DOGFOOD.md`** references `-MotiSeedLifelines` and "Lifelines Metrics (DEBUG)" — update to the new names when the keys/labels change.

## Conflicts flagged against the originally-proposed mapping

1. `LifelineTypeOverrideStore` → the inventory's first instinct was `Trajectory…`, but it overrides `StrandType` (achievement vs maintenance), an **entity** attribute → mapped to **`StrandTypeOverrideStore`**. (Decision recorded above.)
2. `LifelineInstrumentation` / `LifelineMetricRecord` are feature-level metrics, not the entity → mapped to **`Trajectory…`** even though the co-located `StrandCoverageSnapshot` stays Strand-named. Slight asymmetry, intentional.
3. View-component folder (`Views/Components/Lifeline/`) contains non-strand pieces (`TrajectoryAxis`, `TimelineNarrator`). Named **`Strand/`** to pair with `Models/Strands/`; alternative `Views/Components/Timeline/` if you prefer surface-naming. (Decision needed.)

No case was found where **Strand** meant the projection or **Trajectory** meant the entity — the only real cleanup is eliminating **Lifeline** plus renaming the misleading `SessionState` (now `ProgressState`).

---

# Architecture: RootTabView decomposition

> **Status: PLAN ONLY — not executed.** This is the design for a later pass. No code has been changed for this section. It follows the vocabulary cleanup and is sequenced into independently build+test-gated steps.

## Why

`RootTabView` (in `MotiApp.swift`) has grown into a god view: ~340 lines owning tab routing, three sheet presentations, the checkpoint floating card, **persistence** logic (check-in dedup, checkpoint bookkeeping), notification reconciliation, and widget-snapshot triggering. Persistence and dedup do not belong in a view, and the widget trigger is a per-render O(n) allocation. The parser layer already demonstrates the target pattern (protocol + `EnvironmentKey` + `@Environment`); this brings the rest of the app into line.

## Current responsibilities (inventory)

| # | Responsibility | Current location | Keep in view? |
|---|---|---|---|
| 1 | Tab routing + tab bar + Plan badge | `selectedTab`, `selectedContent`, `MotiTab`, `MotiTabBar`, `planAttentionCount` | **Yes** — this is the view's job. |
| 2 | Onboarding gate | `hasCompletedOnboarding` branch | Yes. |
| 3 | Three sheet presentations | `QuickCaptureView`, `CheckInSheet`, `WorkItemDetailView` (re-plan) | Yes (presentation), but the *save callbacks* move out. |
| 4 | Checkpoint floating card + handlers | `handleCheckpointResponse`, `handleCheckpointDismiss` | Presentation stays; **persistence moves out**. |
| 5 | Task check-in persistence + dedup | `saveTaskCheckIn` (dedup by `checkpointID`) | **Move to service.** |
| 6 | Checkpoint response persistence | `handleCheckpointResponse` body + `markFired` | **Move to service.** |
| 7 | Notification reconciliation | `.task` / `.onChange` / `.onChange(scenePhase)` → `WorkItemNotificationScheduler.shared.reconcile` | **Move to a lifecycle modifier.** |
| 8 | Widget snapshot trigger | `widgetChangeToken` + `.onChange` → `writeWidgetSnapshot` | **Replace mechanism.** |
| 9 | Scene-phase checkpoint resolution | `.onChange(scenePhase)` → `scheduler.resolvePassedCheckpoints` | Move with #7. |

## Extraction 1 — `ProgressPersistence` service (responsibilities #5, #6)

Move all `SessionCheckIn` / `WorkSession` writes out of the view into one `@MainActor` service. Proposed surface:

- `recordTaskCheckIn(_ request: TaskCheckInCoordinator.Request, state: ProgressState, note: String, in: ModelContext)` — the dedup-by-`checkpointID` insert-or-update (currently `saveTaskCheckIn`).
- `recordCheckpointResponse(_ event: CheckpointCoordinator.CheckpointEvent, state: ProgressState, in: ModelContext)` — creates the `SessionCheckIn` and calls `markCheckpointFired` (currently the body of `handleCheckpointResponse`).
- `markCheckpointFired(_ event:, in session: WorkSession, context: ModelContext)` — the `firedCheckpoints` bookkeeping + session deactivation (currently `markFired`).

Injected via `EnvironmentKey` (`\.progressPersistence`) exactly like `taskUnderstandingService`; the default value is the live implementation, a fake is injectable in tests. **Payoff:** the check-in dedup rule (repeated notification taps must update-in-place, not duplicate) becomes unit-testable in isolation for the first time — today it can only be exercised through the whole view.

Note on the context: the methods take `ModelContext` as a parameter (the view already has `@Environment(\.modelContext)`), so the service stays a stateless, easily-faked value rather than capturing a context.

## Extraction 2 — replace `widgetChangeToken` (responsibility #8)

**Problem.** `widgetChangeToken` concatenates *every field of every work item and project* into a `String` on **every** `body` evaluation, then `.onChange(of: token)` writes the snapshot when it differs. Cost is O(n · fields) allocation per render and grows with the dataset — paid even when nothing changed.

**Target.** Stop deriving a giant reactive string. Introduce a `WidgetSnapshotCoordinator` (injected service) exposing `scheduleRefresh()` that coalesces bursts (debounce ~0.25s) and calls `WidgetSnapshotWriter.write`. Call `scheduleRefresh()` from the handful of real mutation sites — all of which already call `modelContext.save()`:

- QuickCapture create/save, `WorkItemDetailView` save/delete, `PlanView` delete, `EditProjectSheet` save, `ProjectsView` delete/reorder, and the two `ProgressPersistence` methods above.

This converts "recompute a fingerprint every frame" into "signal on the ~7 writes that actually change data." **Version-stamp variant:** if a reactive trigger is preferred over explicit calls, back the coordinator with a single monotonic counter bumped on each save (the pattern `StrandPreferenceStore.revision` already uses) and `.onChange(of: clock.version)` — O(1) per render. Either way, drop the per-field string. Risk to watch: a new mutation path that forgets to signal → stale widget; mitigate by funneling saves through one helper and asserting in DEBUG.

## Extraction 3 — notification + scene-phase lifecycle (responsibilities #7, #9)

Fold the three reconcile triggers and the scene-phase checkpoint resolution into a private `.reconcilesNotifications(workItems:sessions:)` view modifier (or a small `AppLifecycleCoordinator`). Pure move of existing calls; no behavior change. Low priority, do last.

## Migrating the five `.shared` singletons to environment DI

Match the parser pattern: define an `EnvironmentKey` whose `defaultValue` is the current shared instance (so behavior is identical on day one), add an `EnvironmentValues` accessor, inject once at the app root in `MotiApp` (alongside the existing `.environment(\.taskUnderstandingService, …)`), and replace `X.shared` in views with `@Environment(\.x)`.

| Singleton | Observed by UI? | DI difficulty | Order |
|---|---|---|---|
| `SoundManager` | No | Trivial | 1 |
| `AppleCalendarSyncService` | No | Easy | 2 |
| `WorkItemNotificationScheduler` | No | Easy | 3 |
| `TaskCheckInCoordinator` | **Yes** (`pendingRequest` drives a sheet) | Medium | 4 |
| `TimelineCheckpointScheduler` | **Yes** (`coordinator.pendingCheckpoint` drives the floating card) | Medium | 5 |

**Critical caveat — environment DI only reaches views.** Several of these singletons are also called from *non-view* code: `WorkItemNotificationScheduler.shared` and `AppleCalendarSyncService.shared` are invoked from services and from `QuickCaptureView`'s save path deep in async work; `TimelineCheckpointScheduler` calls into other services. `@Environment` cannot reach those call sites. So this migration has two seams:

1. **View layer →** environment injection (the parser pattern).
2. **Service-to-service →** constructor/parameter injection from a single composition root (e.g. build the graph in `MotiApp` and pass dependencies in), *not* `@Environment`.

Do not attempt to route service-to-service calls through the environment. The two observed coordinators (#4, #5) are the highest risk: they publish state that drives presentation, so injection must preserve their `@Observable`/`ObservableObject` identity or the checkpoint card / check-in sheet silently stops appearing — verify each with a manual foreground-a-checkpoint pass, not just the unit suite.

## Sequencing (each step independently build+test-gated)

1. **Extract `ProgressPersistence`** + add dedup/bookkeeping tests. Highest value, lowest risk (pure logic move; view shrinks ~80 lines).
2. **Replace `widgetChangeToken`** with `WidgetSnapshotCoordinator` (or version stamp). Self-contained.
3. **Extract the lifecycle modifier** (#7, #9). Pure move.
4. **DI-migrate the 3 non-observed singletons** (SoundManager, AppleCalendarSyncService, WorkItemNotificationScheduler).
5. **DI-migrate the 2 observed coordinators** last, with manual verification of the checkpoint card and check-in sheet.

## Risks

- **Observation regressions** (highest): injecting `TaskCheckInCoordinator` / `TimelineCheckpointScheduler` wrongly can break the reactive presentation of the check-in sheet and checkpoint card. Manual verification required.
- **Split DI seams**: environment for views, constructor injection for service-to-service — mixing them (trying to use `@Environment` off the view tree) will not compile / will silently fall back to the singleton.
- **Widget staleness**: any mutation site not wired to `scheduleRefresh()` leaves the widget stale; centralize saves and add a DEBUG assertion.
- **`@MainActor` + `ModelContext` threading**: the persistence service must stay `@MainActor`, matching the current call sites, to avoid SwiftData context hopping.
- **Not in scope**: renaming the `SessionCheckIn` `@Model` (store migration) — tracked separately in the Canonical Vocabulary "Deferred" list.
