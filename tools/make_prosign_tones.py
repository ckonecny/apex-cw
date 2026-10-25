#!/usr/bin/env python3
"""Synthesises the short tone that can introduce a prosign in the audio
trainer (instead of the spoken words "Pro sign").

Like the confirmation tones (make_confirm_tones.py) the sounds are the
project's own work, made from sine waves with the Python standard library
only: no recording or third-party sound (CLAUDE.md rule 11), GPL-3.0-or-later.

    python3 tools/make_prosign_tones.py [OUT_DIR]

writes prosign_tone_<name>.wav (mono 16-bit 44.1 kHz) to OUT_DIR (default:
android/android/app/src/main/res/raw/). Tones: bell, harp, gong (chosen by ear
from four candidates; the wooden "tock-tock" was dropped).
"""
import math
import os
import sys

import make_confirm_tones as T

SR = T.SR
BELL = [(1, 1.0, 1.0), (2.0, 0.35, 0.7), (2.76, 0.3, 0.5), (5.4, 0.1, 0.3)]


def mix(parts):
    """Overlay (offset_ms, samples) parts."""
    n = max(int(SR * o / 1000) + len(s) for o, s in parts)
    out = [0.0] * n
    for o, s in parts:
        i0 = int(SR * o / 1000)
        for i, v in enumerate(s):
            out[i0 + i] += v
    return out


def bell():
    return T.reverb(T.pluck(523.3, 600, BELL, 330, attack_ms=3), 0.12, 0.2, 0.35, 150)


def harp():
    return mix([(i * 85, T.pluck(f, 260, T.M_SOFT, 150, attack_ms=5))
                for i, f in enumerate((523.3, 659.3, 784.0))])


def gong():
    return T.reverb(T.tremolo(T.vibrato_note(220.0, 700, 300, rate=3.5, cents=6),
                              rate=3.5, depth=0.15), 0.15, 0.3, 0.4, 200)


TONES = {'bell': bell, 'harp': harp, 'gong': gong}

if __name__ == '__main__':
    if len(sys.argv) > 1:
        T.OUT = sys.argv[1]
    os.makedirs(T.OUT, exist_ok=True)
    for name, f in TONES.items():
        T.write_wav('prosign_tone_' + name, T.normalise(f(), 0.75))
