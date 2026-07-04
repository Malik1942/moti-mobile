# Horizon Timeline v2 — T0 Data Layer Audit

**Branch:** `feature/horizon-timeline` · **Date:** 2026-07-04 · **Verdict: GO for Session 1**

Blocking data-layer audit from the implementation breakdown (T0). Verified against the
real schema, not assumed. Score: **3 PASS · 2 PARTIAL · 0 FAIL.** No `✗`, so Workstream 1
is unblocked.

## Verdict table

| # | Item | Status | Evidence | Note |
|---|------|:------:|----------|------|
| 1 | Achievement strands expose a due date (optionality handled) | ⚠️ | `Strand.deadline: Date?` (`Strand.swift:98`), derived in `StrandTimelineBuilder.deadline(for:)` (`:193-195`), nil-guarded throughout | Date + optionality are correct (nil = true absence, no sentinel). ⚠️ only because the PRD's *countdown* and *Later band* don't exist in the data layer yet — those are Horizon-build tasks (P4/P5), not data gaps. |
| 2 | Maintenance event history → derive `typical_gap` (≥3 dated events) | ⚠️ | `StrandPresence` sorts past events (`:128-133`), computes inter-event gaps (`:203-213`), `median()` (`:236-244`). Sources: `WorkItem.createdAt/updatedAt` + `CompletionLog.timestamp` | Mechanically sufficient & already implemented. ⚠️: (a) only **recurring** items produce a multi-point dated series (non-recurring `.done` writes no `CompletionLog`, `WorkItemCompletion.swift:26-33`); (b) existing baseline is ≥2-events/median-of-all-gaps vs PRD §11's ≥3-events/median-of-last-5 → **T3 implements the spec-exact version** (P3). |
| 3 | Completion is a state, not a deletion | ✓ | `WorkItemCompletion.complete()` sets `status=.done` / logs `CompletionLog`, never deletes (`:26-51`); all 8 `modelContext.delete` sites are explicit user trash/reset | Past region reconstructable from surviving `createdAt`/`updatedAt`/`CompletionLog.timestamp`. Watch-items: hard-delete is user-reachable; non-recurring completions carry only mutable `updatedAt` (P6, deferrable). |
| 4 | Strand origin/created date exists and is trustworthy | ✓ | `WorkItem.createdAt: Date` non-optional (`:19`), default `.now` (`:51`), assigned once (`:69`); migrators never touch it; no `VersionedSchema` | Trustworthy origin, cleanly separated from mutable `updatedAt`. Already consumed as the `.created` origin event (`StrandTimelineBuilder.swift:149`). |
| 5 | Achievement/Maintenance classification readable from the model | ✓ | `enum StrandType {achievement, maintenance}` (`Strand.swift:11-14`); `computedType` + `userOverrideType` + `var effectiveType` (`:53-61`); UI reads `strand.effectiveType` | First-class enum, single read field. Computed (never persisted); default maintenance, achievement is the qualified exception. Override path is DEBUG-only. |

## Persistence & architecture context

- **Persistence is SwiftData.** Domain entities are `@Model final class` (`WorkItem`, `Project`, `CompletionLog`, `WorkSession`) in one `ModelContainer` (`MotiApp.swift:16-25`). `CompletionLog` is an append-only audit trail.
- **`Strand` is NOT persisted** — a pure render-only value type (`struct Strand`, `Strand.swift:42`) recomputed every render by `StrandTimelineBuilder.build()` from live model objects. **This is the biggest de-risker: any new field on `Strand` / a new `CountdownPayload` needs zero data migration.**
- **Timeline wiring:** root is `RootTabView` (`MotiApp.swift:74`); tab content is the `selectedContent` switch (`:305-328`). The `.timeline` case already branches on `@AppStorage("useTrajectoryTimeline")` (`:78`): ON → `TrajectoryTimelineView` (axis), OFF → legacy `TimelineView`. Both are self-contained `NavigationStack` roots. **T11+T14 swap is localized to this ~24-line function.**
- **PRD correction:** the "no red token exists" premise is **false**. `MotiTheme.today = systemRed` (`MotiDesignSystem.swift:13`) is used on the current timeline hero. T6 must consciously remap overdue → amber and avoid `MotiTheme.today`/`Color.motiAccent` on Horizon surfaces.

## Derived pre-work tasks

Ordered by dependency. **None block T1/T2/T3.**

- **P1 — `FeatureFlag` abstraction with a canonical `horizonTimeline` key.** *(gates T14)* No `FeatureFlag` type exists; the `"useTrajectoryTimeline"` string is hand-duplicated across 4 files. Add a `FeatureFlag` enum with an `@AppStorage`-backed accessor, default off, DEBUG-Settings toggle.
- **P2 — Reconcile tri-state Timeline root** `{legacy, axis-as-Map, Horizon}`. *(gates T11, depends P1)* Present the axis view as a Map (sheet/cover, not push — avoid nesting its `NavigationStack`).
- **P3 — Decide `typical_gap` definition.** *(gates T3 finalization)* Implement PRD §11-exact (≥3 events, median of last 5, else nil) as a pure helper; prefer `RecurrenceRule` declared cadence for recurring strands. **Resolved in this branch: T3 implements the spec-exact version.**
- **P4 — Per-Strand horizon banding** (Now/Next/Later) driven by `Strand.deadline`. *(Horizon-build)*
- **P5 — Countdown / time-remaining derived value** with nil-deadline suppression. *(Horizon-build; use `TrajectoryProjection.hasGoal` to distinguish achievement-with-deadline)*
- **P6 — (Non-blocking) Harden Past region** against edits-after-completion (mutable `updatedAt`) and hard-delete. Deferrable past Session 1.

## Phase 2 seam confirmations

- **`QuietnessProvider` (`isQuiet(Strand) -> Bool`) — clean.** Only the `Strand` value type crosses the boundary; no `TrajectoryProjection`/`TrajectoryOutcome` leaks — the `Bool` is all rows see. Phase-1 reads presence scalars + `deadline`; Phase-2 reuses `TrajectoryOutcome.needsAttention`. **Vocabulary hazard:** `PresenceState.quiet` / `TrajectoryOutcome.quiet` mean "weakening," the *opposite* polarity from the provider's "calm — not worth surfacing." Name it `isCalm` / `!needsSurfacing` or comment heavily.
- **`CountdownPayload.requiredDuration: TimeInterval?` — seam designable now, populated value Phase-2-blocked.** Correctly nil in Phase 1: the engine emits `paceRatio` (unitless) and `actualStartDate` (past date) but **no projected-landing / days-required-at-pace scalar**. Population needs an additive field on `TrajectoryProjection` (no migration, since never persisted).
- **Divergence stability gate has NO engine source.** `TrajectoryProjection` has no `confidence`/`variance` field. `solidFraction` is a *drawing extent* (clamped 0.12–0.55) — reusing it as a confidence proxy violates the PRD invariant. Phase 2 must add an explicit `variance`/`stability` field or gate on `StrandPresence.baselineSource`.

## Go / No-Go — Session 1 (T1 + T2 + T3)

**GO.** T1 (pure date math) needs nothing. T2 builds on `Strand.deadline` + `effectiveType` (present, trustworthy). T3 begins against the live model now; the only constraint is to implement the PRD §11-exact `typical_gap` rather than blindly reusing `baselineCadenceDays`. P1/P2 gate surface wiring (T11/T14), not the domain — sequenced for a later session. No data migration required anywhere in this branch.
