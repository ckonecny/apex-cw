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
  *(2026-09-25: the macros no longer exist in `wifi_trx_screen.dart`, and
  Callsign/Name were never read anywhere, so both prefs and the Settings >
  WiFi Trx section were removed; see "Dead-code cleanup" below.)*
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
   however errors are currently selected there. **Done/obsolete, user-confirmed 2026-09-25.**
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
picture: `docs/TRAINING-CONCEPT.md`. Current: **Phases 1 and 2 done and device-tested 2026-09-25; Phase 3 done and device-tested (3a–3e); Phase 4 (char stats split hear/echo, 📊 in each training) done and device-tested; Phase 5 (block flow + result page in Echo, display only; `docs/training/P5-echo-bloecke.md`) done (5a–5c device-checked stepwise; full testplan deferred by user); Phase 6 (adaptive suggestions in Echo block flow; `docs/training/P6-echo-vorschlaege.md`) done, 6a–6d device-checked stepwise, full testplan deferred by user; Phase 7 (Koch as char set, start page with Hören/Geben, classic flow removed, unified practice view; `docs/training/P7-zeichenvorrat-startseite.md`) implemented 7a–7g and device-checked stepwise, full testplan still to be run by the user; next: Phase 8 (extras: Reaktionszeit, Presets, Trend, Verwechslungspaare, paddle choice Wiederholen/Weiter in the Hören block view) (P2 spec: `docs/training/P2-trainingsprofile.md`)
approval** (`docs/training/P1-echo-grundlagen.md`): fixes Echo Trainer never
pushing spacing/Practice Set/Boost to the generator and never setting the
keyer WPM (rule 2), adds a firmware-style answer speed cap ("Gebe-Tempo"),
(Adaptive Speed deliberately untouched until phases 5/6). File Player is last
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
Firmware modules still to port, in this order, one per session (a larger
module takes several sessions in a row). Effort: S = 1 session,
M = 2–3, L = 3–5. Multiplayer (ESP-NOW) is left out everywhere, see
DECISIONS.md.

| # | Module | What it is | Effort | Notes |
|---|---|---|---|---|
| 1 | **Morsel** (`MorseMorsel.cpp`, ~1.8k lines) — ported 2026-09-25, see below | Word guessing like Wordle: the word is played in CW and keyed back; letter boxes turn green/red. Words and abbreviations from the Koch lesson. | M | Word lists, Koch set, keyer and decoder already exist. Needs the `<err>` prosign (8 dits = delete the last char); build it together with the error-sign item from the upstream check. |
| 2 | **Memory Chain** (`MorseMemoryChain.cpp`, ~830) — ported 2026-09-25, see below | One new char per round, the whole chain is keyed from memory. Modes: Koch characters / call signs. | S–M | Call signs come from `CallsignData.kt`. High scores per mode. |
| 3 | **Trailblazer + Fox Hunt** (grid engine ~400, score ~300, games ~360 + ~440) | Maze: Trailblazer shows the next letter (keying), Fox Hunt only plays it and you key the direction (hearing). | M | Build the grid engine once for both games. |
| 4 | **Morse Invaders** (`MorseGame.cpp` ~1.1k + game mode/sprites) — ported 2026-09-25, see below | Arcade: falling characters get "shot" by keying them. | L | Real-time game loop plus graphics (CustomPainter/Ticker), timing against the native keyer. |
| 5 | **Radio Cave** (`MorseRadioCave.cpp`, ~2.65k) | Text adventure, every command keyed in Morse. 12 rooms, items, puzzles. | L | Mostly content and a state machine, UI is simple. Keep the English texts. |
| 6 | **Fight the Pileup** (`MorsePileup.cpp`, ~1.8k) | Work a pileup of call signs. | M–L | Single player only; the multiplayer part is ESP-NOW. |
| 7 | **QSO Bot** (`MorseQsoBot.cpp` ~1.2k + match/content) — ported 2026-09-25, see below | Simulated QSO, the bot answers to what was keyed. | L | The most valuable training module still missing. |
| 8 | **CW decoder via mic** (`goertzel.cpp`, ~160) | Decode CW from the microphone (Goertzel). | M–L | The algorithm is small. The work is a native audio input (AAudio), mic permission and robustness against noise. |
| 9 | **File Player** | Play your own text files as practice content. | S | File picker plus the existing generator. |
| 10 | **Snapshots** | Saved sets of settings. | S | Overlaps with the named presets (Phase 8d); check before starting whether they merge. |

Separately, a small open item (not a module): the echo answer reset by the
error sign, see "Upstream check" below. It is needed for Morsel anyway.

## Open questions
- ~~QSO Bot: port all QSO types, or SOTA-only first?~~ All three firmware
  types (SOTA/POTA, Standard, Contest) ported 2026-09-25.
- WiFi Transceiver / online relay (cq.morserino.info): background UDP socket
  reliability on Android not yet validated.
- iOS port: keep timing engine native per-platform, or move it into Dart for
  reuse (untested whether Dart timers are precise enough)?
- ~~Dead prototype files `tone_synth.dart`, `paddle_input.dart`, `iambic_keyer.dart`~~ deleted 2026-09-25.
- WiFi Trx: tested against several servers, works (user-confirmed 2026-09-25). Adaptive Copy leftovers (settings visibility, block log, stricter no-speedup rule) closed by the user 2026-09-25.

- WiFi Trx v2: multiple services (add/edit/delete, dropdown), per-service persisted log (long-press to clear), WPM slider, no automatic "hi", quick chips removed. Verified on device.
- Keyer/WiFi Trx word gap now follows InterWord Spc (was fixed 6 dits). Verified on device.

- WiFi Trx tested on device against cq.morserino.info (send + receive OK), service add/edit/delete OK. Next: optional per-service login command, foreground service for background operation, direct Morserino-to-Morserino test, adaptive word gap for straight key.


## Trainings-Umbau Phase 8 (2026-09-25)
Done (installed, partly user-confirmed): Paddle choice per group (Hören), block trend, think-time fix, Echo confirm tones, speed controls, 2 s wait, attempt indicator, stale-text fix. Reaktionszeit dropped. Next: 8c Verwechslungspaare, 8d benannte Presets, then Phase 8 test. Phase 5-7 testplans still with the user. See docs/training/P8-extras.md.
Verwechslungspaare done (Geben stats + result page). Benannte Presets deferred by user.

## Dead-code cleanup (2026-09-25), installed on 63061JEBF01551, not yet user-tested
Removed code that nothing uses:
- Settings > WiFi Trx (Callsign/Name) plus `_TextPrefField`, which was used
  only there. The stored prefs `callsign`/`opName` are left orphaned on
  existing installs, which does no harm.
- `genModeNames()` (cw_content.dart), `_dispCodeAndDisp` (echo trainer), and
  8 unused l10n keys (`opt_unlimited`, `opt_by_char`, `opt_by_word`,
  `settings_default_wpm`, `settings_level_includes_chars`, `ac_start_block`,
  `ac_result_title`, `ac_status_line`).
- Native channel handlers that Dart never calls: generator `pause`/`resume`/
  `choosePaddle`/`getKochChars`, tone `keyOn`/`keyOff`/`dispose`, plus
  `CwGenerator.pause()/resume()` and the `paused` wait loop. The paddle
  choice still runs internally via `generator.choosePaddle()` from the
  keyer callback in MainActivity.
flutter analyze: no warnings. flutter test: all 42 pass. Next: install on
63061JEBF01551 and do a quick check of Settings, Echo, the Koch generator
with Stop<Next>Rep, and WiFi Trx.

## Upstream check (2026-09-25)
Compared firmware commits V9.0..origin/master (V9.0.1 + 9.1 beta):
- f98a409 (Echo Think T.) has already been ported.
- 9aae6f6 (the eeee error sign no longer fires on valid e's): not applicable
  yet, because the error-sign reset of the echo answer (8 dits or "eeee"
  clears the answer) was never ported. Done 2026-09-25 with Morsel, using the
  fixed logic.
- Everything else (settings pause, Koch menu nav, TFT repaint, Pocket click)
  does not apply to the app.


## CW Keyer / WiFi Trx word gap, seconds display (2026-09-25), installed on 63061JEBF01551, not yet user-tested
- CW Keyer: status chips at the top removed.
- CW Keyer and WiFi Trx: ⚙ in the app bar with their own InterWord Spc
  (`profile.keyer|trx.interWordSpace`, default 7 dits instead of the Echo
  value 40). InterChar Spc deliberately not offered: the firmware does not
  use it when keying (see DECISIONS.md).
- Every place where InterChar/InterWord can be set (⚙ sheets of Hören/Geben/
  Keyer/Trx, adaptive suggestion rows) now shows the time in seconds at the
  current WPM next to the dits (`ditsToSeconds`, dit = 1.2/wpm).
- Echo ⚙: hint text says the spacing applies to the played word (and the
  start deadline for the answer), not to the answer itself.
- Open: none new. Upstream item (echo error-sign reset) still open.

## Startseite neu gestaltet, Variante A (2026-09-25)

`home_screen.dart`: ruhige Karten ohne farbige Rahmen (Icon-Chip, neutrale Fläche), Abschnitte "Üben" (Hören, Geben) und "Frei" (CW Keyer, WiFi Trx als Mini-Kacheln). Untertitel zeigt Lektion, Tempo und bei Geben den Trend (aus den Profilen bzw. `BlockHistory`), Aktualisierung nach Rückkehr. WiFi Trx in Amber statt Rot (Rot wirkt wie ein Fehler). Installiert, Test durch User offen. Nicht committet.

## Optik der übrigen Screens angeglichen (2026-09-25)

Neu: `widgets/app_ui.dart` (`AppCard`, `AppButton`, `appBarTitle`). Alle App-Bars flach in Hintergrundfarbe mit Space-Grotesk-Titel. Hören (`adaptive_copy_body.dart`): Karten für Abstand und Schwachzeichen, solide Buttons in Blau, Vorschlagszeilen abgerundet, Quote in Space Grotesk. Geben (`echo_trainer_screen.dart`): Start/Stop und Ergebnis-Buttons solide in Violett, Ergebnisliste als Karte. Keyer und Paddles (`paddle_widgets.dart`): Kartenoptik ohne Rahmen. Schwachzeichen in Amber statt Rot. Nicht umgesetzt aus den Mockups: Fortschrittsbalken, Pegelanimation, Dauer-Kachel. Installiert, Test durch User offen, nicht committet.

### Nachtrag Optik (2026-09-25)

Geben-Titel heißt jetzt "Geben"/"Send" (statt "Echo Trainer"). Buttons einheitlich dezent (getönte Fläche, keine Umrandung, `AppButton`), Hören und Geben beide Teal; Keyer Violett, WiFi Trx Amber. Startseite: Space-Grotesk-Titel, Hinweiszeile je Kachel.

## Morsel (backlog #1) + games tile (2026-09-25), installed on 63061JEBF01551, not yet user-tested

- New "Spielen" section on the start page -> `GamesScreen` -> `MorselScreen`.
- Morsel single player per `MorseMorsel.cpp`: 10 words, clue 48 WPM -5 per
  miss (floor 18), reveal letter, green/red/grey boxes, +5 s per guess, skip
  +60 s, idle replay 12 s / back to lobby 60 s, 7-entry high-score table,
  word length options and suggested Koch minimum. Deviations: DECISIONS.md.
- `<err>` (7+ dits) in `MorseDecoder`; Echo Trainer now clears the answer on
  `<err>` and on "eeee" (with the 9aae6f6 fix) — the upstream check's open item.
- New native method `getWordLists` (generator channel).
- Fix: `getWordLists` first sat on the settings channel (Morsel hung on load).
- Added: clue start speed slider in the lobby (10..48 WPM), see DECISIONS.md.
- To test: clue audio, submit pause, `<err>` in Morsel and Echo, skip,
  results/high scores, back button during play, start page layout with 5 cards.
- Fixed separately (see next section): `playWord()` merged prosign letter pairs.

## Fix: prosign merging in generated text (2026-09-25), user-tested OK

- `playWord()` used to play any letter pair equal to a prosign mnemonic as
  that prosign: START as S T <ar> T, the word AS and abbrev BK as prosigns,
  Koch groups like KAS as <ka> S. Affected CW Generator/Koch Trainer, Echo
  targets and previews (WiFi Trx and Morsel use `playPatterns`, unaffected).
- Now a prosign is played only for an explicit `<XX>` token. Random Groups
  (Pro options) generate `<AS>`, `<KA>`, `<KN>`, `<SK>`, `<VE>`, `<BK>`.
- Echo compares/grades against the target without brackets (decoder emits
  "KA"); the target display shows `<ka>` like the firmware. Adaptive Copy
  strips the brackets (per-character display), so a Pro group there now plays
  K A as letters, consistent with how it is shown and graded.
- To test: Words/Abbrevs with START, PARTY, AS, BK; Random Groups "Pro" in
  CW Generator and Echo (prosign audible, Echo accepts keyed prosign).

## Morse Invaders (backlog #4, 2026-09-25), user-tested OK

- Done out of backlog order at the user's request. Second tile in `GamesScreen`
  -> `InvadersScreen` (`lib/ui/invaders_screen.dart`).
- Koch lesson = the sending lesson (`profile.echo.kochLevel`), read-only in the
  game menu (firmware: `kochFilter`, also not changeable there). Keying speed =
  global `wpm` (firmware: `MorsePreferences::wpm`), +/- in menu and in game.
- Game logic 1:1 from `MorseGame.cpp` in firmware units (33 ms frames, 170 px
  field, y 24..262): spawn interval, speeds, max invaders, lane blocking,
  lowest-match rule, score formula (wpm/10 x urgency x streak), extra life
  every 1000, 10 hits per level, +5 per invader cleared at level up, 5 high
  scores (score, Koch, level, wpm). Start level 1..50 (persisted here).
- Sound effects via new `cw_tone` methods `playEffect`/`stopEffect`
  (`CwTonePlugin.kt`); keying cancels a running effect.
- Pause via the app bar or the back button, also when the app goes to the
  background.
- To test: fall speed/feel at level 1 and higher levels, sound effects vs.
  keying, hit detection with the touch paddles, prosign `<AR>` (+) invaders,
  high score table.

## QSO Bot (backlog #7, 2026-09-25), user-tested OK

- New home tile "QSO Bot" under the free section, next to WiFi Trx ->
  `QsoBotScreen` (`lib/ui/qso_bot_screen.dart`). Frontend = the WiFi Trx
  layout (type dropdown instead of the service, Start/Stop instead of Connect,
  status line, WPM slider, RX/TX log, text input, touch paddles).
- Engine `lib/content/qso_bot.dart`: 1:1 port of `MorseQsoBot.cpp` (state
  machine, the three descriptors SOTA/POTA, Standard, Contest), the matcher of
  `MorseQsoBotMatch.h` and the content pools of `qso_content.h`. Difficulty
  (Beginner/Intermediate/Advanced), contest type (CQ WW / WPX-Sprint), own
  call (empty = OE1XXX) in the gear sheet.
- Bot calls: new `randomCallInfo` on the generator channel;
  `CallsignData.kt` now carries the CQ zone per prefix (table re-extracted by
  script from `callsign_prefixes.h`, 973 entries, the old three fields
  verified identical). Region/common-only from the generator's call prefs.
- `MorseDecoder` takes an `unknown` char (QSO Bot: `*` -> `U`, as the
  firmware), so an undecodable char is not a keyed `?` (= repeat request).
- Engine tests: `test/qso_bot_test.dart` (8 simulated QSOs incl. repeat,
  recovery, `<err>`, contest loop).
- To test: full QSOs of all three types keyed with paddles, the 5 s CQ
  opening, word-gap/over-end timing at your speed, agn/rpt/qrs/qrq, bot speed
  mismatch on Intermediate/Advanced, the typed-text input.


## Memory Chain (backlog #2, 2026-09-25), installed on 63061JEBF01551, not yet user-tested

- Third card in the games hub -> `MemoryChainScreen`
  (`lib/ui/memory_chain_screen.dart`), 1:1 port of `MorseMemoryChain.cpp`:
  one new character per round, key the whole chain from memory, boxes as the
  only feedback (no OK/ERR sounds), 12 boxes per row, cap 48 = "Perfect!".
- Modes Characters (Koch lesson, prosigns filtered out, no immediate
  repeat, one tolerated error per round) and Call Signs (random call via
  `randomCallInfo`, revealed letter by letter, completed call shown green
  for 900 ms, any error ends). Prompt Display (big character until the first
  answer) or Sound (at the keyer speed, pitch shifted by Tone Shift like the
  firmware). Pauses 600/900 ms as in the firmware.
- Game-over reveal (fatal box red, rest of the call dimmed), high scores per
  mode (7 rows, rank by primary then secondary), same fields as the firmware.
- Home games tile subtitle now lists Morsel · Invaders · Memory Chain.
- To test: both modes and both prompts, tolerated error vs. second error,
  call with "/", high-score tables, keying during a Sound prompt is ignored.

## Home tiles without hint line (2026-09-25), user-tested OK

- The small grey hint line under each home tile is removed (plus its
  `home_*_hint` strings); with six tiles the column overflowed by ~10 px.
  Tiles show title + subtitle only.
