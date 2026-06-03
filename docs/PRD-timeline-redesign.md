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
