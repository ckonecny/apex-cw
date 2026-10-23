#!/usr/bin/env python3
"""Synthesises the confirmation tones "Marimba" and "Sanft" (Gentle).

The two sounds are the project's own work, made from plain sine waves by this
script (Python standard library only), and fall under the app's licence,
GPL-3.0-or-later. No recording, sample or third-party sound is used
(CLAUDE.md rule 11). The "Klassisch"/"Classic" tone is not a file: it is the
firmware's two-note sine signal, played by the sidetone engine
(CwTonePlugin.playConfirmTone).

    python3 tools/make_confirm_tones.py

writes four mono 16-bit 44.1 kHz WAV files to
android/android/app/src/main/res/raw/:

  confirm_marimba_ok / _err   two soft marimba notes up (E4 -> G#4) for right;
                              two soft flute-like notes down (E4 -> C4) for wrong
  confirm_sanft_ok / _err     ONE note with a gentle vibrato in a small room:
                              higher (G#4) for right, lower (C4) for wrong

Levels are baked in relative to the sidetone: the app plays the files at the
sidetone volume, so "Marimba" peaks 3.5 dB and "Sanft" 4.4 dB below the Morse
tone (a slightly quieter sound is easier to hear many times in a row).
"""
import math
import os
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                   'android', 'android', 'app', 'src', 'main', 'res', 'raw')

# Partial lists: (multiple of the fundamental, weight, decay factor).
M_SOFT = [(1, 1.0, 1.0), (2, 0.12, 0.5), (4, 0.03, 0.25)]
SOFT = [(1, 1.0, 1.0), (2, 0.18, 1.0)]


def silence(ms):
    return [0.0] * int(SR * ms / 1000)


def pluck(freq, ms, harm, decay_ms, attack_ms=8, tail_fade_ms=30):
    """Soft attack, then an exponential decay; the higher partials fade faster."""
    n = int(SR * ms / 1000)
    a = int(SR * attack_ms / 1000)
    f = int(SR * tail_fade_ms / 1000)
    out = []
    for i in range(n):
        t = i / SR
        env = 1.0
        if i < a:
            env = 0.5 - 0.5 * math.cos(math.pi * i / a)
        if i > n - f:
            env *= (n - i) / f
        v = 0.0
        for p, w, df in harm:
            v += w * math.exp(-t * 1000 / (decay_ms * df)) * math.sin(2 * math.pi * freq * p * t)
        out.append(env * v)
    return out


def vibrato_note(freq, ms, decay_ms, rate=5.5, cents=18, attack_ms=15, tail_fade_ms=30):
    """A note whose pitch wobbles by +-cents at rate Hz."""
    n = int(SR * ms / 1000)
    a = int(SR * attack_ms / 1000)
    f = int(SR * tail_fade_ms / 1000)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        fr = freq * (2 ** ((cents / 1200) * math.sin(2 * math.pi * rate * t)))
        ph += 2 * math.pi * fr / SR
        env = math.exp(-t * 1000 / decay_ms)
        if i < a:
            env *= 0.5 - 0.5 * math.cos(math.pi * i / a)
        if i > n - f:
            env *= (n - i) / f
        out.append(env * (math.sin(ph) + 0.12 * math.sin(2 * ph)))
    return out


def tremolo(s, rate=5.5, depth=0.2):
    return [x * (1 - depth * (0.5 - 0.5 * math.cos(2 * math.pi * rate * i / SR)))
            for i, x in enumerate(s)]


def reverb(s, rt60, wet, damp, tail_ms):
    """Small room: four damped comb filters and two all-passes (Schroeder)."""
    x = list(s) + [0.0] * int(SR * tail_ms / 1000)
    n = len(x)
    acc = [0.0] * n
    for dms in (29.7, 37.1, 41.1, 43.7):
        d = int(SR * dms / 1000)
        g = 10 ** (-3 * (dms / 1000) / rt60)
        buf = [0.0] * d
        idx = 0
        lp = 0.0
        for i in range(n):
            y = buf[idx]
            lp = y * (1 - damp) + lp * damp
            buf[idx] = x[i] + g * lp
            idx += 1
            if idx == d:
                idx = 0
            acc[i] += y
    out = [a / 4 for a in acc]
    for dms, g in ((5.0, 0.7), (1.7, 0.7)):
        d = int(SR * dms / 1000)
        buf = [0.0] * d
        idx = 0
        res = [0.0] * n
        for i in range(n):
            b = buf[idx]
            v = out[i] + g * b
            buf[idx] = v
            res[i] = b - g * v
            idx += 1
            if idx == d:
                idx = 0
        out = res
    return [x[i] + wet * out[i] * 4 for i in range(n)]


def normalise(s, peak):
    m = max(abs(v) for v in s) or 1.0
    return [v * peak / m for v in s]


def write_wav(name, s):
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767)) for v in s))
    print(os.path.normpath(path))


def marimba():
    ok = pluck(330.0, 110, M_SOFT, 100) + pluck(415.3, 260, M_SOFT, 130)
    err = (pluck(330.0, 120, SOFT, 600, attack_ms=22)
           + pluck(261.6, 300, SOFT, 260, attack_ms=22))
    return normalise(ok, 0.4 / 0.6), normalise(err, 0.4 / 0.6)


def sanft():
    def one(f, ms, dec):
        return reverb(tremolo(vibrato_note(f, ms, dec)), 0.12, 0.25, 0.35, 220)
    return (normalise(one(415.3, 380, 150), 0.36 / 0.6),
            normalise(one(261.6, 420, 170), 0.36 / 0.6))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, (ok, err) in (('marimba', marimba()), ('sanft', sanft())):
        write_wav(f'confirm_{name}_ok', ok)
        write_wav(f'confirm_{name}_err', err)
