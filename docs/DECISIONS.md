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

## Adaptive Copy: spacing-up hysteresis, and no new Adaptive-mode toggle
2026-09-22 user feedback: the spacing-tighten proposal fired too readily
relative to the Koch-unlock proposal (unlock needs ~20 occurrences/char;
spacing-up only needed one block's EMA crossing `highThreshold`), and it
piled onto an already-stressful ramp-up through Koch lessons. Explicitly
declined a per-mode enable/disable preference for this ("das müsste man
dann spiegelgleich auch für das lernen von neuen zeichen machen" — mirroring
it for the unlock side too would bloat the settings). Fixed structurally
instead, in two parts:
- `AdaptiveCopyEngine.recordBlock()` (`adaptive_copy_engine.dart`) now
  requires `spacingUpConsecutiveBlocks` (default 2) consecutive high-EMA
  blocks before proposing spacing-up/char-speed-up — an internal engine
  constant, not a Settings-exposed value. Spacing-down (widen, the safety
  net for a struggling block) stays single-block-reactive, unaffected.
- `AdaptiveCopyBody._finishBlock()` additionally suppresses spacing-up/
  char-speed-up proposals for the whole time `kochLevel < activeKochChars
  .length` (still working through the sequence), not just the single block
  that unlocks a character (existing `!unlocked` guard) — generalizing that
  guard's own reasoning to the whole ramp-up phase. The manual spacing +/−
  stepper (`_buildSpacingControl`) is untouched — independent of the
  engine's proposals by design, so the user can still tighten by hand any
  time without being pushed.

## Adaptive Copy: new-char preview stays in-flow, doesn't reuse Learn New Chr
Same 2026-09-22 feedback: engine-driven Koch unlocks happen mid-Adaptive-
Copy-session, before the user has ever heard the new character — unlike the
manual Classic flow, where Learn New Chr (`_openLearnNewChar()`,
`generator_screen.dart`) is used before advancing the Koch level by hand.
Considered routing the accepted-unlock case through that same
`EchoTrainerScreen(fixedTarget: ...)` screen, but explicitly declined — user
wants to stay "im Lern-Flow", not navigate out of Adaptive Copy. Instead
added a "hear it" speaker icon directly on the unlock suggestion row
(`_previewNewChar()` in `adaptive_copy_body.dart`), playing the new
character in place via the same `_genChannel`/done-event plumbing
`_startBlock()` already uses — no new native surface, no screen change.

## Koch character draw weighting ported from firmware (was uniform)
`CwGenerator.kt randomKochChars()` drew uniformly from the active Koch set —
a divergence from `Koch::getRandomChar()` (`MorsePreferences.cpp`), which
draws from the last third of the active set 1-in-3 times (comment there:
"generate the last third of the chars learned a bit more often"). Ported
literally as `weightedKochChar()` rather than inventing a new "boost the
newest character" mechanism, since the firmware's existing weighting already
gives the newest, least-practiced character disproportionate representation
(it always sits in that last third) without any Adaptive-Copy-specific code.
Affects Koch generation generally (Classic and Adaptiv), not just Adaptive
Copy — intentional, since this is a fidelity fix (CLAUDE.md rule 1), not an
Adaptive-Copy-only behavior.

## Changing a `?? default` doesn't reach a pref already persisted as ''
2026-09-23: after changing the Custom Koch Sequence's code default from `''`
to a real sequence, the Settings field still showed empty and the Koch
Trainer's Custom set still drew a "random"-looking (actually
uniform-over-empty-falls-back-elsewhere) sequence on-device. Root cause:
`p.getString('customKochChars') ?? '<new default>'` only substitutes on
`null`, but every prior session had already called `save()`/`_saveLive()`
at least once, persisting the *old* default (`''`) as an actual stored
value — so the lookup never returned `null` again, and the new code default
was permanently unreachable for this already-installed app. Fixed in all
three load sites (`settings_screen.dart`, `generator_screen.dart`,
`echo_trainer_screen.dart`) by treating an empty stored string the same as
absent: `(p.getString('customKochChars') ?? '').isNotEmpty ? ... : '<new
default>'`. General lesson: a persisted-preference default change needs to
survive an already-populated value that matches the *old* default, not just
a missing key — `??` alone only covers a fresh install.

## Adaptive Copy's auto-boost dialed back from Strong to Moderate
2026-09-23 user report: in a 9-character Koch lesson, marking one character
wrong once made it ~80% of the very next block — far too extreme a spike.
Root cause: `AdaptiveCopyBody._startBlock()` always pushed `boostLevel` 2
("Strong", `CwGenerator.kt boostAttempts()` = 8 rejection-sampling draws)
whenever there was any accepted weak character. `boostAttempts()` itself is
a faithful firmware port (`practiceBoostAttempts()` in
`MorsePreferences.cpp`, `{Off,Moderate,Strong} -> {1,3,8}`) and stays
untouched — Off/Moderate/Strong is a user-facing Settings choice elsewhere
(CW Generator's own "Practice Set"/Boost) and changing the table itself
would be a fidelity regression (rule 1). What's app-specific, not firmware,
is Adaptive Copy automatically picking Strong every time — so only that
call site was changed to push level 1 (Moderate, 3 attempts) instead.
Weak characters already stay boosted across every block until their
lifetime EMA error rate drops below threshold or the user un-taps them (not
cleared after one block), so a gentler per-block rate integrates to a
sustained-but-not-overwhelming boost across that whole stretch, matching
what the user asked for ("über die nächsten paar Blöcke etwas häufiger als
sonst, aber nicht so extrem"). `generator_screen.dart`'s Classic-mode weak-
chars panel keeps pushing Strong, unaffected — not part of this request.

## Project renamed to "Next CW Trainer"; package namespace dropped oe1wkl
User request: the "Morserino Mobile" name and the `at.oe1wkl.*` package
namespace overstated a connection to Willi Kraml/OE1WKL that doesn't exist —
this project only reuses algorithms/training logic read out of his firmware
source, nothing more. Renamed everywhere: app label/title, Dart package
(`morserino_mobile` → `next_cw_trainer`), Android package/applicationId
(`at.oe1wkl.morserino_mobile` → `at.oe1cko.nextcwtrainer`, `oe1cko` being the
user's own callsign), JNI exported symbol names in `cw_tone_jni.cpp`
(`Java_at_oe1wkl_morserino_1mobile_*` → `Java_at_oe1cko_nextcwtrainer_*`),
MethodChannel/EventChannel name strings (must match on both the Dart and
Kotlin sides), GitHub repo, and local folder. Left untouched: `reference/`
submodule (still the real `oe1wkl/Morserino-32` firmware, pinned per rule 6),
and all README/docs attribution language crediting Willi Kraml/OE1WKL for
the original design/curriculum — that credit is accurate and stays, it's
only the implied *project* affiliation that was misleading.
