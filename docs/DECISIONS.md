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

**Changed 2026-09-25:** the bare two-letter lookahead also matched ordinary
letter pairs (START played as S T <ar> T; the word AS and abbrev BK as
prosigns). In text passed to `playWord()`, a prosign must now be an explicit
`<KA>` token — the firmware's own display form (`cleanUpProSigns()` in
m32_v6.ino). The mnemonic keys stay as they are in `morseTable` and the
decoder (which still emits "KA"); Echo strips the brackets before comparing.

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

## `textDisabled` reserved for actually-disabled UI, not secondary text
`AppColors.textDisabled` (`#3A4A60` dark) is nearly invisible against
`background` (`#111827`) — fine for a genuinely disabled control, unreadable
for informational secondary text. Several places (Adaptive Copy's status
line, spacing control, weak-chars section, Koch Trainer panels) had been
using it for text that's always meant to be read. Systematically switched
those to `textMuted` (`#7A8FB5` dark) instead, which is the theme's actual
"secondary but legible" token. Rule of thumb going forward: `textDisabled`
only for controls/values that are truly inactive right now, `textMuted` for
anything the user is expected to read.

## Effective (Farnsworth) WPM shown alongside character WPM
Users set character speed and inter-char/inter-word spacing independently,
but only the character speed number was ever shown — the actual net word
rate (what matters for real-world copy) was invisible. Added
`effWPM = 50 * charWPM / (31 + 4*interCharSpace + interWordSpace)` (PARIS at
standard timing = 50 dit units/word, of which 31 are the marks themselves;
swap in the real spacing counts to get the true word rate). Reduces to
exactly `charWPM` at standard spacing (31+12+7=50), so it's a strict
generalization, not a separate approximation. Shown as "(eff. {ewpm})" next
to the raw WPM everywhere a status line already exists (Adaptive Copy result
+ idle screens, Koch Trainer Classic + Adaptiv start screens) via one shared
`gen_status_line` / `ac_status_line` string pair — no new formula duplicated
per screen. Not present in `reference/` firmware — confirmed via grep before
adding, so this is a net-new app feature, not a porting-fidelity gap.

## `scale` parameter on shared widget-builders instead of forking them
The Adaptive Copy result screen needed larger text than other screens that
reuse the same `_buildSpacingControl()`/`_buildWeakCharsSection()` methods.
Rather than duplicating the widgets or adding a screen-specific font-size
constant, both methods took an optional `double scale = 1` multiplying every
internal `fontSize`; call sites that want the bump pass `scale: 1.2`,
everyone else is unaffected by default. Reused verbatim for the Koch
Trainer's Classic and Adaptiv start screens once those needed the same
treatment — one pattern, three call sites, no drift between them.

## Adaptive Copy's per-character unlock gate: all active chars, not just the newest
`AdaptiveCopyEngine.shouldUnlockNextChar()` requires *every* character in
`kochActiveChars(kochLevel, activeKochChars)` — i.e. every character learned
so far, not just the most recently added one — to individually clear the
occurrences floor and error-rate threshold before the next Koch character
unlocks. This is intentional (docs/ADAPTIVE-COPY.md, "N=20 for character
unlock"), but easy to misread as "stuck"/buggy once the active set gets
large: content selection is a uniform draw over all active chars, so at
Koch level 12 each character gets on average 1/12 of a block's draws, and
the slowest of 12 to individually clear a 20-occurrence floor can
legitimately take many blocks (see docs/ADAPTIVE-COPY.md, "Also investigated
this session, not a bug", 2026-09-23, for a real on-device case diagnosed by
pulling `charStats` off the device). Rather than changing the gate itself
(no evidence it's wrong), added a read-only **Character Statistics screen**
(`lib/ui/char_stats_screen.dart`, linked from Settings → Adaptive Mode) that
lists every active character's attempts/error-rate/ready-state, sorted
least-ready-first, so the actual blocker is visible in-app instead of
requiring a manual SharedPreferences pull to diagnose.

## Switch: Material defaults need explicit theme overrides, not just `activeColor`
Flutter's Material 3 `Switch` has three separately-themed layers — thumb,
track fill, and track outline — and only the thumb dims by default when
disabled; the *off-state* thumb and the track outline both default to a
near-white neutral that doesn't adapt to dark backgrounds on its own.
Setting `activeColor`/`inactiveTrackColor` alone (already in place) left the
off-thumb and the outline still near-white — reported twice by the user
before the outline layer was found. Fixed by also setting
`inactiveThumbColor` and `trackOutlineColor` (the latter via
`WidgetStateProperty.resolveWith`, since the outline needs its own
active/inactive color pair, not a single value) to theme tokens. Worth
remembering for any future `Switch`/`Checkbox`/`Radio` usage in dark theme —
Material's "off" state is not automatically theme-aware just because the
"on" state is.

## WiFi Trx: networking in Dart, MOPP ported from cwForTx, "hi" registration
- **UDP lives in Dart** (`dart:io` `RawDatagramSocket`), not in Kotlin: no
  native code needed, and the engine singleton is untouched except for one
  new generator call `playPatterns`. One socket bound to port 7373 both
  sends and receives (as `audp` does in the firmware), so NAT mappings and
  server replies line up; falls back to an ephemeral port if 7373 is taken.
- **Encoder is a literal port of `cwForTx()`** (m32_v6.ino), including the
  end-of-word-overwrites-end-of-char step-back and `strlen` trimming;
  decoder rejects what the firmware rejects (version != 01, WPM outside
  5..60, first element 00). Unit-tested against the PARIS@16 example in the
  protocol doc (`test/mopp_test.dart`).
- **Playback uses raw patterns, not text** (`CwGenerator.playPatterns`):
  going through text would turn K+A into the prosign KA (mnemonic
  convention, see rule 3).
- **Deviation:** the firmware sends the keyer-decoder's measured WPM for
  straight key; we send the configured WPM.
- **Registration:** per the Morse-Code-over-IP chatserver README, a client
  registers by sending "hi" at 20 WPM; the server sends empty keepalives
  every 10 s and ":bye" when dropping a client. Taken from a web summary of
  that README, not from the firmware — verify against cq.morserino.info.
- **`INTERNET` permission** added to the main manifest (previously only
  present via Flutter's debug/profile manifests).
- Connection only lives while the WiFi Trx screen is open (no foreground
  service yet).


### WiFi Trx: no automatic registration packet
The automatic "hi" on connect was removed: other services use other commands. Users type what their service expects. Services and logs are stored in prefs (`trxServices`, `trxLog_<id>`); WPM in `trxWpm`. Per-service configurable login commands are a possible later step.

### Keyer word gap follows the InterWord Spc pref
Firmware keyer/Trx modes end a word (m32_v6.ino interWordTimer) (InterWord Spc − 1) dits after a character ends. The app hard-coded 6 dits. `CwKeyer.wordGapDits` is now set via `setInterWordSpace` (KeyerScreen, WiFi Trx; Echo Trainer pushes 7 = old behaviour). Straight key path unchanged (7 dits from key-up; firmware uses the decoder there). Note: app default for `interWordSpace` is 40, firmware default is 7.


### Echo Trainer: Gebe-Tempo (Echo Speed Max) and self-synced prompt config
Training rollout Phase 1 (`docs/training/P1-echo-grundlagen.md`). The answer is expected at min(prompt WPM, `echoAnswerWpmMax`); 0 = same as prompt. Firmware semantics (`m32_v6.ino` 2553-2561, 3166-3171) but 1 WPM steps and a new pref key, so the old `echoSpeedMax` (cap for Adaptive Speed) is not reinterpreted. The keyer WPM is now set per answer (`_applyAnswerConfig`), and the generator's WPM/spacing/Practice Set/Boost per prompt (`_applyPromptConfig`) — the Echo screen previously inherited them from whichever screen ran last (rule 2). Adaptive Speed is intentionally untouched until phases 5/6 (block-based like Adaptive Copy, own profile).


### Training profiles: separate settings for Hören (`hear`) and Geben (`echo`)
Training rollout Phase 2 (`docs/training/P2-trainingsprofile.md`). Per-training values (wpm, kochLevel, groupLength, randomOption, maxWords, wordLengthMax, abbrevLengthMax, interCharSpace, interWordSpace, practiceChars, boostLevel) are stored as `profile.<hear|echo>.<field>` (`lib/content/training_profile.dart`). One-time migration (`profileVersion=1`) copies the old globals into both profiles; the globals stay in prefs untouched (rollback) but are no longer read by the trainings. Keyer and WiFi Trx keep the global `wpm`. Koch sequence stays global, only the lesson is per profile; spacing is per profile. Settings screen has a temporary Hören|Geben switch for the profile-backed fields (to be removed in Phase 3 when settings move into the training screens). Auto-detected weak chars (`CharStatsStore`) are still shared until Phase 4.


### Training settings live in a shared ⚙ sheet on each training screen
Training rollout Phase 3 (`docs/training/P3-einstellungen-in-screens.md`). One `TrainingSettingsSheet` (`lib/ui/widgets/training_settings_sheet.dart`) serves Generator/Koch, Adaptive Copy (hear profile) and Echo (echo profile); it saves immediately to the profile/global prefs and the screen reloads them on close (native pushing stays in the screens, rule 2). ⚙ only in the setup state. The temporary Hören|Geben switch and all moved sections are gone from the global Settings; adaptive thresholds stay global keys but are edited in the Adaptive Copy sheet; character stats view/reset stays global. Practice Set groups are capped by the word-length setting; Echo now passes word/group length to the engine.


### Character statistics: separate tracks for Hören and Geben, shown inside each training
Training rollout Phase 4 (`docs/training/P4-zeichenstatistik.md`). `CharStatsStore(track)` persists to `charStats.hear` / `charStats.echo`. One-time migration in `load`: the old single `charStats` (or the even older `adaptiveWeights`) becomes the hear track; the echo track starts empty (its data would be hearing weaknesses). Adaptive Copy and the Koch generator use hear, the Echo Trainer ("Adapt. Rand.") uses echo; echo still records only in that mode. `CharStatsScreen(track)` is opened via 📊 in the Koch generator / Koch echo title bar (no tabs, no entry in global Settings), with a per-track reset. The echo view has no unlock display (weakest characters first).


### Echo Trainer: optional block flow with result page (display only)
Training rollout Phase 5 (`docs/training/P5-echo-bloecke.md`). Profile field `profile.echo.blockFlow` (0 = classic, default; 1 = blocks), chosen in the Echo ⚙ sheet. Block size is the profile's `maxWords` (0 → 10, sheet label "Wörter pro Block", 1..50); learn/preview targets (`fixedTarget`) never use blocks. Per word the screen records `WordResult` (target, first attempt, attempts, outcome first/afterRepeat/failed, first wrong index). The result page shows the first-try rate only (● counts, ◐ "right after repeat" is shown separately and not folded into the percentage — whether it becomes a half hit is decided in Phase 6; failed/revealed words count as wrong). `+` is played at block end; stopping mid-block discards the block. No suggestions, trend or stats changes yet.


### Classic flow is retired: adaptive becomes the default
User decision 2026-09-25 (training rollout, before Phase 6). The classic (firmware-style endless) flow gets no more work. From Phase 6 on, new features (suggestions, stats weighting) apply to the block flow only. Phase 7 removes the classic flow in all sections (Echo, Generator, settings, Adaptive Speed pref) and makes the adaptive/block flow the default. Until then classic stays as is.


### Echo Trainer: adaptive suggestions on the block result page
Training rollout Phase 6 (`docs/training/P6-echo-vorschlaege.md`). Block flow only. Stats "Geben" are booked once per word after the first attempt in all echo contents except learn/preview (`CharStatsStore.recordWord`: first wrong char +4, neighbours +2, right word -1 per char, weights 1..20; chars before the error count right, after it not counted). Suggestions come from `evaluateEchoBlock` on top of `AdaptiveCopyEngine`, using the first-try rate only (right-after-repeat is not a hit) and the shared global adaptive thresholds: new Koch char, spacing tighter/wider, Hör-WPM +1, Gebe-Tempo +1 (only with a cap below Hör-Tempo, default unticked), weak-char chips (boost for one block). Tempo rises are blocked while Koch chars are still open and in the block that adds a char; widening is not. Block EMA is stored globally as `echoBlockEma`. Accepted values are applied on "Nächster Block"/"Beenden".


### Training: Koch is a character set, start page has Hören and Geben, classic flow removed
Training rollout Phase 7 (`docs/training/P7-zeichenvorrat-startseite.md`, approved 2026-09-25). Hören (CW Generator) and Geben (Echo Trainer) each choose a character set (Koch lesson / all characters / practice set) and a content (random, words, abbreviations, call signs, mixed), stored per profile as `charset` and `content`; "Koch Trainer" is no longer a start card and Echo's "Adapt. Rand." is no longer a content (Koch + random always weights by weak chars in the block flow). Firmware basis: `kochActive` is only a character filter plus weighting. Koch sequence stays global, lesson per profile. Tapping a Koch char offers "Anhören"/"Mit Echo üben" (replaces Learn New/Preview buttons). Settings sheet shows only sliders that fit the chosen content. Classic flow is removed in Hören and Geben (incl. Adaptive Speed pref, display modes, each-word-twice, stop-after-word); the per-word echo flow stays. The paddle choice repeat/next is dropped for now and to be re-offered in the Hören block flow in Phase 8. Adaptive Hören for "all characters"/practice set has no unlock/boost/tempo lock (Koch only).


### Echo Think Time: grace period for starting the answer only (firmware fix 2026-09-15)
Training rollout Phase 8. Reference for this spot is `origin/master` commit `f98a409` ("Echo Think T. no longer delays the next prompt"), which is newer than the pinned V9.0; the submodule stays pinned. Before, the app restarted a silence timer of the full think time after every symbol, so every answer was followed by the think time again. Now (`echo_trainer_screen.dart`): the answer must begin within 1400 ms + inter-char + inter-word/3 (at the prompt speed) + think time after the prompt ends; without a first symbol the word is evaluated (wrong). Once the answer has begun, think time no longer applies: the word is evaluated when the keyer reports the word gap (`"  "`), with a fallback timer of max(3 s, 20 dits at the answer speed). Paddle choice repeat/next in the Hören block follows the firmware `Stop<Next>Rep` per group (profile field `stopEach`, default off); the Geben block has none, as in the firmware. Block trend (`blockHistory.<track>`): mean of the last 5 block rates against the 5 before, ▲/▼ from ±3 points, shown from 6 blocks on.


### Reaktionszeit dropped from Phase 8
User decision 2026-09-25: no reaction-time measurement. Depends on too many unrelated factors, no firmware equivalent, and the think time already covers slow starts. Echo also shows "Versuch n von max" from the second attempt and clears stale word/attempt text when a block starts.

## 2026-09-25: Firmware games are in scope (single player)
User decision: the games get ported, which reverses the earlier "out of scope"
in PORTING-MAP.md. They train the same skills (hearing, keying, Koch set),
and most of them build on parts the app already has: word lists, the Koch
set, the keyer, the decoder. Their multiplayer runs over ESP-NOW, which does
not exist on a phone, so it is left out. A replacement via our own server
would be a separate project. High scores go to SharedPreferences instead of
NVS. Order: Backlog in docs/STATUS.md.

## 2026-09-25: Practice Stats are not ported
The firmware's `MorsePracticeStats` (listen/send statistics) is not ported,
and it stays that way. The app has its own statistics, built for the block
flows: per-character stats for Hören/Geben with firmware weighting (Phase 6),
block result, block trend and confusion pairs (Phase 8). In this form they
fit the app better. A second, firmware-like stats layer would duplicate them
without adding anything.

## 2026-09-25: CW Keyer and WiFi Trx get their own word gap

CW Keyer and WiFi Trx each keep a `profile.keyer|trx.interWordSpace` (⚙ in
the app bar, section `wordSpacing`), default 7 dits (firmware default). The
Echo/Hear value no longer leaks into them (it was 40, i.e. ~2 s at 20 WPM).
Only the word gap is offered: the firmware keys with
`interWordTimer = (InterWord Spc - 1) * dit` (m32_v6.ino:1857) and never uses
InterChar Spc when keying; Trx playback spacing derives from the received
speed. The status chips at the top of the CW Keyer were removed.

## 2026-09-25: Einheitliche Optik (Startseite Variante A)

Flache Karten ohne Rahmen, getönte Buttons (`widgets/app_ui.dart`), Space-Grotesk nur für Titel (OFL, `assets/fonts/SpaceGrotesk.ttf`), Monospace für Inhalte. Farben: Hören/Geben Teal, Keyer Violett, WiFi Trx Amber. Rot bleibt Fehlern vorbehalten (Grund: Rot wirkt wie ein Fehler).

## 2026-09-25: Morsel port — deviations from MorseMorsel.cpp

- **Games hub:** the start page gets a "Spielen" section with one "Spiele"
  tile leading to `GamesScreen`; each ported game is a card there.
- **Koch lesson:** starts at the Geben (echo profile) lesson; changes in the
  lobby apply to this visit only, like the firmware restoring `kochFilter`
  on exit. Koch sequence is the global one.
- **Word pool:** only words of letters/digits (a guess can hold nothing else),
  otherwise the same length and Koch filter.
- **Clue audio:** sent as per-letter patterns (`playPatterns`), not text:
  `playWord()` reads letter pairs such as AR/KN/AS inside a word as prosigns
  and drops the letter gap. The keyer is off while the clue plays (shared
  sidetone), so keying cannot cut the clue short as on the device.
- **Submit pause:** max(1200 ms, (keyer word gap + 1) dits at the keyer speed),
  the firmware's `interWordSpace + ditLength`, floor 1200 ms.
- **`<err>`:** the app decoder now emits `MorseDecoder.err` for 7+ dits, as in
  the firmware tree (`MorseDecoder.h` nodes 65/66). Morsel deletes the last
  letter; the Echo Trainer clears the answer, and a fourth "e" in a row counts
  as `<err>` unless it still continues the target (upstream fix 9aae6f6).
- **Controls:** encoder speed/volume -> -/+ for the keyer speed (saved as the
  global `wpm`), volume via the phone. Click = Skip button, long press = back.
- **High scores:** 7 entries in SharedPreferences `morselHi` (JSON), word
  length in `morselWlen`.
- **Clue start speed (app only):** the firmware fixes it at 48 WPM
  (`MSL_START_WPM`). The user found that far too fast, so the lobby has a
  start-speed slider 10..48 (default 48, `morselStartWpm`). Schedule stays
  -5 WPM per miss down to 18; a start below 18 stays at the start speed.
  High-score rows store the start speed and show it as a WPM column.

## 2026-09-25: Morse Invaders port — deviations from MorseGame.cpp

- Koch lesson: the sending lesson (Echo Trainer profile), since the game is
  pure keying (user's call). The firmware has only one global `kochFilter`.
- Extra life: the firmware keeps `nextLifeAt` in a function-static that is
  never reset, so later games in one session earn their first extra life
  late. Reset per game here.
- Start level is persisted; the firmware resets it to 1 on every entry.
- No character rotation option (`posInvaderOrient`): it exists for holding
  the Pocket sideways, irrelevant on a phone.
- Drawing is scaled: x from the 170 px width, y maps the fall path onto the
  available height, so fall times match the device. Game logic keeps the
  firmware units.
- Sound effects: new `playEffect` on the tone channel; keying cancels them in
  `CwTonePlugin.setPlaying`, like `updateSound()` dropping the effect when the
  keyer leaves IDLE.
- Game over offers "Play again" / "To menu"; exiting the whole game is the
  normal back navigation from the menu.

## 2026-09-25: QSO Bot port — deviations from MorseQsoBot.cpp

- Frontend is the WiFi Trx screen layout (user's call), not the firmware's
  keyer scroll display: bot overs are RX lines (shown one character ahead of
  the audio, like `emitNextBotChar`), keying is TX, status texts are info
  lines.
- Engine is UI-free Dart driven by a 20 ms timer (firmware: main loop with
  `delay(2)`). Timeouts, retry budgets and difficulty scaling are unchanged.
- Decoded input is converted to the firmware's `encodeProSigns()` form before
  the matcher: letters lowercase, prosigns as uppercase codes (`<sk>` -> K,
  `<err>` -> R, unknown -> U). Needed because the matcher tells `<err>` from
  the letter r by case.
- Sign-off `K` (uppercase = `<sk>` in the firmware) is written as `<sk>` in
  the templates (CLAUDE.md rule 3). All other template texts are verbatim.
- Bot playback via the generator's `playOne` at the bot's speed; no
  Farnsworth (the app's generator has none in `playOne`). The user's keying
  is not blocked while the bot sends; audio overlaps instead of the firmware
  pausing the bot's tick-driven playback while a paddle element is keyed.
- Own call: new pref `qsoMyCall` (the firmware reads `playerCall`, set in Fight
  the Pileup, which is not ported yet). WPM: own `qsoBotWpm` (default global
  `wpm`), like WiFi Trx's `trxWpm`. Word gap: the CW Keyer's
  (`profile.keyer.interWordSpace`), as the firmware uses the global value.
- Extra: a text field feeds typed words to the bot as if keyed (no audio),
  kept from the WiFi Trx frontend.
- Bot callsigns come from a small prefetched pool (native call is async);
  if it is empty, a plain random EU call is used.


## 2026-09-25: Memory Chain port — deviations from MorseMemoryChain.cpp

- Koch lesson starts at the Geben (echo profile) lesson; lobby changes apply
  to this visit only, like Morsel (the firmware writes `kochFilter` back).
- Lobby uses chips and a Start button instead of encoder/FN and the
  "key to start" gesture; speed is a +/- in the play screen (firmware:
  encoder). No in-game volume control (system volume).
- Sound prompt: the keyer is stopped while the prompt plays and restarted on
  the generator's 'done' (shared sidetone), which also discards keying during
  playback like the firmware's `clearPaddleLatches()`.
- Settings persisted as `memChainOpt` (bit 0 calls, bit 1 sound, as the
  firmware's `mcopt`); high scores as JSON in `memChainHi` /
  `memChainHiCalls`.
- Undecodable patterns and `<err>` count as a wrong answer (any keyed
  character is judged, as in the firmware).

## 2026-09-25: CW decoder via microphone — deviations from goertzel.cpp / MorseDecoder.cpp

- **Split:** Kotlin only captures PCM (`MicInput.kt`); Goertzel and the
  decoder run in Dart on sample time, so they are unit-testable with
  synthesized audio and behave the same live and in tests.
- **Sample rate 16 kHz** instead of 11905 Hz; block length chosen to keep the
  firmware bandwidths (Wide ~700 Hz = 23 samples, Narrow ~175 Hz = 91).
- **Adjustable pitch** (firmware: fixed 698 Hz, the line input is tuned to
  it). The Goertzel uses the exact frequency, not the nearest integer bin.
- **Normalized magnitudes + user threshold:** the firmware's fixed ADC-scale
  `magnitudelimit_low` becomes a floor in dBFS (default -40) with a level
  meter; a phone microphone's level varies far more than the device's line
  input. The automatic limit itself is unchanged, so with constant noise
  above the floor it follows the noise (as on the device).
- **Monitor tone default off:** the device always plays the decoded tone on
  its speaker; on a phone the microphone would pick it up again (feedback).
- **Audio decoder only:** the firmware's decoder mode also decodes a straight
  key on the paddle jack (keyDecoder); not ported, the keyer is stopped on
  this screen. Output is always uppercase (the app's convention), prosigns
  as the tree shows them (`<KA>`), `<err>` is shown, not applied.

## Build identification (2026-09-26)

The app now goes to other users, so each APK must be traceable to a source
state. `app/build.gradle.kts` runs git at build time and stamps
`BuildConfig.GIT_SHA`, `GIT_DIRTY` and `BUILD_TIME`; `versionCode` is the git
commit count (monotonic without manual bumping; falls back to the pubspec
build number outside a git checkout). `versionName` still comes from
`pubspec.yaml` and is bumped by hand per release, with a matching `vX.Y.Z`
git tag. Shown in Settings → Info via the settings channel (`getAppVersion`).
Builds meant for others: `flutter build apk --release` from a clean, tagged
tree (Commit must not show `-dirty`). Release builds are still signed with
this machine's debug key — fine for sideloading, but updates for recipients
must be built on this machine (or with the same keystore).

## User manual: Markdown sources, both languages, built like the firmware's (2026-09-26)

The app now reaches other users, so it gets an end-user manual in `manual/`,
modelled on the Morserino-32's own (`reference/Documentation/User Manual/`):
Markdown sources per language (`manual_de.md`, `manual_en.md`), built with
pandoc → HTML → weasyprint → PDF by `manual/build.sh`, and the built HTML/PDF
committed so they can be handed out next to the APK. EPUB is available from
the script but not committed. The title page is stamped with the pubspec
versionName and the git commit, the same identifiers Settings → Info shows,
so a manual can be matched to an APK.

Written from the code, not from the firmware manual (no text copied from it;
it is CC BY 4.0 but the app's behavior differs in many places). Detail level
follows the firmware manual: every setting with range and default; the
adaptive mode is spelled out with its actual formulas and constants (per-char
EMA α = 0.2, block EMA with the user's α, 70/90 % thresholds, 2-block
hysteresis, 20 occurrences, weak = ≥ 8 attempts and ≥ 12 %, no tighten/speed-up
while Koch chars are still open), so users can see why a suggestion appears.

Rule (CLAUDE.md rule 10): every user-visible change updates both languages in
the same change and rebuilds; `build.sh` fails on broken internal links so a
renamed heading can't silently break cross-references. Headings that pandoc
can't turn into a clean ID (e.g. containing ⚙) carry an explicit `{#id}`.

**Screenshots (2026-09-26):** separate DE and EN screenshots (the UI text
differs), light theme (reads better in print), status bar cropped, 540 px
wide, quantized to 128 colours so the 64 images stay ~2 MB in git. Single
screenshots float beside the text, 2–3 related ones sit side by side with a
caption. Taken from the real app on the phone via adb (`manual/tools/`):
accessibility labels for navigation, the learned paddle keycodes (113/114)
for keying. `input keyevent` jitter makes keying reliable only at ~8 WPM, and
the `monkey --port` server does not work on this phone. The HTML embeds the
images (`--embed-resources`) so it stays a single file to hand out.

## Listen: Boost Practice merged with the weak-character boost (2026-09-26)

Before, a Listen block overwrote the generator's practiceChars/boostLevel with
the weak chars (level 1, or 0 when there were none), so the profile's Practice
Set + Boost Practice never applied in Listen. Now `AdaptiveCopyBody` pushes the
**union** of the profile's practice chars and the included weak chars, at
`max(ownLevel, weak ? 1 : 0)`, where ownLevel counts only if the practice set
is non-empty (a level without chars must not push weak chars to Strong on its
own — Strong was too extreme per 2026-09-23 feedback).

Chosen over "practice set first, weak chars only if room" (the native boost is
a re-draw weighting with no slots, so "room" has no meaning) and over a profile
switch picking one of the two (extra setting, and the two don't conflict).
Trade-off: a larger combined list dilutes the boost per char; weak chars can
still be tapped out. Words/abbreviations stay unboosted, as in the generator.

## Manual: HTML/PDF and screenshots only per release (2026-09-27)

Rebuilding HTML/PDF (~3 MB PDFs per language in git) and retaking
screenshots via adb on every user-visible change was too much overhead per
the user. Rule 10 now splits it: the Markdown sources (`manual_de.md`,
`manual_en.md`) are still updated in the same change, both languages; the
build (`manual/build.sh`) and the screenshot retakes happen only when an
official `vX.Y.Z` is cut. Screens that changed in between are tracked in
`docs/STATUS.md` → "Manual: pending for next release", so nothing is
forgotten at release time. Side effect: the committed HTML/PDF always match
the last release (their title page already names version + commit), which
is what gets handed out next to the release APK anyway. Broken internal links
are now caught at release build instead of per change.

## UI terminology glossary (2026-09-27)

Prompted by outside feedback (Sia): the Word selection card said
"Gruppen-Länge" and "Wörter pro Block" for the same unit, and a sweep found
the same kind of drift across the app (three words for sending speed, two for
high scores, "Punkte" meaning both dits and score, ~40 hard-coded English
labels showing in the German UI). This glossary is binding for new UI text
and for `manual/manual_{de,en}.md`; check it before adding a string.

**Firmware menu names are translated, not copied** (user-confirmed
2026-09-27 over "all English" and "translated label + firmware name as
hint"). Supersedes the earlier
convention (manual intro) of showing Morserino menu names like `Interchar
Spc`, `Random Groups`, `Echo Prompt` verbatim in English: it was applied to
only half the settings (`Tone Shift`, `Max # of Words`, `Echo Repeats`,
`Length Rnd Gr` were already translated), which is exactly what made the UI
inconsistent. The firmware name now appears once in the manual's mapping
table (`Morserino-Begriffe` / `Morserino terms`), so M32 users can still
find their way. Exceptions kept verbatim because they are proper names:
keyer modes (Iambic A/B, Ultimatic, Non-Squeeze, Straight), Koch sequence
names (M32, LCWO, CW Academy, LICW), CurtisB, product/screen names (CW
Keyer, Echo Trainer, QSO Bot, WiFi Trx, Morsel, Morse Invaders, Memory
Chain, vband), WPM, Koch, prosign mnemonics.

| Concept | Deutsch | English | Not |
|---|---|---|---|
| Unit between two word gaps | Wort | word | — |
| …when content is purely random characters | Gruppe | group | "Wort" for random groups |
| Label counting those units | „Gruppen pro Block“ (Zufall) / „Wörter pro Block“ (sonst) | Groups / Words per block | fixed "Wörter" |
| Length of a random group | Gruppenlänge | Group length | Gruppen-Länge, "(Zufall)" suffix |
| Receiving training area / activity | Hören | Listen (area), listening (noun) | hearing |
| Sending training area / activity | Geben | Send (area), sending (noun), key (verb, paddle action) | Senden (DE) |
| Speed of your own sending | Gebetempo | sending speed | Gebe-Tempo, Geben-Tempo, answer/keying speed |
| Speed of what is played | Tempo / Hörtempo | speed / listening speed | Hör-Tempo |
| Time unit | Dit (Pl. Dits), Dit-Länge | dit(s) | Punkte |
| Pause between characters | Zeichenabstand | character spacing | Interchar Spc |
| Pause between words | Wortabstand | word spacing | InterWord Spc, Wortpause (as a setting name) |
| The call sign | Rufzeichen | call sign (label: "Call signs"; "Calls" only in compact game tables) | Callsigns, Call Signs |
| Adaptive block flow | adaptiver Modus | adaptive mode | Adaptive Copy, Adaptiv, Adapt. Rand. |
| Own character selection | Übungsset | practice set | Practice Set (DE) |
| Weighting it up | Übungsset bevorzugen: Aus/Mäßig/Stark | Boost practice set: Off/Moderate/Strong | Boost Practice |
| Order of Koch characters | Koch-Reihenfolge | Koch sequence | — |
| Echo prompt mode | Vorgabe: Ton/Anzeige/Beides | Prompt: Sound/Display/Both | Echo Prompt |
| Characters used in random groups | Zeichen für Gruppen | Group characters | Random Groups |
| Game score list | Bestenliste | High scores | Highscores (DE) |
| Start/stop buttons | Start / Stopp | Start / Stop | English in DE UI |

**Style rules.**
- German compounds without hyphen (Gruppenlänge, Gebetempo, Tonversatz),
  hyphen only next to abbreviations/foreign parts/names (Koch-Lektion,
  Dit-Länge, CW-Decoder, Paddle-Tasten, Start-Level). "z. B." with space.
- English: sentence case for all labels, buttons and section headers
  ("Next block", "Tone softness"); ALL CAPS only where the design uses it
  on purpose (status lines, big buttons). American spelling ("practice" as
  verb too).
- No redundant scope suffixes like "(Zufall)", "(nur Wörter)", "(Echo)" when
  the surrounding section or "Gilt für" hint already says it.
- All user-visible text goes through `Strings.t()`; a literal in a widget is
  only OK for the proper names listed above.

## Koch character tap: playback tile, long press for echo (2026-09-27)

Replaces the Anhören / Mit Echo üben bottom sheet (P7 decision 6), per Sia's
suggestion, user-confirmed: tap plays the character 3× with an overlay tile
(character + code, elements light up in sync); long press opens the echo
drill directly. The tile closes after the last repetition; a tap anywhere
or Back cancels at once (user-requested). Cancel uses a new generator method
`stopOne` (generator.stop() only), because the existing `stop` also
restarts the keyer, which the Geben start screen keeps stopped.

The row shows the whole Koch sequence; characters beyond the lesson are
dimmed but tap/long press still work (user request), so one can listen ahead.
Only the display changed: content generation still uses kochActiveChars().

**Long press → CharPracticeScreen** (user request, replaces the Echo
Trainer's fixedTarget drill, i.e. the port of Learn New Chr / Preview Char).
The character replays in a loop (user-corrected: no tap-to-replay). After
each play a pause runs, its own setting `charPracticePause` (1–20 s, default
4 s, gear icon on the page). First tried with the Echo Trainer's start
deadline (1400 ms + inter-char + inter-word/3 + Echo Think Time), but that is
~12 s at the defaults, too long here, and needs vary per person (user
feedback); a separate key keeps Geben's think time untouched. Keying back
within the pause is optional. A keyed character gets right/wrong feedback (and the confirm tone
if enabled), then replays after 1.2 s / 1.5 s as in the Echo Trainer;
silence replays after 400 ms, like the firmware's KOCH_LEARN/KOCH_PREVIEW
empty-answer branch. Nothing is counted or written to CharStatsStore/block
history. The keyer is stopped
while the prompt plays so prompt and keying never overlap. Settings come
from the Geben profile (wpm, answer speed cap) and the global keyer/tone
prefs, pushed on entry (rule 2).

**Element events.** `CwGenerator.playChar()` fires `onElement(idx, on)` at
each element's key-down/key-up; MainActivity forwards them on the generator
event channel as `elementOn`/`elementOff` (value = element index within the
character). The display is driven by these rather than by Dart-side timing,
so it cannot drift from the audio. Emitted in every mode; existing
listeners ignore unknown types.

**One stream per channel.** A second `receiveBroadcastStream()` on the same
EventChannel replaces the first one's platform message handler, so only the
newest subscriber receives events. `char_playback_overlay.dart` therefore
shares one stream between the tile and `playCharThrice()` (found on device:
the tile stayed grey).


## Echo answer word end follows the spacing settings (2026-09-27)

User report: with group length 2 the answer was scored after the first
character when pausing briefly. Cause: the Echo Trainer pushed a fixed
`setInterWordSpace 7` (6 dits after character end, ~0.4 s at 18 WPM), far
tighter than the firmware. Firmware, `m32_v6.ino` keyer IDLE path, echo
branch: `interWordTimer = 2*interCharacterSpace + ditLength +
interWordSpace/8`, with `interWordSpace = max(IW, IC+4)` from
`updateTimings()`; its comment says this is meant to allow longer pauses
between characters "like in listening". Straight key goes through
`MorseDecoder.cpp` (INTERCHAR_), where echo mode uses `lacktime = IW + 1`
dits from key-up.

The app now does the same with the Geben profile's IC/IW:
`_answerEndDits = round(2·IC + 1 + max(IW, IC+4)/8)` for the paddle keyer
and `IW + 1` for the straight key, pushed in `_applyAnswerConfig()` before
every answer (an accepted spacing suggestion changes IC/IW mid-session).
Dits are at the answer speed (the firmware has only one speed; the keyer
measures in its own dits). No separate setting: the existing spacing
sliders now also govern the answer, and adaptive spacing makes the answer
stricter over time. The answer safety timer is raised to that gap + 20 dits
(min 3 s) so it never fires first.

`CwKeyer.straightWordGapDits` (was hard-coded 7) is new, set via
`setStraightWordGap`. `setInterWordSpace` resets it to 7, and the Echo
Trainer pushes `setInterWordSpace 7` on dispose, so other screens don't
inherit the long echo gaps (rule 2). Supersedes the "Echo Trainer pushes 7 =
old behaviour" note in the keyer word-gap entry above.

## Gebetempo floor 10 WPM (2026-09-27)

User request: 5 WPM as the lowest answer speed is uselessly slow. The
Gebetempo cap (`echoAnswerWpmMax`, 0 = same as Hören) now starts at
`kGiveWpmMin = 10` (lib/content/echo_suggestions.dart) on the Geben start
page slider, the ⚙-sheet slider and the −/+ stepper on the result page. The
sliders' leftmost notch (9) stands for "same as Hören". Stored values 1–9
are raised to 10 on load (`kGiveWpmCap`). App-only setting, no firmware
counterpart to check against.

Extended the same day (user request): the listening speed of Hören and Geben
also starts at 10 (`TrainingProfile.minWpm`, `clampWpm()` on load; also the
home tiles, CharPracticeScreen and the ⚙ sheet's seconds display);
`kGiveWpmMin` now refers to it. CW Keyer, WiFi Trx, QSO Bot and the games
keep 5–60.
