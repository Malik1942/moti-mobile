# Trajectory Timeline Dogfood

Use this guide to evaluate the trajectory timeline on real local data before any v1.5 feature work.

## Flip the Flag

1. Open Settings.
2. Go to Timeline.
3. Turn on Use Trajectory Timeline.

The flag is off by default. DEBUG sample data is launch-argument only and should not appear unless the app is started with `-MotiSeedStrands YES`.

## What to Watch For

After about two weeks of normal use, review:

- The glance-and-close rate: how often the timeline can be opened, understood, and closed without action.
- Which trajectory outcomes appear in real use: on-time, behind, sustained, fading.

Keep the read focused on actual behavior. The timeline should keep future primary, past bounded, and trajectory plus present state on the axis. It is not a worklist.

## Coverage Meaning

Coverage answers whether strands have actual behavioral events feeding them.

- Total strands: all strands currently rendered.
- Achievement zero-event: achievement strands with no events over achievement strands total.
- Maintenance zero-event: maintenance strands with no events over maintenance strands total.

If the maintenance zero-event fraction is above about 50%, the maintenance-feeding problem from PRD §13 is urgent and must be solved before v1.5. If it is low, v1.5 gating can begin with real coverage data behind it.

## Share Metrics

In the DEBUG panel, tap Copy metrics to clipboard and paste the result into the build-review thread. The format is:

```text
total strands: N
achievement: N/M zero-event
maintenance: N/M zero-event
```

Add a short note naming which trajectory outcomes were visible and whether the bounded-past / future-scroll layout felt right on real content.
