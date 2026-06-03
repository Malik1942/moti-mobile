# PRD — Timeline Redesign

**Branch:** `timeline-redesign`
**Status:** Draft, ready to build
**Last updated:** 2026-06-02

---

## 1. Summary

Moti's Timeline is a **trajectory engine** — not a task list, a calendar, or a presence mirror. Each thing the user cares about is a *future* (internally a *strand*). The Timeline's one job is to answer, at a glance: **based on how you're actually behaving, where is each of your futures heading — and will it get there?**

This is the real differentiator:

- A calendar shows what is *scheduled* — and assumes you'll do it.
- A task list shows what *remains* — and assumes you'll get to it.
- A habit tracker shows past *compliance*.
- Moti **projects the outcome from your actual behavioral trajectory.** It assumes nothing; it extrapolates what you are really doing.

**Future is primary; the past is bounded feedback.** The layout reflects this. `Now` sits near the top with a small, bounded zone of recent past above it (quick feedback — "how have I been doing"). The future expands *downward* through scroll (relatively unbounded — plan and projection as far out as you like). Near-term future is concrete and **solid**; far-term future is drawn as **dashed, fading trajectory hints** — the further out, the more it is a projection, not a promise.

Presence and drift are still computed, but they are the **input** that shapes each trajectory — they are not the organizing principle. Drift is a signal that feeds the forecast; it is not the product.

This redesign is a visual-grammar change plus a compute change, not a feature add. No new task model. No prescriptions.

---

## 2. Problem

People live across several futures at once — some with deadlines (Move, Job Search, a launch), most without (Health, Parents, Friends, a relationship). These futures compete, overlap, reinforce, and conflict, and the brain cannot hold that structure over time.

Existing tools fail in two ways: they over-structure (nag, demand upkeep) or they forget (completion = deletion). They are also built almost entirely for deadline-bearing tasks, which makes them blind to the most common real failure: a *maintenance* future sliding silently because nothing ever reminds you about it until it's a crisis ("I haven't worked out in three weeks," "I haven't called home in a month").

The current Timeline reads like a task list or a calendar. It is mediocre, it shows neither drift nor where the current pace is heading, and a normal person cannot tell from it what Moti is for.

---

## 3. Goals and non-goals

**Goals**

- Show each future's **trajectory** at a glance — on-time, slipping, fading, or sustained — with no learning curve.
- Make silent neglect of maintenance futures visible without shaming the user.
- Surface contention (two futures crowding the same window) when it exists.
- Mirror the user's own behavior back to them; never decide for them.
- Stay calm by default — a future that is on-track and sustained should look quiet; only the one slipping or fading raises its voice.

**Non-goals**

- Becoming a calendar (do not out-calendar the calendar; no hour-by-hour scheduling).
- Becoming a worklist (no task lists on the main axis).
- Prescribing what to do next, or predicting *life consequences* ("this will hurt your career"). Projecting the *behavioral* trajectory ("at this pace, Launch slips ~2 weeks") is the core feature; interpreting what that means for the user's life is not.
- Requiring maintenance, journaling, or manual status updates.

---

## 4. Core concept and product architecture

- The unit is the **future** (internally a *strand*), not the task and not the date.
- Time runs **vertically**: `Now` near the top, a bounded slice of recent past above it, the future expanding **downward** as you scroll.
- The primary read is each future's **trajectory** — where its current pace lands it relative to where it is meant to go.
- **Certain vs. projected:** recent actual behavior and committed near-term plans are drawn solid; the far-future projection is dashed and fades — certainty decreases with distance.
- The past is **bounded** (recent feedback only, not an infinite archive). Detailed tasks never appear on the main axis as a worklist; they are previewed on tap and owned by **Projects**.

### 4.1 Three surfaces (clarity from separation, not aggregation)

Moti is three distinct surfaces answering three distinct questions. They must not collapse into one dashboard.

| Surface | Question | Role |
|---|---|---|
| **Timeline** | Where is each future heading? | Trajectory + orientation. Primary surface and Moti's unique value. |
| **Peek** | Why? | Context overlay on a single future (§6.2). Understanding, not task management. |
| **Plan** | When / what next? | Execution: tasks, scheduling, calendar, time-specific commitments. |

Design inversion — most tools run **Execution → Awareness**; Moti runs **Awareness → Execution.** Users first see what matters, then decide what to do. *Separate the surfaces, not the flow:* from a drifted line, one tap should drop the user into Plan already focused on that future. Clarity comes from separation; the journey must still be seamless.

### 4.2 Plan is the sensor (the capture loop)

Trajectory is **computed from behavioral events** (complete / defer / touch) — the projection is only as good as the record of what you actually did — and those events are generated in the **execution** layer. The dependency is therefore a loop, not one-directional:

> Plan captures behavior → Timeline projects the trajectory → Timeline points attention back → Plan.

Implication: **the forecast is only as good as captured behavior.** If Plan / capture is under-built, users execute in other apps, the event stream dries up, and the trajectory goes blind — Moti would be reduced to guessing from scheduled-but-maybe-not-done tasks, which is exactly the calendar assumption it must not make. Plan is "a tool" in emphasis but load-bearing in architecture. Corollary to the product test ("if we kept one surface, keep Timeline"): true as *positioning* — the unique value is the trajectory read — but false as *architecture*. The Timeline is not a standalone system; **unique ≠ sufficient.**

### 4.3 Input philosophy

Input stays user-driven and unchanged from today: the user decides what to track, plan, and care about; onboarding may *suggest* but never imposes; the focus is long-term, long-arc futures. The system tracks progress at **25 / 50 / 75 / 100%** checkpoints — a discrete, low-load cadence to keep. How that signal gets *richer without adding load* is covered in §6.2 and §8.

---

## 5. Visual grammar (simplified — the key change)

The main view has **one primary signal and one identity channel.** Nothing here requires the user to be taught.

| Channel | Encodes | Rule |
|---|---|---|
| **Vertical position (primary)** | Time / trajectory | `Now` near the top; bounded past above, future expanding downward (scroll = forward). Each future's projected path runs down; where it lands relative to its goal is the read. |
| **Solid vs. dashed** | Certain vs. projected | Recent actual behavior + committed near-term plans = solid. Far-future projection = dashed, fading with distance — certainty decreases the further out you look. |
| **Color (identity)** | Which future this is | Same future, same color, across time and screens. Color is **identity, never status** — not a red/amber/green risk scale. |

**Dropped on purpose** (too much learning curve, too easy to misread, too decorative): thickness-as-importance, height/vertical-lift-as-momentum, and the "Converted" soft-bridge auto-link.

### 5.1 Present-moment states (read at the Now band)

| State | Recent activity near Now | Read |
|---|---|---|
| **Active** | dense, solid marks right up to Now | being fed, fresh |
| **Quiet** | sparse, fading marks approaching Now | present but slowing |
| **Drifted** | a visible empty gap just above Now before the last mark | silently falling out of the present |
| **Paused** | dashed + explicit `Paused` label | intentionally set down (not neglect) |

The distinction between **Drifted** and **Paused** is load-bearing: drift is silent neglect; paused is a deliberate choice (dashed + label). The user must always be able to tell "did I ignore this, or did I put it down on purpose?"

### 5.2 Trajectory outcomes (the forward read — the hero)

Read from the dashed projection below Now, against each future's goal/deadline marker:

| Outcome | How it's drawn | Read |
|---|---|---|
| **On-time** | projection reaches completion at or before the deadline marker | will make it |
| **Behind** | projection reaches completion past the deadline; the gap = slippage | will be late |
| **Fading** | projection thins and fades to nothing | at this pace, this disappears |
| **Sustained** | projection continues at a steady rhythm | stays alive |

In v1 these are **directional** (on-time / behind / fading / sustained), not precise day-counts — precise slippage ("~2 weeks late") needs effort estimates and is gated to v2 (§9).

---

## 6. Screens

Two screens define the redesign. If both hold, the direction holds.

### 6.1 Main Timeline (default view)

- **Vertical time, future-primary.** `Now` sits near the top. Above it: a small bounded zone of recent past (~2 weeks) — solid marks, actual behavior, the quick feedback. Below it: the future, expanding downward through scroll.
- **No worklist on the axis** — but each future's committed near-term plan appears as solid forward nodes, and beyond them a **dashed, fading trajectory projection**.
- **Top:** one synthesized, forward-looking sentence (computed, phrased by the model), e.g. "On current pace: Launch slips ~2 weeks, Fitness fades by July."
- **Body:** each future is a column. Solid = certain (recent actual + committed plans); dashed/fading = projection. The four trajectory outcomes (§5.2) are readable from the projected path alone.
- **Calm by default.** A future that is on-track and sustained should look quiet; the eye is drawn to the one slipping or fading.

**Acceptance criteria**

1. Each future's trajectory outcome (on-time / behind / fading / sustained) is legible at a glance, without reading text.
2. Solid (certain) vs. dashed (projected) is immediately distinguishable.
3. The bounded-past / expansive-future asymmetry reads correctly — scroll goes *forward*.
4. It does not look like a dashboard, a Gantt, or a calendar.

### 6.2 Peek sheet (on tapping a line)

- The sheet **overlays the timeline** — other lines stay faintly visible behind it. It is not a page navigation. This preserves cross-future context.
- Content is **type-dependent** — achievement and maintenance futures are not the same kind of thing and must not share one generic checklist.

**Achievement future** (has a deadline; e.g. Move, Job Search, Portfolio)

- Current state, in behavioral terms ("Moving toward deadline · 4 actions done, 2 deferred").
- **Milestone health** (the evolution of today's good/normal/bad). Progress is checked at the 25 / 50 / 75 / 100% checkpoints. The richer signal lives **here, in the Peek — never on the main axis**, and only for achievement futures (maintenance has no 100%). It is rendered as a *continuous felt texture* on the forward path (whether the line is tracking its expected pace) plus at most **one natural-language line** ("a bit behind the pace you set, but the deadline's still reachable") — more informative than a label, still one glance. See §8 for the model-detail-vs-display-load rule.
- **Forward nodes**: the upcoming steps drawn as points the line passes through on its way to the deadline marker — *not* a checklist (e.g. `Book movers → Pack kitchen → Change address → move day`).
- One action: `Protect next step` / `Open in Projects` / `Mark as paused`.

**Maintenance future** (no tasks; e.g. Fitness, Parents, Friends)

- **Rhythm**: "Usually weekly · quiet for 18 days."
- **Last traces** (dated history, not checkboxes): `May 3 Evening walk / May 7 Gym / May 12 Skipped / Since: Quiet`.
- **Why it went quiet, if computable** — stated as **co-occurrence, never causation**: "It faded as Work and Move rose during the same weeks." Do **not** write "crowded out."
- **Gentle re-entry**: `Make space this week` / `Not this week` / `Lower priority`. Never `Add task`. Never an empty `No tasks` state.

**Acceptance criteria (maintenance peek)**

1. No checklist appears.
2. It shows rhythm and the **shape of absence**, so it never looks like an unconfigured habit app.
3. Re-entry is lightweight and optional.
4. It does not shame the user; `Not this week` is a first-class, peaceful option.

Full task management lives in **Projects**, reached via a link from the achievement peek. The Timeline previews the path; Projects is where execution happens.

---

## 7. Interaction and flow

1. **Glance & close** — the 90% case. Open it, the top line + the calm shape reassures, close it. The reassurance is the product.
2. **Notice** — the eye lands on the one line raising its voice (drifted, or crowded).
3. **Tap → peek** — the sheet opens over the timeline (context preserved).
4. **Optional one-tap action** — `Make space` / `Not this week` / `Mark paused` / dismiss. All reversible. These **execute the user's choice**; they never make the choice.
5. **Past recedes** — quiet and completed history fades upstream; no overdue wall.

Capture does not happen on the Timeline. The Timeline reflects the shape; it is not an input surface.

**Re-entry (the north star):** after weeks away, the top line becomes a generated recap ("While you were away: Work kept moving, Fitness went quiet, Move is closing in"), then the same calm view. No triage demanded.

---

## 8. Compute model (what is true vs. how it's said)

Principle: **structure is computed (deterministic, trustworthy); the model only narrates, compresses, and fills priors; the visuals are the inspection layer.** The algorithm decides what is true; the model decides how to phrase it. It is never an oracle.

| Signal | Source | Estimate needed? |
|---|---|---|
| Reach-to-Now / drift | Last-activity recency vs. the strand's **own** baseline cadence; pure counting of behavioral events (created / completed / deferred / touched) | No — zero-estimate, pure event counting |
| Active vs. Quiet | Recent activity density vs. that strand's baseline | No |
| Contention (Crowded) | **Temporal overlap** of demands landing in the same window (calendar math) | No for "same window"; intensity tiers need estimates → deferred |
| Achievement forward nodes | The project's existing steps / deadline, pulled from Projects | No |
| "Why it went quiet" | Co-occurrence detection — which strands rose while this one fell. Stated as co-occurrence. Deeper causal / "conversion" links are **model-proposed, user-confirmed**, never auto-asserted. | No |
| Milestone health (achievement) | Progress vs. the 25/50/75/100% checkpoints and the deadline: pace, consistency, trajectory | Pace/consistency: no. Trajectory-to-deadline: light, improves with history. |
| **Trajectory projection (the hero)** | Extrapolate the dashed forward path from actual pace. Achievement: progress-so-far vs. time-remaining → on-time / behind. Maintenance: current feeding rate → sustained / fading. | **Directional** version (on-time / behind / fading / sustained): no — pure event-rate + calendar. **Precise** day-counts ("~2 weeks late"): yes → gated to v2. |

The projection extrapolates *actual behavior*, never assumes scheduled work will happen — that assumption is the calendar's, and the thing Moti exists to avoid (§14).

**Model detail vs. display load.** "More detailed" must never mean "more for the user to read or maintain." Detail is allowed to grow only in three places: (a) the **computation** (track a continuous, multi-factor health internally instead of three buckets), (b) **form** (render it as a felt texture, which is *lower* load than a label — pre-attentive, no reading), and (c) the **on-demand Peek** (the decomposition appears only when the user taps in). Counterintuitive but central: replacing the `good / normal / bad` label with a continuous texture *raises* detail and *lowers* ambient load. The main view's load must stay at or below its current level; if a detail can't be felt or deferred to Peek, it does not ship (see §14).

**Where events come from.** Every signal above is computed from behavioral events, which are produced in the execution layer (Plan / capture / completions). The trajectory projection is therefore only as good as event capture (§4.2). The hardest open dependency is feeding the signal for *maintenance* futures, which have no tasks (§13).

**Drift baseline:** derived from the strand's own historical cadence (a weekly-touched strand flags after roughly its own interval). If there is no history, degrade to deferral-count or a single one-time cadence question. Never invent urgency.

The drift signal is a **mirror**: it relies only on Moti's record of the user's own past behavior — the one kind of context Moti has more of than the user's own memory. It does not need any context about the outside world.

---

## 9. Phasing and development strategy

The phases below are a **gated sequence, not a calendar.** Each later phase is unlocked by a *measured signal* from the one before it — and the ideal outcome for several of them is that they never need to be built. Build by **data-trustworthiness**, not by which feature is most attractive.

**Governing rule:** ship what you can compute now; defer anything that depends on a guess until the loop that makes the guess trustworthy exists.

### 9.1 Tracks (by what data they need)

| Track | Needs | When it works |
|---|---|---|
| Zero-estimate | Event counting + calendar | Day one, for any user |
| History-improving | Accumulated per-strand history | Improves automatically as data accrues — no new build, just better priors |
| Estimate-dependent | Trustworthy effort estimates | Only after the estimate-correction loop exists |

### 9.2 v1 — zero-estimate core (this branch)

Vertical future-primary layout (bounded past above `Now`, future scrolling down) + present-moment states (Active / Quiet / Drifted / Paused) + **directional trajectory projection** (on-time / behind / fading / sustained, from event-rate + calendar — no precise day-counts yet) + the behavioral mirror as the projection's input + `What matters now` (forward-looking) + both peek sheets. Type inference is override-ready but has no user-facing flow (see §9.5). **Also in v1, cheaply: instrument the gates (§9.4)** — without this, every later phase is decided by gut.

### 9.3 v1.5 — gated additions (build only if v1 telemetry shows they're needed)

- **Temporal-overlap contention** — a single `Crowded` form (shared pressure node where two strands land in the same window; one form, no severity tiers). *Gate: first confirm the drift mirror itself delivers value and that users actually notice/care about contention. Contention is the least-proven piece of the grammar — treat it as a bet to test, not a given. Do not speculatively build a full contention visual language.*
- **"Looks wrong?" type correction** in the peek sheet — stored as a **local preference only**, no learning. *Gate: only if mis-typing actually bites (measured via dev-override usage / "wrong sheet opened"). If inference is right ~95% of the time, this may never be built.*

### 9.4 Instrumentation (required in v1 — it decides everything after)

Log the signals that gate later phases: type mis-type rate, drift-flag dismissal rate ("no, that's fine"), contention false-positive rate, glance-and-close rate, and re-engage / park / ignore outcomes on surfaced strands. Cheap to add, and the only honest basis for deciding v1.5 and v2.

### 9.5 Type and override — an escalating ladder

- **v1:** strand-level `computedType` / optional `userOverrideType` / `effectiveType = userOverrideType ?? computedType`. Default to **Maintenance**; Achievement is the qualified exception (single terminal deadline AND no recurring activity). Developer-only override map keyed by strand id, for testing both peek sheets — no user entry point. Shape the type so v2 can add `computedTypeAtOverride` **without a migration**. Do not add that field, a user flow, or learning yet. Accept that dual/ambiguous strands (Job Search, a half-marathon block of Health) get mis-typed in v1 — that is acceptable because override is not user-facing, and the dev map covers testing. Do **not** "fix" it by adding inference intelligence; the simple rule is a placeholder, not a bug.
- **v1.5:** the local-only "Looks wrong? — Ongoing care / Goal with an end" correction. User-facing words are the plain-language pair; the internal enum stays achievement/maintenance.
- **v2:** persisted override + `computedTypeAtOverride` (divergence detection and rollback — e.g. a half-marathon block ends and Moti can ask "back to ongoing care?") + **rule-based** learning built from *observed* correction patterns, never speculative and never LLM-learned. E.g. a class of strands corrected the same way becomes a default; a single deadline-bearing strand corrected to Maintenance is remembered per-strand only.

### 9.6 Estimate-dependent track (v2) — gated on a loop first

Runway, deadline-pressure visuals, **precise trajectory day-counts ("~2 weeks late")**, and contention **intensity** tiers all consume effort estimates, which are unreliable until corrected. So the **first** thing built in this track is the cheap one-tap estimate-correction loop ("way more / way less than that"); let it accumulate, and only then turn on the features that read estimates. Building precise projections before the correction loop is building on sand — v1 stays directional (on-time / behind / fading / sustained). User-confirmed conversion bridges also live here.

### 9.7 Defer the Future model

Type is ultimately temporal/episodic — a maintenance strand can host an achievement episode (the half-marathon). Do **not** pre-build a richer Future model. Keep the strand model minimal and override-ready; let any migration be a later phase driven by real friction, not anticipated elegance.

### 9.8 Keep the three layers swappable

Compute (pure functions over events, UI-free, unit-tested) · Phrasing (model: computed structure → sentence; swappable and A/B-able) · Visual (Lifeline component + states; redesignable). Never entangle them — the model must not decide state, the visual must not read raw events. This separation is what keeps every later change local and cheap.

---

## 10. Edge cases and empty states

- **New user / few strands:** calm, no nagging.
- **Maintenance line with no tasks:** never `No tasks`; show rhythm + last traces + the shape of absence.
- **A fully calm week:** serene; `What matters now` may simply say "Everything's still in reach."
- **No history for a drift baseline:** fall back to deferral counts or a one-time cadence ask; do not fabricate urgency.
- **Many strands:** the calm-by-default rule must still hold — quiet strands recede so the one exception stands out; if the screen reads as "many pretty lines," the design has failed.

---

## 11. Accessibility

- Do not rely on color alone. Color carries identity; **state is carried by position (reach-to-Now) and labels**, so the view remains readable in grayscale (the gap does the work).
- Minimum font size 11px.
- Honor reduced-motion: lines render statically, no decorative animation.

---

## 12. Validation and success

**Qualitative gates**

- **Tuesday test:** on an ordinary, calm day the surface earns its place — glance and close reassures.
- **Conflict test:** a real collision is *felt*, not painted as quiet as everything else.
- **Two-screen acceptance:** the criteria in §6.1 and §6.2.

**Candidate metrics**

- High glance-and-close rate on calm days (a feature, not a drop-off).
- Share of surfaced drifted strands that are either re-engaged or consciously parked (vs. ignored).
- No increase in strand/project deletion or app abandonment after launch.

---

## 13. Open questions

- **How does the signal get fed — especially for maintenance futures?** This is the most load-bearing open problem (bigger than contention). Achievement futures generate events through task execution; maintenance futures have no tasks, so a "touch" must come from somewhere — integration (Apple Health, Calendar, location), inference, or a single near-zero-friction "did this." If it requires manual logging, the maintenance trajectory is fake and Moti degrades into a habit tracker. Must be near-zero friction.
- **Is contention worth building at all?** It is the least-proven part of the grammar. Validate that the drift mirror delivers value and that users notice/care about crowding *before* investing in contention's visual language (beyond the single `Crowded` node). Treat it as a bet, gated per §9.3.
- **Strand definition:** auto-proposed-from-behavior with one-tap user confirm, vs. user-created. Avoid reintroducing a setup/maintenance tax.
- **Drift baseline without history:** the lightest possible signal that still feels accurate.

(The Achievement/Maintenance override path is no longer open — it is decided as the gated ladder in §9.5.)

---

## 14. Non-negotiables (hold the line)

- **Moti projects from actual behavior, never assumes the plan executes.** The calendar assumes you'll do what's scheduled; Moti extrapolates what you're actually doing. Drift/presence is an *input* to the trajectory, not the organizing principle. The day this inverts back into a presence mirror or a compliance tracker, the product has lost its point.
- **Future is primary; the past is bounded.** `Now` near the top, limited recent past above (feedback only), the future expanding downward. Never an infinite archive; never let the past become the main view.
- The main axis shows **trajectory + present state**, not a worklist. Detail is on tap. Execution is in Projects.
- Lines must not become decoration: every visual property maps to a computed quantity.
- The peek sheet must not become a checklist.
- Moti directs **attention**, never **choice**.
- **Three surfaces stay separate.** Clarity comes from separation, not aggregation; resist collapsing Timeline / Peek / Plan into one dashboard.
- **The anti-bulk test.** Any new detail may live only in computation, form, or the on-demand Peek. If it must be *constantly read* or *manually maintained* to be useful, it is burden — it does not ship. Stay a utility app; do not overreach.
- **Describe, never interpret.** The Timeline reflects where attention actually went and where the current pace lands. It never tells the user what their life means, what they are becoming, or what to change — and never cultivates dependence.
