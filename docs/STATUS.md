# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/next_cw_trainer (private).
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
- **Project renamed "Morserino Mobile" → "Next CW Trainer" (2026-09-23):**
  app label/title, Dart package (`morserino_mobile` → `next_cw_trainer`),
  Android package/applicationId (`at.oe1wkl.morserino_mobile` →
  `at.oe1cko.nextcwtrainer`, incl. JNI symbol names and MethodChannel/
  EventChannel names), GitHub repo (`ckonecny/morserino_mobile` →
  `ckonecny/next_cw_trainer`), and local project folder (`~/morserino_mobile`
  → `~/next_cw_trainer`) all updated. README/CLAUDE.md/docs now spell out
  that this project has no connection to Willi Kraml/OE1WKL beyond reusing
  algorithms/training logic read out of the firmware source. Old app
  (`at.oe1wkl.morserino_mobile`) uninstalled from `63061JEBF01551`, new one
  built and installed successfully.

- **WiFi Trx (2026-09-23), first version, installed on 63061JEBF01551 but
  not yet tried against a real server:** new home card "WiFi Trx". One
  endpoint (name or IP, default `cq.morserino.info`, empty = broadcast),
  connect/disconnect, receive (word-by-word playback at the sender's WPM +
  RX/TX log), send via keyer/touch paddles (per word) or typed text, macros
  CQ / Call+Name / `:usr`. New prefs in Settings > WiFi Trx: Callsign, Name.
  Uses system WLAN/mobile data (no SSID/password). See DECISIONS.md.
  Next: test against cq.morserino.info (registration "hi" @20 WPM assumed
  from the chatserver README, not verified against that exact server),
  multiple endpoints (add/edit/delete), maybe a foreground service.

## Working / verified on device
Everything above, tested on 63061JEBF01551.

## Next steps — requested by user (2026-09-23), to be done one per session
1. ~~Output Case lower/UPPER setting not applied in Adaptive Copy mode.~~
   **Done, user-confirmed working on-device (2026-09-23).**
2. ~~Change default Custom Koch Sequence.~~ **Done, user-confirmed working
   on-device (2026-09-23)** — needed a second fix, see below.
3. ~~Change InterCharSpc/InterWordSpc defaults to 28/40.~~ **Done,
   user-confirmed working on-device (2026-09-23).**
4. ~~Couple the InterCharSpc/InterWordSpc sliders.~~ **Done, user-confirmed
   working on-device (2026-09-23).**
5. **Simplify the Adaptive Copy error-marking flow after a block.** Currently
   fiddly; user wants: tap the word that had an error → that word's
   characters are shown individually → tap the wrong character(s) in it →
   back out to the block overview, which then shows the marked/wrong
   characters highlighted in place. Needs a new per-word drill-down screen/
   state in `adaptive_copy_body.dart`'s result/marking flow, replacing
   however errors are currently selected there. **Not started.**
6. ~~Weak-character boost after a single miss is far too aggressive.~~
   **Done (2026-09-23), installed on-device.** Not separately called out
   by the user during the "passt jetzt überall" confirmation, which was
   about the output-case follow-up — not yet explicitly re-confirmed
   through a real Adaptive Copy session with a miss.

**2026-09-23, follow-up to item 1 — user-confirmed working on-device:**
lower/UPPER Output Case now also applies to raw-character chip displays it
had missed — the Koch Trainer/Echo Trainer start screens' active-sequence
row, the Koch Trainer weak-characters chips, the Koch level preview in
Settings, and the Preview Char picker sheet. Fixed: `generator_screen.dart`
gained its own `_displayChar()` helper (mirroring `AdaptiveCopyBody`'s)
applied to its weak-chars chips and `_PreviewCharSheet`; `_KochCharsRow`
(duplicated in `generator_screen.dart` and `echo_trainer_screen.dart`) and
`_KochLevelPreview` (`settings_screen.dart`) each gained an `outputCase`
param threaded from their screen's own `_outputCase` field.

**2026-09-23 session: items 1, 2, 3, 4, 6 implemented, `flutter build apk
--debug` succeeded and installed on `63061JEBF01551`.** User confirmed on
first on-device check: output case (1), InterChar/InterWord defaults +
coupling (3, 4) all working. Custom Koch Sequence default (2) was **not**
visible — Settings field stayed empty and Koch Trainer's Custom set still
drew what looked like a random sequence. Root cause: the `??` fallback only
fires on `null`, but this already-installed app had persisted the *old*
default (`''`) as a real stored value in an earlier session, so the new
code default was unreachable. Fixed by treating an empty stored string the
same as absent in all three load sites — see docs/DECISIONS.md "Changing a
`?? default` doesn't reach a pref already persisted as ''" — rebuilt,
reinstalled. Not yet re-checked by the user. Details of the original
changes:
1. `AdaptiveCopyBody` now loads the `outputCase` pref (same key Settings/
   Generator use) and applies it via a new `_displayChar()` helper to every
   place a raw character reaches the screen: the revealed-groups tiles, the
   marking grid, the weak-characters chips, and the Koch-unlock suggestion
   label. Underlying data (comparisons, `charTypeColor`, wrong-position
   keys) stays uppercase internally — display-only change.
2. Default Custom Koch Sequence changed from `''` to
   `esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?` in all three places it's loaded
   (`settings_screen.dart`, `generator_screen.dart`,
   `echo_trainer_screen.dart`) plus their field initializers.
3. `_interCharSpace`/`_interWordSpace` defaults changed from 3/7 to 28/40 in
   `settings_screen.dart` and `generator_screen.dart` (field initializers +
   `getInt(...) ?? ...` fallbacks). Left the native `CwGenerator.kt`/
   `MainActivity.kt` 3/7 fallbacks alone — those mirror the firmware's own
   documented defaults (`MorsePreferences.cpp` comment) and are always
   overridden by whichever screen pushes its config on entry anyway (rule
   2), so changing them would be a fidelity regression, not a UI default.
4. `settings_screen.dart`'s Interchar Spc / InterWord Spc sliders now cross-
   clamp each other's `onChanged`: raising Interchar Spc above the current
   InterWord Spc carries InterWord Spc up with it; lowering InterWord Spc
   clamps it at the current Interchar Spc instead of going below. Kept as
   two separate sliders (not a single `RangeSlider` like the threshold pair)
   since their min/max/units genuinely differ (3–45 vs 6–105 dits).
6. `AdaptiveCopyBody._startBlock()`'s auto-boost for weak characters now
   pushes `boostLevel` 1 (Moderate, 3 draw attempts) instead of 2 (Strong, 8
   attempts) — see `docs/DECISIONS.md` for the reasoning. Scoped to Adaptive
   Copy's automatic boost only; `generator_screen.dart`'s manual Koch
   weak-chars panel (Classic mode) still uses Strong, unchanged, since that
   wasn't part of this request.

## In progress: Trainings-Umbau Hören/Echo/Einstellungen (2026-09-23)
Phased rollout, one phase at a time: spec → user approval → implement →
install → user test → next phase. **Entry point for every session on this:
`docs/training/README.md`** (phase table + status + spec template); target
picture: `docs/TRAINING-CONCEPT.md`. Current: **Phase 1 spec awaiting
approval** (`docs/training/P1-echo-grundlagen.md`): fixes Echo Trainer never
pushing spacing/Practice Set/Boost to the generator and never setting the
keyer WPM (rule 2), adds a firmware-style answer speed cap ("Gebe-Tempo"),
and makes Adaptive Speed ±1 per word like the firmware. File Player is last
(phase 9, low priority).

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

## UI polish: dark-theme contrast, effective WPM, Koch coloring, Character Statistics screen (2026-09-23)
Series of on-device UI reports acted on this session, all built and
installed on `63061JEBF01551`, user-confirmed working:
1. **Dark-theme contrast fix:** Adaptive Copy's status line and "Abstand
   anpassen" spacing block were using `c.textDisabled` (near-invisible on
   dark background) for text meant to be read. Swapped to `c.textMuted`
   everywhere this pattern showed up (status line, spacing control, weak-
   chars section, Koch Trainer panels) — see docs/DECISIONS.md.
2. **Effective (Farnsworth) WPM:** new `{ewpm}` figure derived from char WPM
   + inter-char/inter-word spacing (`50 * charWPM / (31 + 4*ic + iw)`),
   shown next to the raw WPM in the shared status-line strings
   (`gen_status_line`/`ac_status_line`) on the Adaptive Copy result + idle
   screens and both Koch Trainer start-screen variants (Classic and
   Adaptiv). Net-new feature, no `reference/` equivalent — see
   docs/DECISIONS.md.
3. **Larger text on the Adaptive Copy result screen** (status line,
   suggestions, spacing control, weak-chars section all bumped, big "100%"
   left as-is) via a new `scale` parameter on the shared widget-builders,
   reused for the Koch Trainer's Classic and Adaptiv start screens once
   those needed the same treatment.
4. **Koch-sequence digit coloring:** the active-characters row (`_KochCharsRow`,
   duplicated in `generator_screen.dart` and `echo_trainer_screen.dart`) now
   colors digits differently from letters via the existing `charTypeColor()`
   helper, matching the rest of the app instead of a flat single color.
5. **New Character Statistics screen** (`lib/ui/char_stats_screen.dart`,
   linked from Settings → Adaptive Mode → "Zeichen-Statistik anzeigen"):
   lists every active Koch character's attempts/occurrences floor, lifetime
   error rate, and unlock-readiness, sorted least-ready-first. Added after
   diagnosing a user report ("next character never unlocks despite lots of
   correct reps") that turned out not to be a bug — see docs/DECISIONS.md
   "Adaptive Copy's per-character unlock gate" and docs/ADAPTIVE-COPY.md
   "Also investigated this session, not a bug (2026-09-23)" for the full
   on-device diagnosis (pulled `charStats` off `63061JEBF01551` directly).
6. **Dark-theme Switch styling:** the Settings screen's toggle switches had
   a near-white off-state thumb and track outline that didn't follow the
   theme (Material 3 defaults, not previously overridden). Added
   `inactiveThumbColor`/`trackOutlineColor` to `_ToggleRow`'s `Switch` — see
   docs/DECISIONS.md.

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

- WiFi Trx v2: multiple services (add/edit/delete, dropdown), per-service persisted log (long-press to clear), WPM slider, no automatic "hi", quick chips removed. Verified on device.
- Keyer/WiFi Trx word gap now follows InterWord Spc (was fixed 6 dits). Verified on device.

- WiFi Trx tested on device against cq.morserino.info (send + receive OK), service add/edit/delete OK. Next: optional per-service login command, foreground service for background operation, direct Morserino-to-Morserino test, adaptive word gap for straight key.
