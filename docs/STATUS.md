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
Koch-level unlock computed after each block), and a result-screen override
UI (`_SuggestionRow`) letting the user accept/reject/adjust each proposal
before it's applied on "Finish"/"Next Block", rather than it landing
automatically. Built and installed on `63061JEBF01551`.
**Run through a real multi-block session on-device and confirmed working**
(unlock, tempo/spacing step, override controls). Since then, fixed a unlock-
threshold trap (100% high threshold was unreachable), a "spacing widened:
X→X" no-op notice, switched the "weak characters" display from this-block-
only to the character's lifetime EMA, and added the ability to tap weak
characters on the result screen to include/exclude them from a boosted draw
in the next block (reuses the existing Practice Set/Boost mechanism). See
docs/ADAPTIVE-COPY.md "Flagged TODOs" for details on each.

**This session (2026-09-22):** brainstormed two more on-device reports with
the user, agreed on an approach for each, then implemented and installed
both (see docs/DECISIONS.md for the reasoning behind each choice):
1. Spacing-tighten/char-speed-up proposals no longer fire off a single good
   block (`AdaptiveCopyEngine.recordBlock()` now needs
   `spacingUpConsecutiveBlocks` = 2 consecutive high-EMA blocks,
   `adaptive_copy_engine.dart`), and are suppressed entirely while
   `kochLevel < activeKochChars.length` (still working through the Koch
   sequence), not just in the single block that unlocks a character
   (`AdaptiveCopyBody._finishBlock()`). Spacing-down (widen) and the manual
   +/− spacing stepper are both unaffected — no new Settings toggle.
2. The Koch-unlock suggestion row now has a "hear it" speaker icon
   (`_previewNewChar()` in `adaptive_copy_body.dart`) that plays the
   just-unlocked character in place, twice, without leaving Adaptive Copy.
3. Ported the firmware's Koch character weighting (`Koch::getRandomChar()`,
   "last third of chars learned a bit more often") into
   `CwGenerator.kt randomKochChars()`, which had been drawing uniformly — a
   genuine fidelity gap. This also means the newest/least-practiced
   character now naturally comes up more often, addressing the user's
   request for that without any Adaptive-Copy-specific boost code. Affects
   Koch generation generally, not just Adaptive Copy.

Engine test updated for the new hysteresis behavior + two new hysteresis
tests (`adaptive_copy_engine_test.dart`), all passing. `flutter build apk
--debug` + install succeeded on `63061JEBF01551`. **Confirmed working
on-device** through a real session — user reported "funktioniert super".

**Previous session (2026-09-21):** two more on-device reports acted on — (1) a
manual "ABSTAND ANPASSEN" spacing control (−/+ steppers on
`interCharSpace`/`interWordSpace`, independent of the engine's own
suggestions) now always shows on the idle/start screen and every result
screen, not just when the engine happens to propose a spacing change; (2) a
block that unlocks a new Koch character no longer also proposes a spacing-
tighten/char-speed-up in that same block (`_finishBlock()` in
`adaptive_copy_body.dart`) — a new character alone is enough to absorb at
once, per user feedback ("wird mir das zu schnell"). Both built/installed on
`63061JEBF01551`, not yet exercised through a real session. Also confirmed
(not a bug): a block with 2 errors can still trigger a spacing-tighten
suggestion — intended EMA-smoothing behavior, not a bug; see
docs/ADAPTIVE-COPY.md "Also investigated this session, not a bug" for the
full explanation and an open (declined-so-far) offer to add a stricter
no-speedup-after-error rule.

## Koch Trainer / CW Generator GUI cleanup (this round)
Implemented the setup-screen decluttering flagged below, plus a round of
requested layout/readability fixes to `generator_screen.dart` and
`adaptive_copy_body.dart`:
- **Setup-screen declutter:** content-mode selector (Random/Abbrevs/Words/
  Mixed), Learn New/Preview/Practice Echo, and the Classic/Adaptiv toggle
  are now hidden while a block/session is actively running (Classic:
  `_running`; Adaptiv: `AdaptiveCopyBody` reports its own idle-vs-active
  phase back via a new `onActiveChanged` callback, since that state lives
  inside the child widget).
- **Back button during practice:** the app bar back arrow now goes through
  `PopScope`/`Navigator.maybePop`; while a block/session is active it
  returns to this same screen's setup/start state (Classic: stops the
  session; Adaptiv: resets `AdaptiveCopyBody` to idle via a new
  `AdaptiveCopyController`) instead of leaving the screen. Only pops for
  real when nothing is running.
- **1s "get ready" pause:** both Classic's Start button and Adaptiv's
  "Start Block" now wait one second (declutter already applied, so the
  screen is already calm) before anything actually plays.
- **Koch Trainer start-screen weak characters:** the (otherwise empty)
  output box on the Koch Trainer's start screen now shows the lifetime-weak
  characters (same `weakCharsLifetime()` helper in `char_stats.dart`, now
  shared with `AdaptiveCopyBody`) with tap-to-exclude chips; the resulting
  set is pushed as `practiceChars`/`boostLevel` when Start is pressed, and
  restored to the Settings-persisted values on dispose (shared-singleton
  rule).
- **Revealed-groups layout:** `AdaptiveCopyBody`'s "Sent" review screen
  replaced a single left-stuck column with a centered, wrapping grid of
  fixed-width tiles that uses the whole middle area, still scrollable if it
  overflows.
- **Character-type coloring:** letters/digits/other (punctuation, prosign
  tokens) are now colored with three distinct theme colors (`accent`/
  `info`/`accentPurple`, via a new `charTypeColor()` helper in
  `util/char_color.dart`) in the Classic log display, the Adaptiv review
  grid, and the marking screen (correct chars only — wrong stays red).
Built and installed on `63061JEBF01551` earlier this session; exercised
live on-device through several Koch Trainer/Adaptiv sessions during this
session's debugging (see "Known issues" below) with no problems noticed —
user said it "sieht gut aus bis hier her" (looks good so far). Not a
per-change checklist verification, just general confirmation nothing broke.

## Known issues
- **Intermittent dark/locked screen during practice — root cause not
  found, not reproduced.** User report: screen went dark mid-practice once
  more this session, previously flagged as something that must never
  happen (`KeepScreenOn`, `android/lib/util/keep_screen_on.dart`, exists
  specifically to prevent this). Investigated: `KeepScreenOn.enable()`/
  `disable()` call sites in `generator_screen.dart` (init/dispose-bound)
  are unchanged and correct; no native (`MainActivity.kt`) diff this
  session; predictive-back is not enabled in the manifest, ruling out a
  back-gesture animation glitch; proximity sensor ruled out (user confirmed
  phone was lying flat on the table, not covered). Live `adb`-based testing
  (polling `dumpsys window windows`/`dumpsys power` through 40s–100s+ idle
  windows across the Adaptive Copy sending/revealed/result phases) never
  reproduced a drop — the `KEEP_SCREEN_ON` flag held throughout. However,
  that testing was done with the phone connected via USB to the Mac for
  `adb`; the user's real practice setup has the USB port occupied by a
  USB-to-audio adapter + headset instead, not connected to a computer — and
  the user reports no recurrence at all since switching to that real setup
  mid-session. Being tethered to a host for debugging can suppress some
  Android power-management behavior, which may explain why it couldn't be
  reproduced under test conditions; not confirmed, just the leading
  hypothesis. No code change made — nothing in the diff explains a
  regression, and the bug may be a device power-management interaction
  rather than an app bug at all. **Next step:** keep an eye on it during
  normal (headset, no computer) practice; if it recurs, report back
  immediately (what phase of the flow, how long idle beforehand) so it can
  be investigated further, ideally with a wireless-adb test setup that
  doesn't require a USB tether to the Mac.

## Backlog (later iteration, not urgent)
(nothing currently queued here)

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
