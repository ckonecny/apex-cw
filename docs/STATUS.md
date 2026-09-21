# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/morserino_mobile (private).
Latest tagged build: v0.1.0.

## Done
- CW Keyer: all 5 modes, decode-to-text, CurtisB timing, AutoChar Spacing.
- CW Generator + Koch Trainer: all content modes, LICW Carousel, Random
  Groups, Practice Set/Boost, weighted callsign generator.
- Echo Trainer: standalone + Koch-nested, adaptive speed, repeat/reveal flow,
  Max # of Words.
- Settings: WPM, pitch/softness/shift, spacing, Koch sequences, DE/EN UI,
  theme, pinch-zoom text size.
- Native engine (Kotlin CwGenerator/CwKeyer + C++ AAudio sidetone) is a
  shared singleton synced from each screen's own entry point.
- README + docs/PORTING-MAP.md keep the firmware comparison; canvas artifact
  has the full per-preference audit (not duplicated here).

## Working / verified on device
Everything above, tested on 63061JEBF01551.

## Next 3 steps (candidates, not yet decided)
1. Koch Sequence Prosign extension (6 prosigns at the end of each sequence) —
   small, self-contained.
2. RECALL/STORE Snapshot (named settings profiles) — small-medium.
3. CW Generator File Player — medium (needs Android file picker).

## In design: Adaptive Copy Mode
New listen-and-copy-on-paper mode with per-character stats driving
speed/spacing/Koch-level adaptation. Not a firmware port — net-new concept.
Design decisions, build order, and open points: see `docs/ADAPTIVE-COPY.md`.
Done so far: `char_stats.dart` (shared per-character stats store, Echo
Trainer's "Adapt. Rand." runs on it), the Koch Trainer UI skeleton
(Classic/Adaptiv toggle + send→reveal→mark→result flow, tested on device),
`adaptive_copy_engine.dart` (pure-Dart EMA-based tempo/unlock decision
logic, unit tested), the "Adaptive Mode" settings section in
`settings_screen.dart` (4 threshold sliders, persisted), and wiring the
engine into `AdaptiveCopyBody._finishBlock()` (spacing/char-speed steps and
Koch-level unlock now actually apply after each block, surfaced as notice
chips on the result screen). Built and installed on `63061JEBF01551`.
**Not yet run through a real multi-block session on-device** — only
confirmed it builds/installs; whether the adaptation actually feels right
(step sizes, timing) still needs testing. See docs/ADAPTIVE-COPY.md
"Starting point for the next session" for the test checklist.

## Backlog (later iteration, not urgent)
- **Koch Trainer setup-screen decluttering:** the pre-start controls (Learn
  New Chr/Preview/Echo/CW Generator picker, WPM, Koch lesson, content mode)
  are needed before starting but are just distracting, irrelevant noise once
  a training run is actually active. Collapse/hide them once running, same
  idea for any other screen with the same setup-then-run shape (e.g. the
  planned Adaptive Copy flow itself). Flagged during Adaptive Copy Mode
  design (docs/ADAPTIVE-COPY.md), applies more broadly.

## Open questions
- QSO Bot (~1800 LOC in firmware): worth doing at all, and if so, SOTA-only
  first rather than all 4 types?
- WiFi Transceiver / online relay (cq.morserino.info): background UDP socket
  reliability on Android not yet validated.
- iOS port: keep timing engine native per-platform, or move it into Dart for
  reuse (untested whether Dart timers are precise enough)?
- `android/lib/audio/tone_synth.dart`, `android/lib/input/paddle_input.dart`,
  `android/lib/keyer/iambic_keyer.dart` are unimported dead code from an early
  pure-Dart prototype — safe to delete, not yet done.
