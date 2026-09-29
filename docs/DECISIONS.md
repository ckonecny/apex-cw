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

## No local identifiers online (2026-09-28)
The device serial of the test phone had been written into STATUS.md,
ADAPTIVE-COPY.md and CLAUDE.md on every "installed on …" line, and every
release APK contained this Mac's home path: Flutter compiles the absolute path
of `.dart_tool/flutter_build/dart_plugin_registrant.dart` into `libapp.so`
(the old v0.1.0 debug APK even every pub-cache path). `--obfuscate
--split-debug-info` does not remove it (tested). Now:
- Docs say "the test phone"; the serial lives in the gitignored
  `CLAUDE.local.md`.
- `tools/githooks/` (install per clone with `tools/githooks/install.sh`):
  pre-commit, commit-msg and pre-push hooks reject any string listed in
  `.git/info/forbidden-strings` (local, never pushed, so the list itself
  doesn't leak). Currently: the serial, the home path, the user name.
- `tools/build_release.sh vX.Y.Z` clones the tag to `/tmp/nct-release`, builds
  there (the path in the APK becomes `/private/tmp/nct-release/...`), and
  refuses the result if the APK contains `$HOME`, the user name or a forbidden
  string. v1.1.0 and v1.2.0 APKs on GitHub were rebuilt this way from their
  tags (same versionCode) and replaced.
- Not rewritten: git history still has the serial in old commits (harmless
  identifier; a rewrite needs a force-push).

## Licence: GPL-3.0
2026-09-28. The Morserino-32 firmware is GPL-3.0-or-later (header of
`m32_v6.ino`, `reference/Software/LICENSE`). The app ports not just ideas but
data tables (word lists, abbreviations, call sign prefixes, QSO texts) and
closely follows the code, so it is treated as a derivative work and released
under GPL-3.0-or-later too; the repo had no licence before. Consequences:
source stays public (repo made public on GitHub 2026-09-28, before that
the licence page linked to a private repo — the one gap), every APK carries the licence texts (Settings → Info →
Licences via `showLicensePage`, entries registered in `lib/licenses.dart`).
The GPL text is bundled as `assets/licenses/GPL-3.0.txt`, a copy of the root
`LICENSE` (a test keeps them identical — Flutter assets can't live outside
`android/`). Third-party parts keep their own licences: Zork story files MIT
(Microsoft 2025), fonts SIL OFL 1.1 (texts from google/fonts), Flutter packages
MIT/BSD/Apache — all GPL-compatible. "Zork" is a trademark not covered by the
MIT licence: used only descriptively, never in app name/icon/store title, with
a non-affiliation note.

Guard (2026-09-28, user request: warn before anything that contradicts the
licence, keep all licence references current): CLAUDE.md rule 11 plus
`test/license_compat_test.dart`, which runs with every `flutter test`:
- each pub package's LICENSE (Flutter SDK packages: the SDK's) must match a
  GPL-compatible licence (MIT, BSD, Apache-2.0, zlib, ISC, MPL-2.0, LGPL,
  GPL-3.0, OFL-1.1, Unlicense) and contain no incompatible terms (Commons
  Clause, BSL, SSPL, Elastic, non-commercial, "Good, not Evil", CC-ND);
- every file under `assets/` must sit under a prefix mapped to a licence
  entry registered in `lib/licenses.dart`;
- Gradle `implementation(...)`-style libraries must be on an allow-list
  (empty today).
Text heuristics, so the test is a tripwire, not a legal review: a pass
doesn't replace reading the licence when adding something. Bundled
sub-libraries a package's LICENSE doesn't mention are checked by hand: SoLoud
inside flutter_soloud (zlib; decoders public domain/MIT-0) is on the licence
page as its own entry.

## Default custom Koch sequence: "Heinz – just me" course order
The Custom Koch Sequence default `esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?` is
the order of the YouTube Morse course by "Heinz – just me"
(https://www.youtube.com/watch?v=WhjCvgC0iHg&list=PLZjVloEmSdLgGGT_exNDoXzmnV-q0zmET),
chosen by the author. Credited in both manuals (Koch sequence section) and the
README credits (2026-09-28).

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
Builds meant for others: `tools/build_release.sh vX.Y.Z` (since 2026-09-28,
see "No local identifiers online"), which builds the tag from a clean clone
(Commit must not show `-dirty`). ~~Release builds are still signed with
this machine's debug key~~ — superseded 2026-09-28 by "Play Store
preparation" (upload key).

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

## Hören: typing mode with an own on-screen keyboard (2026-09-27)

App-only extension, no firmware counterpart. Concept + mockups:
https://claude.ai/artifact/733FKS7KDyoeJyiu1nmctd (private). All points
confirmed by the user on 2026-09-27:

- **Mode choice:** the Hören start page gets two start buttons, **Papier**
  (today's flow, unchanged) and **Tippen**; the last used one is filled.
  "Nächster Block" stays in the current mode; switching only via the start
  page.
- **Flow:** one word/group per step (same mechanism as "Nach jeder Gruppe
  anhalten"). Typing is accepted from the first tone; the check runs after
  the word has finished: automatically once the input has the word's length
  (+0.4 s in which ⌫ cancels) or earlier with ⏎. Right: ✓, next after ~1 s.
  Wrong: the word is replayed at once, empty field, first attempt shown
  small and struck through (no hint where the error was). After the last
  attempt or **Passen**: solution 2 s, then next. Timings as in Geben.
- **Attempts per word:** ⚙-sheet setting 1–3, default 2 (1 = no retry).
- **Passen** is a fixed key bottom left, available in every attempt (in the
  first attempt = "nothing recognised"); ⏎ wide bottom right. No confirm
  dialog. No "hear again" button; the replay is the second attempt.
- **Keyboard:** own widget, not the system keyboard. QWERTY + digit row, all
  keys always at their fixed position; keys outside the charset are drawn
  inactive (outline, faint label, no action, no vibration). Punctuation row
  (`. , : - / = ? @ +`) only if the charset has punctuation; prosigns
  (AS KA KN SK VE BK, one key each, ⌫ deletes as a whole) in the bottom row
  only if the charset has prosigns. No space key. Key preview bubble. No key
  click sound (would clash with the CW tone), short vibration (switchable).
  Portrait only for now; landscape maybe later.
- **No time pressure:** no think-time limit after the word.
- **Statistics:** same Hören statistics as the paper mode (shared profile,
  shared weak chars, block EMA, trend, Koch unlock). Only the **first**
  attempt counts (as in Geben); passing in the first attempt = every char of
  the word wrong. Per-char grading via Levenshtein alignment with backtrace:
  substitution/deletion = that played char wrong; extra typed chars are
  ignored (a char that was not played cannot be wrong).
- **Spacing suggestions:** in the typing mode the adaptive mode only
  suggests changes to the **inter-character** spacing (inter-word spacing has
  no effect there).
- **After the block:** the usual "Gesendet" page, errors pre-marked from the
  first attempts, typed text under each group; marks can be removed by
  tapping (typos). Then the **unchanged** result page (no ●◐○ split, no
  confusion list).

## System font size: capped at 1.3 (2026-09-27)

- The Android font-size setting is honoured, but clamped to **1.3×**
  (`kMaxTextScale` in `widgets/app_ui.dart`, applied app-wide via
  `MediaQuery.withClampedTextScaling` in `main.dart`'s `MaterialApp.builder`).
  Pixel offers 7 steps (≈0.85 … 2.0); 1.3 is step 4. Beyond that the
  training screens (fixed-height typing view, half-width buttons, 7 home
  cards) stop fitting. Fully ignoring the setting was rejected: many users
  are older and set large fonts on purpose.
- **Fixed-geometry elements ignore it** (`NoTextScale`): the CW keyboard and
  the Koch character tiles in `CharsetHeader` — their labels are already
  sized for the box.
- **Fixed heights that hold text** (kept fixed so the layout doesn't jump
  between states) are multiplied by `textScaleOf(context)` instead of being
  literal pixels: typing-mode slots, Einzelzeichen-üben feedback line,
  Memory Chain prompt box.
- `AppButton` labels are one line and shrink to fit (`FittedBox`) instead of
  clipping; horizontal padding reduced to 12.
- Long scroll areas use `ScrollHint` (always-visible scrollbar + bottom fade
  while there is more): Hören "Gesendet" overview, Hören result page, and the
  home screen, which switches from 7 height-sharing cards to fixed-height
  cards in a scroll view when the screen is too short for them.
- **Android "Display size" (Anzeigegröße) is ignored entirely**:
  `MainActivity.attachBaseContext` overrides `densityDpi` with
  `DisplayMetrics.DENSITY_DEVICE_STABLE`, so FlutterView always gets the
  stock devicePixelRatio. It scales everything (not just text), so there is
  nothing to cap sensibly; enlarged, the fixed-geometry screens break.
- Test: `android/test/text_scale_test.dart` pumps the home screen at scales
  0.85–2.0 on two phone sizes and fails on any overflow.

## Text adventure: Zork I–III in CW (2026-09-27)
App-only feature, no firmware counterpart (the firmware's own text adventure
"Radio Cave" is unrelated and stays backlog). Concept with mockups (private
artifact): https://claude.ai/artifact/72w1sXjGBDmTx6TG4a4qVa.

- **Source and license.** Microsoft released Zork I–III under the MIT License
  (Nov 2025, historicalsource/zork1–3). The compiled story files in each
  repo's `COMPILED/` are used unmodified (`android/assets/zork/`, provenance
  in its README); no ZIL compiler needed. The license covers the code, not
  the "Zork" trademark (Microsoft says so explicitly), so the card and the
  game screen say "Text-Adventure" / "Teil I–III"; the works' titles appear
  only in the selection list and the credits, with a non-affiliation note.
  No logo or box art.
- **Own interpreter in Dart** (`lib/zmachine/zmachine.dart`, Z-machine v3
  only — all three story files are v3). Not Frotz: GPL, and an NDK bridge for
  something with no timing needs. Pure Dart, no audio/UI; testable headless.
  Proof: `test/zmachine/zmachine_test.dart` plays a complete Zork I solution
  (`zork1_walkthrough.txt`, route after eristic.net, fights as `!until`
  loops) and requires 350/350 points. Fixed seed; `tool/zplay.dart` is the
  dev player for writing/fixing walkthroughs.
- **Own snapshot format ("NCWZ"), not Quetzal.** Autosave, save slots and
  undo are taken *between* commands (machine sitting in `sread`), which
  Quetzal can't express portably; export was declined by the user, so
  portability buys nothing. In-game SAVE hands a snapshot to the host (new
  slot, named "room · score"); in-game RESTORE pauses the machine until the
  host picks a slot (`completeRestore`).
- **Audio-only character replacement** (`lib/adventure/cw_text.dart`): the
  screen shows the game's text unchanged; for `playOne()` `' " ( ) [ ] *`
  etc. are dropped, `!` → `.`, `;` → `,`, `&` → AND, paragraphs get a double
  word gap. `CwGenerator.kt`'s table is not extended (user decision).
- **Playback = one `playOne()` per answer**, word highlight by counting the
  generator's `char` events against the words' played lengths. This only
  works because the audio string contains nothing but playable characters
  (unknown ones would be skipped silently and desync the count).
- **CW scope** "Room / message": the first line equals the status-line room
  → room name only; otherwise first sentence. "First sentence" includes a
  leading room-name line.
- **Settings**: own prefs `adv.*` for all three games (wpm, one spacing pair
  — user decision, same ranges/coupling as the Geben sheet; scope; show
  text; verbosity). First visit copies wpm/spacing from the Hören profile.
  Pushed to the generator on entry and before every play (rule 2).
  Verbosity is applied by sending BRIEF/SUPERBRIEF/VERBOSE silently — checked
  in all three games that these cost no move.
- **Undo**: 20 snapshots in memory, not persisted (the original has none;
  user approved).
- **Input** (step 2): the Hören `CwKeyboard`, pass key = space. Paddle input
  (step 3) will use `<AR>` / K / button to send and `<ERR>` = delete last
  word (user decision).
- **Keying** (step 3): shared `CwKeyer` + `MorseDecoder` (unknown = `*`),
  like the QSO Bot; the keyer runs for the whole screen, so a hardware
  paddle also works with Input = Keyboard. Keyer mode / CurtisB / ACS from
  the keyer prefs, speed = own "Geben" value (`adv.giveWpm`, 0 = like
  listening). Word end = the Geben learn mode's rule on the adventure's
  spacing pair: 2 × IC + 1 + max(IW, IC + 4) / 8 dits (straight key
  IW + 1), pushed with every speed/spacing change; dispose resets the
  keyer's word gap to 7 (rule 2). `<AR>` decodes as `+` (same code; no game
  uses `+`) and sends at once; "K" only counts when it is a whole word at a
  word gap (no word K in the three dictionaries). Other prosigns are
  dropped. Input is ignored unless the game waits for a command and the
  screen is the top route (sheets, saves page). The first keyed element
  stops playback (`stopOne`, which leaves the keyer running). Default input
  = paddle (concept order).
- **Map** (step 4, `lib/adventure/adventure_map.dart`,
  `lib/ui/adventure_map_screen.dart`): rooms = children of the start room's
  parent; exits = direction properties 31..19 (N E W S NE NW SE SW U D IN
  OUT LAND, from `<DIRECTIONS …>` in 1dungeon.zil), by length: 1 = UEXIT,
  4 = CEXIT, 5 = DEXIT → drawn; 2 = NEXIT, 3 = FEXIT → not (routine). Room
  positions are hand-placed per game in `assets/zork/<id>_map.json`
  (Zork I: 110 rooms), which also holds the TOUCHBIT attribute number (Zork I
  3, Zork II 2, Zork III 9 — found by checking which attribute only the start
  room has), FEXIT targets from the source ("extra": maze diodes, trap door,
  grating, chimney) and "jumps": pairs too far apart for a line, drawn as a
  note under both rooms. No images from Infocom/fan maps (not MIT).
  "Visited" = TOUCHBIT rooms + walked paths; a path is recorded only when
  one command moves between rooms the map connects (teleports and "N. N"
  don't draw false paths). Walked paths are saved with every save (auto and
  slots, key `walked`), truncated on undo, cleared on restart (menu and the
  game's RESTART). "Whole map" asks every time (user request 2026-09-28;
  first built as once per part), until "Don't ask again" in the dialog sets
  `adv.mapWarn` = false; back on in the adventure settings (section Map).
  Parts without a layout file show no map button. Tests: every room placed,
  no overlaps, no line through another room, and every direction step of
  the full Zork I solution walks a connected pair.
- **Step 5 (2026-09-28)**: solution scripts for Zork II (400/400) and Zork
  III (7/7, reaches the Treasury) at seed 1, written from the eristic.net
  walkthroughs; random parts use `!until` (carousel/low room via "w. se",
  wait-outs via `diagnose` until "perfect health"; the diamond maze was
  stepped by the window's glow per DIAMOND-MOTION in 2actions.zil).
  **Interpreter change:** storew/storeb (and word writes) outside dynamic memory are
  now dropped. Zork II's PICK-ONE on the FANTASIES table (the Wizard's
  "Fantasize") has no counter word, prints a garbage string and writes into
  static memory; keeping the write corrupted code and crashed the game
  (illegal opcode). Infocom's paging interpreters lost such writes. The
  garbage line itself is the original's behaviour and stays.
- **Maps II/III**: layout files add `"directions": 14` (CROSS = 18, not a
  direction in Zork I), TOUCHBIT 2 / 9, and `labels` (free text; Zork III's
  three museum copies 948/776/777). Routine exits from the ZIL: Zork II
  balloon levels, bucket in the well, cage, cake sizes (Tea/Posts Room),
  bank walls (Depository ↔ Small Room/Vault); Zork III viewing-table
  visions, Beam Room → Hallway, mirror box in/out, Royal Puzzle, prison
  cell rotation. Mirror box, table visions, viewing-room exits, ledge jumps
  and the diamond stairway are notes, not lines. The map test's path check
  skips Zork II's diamond maze (DIAMOND-LOSS drops you in a random room).
- **Playback and help follow-ups (2026-09-28, user request)**: "Stopp"
  became **Pause / Weiter**; resume replays from the start of the word that
  was playing (the generator's `stopOne` can't hold mid-word; a word is the
  unit the display and `_heard` already track). The **Text** (eye) button
  toggles: hiding clears `_heard`, so the words reappear as they are played
  again — in every "Show text" mode, including "Always" (which now starts an
  answer with `_revealed` = true). Replay (user decision): **Nochmal tap =
  the sentence** playing (during the gap right after a word: its sentence;
  stopped: the paused/last word's), **hold = whole answer** (like `?`),
  **tap a word = only that word**. Sentence and word end paused with Weiter
  at the next word, so listening goes on where it was. The help
  sheet explains this under "Abspielen". The command
  sheet ends with "What it's about" per part: goal and scoring (Zork I 350,
  II 400, III 7 "potential"), moves (MOVES counts parsed commands; Zork I/II
  skip CLOCKER for SCORE/SAVE/BRIEF etc. — gmain.zil; Zork III's main.zil
  counts all) and death (I/II: SCORE-UPD −10 and RANDOMIZE-OBJECTS; Zork I
  ends at the third death, Zork III at the fourth) — from the historicalsource
  ZIL, not from memory.
- **App icon (2026-09-28, v1.2.0)**: design by Sia, OE1LMR (the user's friend),
  delivered as a finished rounded-square JPEG (`android/tool/icon/
  icon_source.jpg`). Launchers mask icons themselves, so
  `tool/icon/make_icon.py` rebuilds the blue panel full bleed (a colour
  plane fitted to the panel outside the logo) and lifts the logo with its
  shadow off by its difference from that plane. Adaptive icon (API 26+):
  opaque foreground with the logo at 56 % of the 108 dp layer, background
  colour `#5874A8`; legacy `ic_launcher.png`: rounded square, logo at 78 %.
  Re-run the script after changing the source.
- **Games order (2026-09-28, user request)**: Morse Invaders, Text-Adventure,
  Morsel, Memory Chain — on the games page and in the home tile subtitle.
- **Manual file names carry the version (2026-09-28, user request)**:
  `manual/build.sh` writes `NextCWTrainer_Handbuch_v<version>.{html,pdf}` /
  `NextCWTrainer_Manual_v<version>.*` (version from `android/pubspec.yaml`),
  so a PDF passed around on its own still shows which release it belongs to.
  Only the current release's build stays in `manual/` (the script deletes
  the others; older ones live on their GitHub releases), and the script
  rewrites the links in `README.md` and `manual/README.md`. The v1.2.0 files
  were renamed accordingly. Release assets use the same versioned names.
- **Author credits (2026-09-28, user request)**: Christian Konecny, OE1CKO,
  as developer in Settings → Info (first row, with a "Danke" row for
  Morserino-32/OE1WKL, the icon by Sia/OE1LMR and Zork/Infocom), on the
  manual title page, in its edition block and PDF author metadata, and in
  the README. Deliberately not on the home screen, and no contact address
  (an e-mail in a handed-out PDF would be public; the repo is public too
  since 2026-09-28).


## Play Store preparation: upload key, AAB, 64-bit only (2026-09-28)

Goal: publish on Google Play (user request). Code side:
- **Signing:** release builds use the Play **upload key** from
  `android/android/key.properties` (gitignored, like the `*.jks` keystore,
  which lives outside the repo). Without that file, release builds fall back
  to the debug key so `flutter run --release` keeps working;
  `tools/build_release.sh` refuses to run without it and copies it into its
  /tmp clone. Play App Signing holds the actual app signing key.
  Consequence: APKs from the next release on are signed with a different key
  than v1.0.0–v1.2.1 (debug key) — sideloaded installs must uninstall once
  (settings/stats lost). Whether GitHub APKs keep the upload key (then they
  can't update a Play install, and vice versa) or Play is told to use our own
  key as app signing key is still open (STATUS).
- **App Bundle:** `build_release.sh` now builds APK **and** AAB and scans
  both for local identifiers. First real run (v1.2.2) found the home path in
  the AAB's `base/resources.pb` (source paths of every resource, from
  `~/.gradle/caches/.../transformed/`); the APK was clean. Fix: the script
  sets `GRADLE_USER_HOME=/tmp/nct-gradle-home` (kept between runs).
- **ABIs: arm64-v8a + x86_64 only.** `libcw_audio` was only ever built for
  those (CMake `abiFilters`), but Flutter's Gradle plugin overwrites
  `defaultConfig.ndk.abiFilters` with its own list incl. armeabi-v7a, so every
  APK so far also shipped 32-bit ARM without `libcw_audio.so` — a 32-bit
  device would crash at `System.loadLibrary`. Now `ndk.abiFilters` lists the
  two ABIs and `disable-abi-filtering=true` in `gradle.properties` keeps
  Flutter from re-adding armeabi-v7a; Play then won't offer the app to
  32-bit-only devices. (Adding 32-bit support would mean building
  libcw_audio for armeabi-v7a — not worth it, no 32-bit-only user known.)
- **Checked, no change needed:** targetSdk/compileSdk 36 (Flutter 3.47
  default; meets Play's current requirement); every `.so` is 16 KB
  page-aligned (LOAD alignment 0x4000 or 0x10000; NDK 28).
- **`INTERNET` permission stays** (WiFi Trx); Play's data-safety form must
  say it only connects to servers the user enters. `RECORD_AUDIO` (decoder)
  requires a privacy policy URL.
- **App signing key = our own key (user decision 2026-09-28).** At the first
  Play upload, choose "export and upload a key from a Java keystore" (PEPK)
  with `nct-upload.jks`, instead of a Google-generated key. Reason: GitHub
  APKs and Play installs then share one signature, so users can switch
  channels without losing data (phones without Google services, existing
  sideload users). Cost: losing keystore or password means no more updates
  ever — keystore backed up (NAS + offsite), password in the user's password
  manager. Play allows one later upgrade to a Google-managed key if needed.

## Positioning: a CW trainer in its own right (2026-09-28, user decision)
Public texts and graphics (Play listing, feature graphic, README, manual
introduction) lead with what the app does — not "the Morserino-32 training
modes on your phone". The Morserino-32 and Willi Kraml, OE1WKL, are credited
as the source of many ideas and much of the training logic, with thanks and
the non-affiliation note, after the description. Reason: the user doesn't
want to sell the app as the Morserino's mobile counterpart, and thinks Willi
wouldn't like that either. Dropped with it: the "build or buy a Morserino-32,
this app is not a replacement" paragraph. Factual references stay (Koch
sequence "M32", the Morserino-terms table, firmware notes in DECISIONS/
PORTING-MAP).

## System bar insets: one SafeArea for all routes (2026-09-28)
With targetSdk 35+ Android 15+ forces edge-to-edge, so the navigation bar
draws over the app. Most screens only padded the top (AppBar), so on a
Fairphone 6 with 3-button navigation the Hören start buttons sat under the
nav bar. Fix: `MaterialApp.builder` wraps every route in
`SafeArea(top: false)` on a `ColoredBox` with the page background — not per
screen, because per-screen fixes get forgotten (same lesson as the shared
engine config). Screens that already added `padding.bottom` themselves
(CW keyboard, adventure) now see 0 there and are unchanged. Cost: the
keyboard's darker surface no longer extends behind the nav bar.

## Debug builds signed with the upload key (2026-09-29)
The test phone runs an app signed with the Play upload key (migrated
2026-09-28), so a default debug-key APK failed with
INSTALL_FAILED_UPDATE_INCOMPATIBLE and had to be re-signed by hand with
apksigner. `app/build.gradle.kts` now signs the `debug` build type with the
`upload` config whenever `android/key.properties` exists; without it (other
machines) the normal debug key is used. Plain `flutter build apk --debug` +
`adb install -r` works again.
