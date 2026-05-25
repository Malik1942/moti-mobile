#!/usr/bin/env bash
# Regenerate Moti's sound pack and install uncompressed CAF files into the app.
#
#   1. synthesize WAVs from generate_sounds.py (pure stdlib, original tones)
#   2. convert each to uncompressed 16-bit PCM CAF via afconvert (built into macOS)
#   3. copy the CAFs into Moti/Resources/Sounds/ (the app's bundled sound folder)
#
# CAF + LEI16 = uncompressed, low-latency playback — ideal for short UI cues.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAV_DIR="$HERE/wav"
DEST="$HERE/../../Moti/Resources/Sounds"

python3 "$HERE/generate_sounds.py"

for name in capture understood reorganized ambiguous completed error; do
  afconvert -f caff -d LEI16@44100 -c 1 "$WAV_DIR/$name.wav" "$DEST/$name.caf"
  echo "built $DEST/$name.caf"
done

echo "Done. CAF files installed in $DEST"
