#!/usr/bin/env python3
"""Generate Moti's quiet cognitive-feedback sound pack.

Pure-stdlib additive synthesis (no numpy / no third-party deps). Writes mono
16-bit 44.1 kHz WAV files, one per SoundManager.Event. The accompanying
`build.sh` converts these to uncompressed CAF for the app bundle.

These tones are 100% original, generated from sine partials and smooth
envelopes — no sampled or copyrighted material. Re-run to tweak the palette.

Design brief (kept soft, short, low-distraction — they play *under* the UI):
    capture     soft landing / grounded tap
    understood  gentle confirmation / bloom
    reorganized subtle settle / downward glide
    ambiguous   gentle suspended uncertainty (not harsh)
    completed   calm closure (not gamified)
    error       soft low warning (not alarming)
"""

import math
import os
import struct
import wave

SR = 44100  # sample rate


# --- envelope & partial helpers -------------------------------------------

def _attack_release(n, i, attack_s, release_s):
    """Raised-cosine attack and release; flat in the middle. Range 0..1."""
    a = max(1, int(attack_s * SR))
    r = max(1, int(release_s * SR))
    if i < a:
        return 0.5 - 0.5 * math.cos(math.pi * i / a)
    if i > n - r:
        j = i - (n - r)
        return 0.5 + 0.5 * math.cos(math.pi * j / r)
    return 1.0


def _exp_decay(i, tau_s):
    return math.exp(-(i / SR) / tau_s)


def _glide(i, n, f0, f1, curve=1.0):
    """Frequency that moves f0 -> f1 across the buffer (curve>1 = ease-out)."""
    x = (i / max(1, n - 1)) ** curve
    return f0 + (f1 - f0) * x


def _render(duration_s, fn):
    """fn(i, n) -> float sample in roughly -1..1."""
    n = int(duration_s * SR)
    return [fn(i, n) for i in range(n)]


# --- individual voices -----------------------------------------------------

def capture():
    """Grounded tap with a tiny pitch drop — a thought lands and settles."""
    dur = 0.16
    def fn(i, n):
        f = _glide(i, n, 232.0, 208.0, curve=0.6)        # soft downward settle
        body = math.sin(2 * math.pi * f * i / SR)
        # very short higher partial gives a soft tactile "tip" without a click
        tip = 0.25 * math.sin(2 * math.pi * f * 3 * i / SR) * _exp_decay(i, 0.012)
        env = _exp_decay(i, 0.05) * _attack_release(n, i, 0.004, 0.03)
        return 0.5 * (body + tip) * env
    return _render(dur, fn)


def understood():
    """Rising third that blooms — intent recognized."""
    dur = 0.42
    f_lo, f_hi = 523.25, 659.25                          # C5 -> E5 (major third)
    def fn(i, n):
        t = i / SR
        # second tone enters slightly later for a soft bloom
        a = math.sin(2 * math.pi * f_lo * t) + 0.4 * math.sin(2 * math.pi * f_lo * 2 * t)
        delay = int(0.06 * SR)
        b = 0.0
        if i > delay:
            b = math.sin(2 * math.pi * f_hi * (i - delay) / SR)
        swell = 0.6 + 0.4 * min(1.0, t / 0.12)           # gentle amplitude bloom
        env = swell * _exp_decay(i, 0.22) * _attack_release(n, i, 0.025, 0.10)
        return 0.34 * (a + b) * env
    return _render(dur, fn)


def reorganized():
    """Downward glide that settles — the plan resettles into place."""
    dur = 0.34
    def fn(i, n):
        f = _glide(i, n, 494.0, 330.0, curve=1.8)        # B4 -> E4, ease-out settle
        tone = math.sin(2 * math.pi * f * i / SR) + 0.3 * math.sin(2 * math.pi * f * 2 * i / SR)
        env = _exp_decay(i, 0.16) * _attack_release(n, i, 0.012, 0.07)
        return 0.42 * tone * env
    return _render(dur, fn)


def ambiguous():
    """Suspended major second with slow vibrato — unresolved, but gentle."""
    dur = 0.46
    f1, f2 = 587.33, 659.25                              # D5 + E5 (mild, unresolved)
    def fn(i, n):
        t = i / SR
        vib = 1.0 + 0.004 * math.sin(2 * math.pi * 5.0 * t)   # subtle wobble = uncertainty
        a = math.sin(2 * math.pi * f1 * vib * t)
        b = math.sin(2 * math.pi * f2 * vib * t)
        env = _exp_decay(i, 0.30) * _attack_release(n, i, 0.04, 0.16)
        return 0.30 * (a + b) * env
    return _render(dur, fn)


def completed():
    """Warm descending fifth to the tonic — calm closure, not a fanfare."""
    dur = 0.60
    f_hi, f_lo = 392.00, 261.63                          # G4 -> C4 (resolves down)
    def fn(i, n):
        t = i / SR
        a = math.sin(2 * math.pi * f_hi * t)
        delay = int(0.10 * SR)
        b = 0.0
        if i > delay:
            tb = (i - delay) / SR
            b = math.sin(2 * math.pi * f_lo * tb) + 0.35 * math.sin(2 * math.pi * f_lo * 0.5 * tb)
        env = _exp_decay(i, 0.32) * _attack_release(n, i, 0.02, 0.18)
        return 0.32 * (a + b) * env
    return _render(dur, fn)


def error():
    """Low, soft two-note descent — a gentle "hm", never an alarm."""
    dur = 0.40
    f_hi, f_lo = 196.00, 155.56                          # G3 -> Eb3 (low, muted)
    def fn(i, n):
        t = i / SR
        a = math.sin(2 * math.pi * f_hi * t)
        delay = int(0.13 * SR)
        b = 0.0
        if i > delay:
            b = math.sin(2 * math.pi * f_lo * (i - delay) / SR)
        env = _exp_decay(i, 0.20) * _attack_release(n, i, 0.012, 0.12)
        return 0.40 * (a + b) * env
    return _render(dur, fn)


VOICES = {
    "capture": capture,
    "understood": understood,
    "reorganized": reorganized,
    "ambiguous": ambiguous,
    "completed": completed,
    "error": error,
}


def _normalize(samples, peak=0.7):
    hi = max(1e-9, max(abs(s) for s in samples))
    g = peak / hi
    return [s * g for s in samples]


def _write_wav(path, samples):
    samples = _normalize(samples)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wav")
    os.makedirs(out, exist_ok=True)
    for name, fn in VOICES.items():
        path = os.path.join(out, name + ".wav")
        _write_wav(path, fn())
        print("wrote", path)


if __name__ == "__main__":
    main()
