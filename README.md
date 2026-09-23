# Next CW Trainer

An Android app (Flutter UI + native Kotlin/C++ audio and keying) that brings
the core CW/Morse **training** modes of the [Morserino-32](https://github.com/oe1wkl/Morserino-32)
to a phone or tablet.

## Project intent

This is an independent, community side project with **no connection** to
Willi Kraml (OE1WKL) or the Morserino-32 team beyond reusing algorithms and
training logic read out of the original firmware source — it is not a
replacement for it, a fork of its source, or an official product of the
Morserino-32 team.

The complete idea behind the Morserino-32, its training curriculum (the Koch
method sequencing, the Echo Trainer flow, the QSO Bot concept, and everything
else), and years of careful refinement by Willi and his team are entirely
theirs. This app exists because that design is worth having in your pocket
too — it was built by reading the [original firmware source](https://github.com/oe1wkl/Morserino-32)
and reimplementing its training logic as faithfully as possible for Android,
from scratch, in Dart/Kotlin. It contains none of the original C++ firmware
code and is not affiliated with, endorsed by, or sponsored by Willi Kraml,
OE1WKL, or the Morserino-32 project. Aside from that shared lineage in the
training algorithms, this project and Willi Kraml/OE1WKL have no connection
to each other.

If you don't already own a Morserino-32: go build or buy one, it's a
wonderful piece of hardware — see the [main project](https://github.com/oe1wkl/Morserino-32)
for where to get one. This app is for practicing on the go with what's
already in your pocket, not a substitute for it.

This port was built against **firmware version 9.0.0** (`VERSION_MAJOR`/
`_MINOR`/`_PATCH` in `morsedefs.h` at the time this app was started) — later
firmware changes aren't automatically reflected here and would need their own
review against this app's behavior.

## What this app is — and isn't

This app focuses on the parts of the Morserino-32 that are genuinely useful
as **pure training software**, with no special hardware required for most of
it — just your phone's speaker, screen, and (optionally) a keying device:

- **CW Keyer** — practice keying with a real paddle or straight key (see
  below), decoded to text live, just like the device.
- **CW Generator** and **Koch Trainer** — listen to generated CW (random
  characters, words, callsigns, abbreviations, mixed content, your own
  practice-character set), with the same content pools, spacing rules and
  display conventions as the original.
- **Echo Trainer** — both standalone and nested inside the Koch Trainer,
  including adaptive speed, configurable repeats, and the repeat/reveal flow
  of a missed word.
- Matching settings: WPM, tone pitch/softness/shift, inter-character/word
  spacing, CurtisB timing, AutoChar Spacing, Koch sequences (including the
  LICW Carousel), Random Groups, Practice Set/Boost, callsign generation
  options, and more — ported from the firmware's own preference definitions,
  not guessed at.

What it deliberately does **not** try to reproduce, because it depends on
hardware a phone doesn't have or is simply out of scope for a training app:
physical rotary-encoder/button navigation, the OLED/LCD display hardware
itself, radio/transceiver modes (LoRa, WiFi TRX to a real rig, iCW/Ext Trx,
ESPNow), the TFT-only games, and on-device firmware/OTA or WiFi AP management.
Where Android already has a better native equivalent, the app uses that
instead of imitating the device: the OS theme instead of a "Theme"
preference, pinch-to-zoom text size instead of a fixed "Font Size" option, an
in-app German/English switch (the original device's UI is English-only), and
on-device paddle-key learning instead of fixed factory adapter presets.

## Using a real paddle or straight key

The CW Keyer and Echo Trainer can take input from a real Morse paddle or
straight key, the same way the Morserino-32 itself can act as a keying
dongle for a computer. A phone has no analog paddle input, so you need a
small USB (or USB‑OTG) adapter that turns paddle contacts into keystrokes:

- **[vband](https://hamradio.solutions/vband/)** — a widely used, ready-made
  USB adapter built exactly for this (dit and dah as two distinct keys).
- **Something homemade** works just as well: any small USB‑HID device (for
  example, an Arduino/Pro Micro running a simple keyboard-emulation sketch)
  that reports the dit and dah paddle contacts as two separate keystrokes.

Whichever adapter you use, open **Settings → Learn Paddle Keys** and press
each paddle once — the app learns whatever two keys your adapter happens to
send, so there's no fixed list of supported adapters to match against.

## Feature status

| Area | Status | Notes |
|---|---|---|
| CW Keyer (Iambic A/B, Ultimatic, Non‑Squeeze, Straight Key) | ✅ Supported | Live decode to text; CurtisB timing, AutoChar Spacing |
| CW Generator (Random / Words / Callsigns / Abbrevs / Mixed / Practice Set) | ✅ Supported | Ported content pools and generation rules |
| Koch Trainer (levels, M32/LCWO/CW Academy/LICW/Custom sequences, nested Generator/Echo submodes) | ✅ Supported | Includes the LICW Carousel entry point |
| Echo Trainer (standalone and Koch‑nested, incl. Adaptive Random) | ✅ Supported | Adaptive speed, repeat/reveal flow, Max # of Words |
| Session markers, spacing, WPM, tone pitch/softness/shift | ✅ Supported | |
| Theme, pinch‑to‑zoom output text size, German/English UI | ✅ Supported | Android-native equivalents of device-only prefs |
| Physical controls, OLED/LCD hardware, on‑device menu navigation | ❌ Not applicable | Touchscreen UI instead |
| Radio/Transceiver hardware modes (LoRa, WiFi TRX to a rig, iCW/Ext Trx, ESPNow) | ❌ Not applicable | No radio hardware on a phone |
| TFT‑only games (Morse Invaders, Fight the Pileup, Radio Cave, Morsel, Trailblazer, Fox Hunt) | ❌ Not applicable | Out of scope for a training app |
| Device firmware/OTA update, WiFi AP setup page | ❌ Not applicable | Android has its own update/network mechanisms |
| WiFi Transceiver as an online meeting point (e.g. cq.morserino.info, qsobot.online) | 🚧 Not yet implemented | Technically feasible; a UDP-based protocol |
| QSO Bot (SOTA / POTA / Standard / Contest simulated partner) | 🚧 Not yet implemented | Large feature; not started |
| CW Decoder (microphone → text) | 🚧 Not yet implemented | |
| File Player, CW Memories, Settings Snapshots | 🚧 Not yet implemented | |

## Development

Built with Flutter (UI, Dart) and native Kotlin/C++ on the Android side
(low-latency AAudio sidetone, iambic keyer and CW generator timing). The
Flutter project lives in `android/` (run `flutter` commands from there): see
`android/lib/` for the Flutter app and `android/android/app/src/main/kotlin`
and `android/android/app/src/main/cpp` for the native pieces.

`reference/` is a read-only git submodule of the original firmware, pinned
at tag `V9.0` (the v9.0.0 baseline above) — the source of truth this port is
checked against. See `docs/PROJECT.md` for the full repo layout and
`docs/STATUS.md`/`docs/DECISIONS.md`/`docs/PORTING-MAP.md` for current state,
architecture rationale, and the module-by-module porting status.
