# Architecture Decisions

Short log of the non-obvious calls made so far, newest first within each
topic isn't tracked — this is a flat reference, not a changelog.

## Engine split: Flutter UI, Kotlin/C++ for timing-critical code
CW keying/generation needs sub-ms timing precision that Dart's UI-thread
timers can't reliably guarantee. `CwKeyer.kt`/`CwGenerator.kt` run on
dedicated 1ms-tick threads; `cw_tone_jni.cpp` uses AAudio directly for the
lowest achievable audio latency. Flutter (Dart) owns everything else: all
screens, content tables, i18n, decode-to-text logic.

## Shared singleton native engine, not per-screen instances
`CwGenerator`/`CwKeyer` are single instances reused across screens via
MethodChannel, mirroring the firmware's one global generator/keyer. Trade-off:
every screen must explicitly re-sync wpm/pitch/mode/etc. on entry, since nothing
else does it automatically — this exact bug (stale value left by whichever
screen ran last) has been hit and fixed repeatedly (wpm, spacing, pitch,
keyer mode, CurtisB timing).

## Prosigns as two-character mnemonic keys, not the firmware's case trick
The firmware distinguishes prosigns from letters by case (single uppercase
letter = prosign). `playWord()` here uppercases all text before parsing, so
that trick isn't available; prosigns are instead keyed as two-letter mnemonics
("KA", "KN", "SK", "AS", "VE", "BK") recognized via lookahead in `morseTable`.

## Generation-token counter to kill stale async callbacks
`CwGenerator.generation` is bumped on every `stop()`; every callback checks it
before firing. Root-fix for a race where a just-stopped generator thread's
delayed 'done' event arrived during the next session's start marker and
corrupted it — found via live logcat, not by static reading.

## Custom lightweight i18n instead of `intl`
`Strings` is a static map + `ValueNotifier<int>`, no codegen. Chosen
deliberately over the full `intl` package for now; a later switch to `intl`
stays open if translation needs grow.

## Per-screen `ValueListenableBuilder` for instant language switching
`Strings.t()` is a plain function call with no InheritedWidget, so only a
screen that explicitly wraps its own `build()` in a `ValueListenableBuilder`
reacts immediately (matches how Theme already works). A single top-level
wrapper around `MaterialApp` does not reach already-pushed routes.

## Echo Trainer as one continuous scrolling log, not a flashcard UI
Rewritten to match the CW Generator's log pattern (colored role spans,
auto-scroll) instead of a big-target/big-input flashcard screen, mirroring
the real device (no separate "big" UI there either) and per explicit request
to keep the two screens' output concept consistent.

## Paddle presets removed in favor of Learn Paddle Keys only
The vband/Arduino quick-select preset rows in Settings were redundant once
on-device paddle-key learning exists (it covers any adapter's key mapping
already); removed rather than kept as a shortcut.

## Firmware version pinned and recorded (v9.0.0)
The port targets a specific firmware snapshot rather than "whatever's
current" — recorded in the README so future firmware changes are a known,
reviewable diff rather than silent drift.

## Audio output tracked by device category, not AAudio device id
`AudioRouteManager.kt` persists the user's output preference (Auto/Speaker/
Wired-USB/Bluetooth) as a category, not as an `AudioDeviceInfo.id` — Android
reassigns ids each time a device is plugged in or paired, so an id captured
once would go stale on the very next reconnect. AAudio also does not
re-route an already-open stream when the active output changes; a real
`AAUDIO_ERROR_DISCONNECTED` (or any other stream error) requires closing and
reopening a fresh stream, which the old `errorCallback` in `cw_tone_jni.cpp`
didn't do (it tried to restart the same, now-dead handle) — root cause of the
"unplug USB/Bluetooth, sidetone goes silent until app restart" bug.
`AudioDeviceCallback` in `AudioRouteManager` drives that reopen automatically
on every device add/remove, in addition to the manual Settings picker.

## Native (not Dart) engine, iOS reuse deferred as an open question
Given the sub-ms timing requirement above, porting to iOS means either a
Swift rewrite of the engine or moving that logic into Dart and accepting
unverified Dart-timer precision — deliberately not decided yet (see
STATUS.md).
