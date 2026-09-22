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
- Audio output device handling: auto-detects USB/Bluetooth connect and
  disconnect while running (no more app restart needed to pick up the new
  device), plus a manual Auto/Speaker/Wired-USB/Bluetooth picker in Settings.
- README + docs/PORTING-MAP.md keep the firmware comparison; canvas artifact
  has the full per-preference audit (not duplicated here).

## Working / verified on device
Everything above, tested on 63061JEBF01551.

## Next 3 steps (candidates, not yet decided)
1. Koch Sequence Prosign extension (6 prosigns at the end of each sequence) —
   small, self-contained.
2. RECALL/STORE Snapshot (named settings profiles) — small-medium.
3. CW Generator File Player — medium (needs Android file picker).

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
