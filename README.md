# Moti

Moti is an AI-assisted planning app designed to help people turn rough task captures into structured, realistic, and adaptive plans.

It is built for students, designers, makers, and project-based workers who often manage multiple deadlines, shifting priorities, and messy personal workflows.

## What Moti is designed for

Most task apps assume users already know how to break work down clearly.

Moti is designed for the moment before that: when a task is still vague, scattered, or emotionally hard to start.

It helps users capture what they need to do, understand the context behind it, and generate a plan that can evolve as the situation changes.

## Target Users

Moti is designed for people who:

- Work across multiple projects and deadlines
- Capture tasks in messy, natural language
- Need help breaking large tasks into smaller steps
- Want lightweight planning without over-managing every detail
- Benefit from adaptive reminders and progress check-ins
- Prefer a calm planning companion over a rigid productivity system

## What Moti Can Do

Moti supports:

- Quick task capture
- Project-based organization
- AI-assisted task understanding
- Deadline-aware planning
- Timeline-based progress checkpoints
- Lightweight status check-ins: Good, Normal, or Bad
- Project pulse widgets
- Plan refinement when the generated plan needs improvement

## Intelligence Modes

Moti uses different intelligence approaches depending on the situation.

### Rule-Based Mode

Rule-based logic is used for fast, predictable, low-cost task parsing.

It works best when the input is simple, such as:

- Clear due dates
- Basic task titles
- Simple reminders
- Lightweight capture without deep reasoning

This mode is reliable, local-friendly, and easy to debug.

### SLM Mode

The Small Language Model mode is designed for more flexible task understanding while staying lightweight.

It is useful when the user input is slightly messy but does not require deep project reasoning.

SLM mode can help with:

- Interpreting natural language task captures
- Extracting intent
- Identifying rough time information
- Structuring simple task details

This mode balances flexibility, speed, and efficiency.

### LLM Mode

The Large Language Model mode is used when deeper reasoning is needed.

It is designed for complex planning situations, such as:

- Multiple deadlines
- Project context
- Ambiguous task scope
- Breaking down large work into smaller steps
- Creating realistic schedules
- Refining a plan based on user feedback

In LLM mode, Moti can use current date, task context, project information, and user refinement input to generate a more adaptive plan.

Smart Capture is only activated in LLM mode, so advanced AI behavior is used intentionally when the task requires deeper reasoning.

## Current Status

Moti is currently in active development.

The current version explores how rule-based systems, SLMs, and LLMs can work together inside a personal planning app, each used where it fits best.

## Tech Stack

- Swift
- SwiftUI
- SwiftData
- WidgetKit
- App Groups
- Gemini API
- Xcode

## Author

Built by Malik Zhang.
