# Moti sound assets

This folder holds the audio for Moti's quiet cognitive-feedback layer. The six
shipped files below are **bundled in the Moti target** (Copy Bundle Resources).

`SoundManager` (`Moti/Services/SoundManager.swift`) looks each file up in the
app bundle by name, trying these extensions in order: `.caf`, `.wav`, `.m4a`,
`.aiff`, `.mp3`. If a file is missing, that event is a silent no-op — the app
never crashes, so it's safe to ship before every sound exists.

## Shipped files (name = event)

All are original, synthesized tones — **mono, 16-bit PCM, 44.1 kHz, CAF**
(uncompressed, low-latency). No sampled, Apple-system, or third-party audio.

| File              | Event         | Length | Sonic direction                                   |
|-------------------|---------------|--------|---------------------------------------------------|
| `capture.caf`     | `.capture`    | 0.16 s | soft landing/tap — short pitch-drop "thock"       |
| `understood.caf`  | `.understood` | 0.42 s | gentle confirmation/bloom — rising major third    |
| `reorganized.caf` | `.reorganized`| 0.34 s | subtle settle — eased downward glide              |
| `ambiguous.caf`   | `.ambiguous`  | 0.46 s | gentle uncertainty — unresolved major 2nd + wobble|
| `completed.caf`   | `.completed`  | 0.60 s | calm closure — warm descending fifth to the tonic |
| `error.caf`       | `.error`      | 0.40 s | soft warning — low two-note descent, never an alarm|

## How they were made

Fully reproducible, dependency-free synthesis lives in `tools/sounds/`:

```sh
bash tools/sounds/build.sh
```

This runs `generate_sounds.py` (pure Python stdlib — additive sine partials with
smooth attack/decay envelopes, no numpy) to render WAVs, then converts each to
uncompressed CAF with macOS's built-in `afconvert` and installs them here. After
adding/changing files, run `xcodegen generate` so the new resources are wired
into the project's Copy Bundle Resources phase.

## Guidelines (for future edits)
- Keep them short (< ~1 second) and soft. These play *under* the UI.
- Prefer `.caf` or `.wav` (uncompressed, low latency) for crisp, instant playback.
- Normalize levels so no single sound jumps out; per-event balance is also
  tunable via `Event.volumeScale` in `SoundManager.swift`.
- Default base volume is intentionally low (`SoundManager.baseVolume = 0.35`).

## How playback behaves
- Category `.ambient` + `.mixWithOthers`: mixes under music, never grabs the
  mic (so it can't fight voice capture), and respects the hardware silent switch.
- A short cooldown prevents rapid-fire overlap.
- Honors the Settings → **Sound effects** toggle (`soundEffectsEnabled`).
