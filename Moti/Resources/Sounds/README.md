# Moti sound assets

Drop the audio files for Moti's quiet cognitive-feedback layer here, then add
them to the **Moti** target (or add this `Sounds` folder to the project as a
*folder reference* so new files are bundled automatically).

`SoundManager` (`Moti/Services/SoundManager.swift`) looks each file up in the
app bundle by name, trying these extensions in order: `.caf`, `.wav`, `.m4a`,
`.aiff`, `.mp3`. If a file is missing, that event is a silent no-op — the app
never crashes, so it's safe to ship before every sound exists.

## Expected files (name = event)

| File              | Event         | Sonic direction                         |
|-------------------|---------------|-----------------------------------------|
| `capture.*`       | `.capture`    | soft tactile tap, grounded              |
| `understood.*`    | `.understood` | subtle shimmer / airy pulse             |
| `reorganized.*`   | `.reorganized`| magnetic settle / soft glide            |
| `ambiguous.*`     | `.ambiguous`  | gentle suspended tone                   |
| `completed.*`     | `.completed`  | light release                           |
| `error.*`         | `.error`      | soft low cue, not alarming              |

## Guidelines
- Keep them short (< ~1 second) and soft. These play *under* the UI.
- Prefer `.caf` or `.wav` (uncompressed, low latency) for crisp, instant playback.
- Normalize levels so no single sound jumps out; per-event balance is also
  tunable via `Event.volumeScale` in `SoundManager.swift`.
- Default base volume is intentionally low (`SoundManager.baseVolume = 0.35`).

## How playback behaves
- Category `.ambient` + `.mixWithOthers`: mixes under music, never grabs the
  mic, and respects the hardware silent switch.
- A short cooldown prevents rapid-fire overlap.
- Honors the Settings → **Sound effects** toggle (`soundEffectsEnabled`).
