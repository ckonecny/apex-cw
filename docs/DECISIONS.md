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
The automatic "hi" on connect was removed: other services use other commands. Users type what their service expects. Services and logs are stored in prefs (`trxServices`, `trxLog_<id>`); WPM in `trxWpm`.

### Keyer word gap follows the InterWord Spc pref
Firmware keyer/Trx modes end a word (m32_v6.ino interWordTimer) (InterWord Spc − 1) dits after a character ends. The app hard-coded 6 dits. `CwKeyer.wordGapDits` is now set via `setInterWordSpace` (KeyerScreen, WiFi Trx; Echo Trainer pushes 7 = old behaviour). Straight key path unchanged (7 dits from key-up; firmware uses the decoder there). Note: app default for `interWordSpace` is 40, firmware default is 7.


### Echo Trainer: Gebe-Tempo (Echo Speed Max) and self-synced prompt config
Training rollout Phase 1 (`docs/archive/training/P1-echo-grundlagen.md`). The answer is expected at min(prompt WPM, `echoAnswerWpmMax`); 0 = same as prompt. Firmware semantics (`m32_v6.ino` 2553-2561, 3166-3171) but 1 WPM steps and a new pref key, so the old `echoSpeedMax` (cap for Adaptive Speed) is not reinterpreted. The keyer WPM is now set per answer (`_applyAnswerConfig`), and the generator's WPM/spacing/Practice Set/Boost per prompt (`_applyPromptConfig`) — the Echo screen previously inherited them from whichever screen ran last (rule 2). Adaptive Speed is intentionally untouched until phases 5/6 (block-based like Adaptive Copy, own profile).


### Training profiles: separate settings for Hören (`hear`) and Geben (`echo`)
Training rollout Phase 2 (`docs/archive/training/P2-trainingsprofile.md`). Per-training values (wpm, kochLevel, groupLength, randomOption, maxWords, wordLengthMax, abbrevLengthMax, interCharSpace, interWordSpace, practiceChars, boostLevel) are stored as `profile.<hear|echo>.<field>` (`lib/content/training_profile.dart`). One-time migration (`profileVersion=1`) copies the old globals into both profiles; the globals stay in prefs untouched (rollback) but are no longer read by the trainings. Keyer and WiFi Trx keep the global `wpm`. Koch sequence stays global, only the lesson is per profile; spacing is per profile. Settings screen has a temporary Hören|Geben switch for the profile-backed fields (to be removed in Phase 3 when settings move into the training screens). Auto-detected weak chars (`CharStatsStore`) are still shared until Phase 4.


### Training settings live in a shared ⚙ sheet on each training screen
Training rollout Phase 3 (`docs/archive/training/P3-einstellungen-in-screens.md`). One `TrainingSettingsSheet` (`lib/ui/widgets/training_settings_sheet.dart`) serves Generator/Koch, Adaptive Copy (hear profile) and Echo (echo profile); it saves immediately to the profile/global prefs and the screen reloads them on close (native pushing stays in the screens, rule 2). ⚙ only in the setup state. The temporary Hören|Geben switch and all moved sections are gone from the global Settings; adaptive thresholds stay global keys but are edited in the Adaptive Copy sheet; character stats view/reset stays global. Practice Set groups are capped by the word-length setting; Echo now passes word/group length to the engine.


### Character statistics: separate tracks for Hören and Geben, shown inside each training
Training rollout Phase 4 (`docs/archive/training/P4-zeichenstatistik.md`). `CharStatsStore(track)` persists to `charStats.hear` / `charStats.echo`. One-time migration in `load`: the old single `charStats` (or the even older `adaptiveWeights`) becomes the hear track; the echo track starts empty (its data would be hearing weaknesses). Adaptive Copy and the Koch generator use hear, the Echo Trainer ("Adapt. Rand.") uses echo; echo still records only in that mode. `CharStatsScreen(track)` is opened via 📊 in the Koch generator / Koch echo title bar (no tabs, no entry in global Settings), with a per-track reset. The echo view has no unlock display (weakest characters first).


### Echo Trainer: optional block flow with result page (display only)
Training rollout Phase 5 (`docs/archive/training/P5-echo-bloecke.md`). Profile field `profile.echo.blockFlow` (0 = classic, default; 1 = blocks), chosen in the Echo ⚙ sheet. Block size is the profile's `maxWords` (0 → 10, sheet label "Wörter pro Block", 1..50); learn/preview targets (`fixedTarget`) never use blocks. Per word the screen records `WordResult` (target, first attempt, attempts, outcome first/afterRepeat/failed, first wrong index). The result page shows the first-try rate only (● counts, ◐ "right after repeat" is shown separately and not folded into the percentage — whether it becomes a half hit is decided in Phase 6; failed/revealed words count as wrong). `+` is played at block end; stopping mid-block discards the block. No suggestions, trend or stats changes yet.


### Classic flow is retired: adaptive becomes the default
User decision 2026-09-25 (training rollout, before Phase 6). The classic (firmware-style endless) flow gets no more work. From Phase 6 on, new features (suggestions, stats weighting) apply to the block flow only. Phase 7 removes the classic flow in all sections (Echo, Generator, settings, Adaptive Speed pref) and makes the adaptive/block flow the default. Until then classic stays as is.


### Echo Trainer: adaptive suggestions on the block result page
Training rollout Phase 6 (`docs/archive/training/P6-echo-vorschlaege.md`). Block flow only. Stats "Geben" are booked once per word after the first attempt in all echo contents except learn/preview (`CharStatsStore.recordWord`: first wrong char +4, neighbours +2, right word -1 per char, weights 1..20; chars before the error count right, after it not counted). Suggestions come from `evaluateEchoBlock` on top of `AdaptiveCopyEngine`, using the first-try rate only (right-after-repeat is not a hit) and the shared global adaptive thresholds: new Koch char, spacing tighter/wider, Hör-WPM +1, Gebe-Tempo +1 (only with a cap below Hör-Tempo, default unticked), weak-char chips (boost for one block). Tempo rises are blocked while Koch chars are still open and in the block that adds a char; widening is not. Block EMA is stored globally as `echoBlockEma`. Accepted values are applied on "Nächster Block"/"Beenden".


### Training: Koch is a character set, start page has Hören and Geben, classic flow removed
Training rollout Phase 7 (`docs/archive/training/P7-zeichenvorrat-startseite.md`, approved 2026-09-25). Hören (CW Generator) and Geben (Echo Trainer) each choose a character set (Koch lesson / all characters / practice set) and a content (random, words, abbreviations, call signs, mixed), stored per profile as `charset` and `content`; "Koch Trainer" is no longer a start card and Echo's "Adapt. Rand." is no longer a content (Koch + random always weights by weak chars in the block flow). Firmware basis: `kochActive` is only a character filter plus weighting. Koch sequence stays global, lesson per profile. Tapping a Koch char offers "Anhören"/"Mit Echo üben" (replaces Learn New/Preview buttons). Settings sheet shows only sliders that fit the chosen content. Classic flow is removed in Hören and Geben (incl. Adaptive Speed pref, display modes, each-word-twice, stop-after-word); the per-word echo flow stays. The paddle choice repeat/next is dropped for now and to be re-offered in the Hören block flow in Phase 8. Adaptive Hören for "all characters"/practice set has no unlock/boost/tempo lock (Koch only).


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
NVS. Open ports: GitHub issues #13–#15.

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
"Radio Cave" is unrelated, see GitHub issue #14). Concept with mockups (private
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
- **New app logo (2026-10-06)**: Sia, OE1LMR, redesigned the logo (teal "C"
  ring around a purple-to-orange "W", flat navy panel). Same pipeline: new
  `icon_source.jpg` (1280 px), `make_icon.py` adapted (panel bounds, corner
  radius, alpha threshold; legacy icon logo at 70 %, was 78 %, the larger
  "C" touched the edge), adaptive background colour `#122241`. Also
  replaced: README icon (`icon_rounded.png`), landing page
  `site/img/icon.png`. `android/tool/icon/social_preview.png` (1280x640) is
  for GitHub's social preview (Settings, manual upload; no API). Play
  graphics and manual still carry the old look: see "pending" in STATUS.md.
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

## Learning resources: Morse tree and links (2026-09-29, user request)
New home tile "Lernressourcen" (own group "Lernen") opens a hub with tiles,
built like the games hub (the tile widget is now the shared `HubCard` in
`widgets/app_ui.dart`). Entries: interactive **Morse tree**,
**Character chart** and **Links**.
- **Tree is drawn from `MorseDecoder.table`**, not from a picture: the
  dichotomic tree is a mathematical structure, and neither the cryptomuseum
  PDF nor the Wikipedia SVG (own licence per file, CC BY-SA possible) is
  copied or embedded. Levels 1–4 letters; "Ziffern und Zeichen" adds level 5
  (digits, `/ = +`, KA KN AS VE). Codes longer than five elements (some
  punctuation, BK, SK) are not in the tree.
- **Playback via the shared generator** (rule 2): the screen pushes pitch,
  tone softness and wpm on entry and stops the keyer; wpm starts from the
  Listen profile, ±1 on the screen is local and not saved. Path lighting is
  driven by the generator's elementOn/elementOff events, like the tap tile.
  Prosigns are played as `<XX>` (rule 3).
- **Ä Ö Ü and CH are playable** (2026-10-06, found by Sia): the generator's
  `morseTable` got `Ä Ö Ü` and `CH` (`----`, only as `<CH>`); before, the tree
  played nothing for umlauts and CH as C+H (8 elements, wrong lighting). Own
  Text still flattens ä→AE before the generator. Selecting CH shows a footnote:
  `----` is obsolete, send CH as C + H. Leaving "Ziffern und Zeichen" shortens
  a level-5 path to its level-4 ancestor (or clears it).
- **Dit/dah edges look different** (user request 2026-09-29): a dit edge is
  a row of dots, a dah edge one thick solid line; lit ones in the accent
  colour, unlit ones in `textFaint`.
- **Landscape allowed on the tree screen only** (user request 2026-09-29,
  exception to the portrait lock in `main.dart`/manifest): `initState` calls
  `setPreferredOrientations` with portrait + both landscapes, `dispose` locks
  portrait again. Flutter's call overrides the manifest's `screenOrientation`
  at run time. Landscape layout: one slim control row on top, tree fills the
  rest; the deep tree (32 slots at ≥ 24 dp) fits without scrolling.
- **Links open in the external browser** (`url_launcher`, BSD-3-Clause,
  GPL-compatible; the licence guard test passes). Names as text only, no
  logos, plus a non-affiliation note. The app already had INTERNET
  (MOPP/WiFi Trx).
- **Character chart is own drawing** (`morse_chart_screen.dart`): a tile grid
  (letters, digits, punctuation, prosigns) built from `MorseDecoder.table`,
  code as dots and bars; the cryptomuseum PDF is not copied. Playback and
  lighting as in the tree (rule 2 config push, `<XX>` for prosigns, elementOn/
  Off events). Portrait only (no landscape exception needed). Tile order is
  fixed in the screen; the codes come from the table, so they cannot diverge.

## Home: free modes grouped one level down (2026-09-29, user request)
The home screen scrolled with its eight cards and the scroll bar was
unwanted. CW Keyer, CW Decoder, WiFi Trx and QSO Bot moved into a hub
(`free_screen.dart`, "Freie Modi") built from `HubCard` like the games hub.
Home now has five cards in four groups; the fit formula in `home_screen.dart`
counts five cards, and the scroll fallback stays for huge system fonts.

## Debug builds signed with the upload key (2026-09-29)
The test phone runs an app signed with the Play upload key (migrated
2026-09-28), so a default debug-key APK failed with
INSTALL_FAILED_UPDATE_INCOMPATIBLE and had to be re-signed by hand with
apksigner. `app/build.gradle.kts` now signs the `debug` build type with the
`upload` config whenever `android/key.properties` exists; without it (other
machines) the normal debug key is used. Plain `flutter build apk --debug` +
`adb install -r` works again.
- **Done 2026-09-29:** the console had already generated a Google key when
  the app was created (before any upload); replaced via App-Signatur →
  "Schlüssel ändern" → "Java KeyStore exportieren und hochladen" (PEPK).
  App signing key SHA-256 now 98:D9:CD:80:…:47:BD:F2:72 = `nct-upload.jks`,
  which is also the upload key.

## Statistics: detail sheet, per-char history and timestamp (2026-09-30, user request)
- Tap on a row in "Statistik Hören/Geben" opens a bottom sheet
  (`ui/widgets/char_stat_sheet.dart`). The row itself now spells out why a
  Hören character is still not ready ("noch k nötig", "unter X %"), the
  percent is labelled "aktuell" (it is the moving average, α = 0.2, that the
  unlock rule uses — not an overall rate).
- `CharStat` got two fields, both written only when present so old data loads
  unchanged: `h` = last 30 results as a '1'/'0' string, `t` = epoch ms of the
  last attempt. **No back-fill:** they fill from the next practice on. Chosen
  over `lastBlock` for "last practised" because the block counter restarts
  every session. `t` is also the groundwork for the long-term progress view
  the user wants (dated aggregates would still have to be added).
- "Right answers in a row until the threshold" is computed from the EMA step
  itself (`CharStat.correctsToReach`), capped at 100 (→ null).
- Hearing mix-ups are **not** available: Adaptive Copy only marks positions
  as wrong, it never sees what the user heard. Only the Send track records
  confusion pairs; the sheet says so instead of showing an empty list.
- The sheet's "Anhören" pushes wpm/spacing/sidetone itself before playing
  (rule 2) — wpm and spacing from the track's own profile.

### Correction (2026-09-30): Send has an unlock too, the statistics now show it
The 2026-09-30 sheet first treated Send as "no unlock" — copied from the old
P4 note ("The echo view has no unlock display") without checking.
`evaluateEchoBlock` (`echo_suggestions.dart`) does unlock the next Koch
character on the Send track with the same rule (occurrences floor + hit rate
≥ threshold on every active char; Koch + random content only). The statistics
screen and the detail sheet now show ready/hourglass, the "x of y ready" box,
the reasons and the unlock gap on **both** tracks. Sort order differs on
purpose: Listen = not-ready first, Send = weakest first. Only the mix-ups
stay Send-only (Listen has no typed character to compare).

## Progress view over time: decisions and data collection (2026-10-01, user request)
Issue #16, merged with #4. Decided with the user:
- **Dropped:** CSV export and backup/restore (not wanted at all). #4 closed.
- **Data (done):** per-day aggregates, separate per track (Hören/Geben), kept
  in `CharStatsStore.days` (`charStats.<track>.days`): attempts, errors,
  wpm sum (average) and day maximum, and per character [attempts, errors].
  Booked in `record` / `recordWord`, the same single place as the history
  strip. wpm is set by the screen before recording (hear: block wpm, send:
  hearing wpm). **No back-fill**; a statistics reset wipes the days too.
  Storage is one JSON string per track, rewritten on every save (~0.5 KB per
  active day, a few hundred KB after years at most).
- **View (next, after a mockup is approved):** overall rate, speed, curve per
  character (in the detail sheet), overview of all characters, practice
  time/days. Lives behind the existing statistics icon of Hören and Geben.
  Charts drawn with `CustomPaint`, no package (no licence check needed).
- **Later, own issues:** per-character speed/reaction time (#19), mix-ups over
  time (#20).

### Progress view: UI as built (2026-10-01, approved mockup)
- Stats screen gets a switch "Zeichen | Verlauf" (`SegmentedButton`); the
  Verlauf tab is `ui/progress_view.dart`, series logic in
  `content/progress_series.dart` (pure Dart, tested).
- Range 4 weeks / 12 weeks / All. Buckets: day / week (Monday start) / month;
  "All" turns to months beyond 26 weeks. Empty buckets stay gaps in the curves.
- KPIs = latest bucket **with practice**, weighted by attempts (rate, wpm; wpm
  ignores attempts without a wpm), arrow vs. the previous bucket with practice
  (±3 points flat band). Days practised = "d/t", t counted from the start of
  the range (All: from the first practice day). No practice time (not stored).
- Heatmap: weekly (4-week range uses 7-day blocks), cell colour only from 5
  attempts, red (≤ 60 %) → amber → accent (≥ 90 %); characters and header stay,
  cells scroll; "Weakest first" sort; tap opens the detail sheet. No
  "stays weak" verdict text (no criterion defined).
- Detail sheet: "Trefferquote pro Woche" (12 weeks) with tabs Hits | Attempts,
  threshold dashed. Not the moving average, not the overall rate.
- Charts: `ui/widgets/progress_charts.dart` (`CustomPaint`, no package).


## 2026-10-01: Straight key gets its own adaptive decoder (issue #17)
`StraightKeyDecoder.kt` ports the firmware decoder (`MorseDecoder.cpp`, V9.0 "Version 6 and newer": running `ditAvg`/`dahAvg`, dit/dah threshold = sqrt(ditAvg*dahAvg), character gap 2.2/2.3/2.4 and word gap 5/5.5/6 dits by speed, echo word gap IW+1 only up to 30 WPM as in the firmware). It is pure logic and used only by the straight-key branch of `CwKeyer`; paddle modes are not touched on purpose (well tested, kept strictly separate). Differences from the firmware: no noise blanker (touch input does not bounce), and the start speed is the screen's WPM (later: one start value in the general settings) instead of the fixed 20 WPM-equivalent values. The firmware never reads the configured WPM for the straight key (keyer/Trx show and send the measured WPM). The measurement restarts when WPM or mode is set. A word gap is only reported after a real character (filtered glitches produce none).

Follow-up decisions (stages 2–6): one general setting "Starttempo Handtaste" (`straightStartWpm`, 5–40, default 15) is the initial estimate for every screen; AutoChar Spc is hidden for Straight (it is a paddle aid). The measurement restarts when the mode is pushed (screen entry), but not on keyer stop/start (the Echo Trainer restarts the keyer per word). The measured WPM is display and timing only: it goes over its own EventChannel (`cw_straight_wpm`), never into the saved `wpm`, and the symbol stream stays unchanged. Screens show their WPM control disabled and following the measured value; WiFi Trx packets carry it (firmware behaviour); Echo statistics record it; Echo block suggestions drop Gebe-Tempo +1 and spacing for Straight (Hör-WPM +1 and Koch unlock stay). The firmware threshold for the character gap (2.2 dits) is kept on purpose, although a very slow beginner can get a slow S read as three E before the measurement has adapted; the start speed is the remedy.

## 2026-10-01: Own texts (File Player), issue #8
Replaces the firmware's File Player (`MorseFilePlayer`-style: one uploaded file, up to 16 `$` parts, remembers the position, wraps at the end, optional "Randomize File"). App-only differences, decided with the user: texts come in through the **clipboard** (no file picker, so no format question and no storage permission); any number of texts, each with a title, no editing (paste a corrected copy instead; the 16 parts are replaced by several texts); max 20,000 characters per text; stored in the app support directory `owntexts/` (`index.json` + `<id>.txt`). Position (word index) is saved per text, opening a started text asks Continue / Start over; the end wraps to the start (firmware behaviour). "Randomize File" is not ported (follow-up if wanted).

Audio flattening (`owntexts/text_passage.dart`), screen text stays original: Ä Ö Ü ß → AE OE UE SS, other accents dropped, `!`→`.`, `;`→`,`, `&`→AND, dashes→`-` (a lone dash between spaces is skipped), unknown characters dropped (as in the firmware). Prosigns as `<KA>` or `[KA]` (the firmware accepts both; rule 3), `<CT>` = KA; they count as one engine char event.

Playback reuses the Zork scheme (`playOne` of a word range, `char`/`done` events mapped back to words) but with its **own** `TextPassage` class so the working Zork code stays untouched; merging both is issue #23. Tempo and spacing are read by the engine per element, so changing them during playback needs no restart. Own profile `own.*` (wpm, spacing, show), seeded from the Hören profile on first use; the screen pushes pitch/softness/speed on entry (rule 2). Tap on a word = play from there (also in "after playing" mode, unlike Zork where hidden words are not tappable). The screen stays awake while a text is open; playback with the screen off and lock-screen/Bluetooth controls are issues #21 and #22, sharing from other apps #24 (done, see "Share text into Own texts").


## 2026-10-02: Interference simulation (issue #6)
Noise, QRM, QSB, pitch drift and timing jitter ("bad fist") on the **other station's** signal, to practise under poor conditions. Decided with the user: **synthetic**, generated in the audio callback (no recordings: no licence questions, no size, every mix possible); QRM starts as random patterns (a real second text can replace them later); only the other station is affected, the user's own sidetone stays clean; **no statistics integration** (runs with interference are not marked).

- **Where.** `interference.h` is pure DSP (host-testable, no Android includes) used by the single oscillator callback in `cw_tone_jni.cpp`; parameters are atomics, `beginBlock()` once per block, `process()` per sample on the audio thread. Timing jitter lives in Kotlin (`CwGenerator`: random factors on elements and gaps, `CwTonePlugin.jitter`), because the timing is made there.
- **Deviation from rule 2 (deliberate).** The interference profile is a *global user setting*, pushed to the engine at app start (`InterferenceProfile.pushSaved()`) and on every change, not by each screen on entry. Gating is done by an **rx flag** (`CwAudioNative.setRx`) that `CwGenerator` sets while it plays the other station (`playOne`, `playPatterns`, `start`) and clears in the finally blocks (guarded by the generation counter) and in `stop()`. The user's keying never passes through the interference path. Side effect: every screen that plays through `CwGenerator` gets the interference, including the reference screens (character practice, chart, tree). The user wanted exactly that (and the app bar icon there too), see the "Ambient" entry below.
- **Receiver filter and noise.** One slider "Receiver filter" (RBJ band-pass at the sidetone pitch, Q 1.5..20, double precision). Noise and crackle pass **two** identical stages (12 dB/oct; one stage let audible hiss through at 2-5 kHz), the tone passes **one** stage with Q capped at 3 (two high-Q stages made every key-down/up ring), QRM one stage with Q capped at 6 (so the filter can cut it but not remove it). A fixed treble roll-off (two one-pole low-passes, 800..3200 Hz, slider "Noise colour") sits before the band-passes.
- **SNR semantics.** The noise slider is an SNR in a fixed **2.4 kHz reference bandwidth** (+20 dB at 0 %, -10 dB at 100 %), computed from the power gain of the whole noise chain (sum of the squared impulse response, cached per pitch/Q/colour). A narrower filter therefore really improves the SNR, as at a real receiver. (First version normalised the noise to a constant level *after* the filter: a narrow filter then turned the tone into "mush" because the remaining narrow-band noise was as loud as the tone.) Mild AGC (`1/sqrt(1+0.25 r^2)`) plus a `tanh` soft limiter instead of hard clipping, which crackled at SNR below about 0 dB.
- **Realism details** (all from listening tests on the test phone): slowly wandering noise level, rare short crackle bursts smeared by the filter; QSB two sines, frequency random walk 0.008..0.03 Hz, depth up to about 8 dB; drift = mean-reverting random walk (tau 4 s, +-15 Hz typical, +-30 Hz at most); the rx level fades over 50 ms so nothing jumps when the station starts or stops.
- **QRM.** Second keyed oscillator in the callback: overs of 3..12 characters at 12..28 WPM, frequency 100..350 Hz above/below the tone, random dit/dah patterns, 1..4 s pause between overs, 5 ms keying edges.
- **UI.** Settings card "Störungen" (switch, presets Light / HF evening / Pile-up / Custom, sliders, "Try it"); app bar icon `graphic_eq` (`ui/widgets/interference_button.dart`) on the screens that play another station: grey = off, accent = on, tap toggles, long press opens the settings page. Prefs `interfOn`, `interfPreset`, `interfNoise|Qrm|Qsb|Drift|Jitter|Filter|Color`. "Try it" uses the Hören profile's wpm and spacing and random character groups: a known phrase ("CQ CQ DE ...") is much easier to read through noise and gave a misleadingly clean impression.
- Tests: `test/interference_profile_test.dart` (profile, presets, engine levels). The DSP itself was tuned by ear; no automated audio test.

## 2026-10-03: Interference "ambient" (constant noise), follow-up to issue #6
Wish: the noise should not only sound while the other station is played but stand permanently while an exercise is active, and for lessons for the whole block (not during the result page / corrections). More realistic but more tiring, so it is a **separate setting** "Constant noise" (`interfAmbient`, default off = old behaviour).

- **Engine.** `Interference` has a second flag `setAmbient` (`CwAudioNative.setAmbient`, plugin method `setAmbient`) next to the rx flag, with its own fade level. The *bed* (noise, crackle, QRM) follows `ambient || rx`; the tone processing (QSB, filter, drift) still only follows `rx`. So the own sidetone stays clean even when the noise runs under the user's keying (the user wanted the noise to stand while keying, e.g. in the echo trainer). With both flags equal the output is the same as before.
- **Who asks.** Screens request it with `InterferenceProfile.requestAmbient(this)` / `releaseAmbient(this)`. It counts owners (a Set) instead of one flag, because screens stack (e.g. character practice opened from a result page). The native flag is `owners.isNotEmpty && enabled && ambient`; `push()` re-evaluates it when the profile changes (app bar icon, settings). Again global, not pushed per screen (deviation from rule 2, see above) but screens must release it on every exit path, including `dispose`.
- **Scope.** Hören and Echo: from block start to the result page (not during the result page, corrections, boost choice). Morsel / Memory Chain: from game start to results / game over. QSO Bot: session (start until done/abort). WiFi Trx: while connected. Own texts: while playing, not while paused. Adventure, character practice, Morse chart, Morse tree: while the screen is open. Not affected: the one-off character playback from statistics/result pages (`playCharThrice`, still through the rx flag only) and Morse Invaders (no other station, no icon).

## 2026-10-02: "Paddle" becomes "Morse key" in all user-visible text (issue #25)
EN generic term "Morse key", DE "Morsetaste" (matches the home screen subtitle). Where the two sides of the keyer must be told apart: "dit key" / "dah key" (DE "Dit-Taste" / "Dah-Taste", "linke/rechte Taste"), not "lever/Hebel" and not "paddle". The single-lever key stays "straight key" / "Handtaste". On-screen: "touch keyer" / "Touch-Keyer". Manual heading "Paddle und Morsetaste" is now "Morsetaste" (anchor `#morsetaste` / `#morse-key`), "Learning the paddle keys" is "Learning the dit and dah keys". Settings section header: "vband Morse Key". Internal identifiers (`paddle_widgets.dart`, string keys like `ac_paddle_hint`, native method names `setPaddleChoice`, `startLearnPaddle`, ...) are deliberately **not** renamed: not user-visible, and the Dart/Kotlin channel names must change together (rule 2); a rename would be its own change.

## 2026-10-03: Practice log (issue #30, part of #3)
Foundation for the daily goal / streak (#31), spaced sessions (#33) and the
achievements (#34). Nothing user-visible yet. Code: `content/practice_log.dart`
(models, JSON, storage), `util/practice_clock.dart` (the clock), tests in
`test/practice_clock_test.dart`.
- **Active time, not screen time.** The clock runs only while a training
  screen is open (`PracticeClock.enter(mode)` / `leave()`, placed next to the
  `KeepScreenOn` calls), the app is in the foreground, and the user is active:
  a touch (global pointer route) or a key symbol within 20 s, or audio playing
  (`audioPlaying`, set by Hören and Eigene Texte; each start also touches, so
  the short gaps between words don't break it). One tick per second, a step is
  at most 2 s (a sleeping device must not credit the gap).
- **Counted modes:** Hören (`hear`: generator, adaptive copy, character
  practice), Geben (`echo`), games (`game`), adventure, QSO bot, own texts,
  Morse key (`keyer`). **Not counted:** CW decoder and WiFi Trx (tools, not
  training), reference screens (chart, tree).
- **Sessions:** a session ends after 5 min without credited time. Stored as
  `{start ms, seconds, first mode}`, the last 300 kept. Per day: seconds,
  sessions started, sessions that reached 5 min ("long", for #33).
- **Day = 04:00 to 04:00 local time** (`practiceDayKey`), so practice after
  midnight counts for the evening before. The per-character statistics keep
  plain calendar days; the two are not mixed in one figure.
- **Milestones** `{day, kind, value}`: `koch.hear|echo` (character count, only
  when an adaptive unlock suggestion is accepted — not when the level is set by
  hand, so exploring doesn't count) and `wpm.hear|echo` (records only, accepted
  speed suggestions). Identical kind+value is logged once; two Koch charsets
  with the same count therefore share one entry (accepted). Counting starts
  with this version, no back-fill.
- **Off switch:** `practice.enabled` (default on; the settings UI comes with
  #31/#34, in the general settings). While off nothing is recorded or
  logged; stored data is kept (`reset` keeps the flag too). When switched on
  again the streak has a gap for the time off.
- **Storage:** SharedPreferences `practice.days|sessions|milestones` (JSON),
  saved every 30 s of credited time, on leaving the screen and when the app
  goes to the background. Local only; PRIVACY.md already covers it
  ("Trainingsfortschritt, Statistiken").
- **Known limit:** Bluetooth/paddle key presses count as activity only on the
  screens that listen to the symbol stream (echo, keyer, adventure, character
  practice, games); QSO bot and memory chain rely on touches and playback.

## 2026-10-03: Daily goal and streak (issue #31, part of #3)
- **Logic** in `content/daily_goal.dart` (pure Dart, tested): goal 5/10/15/20/30/60
  min (default 10, `goal.minutes`), grace day on/off (`goal.grace`, default on).
- **Streak:** consecutive practice days (04:00 rollover) with seconds ≥ goal.
  Today never breaks it while open; once met it adds one. A missed day is
  bridged by the grace day, once per Mon–Sun week, only if an older goal day
  follows (a leading miss is not counted); never before the first logged day.
  Frozen days add nothing. A second miss in a week ends the streak.
- **Home card** on top, tap opens `GoalsScreen` (minimal until #34: today, week,
  gear → `GoalSettingsScreen`). Layout: tiles share the height as before; the
  card is full (100·scale, scale floored at 1 because the ring doesn't shrink),
  compact (56·scale) when the full one would not fit, and only then the page
  scrolls. Hidden entirely when `practice.enabled` is off.
- **Switch** "Show daily goal and achievements" in both the goal settings
  (hiding returns to home) and the general settings (the way back); it is
  `practice.enabled`, so it also stops recording.
- Week dots: filled = met, dashed-in-ring = grace day, ring = open/missed.

## 2026-10-03: Reminder (issue #32, part of #3)
- **Own native implementation instead of `flutter_local_notifications`.** The
  package needs core library desugaring (`desugar_jdk_libs`, GPL-2.0 with
  Classpath Exception) in Gradle; per rule 11 that was put to the user, who
  chose "no new library". `Reminder.kt`: AlarmManager + broadcast receiver +
  notification, ~80 lines, no new licence.
- **Scheduling:** Dart (`util/reminder.dart`) computes the next 7 fire times at
  the chosen time of day, skipping today's if the goal of the current practice
  day is already met, and hands them with the text to native. Native stores
  them, arms one inexact alarm (`setAndAllowWhileIdle`, no exact-alarm
  permission, may be a few minutes late) for the earliest, shows the
  notification, arms the next. Boot receiver re-arms after reboot.
- **Re-planning** (`Reminder.refresh`): at app start, when the last training
  screen is left or the app goes to the background (`PracticeClock.onIdle`),
  and after changing reminder/goal/show settings. If the goal is met after the
  app is killed without a pause, that day's reminder may still fire (accepted).
  Text is stored in the language of the last refresh.
- Off by default; `POST_NOTIFICATIONS` is requested only when switching on
  (refusal keeps it off). Off with the goal feature (`practice.enabled`).
- Notification: dit-dah status icon, friendly text, no streak threats.

## 2026-10-03: Spaced sessions (issue #33, part of #3)

- **Setting** `goal.sessions` = 0 (off, default) / 3 / 5. Not a separate goal:
  the day is met when the minutes goal is reached **and** that many sessions
  counted. This keeps one number per day for streak, week dots and reminder
  (`GoalStatus.met`).
- **A session counts** (`countedSessions`) if it has at least
  `kLongSessionSeconds` (5 min) and starts at least `kSessionPause` (15 min)
  after the end of the previous *counted* one. Sessions that are too close are
  skipped, not merged: their time still adds to the total.
- **Session end** is now stored (`PracticeSession.end`, JSON key `e`, set at
  every credited step) because pauses of up to 5 min inside a session make
  start + seconds too early. Old entries without it fall back to start + seconds.
- **Past days** need their session entries. The log keeps 300 sessions; a past
  day without entries counts by time alone, so old days stay valid.
- **Card:** ring shows counted sessions ("1 of 3") and the arc is the lesser of
  time and session progress; subtitle names when the next session counts. The
  "next in N min" text updates when the card is rebuilt, not by a timer.

## 2026-10-03: Achievements (issue #34, part of #3)

- **Computed, not stored.** `achievements(log)` derives all ten from the
  practice log each time the page opens (no per-award state), so a changed rule
  applies to the whole history. Each award keeps every day the rule was met
  (`Achievement.days`); the list shows the first, a tap opens a sheet with the
  meaning, first, last and count. What is counted: characters, weeks with 3,
  4-week runs, days, 5-day sets, weeks, 3-block runs, blocks, records,
  comebacks (a run or set is counted once when reached). Shown on the Achievements page below today/week; no pop-ups.
- **New data:** `PracticeLog.blocks` (`practice.blocks`, max 200): day, track,
  correct share in permille, whether the interference simulation was on
  (`interfOn`). Written next to `BlockHistory.record` in Listen and Send via
  `PracticeClock.block`; off while the feature is off. Block awards therefore
  start with blocks played after this change.
- **Rules:** new character = Koch milestones (#30); "three in a week" counts per
  training and week, the better one counts; weekly series needs 4 consecutive
  Mon–Sun weeks; spread day = 3 counted sessions (`countedSessions`, #33)
  independent of the setting; better week = lower mean error than the week before,
  both with at least 3 blocks (Listen and Send mixed); under 5 % three blocks in a
  row; interference = flag on and under 10 % errors; speed = any WPM record;
  comeback = practice after more than 7 days between two practice days.
- **Left out** (needs data the log lacks): weakest character improved, graded
  interference steps — issue #36.

## 2026-10-03: Weekly review (issue #35, part of #3)

- **Where:** a card on the Achievements page (not the home screen, which stays
  quiet), between today/week and the awards. Hidden for a week without practice.
- **Which week:** Sunday shows the running Mon–Sun week, every other day the last
  finished one (`weeklyReview`). "Once a week" is therefore a matter of when the
  user looks, no extra notification.
- **Figures:** practice time, practice days, new characters (the training that
  went furthest counts, like the awards) and mean error rate of the week's
  blocks (needs `kReviewBlocks` = 3, Listen and Send mixed), each next to the
  week before. No arrows or judgement, "no ranking, no pressure".
- Computed from the practice log on opening, nothing stored. Same switch as the
  rest of the feature.

## 2026-10-03: Trailblazer and Fox Hunt (issue #13) — deviations from MorseGridEngine/Trailblazer/FoxHunt/GridScore.cpp

- **Shared pure-Dart engine** (`lib/content/grid_engine.dart`, scoring in
  `grid_score.dart`), one screen for both games (`maze_game_screen.dart`,
  `MazeGame` enum). 12×4 grid, path, legend, 5 s penalty and CPM formula as in
  the firmware; unit-tested with seeded `Random`.
- **No prosigns in the grid.** The firmware's pool can contain the prosign
  codes S/A/N/K/E/B/+; this app's Koch sets have no prosign characters (see
  `licwCarouselChars`), so cells are single characters and the "keep the
  prosign, reroll the plainer twin" rule is dropped.
- **Neighbour de-duplication runs until stable** (up to 12 passes) instead of
  exactly 3. With 3 passes a clash could be left behind (about 1 in 400 mazes
  with a 6-letter pool); with a very small pool (≤ 4 characters) it stays
  unavoidable, as in the firmware.
- **Fox Hunt clue and keyer.** The keyer is stopped while the one-letter clue
  plays (it shares the sidetone) and restarted on the generator's `done`;
  keying during that fraction of a second is discarded. The firmware cancels
  the clue when the keyer becomes active instead. Auto-replay after 5.5 s
  idle additionally waits 1.5 s after the last keyed element, so it never
  cuts into a letter being keyed. OK pause before the next clue is 600 ms
  (OK tone ≈ 290 ms + the firmware's 300 ms breath).
- **OK/ERR tones** are the firmware's `soundSignalOK`/`soundSignalERR` note
  pairs through the shared `playEffect`; dropped while a touch paddle is held.
- **UI:** Start button instead of the "key to start" gesture, replay button
  instead of the black-button click, +/- speed in the play screen (as Memory
  Chain); Koch lesson for the visit only. High scores as JSON in
  `trailblazerHi` / `foxHuntHi` (7 rows, ranked by CPM; an all-zero CPM never
  ranks). Multiplayer (`MorseGridNet`) is out of scope (ESP-NOW).

## 2026-10-03: Fight the Pileup (issue #15) — deviations from `MorsePileup.cpp`

- **Scope:** single player only (ESP-NOW lobby, beacons, roster, `/ftp/`
  packets, winner announcement are not ported). The firmware's "attack" step
  stays: after a correct defend the pileup pauses and one shown call sign must
  be keyed for +50; with no other players it only scores (literal 50 in
  `handleAttackSubmit`).
- **Rules** are in `lib/content/pileup_engine.dart` with an explicit clock, so
  they are unit-tested (`test/content/pileup_engine_test.dart`): difficulty
  table, 3 lives, `dropsPerLife`, timeout counted from activation, queue
  patience (`queuedSince`, shifted by the attack pause), spawn interval
  shortening with the streak (cap 20), scores 100 + 10 x streak / -25 / +50.
- **No call sign / name entry** (firmware `stateNameEntry`, `FTP_CODE_CHALLENGE`
  entry code): the identity only matters for multiplayer, and the code
  challenge is the firmware's paddle warm-up. Both are left out.
- **No high scores:** the firmware keeps none for the pileup (the game-over
  screen shows the run only), so none are added.
- **Call signs:** `getRandomCall(0)` via the existing `randomCallInfo`, with
  the call-sign preferences (region, common only), prefetched 4 deep.
- **Playback:** the active caller loops through the generator (`playOne`) at
  the player's keyer speed, pitch x 15/18 (the firmware's attack pitch), gap =
  word space + 3 dits (`MorseCwEngine` inter-loop gap). The keyer stays on;
  the first keyed element stops the playback (`stopOne`) and the pitch is put
  back. Playback resumes when the input is clear and 2 s after a submit.
- **Auto-submit:** after max(1200 ms, interWord x dit + dit) of silence, as the
  firmware; additionally a Send button for touch (no encoder click).
- **Sounds:** the firmware effect durations (15–40 ms) are tripled, they are
  clicks otherwise on a phone speaker.
- **Flash text** stays 0.7 s (400 ms in the firmware) and is localised.
- A wrong answer shows only "WRONG" (the firmware shows `typed!=expected` as a
  debug aid, which would give the answer away).

## 2026-10-03: Radio Cave (issue #14) — port and deviations
Ported from `MorseRadioCave.cpp` (V9.0): rooms, items, descriptions, all
commands, puzzles, the two death traps, the grounded-antenna trap, QSO phrases
and CW clues. Game logic in `lib/content/radio_cave_engine.dart` (pure Dart,
tested), UI in `lib/ui/radio_cave_screen.dart`.
- **Same as the firmware, including quirks:** inventory limit is 2 (the header,
  not the comment in the .cpp); `NEW` always asks for confirmation (the firmware's
  "Already a fresh game" check runs after the step counter went up and can never
  apply); a pending `NEW` confirmation survives movement commands and cancels the
  next command that reaches that check; `JN78DH` shows the refreshed room text
  instead of the keyed message; instant dispatch only for lower-case `s e w i h`
  (and `y` while confirming), so an AS prosign (`S`) waits for the timeout.
- **Prosigns:** the decoder gives multi-letter names; they are mapped to the
  firmware's single upper-case buffer letters (SK->K, AS->S, KA->A, KN->N,
  VE->E, BK->B). The error sign (not `R` as in the firmware, whose decoder
  cannot tell it from R) clears the input; so do four E in a row.
- **Clues** are played with the generator at the clue's own WPM and 696 Hz
  (restored afterwards); prosigns written `<SK>` (CLAUDE.md rule 3). Keying is
  muted while a clue plays, as in the firmware; the touch paddles are disabled.
- **Save:** one JSON string in SharedPreferences (`radioCaveSave`, version 1),
  written after every command, removed on win/death. The firmware writes an NVS
  blob; the content is the same state.
- **Not ported:** encoder modes (speed/volume/scroll): speed is -/+, the text
  scrolls by touch; the protocol "has save" report.
- **Added:** lobby with Continue / New game (the firmware auto-resumes), a
  mini-map drawn from the firmware's room rectangles, a back-to-overview button
  on the end pages. No sound effects (the firmware has none either).

## 2026-10-03: Share text into Own texts, issue #24
`MainActivity` has an `ACTION_SEND` / `text/plain` intent filter. `captureShared` keeps `EXTRA_TEXT` in `pendingShared` (from `onCreate` and `onNewIntent`; an intent replayed from the recents list, `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`, is ignored). Dart takes it over the channel `…/share` (`take`): once after the first frame (cold start) and whenever native sends `shared` (app already running). `ShareIntake` (`util/share_intake.dart`, global `navigatorKey`) then goes back to Home (`pushAndRemoveUntil`, so no training screen keeps the engine busy) and opens `OwnTextsScreen(sharedText:)`, which runs the same `_import` as the clipboard button: same limit, same "nothing to send" check, same title dialog. Nothing is stored before the user confirms. Only plain text is accepted; no file shares (same as #8: no storage permission).

## 2026-10-03: Break reminder (issue #5), reworked 2026-10-08 (issue #48)

- **Unit = answered characters, not blocks (#48).** Block size is the user's
  choice (5 groups of 3 vs 10 of 5 characters), so "6 blocks" meant 90 to 300
  characters and the old rule (first 3 vs last 3 blocks, >= 6 blocks, drop
  >= 15 pp) fired far too late for long blocks and on noise for short ones.
  `BreakWatch.add` now takes one right/wrong entry per character. Hören knows
  the errors only after the user marked them, so both rules run at block end.
  Geben: one entry per target character of a word, right up to the first wrong
  one of the first attempt, a word without a first try fully wrong.
- **Two rules, whichever fires first (`BreakSensitivity`).** *Cluster:* >= k
  wrong within any 20 consecutive characters (windows may span blocks, only
  windows ending in the new block are checked). *Drift:* wrong share of the
  last L characters of the run exceeds that of the first L by >= d points,
  needs 2L characters (integer maths: `(last - first) * 100 >= d * L`).
  A "wrong N in a row" rule was dropped: one passed or lost group (5 wrong in a
  row) would fire it alone.
- **Three steps instead of free thresholds:** early k=7, L=40, d=12; normal
  k=9, L=60, d=15 (default); late k=11, L=80, d=20 (setting `breakHintLevel`).
  Free sliders were rejected as too complex for users. Chosen by simulation
  (random errors, 8x5 blocks, 6 blocks): false alarm at a constant 10 % error
  rate: early 24 %, normal 2 %, late 0 %; after one fully missed group of five
  at 10 %: 84 / 24 / 1 %. The values are a first set, to be tuned on real
  sessions. The fatigue example of the issue (errors 2, 3, 4, 7, 10, 13 of 40)
  fires after block 4 / 5 / 6 (old: 6); pinned in `break_hint_test.dart`.
- **Run = same difficulty (unchanged):** a block's signature (speed,
  answer-speed cap, character/word spacing, Koch level, charset/content, input
  mode, interference on/off and all its levels) must be equal; any change
  starts the run over, so a harder task is never read as fatigue. Deliberately
  strict: adaptive steps also restart it.
- **Once per session** (gap of 10 min without a block = new session, in-memory,
  separate from `PracticeClock`'s 5-minute session which counts time, not
  blocks). Hören and Geben have separate runs, one shared "shown" flag.
- **Never forced, can be turned off:** card on the block result page with
  Break / Continue / Don't show again; setting `breakHint` (default on), back
  on in Settings → General, sensitivity row below it while on. Not in games,
  adventure or other modes.

## Decoder: unknown patterns as "*", firmware's extra characters (issue #37)

`MorseDecoder` shows `*` for an undecodable pattern (firmware: CWtree node 63)
instead of `?`, which was indistinguishable from a keyed `?`. Its table also
gained the tree's `ä ö ü ch ; ! " '` (decode only). Own Text keeps flattening
Ä→AE etc. deliberately: the firmware's player does the same (`utf8umlaut` in
`m32_v6.ino`), and the engine's `morseTable` has no codes for them (the
generator's `pool[]` has ä ö ü ch, but the player never feeds them).

## 2026-10-04: Head copy / comprehension — concept (issue #7)

Agreed with the user before any code; mockup comes next.

- **Content kinds**, one shared engine: (1) short sentences DE + EN built from
  typed building blocks, (2) mini QSO on the same slot engine with the fixed
  QSO sequence, (3) Q-groups as a separate mode (extra layer of special
  knowledge, so it comes last). Sentences first.
- **Sentences from blocks, grammar correct by construction**: the engine does
  no inflection. Every block holds its finished forms (e.g. "der Park" /
  "im Park"); a verb and its object are one block; verb forms are stored per
  person (singular/plural); each sentence pattern fixes the word order. A test
  renders all patterns with random blocks (no gaps, no doubled articles); the
  word lists are written by hand, own text, so licence-clean (rule 11).
  Aim: 10-15 variants per block type, thousands of combinations per language.
- **Questions**: one per slot, always in sentence order (who, what they do,
  where, when), four-option multiple choice, distractors from the same pool.
  Each follow-up question names the correct answer of the one before ("Um wen
  geht es?" -> "Welche Tätigkeit übt Peter aus?" -> "Wo trinkt Peter
  Kaffee?"), even after a wrong answer, so one mistake does not spoil the
  rest. The fixed order is what keeps a question from giving away a later
  slot. Level 1 asks every slot; levels 2 and 3 ask "who" plus one randomly
  chosen further slot per sentence, labelled "Satz N:" (keeps rounds short).
- **Replay allowed** (second listening); the text stays hidden while playing.
- **Levels**: 1, 2 or 3 unrelated sentences in a row, then one question per
  sentence. No stories.
- **Scoring**: hit rate per round, into statistics and daily goal.
- **Content language** is its own setting, independent of the app language.
- **No Koch-level filter** (decided 2026-10-04): sentences use the full
  character set, so the mode is meant for people who know all characters. A
  per-lesson filter was considered and dropped: with few characters there are
  hardly any real words, and German lacks H, D, G, O until late.
- **No nonsense sentences** (user requirement, 2026-10-04): slots are not
  drawn independently. Places carry tags (kitchen, garden, workshop, park,
  shop, office, city, ...); each verb+object block lists the place tags it
  fits, so "repariert das Fahrrad" never meets "in der Küche". The place pool
  holds only real places (no "in der Katze"); animals and things are objects
  inside verb blocks. City names fit almost every activity and give most of
  the variety. Few verbs also carry time tags (no "schläft um 12 Uhr
  mittags"). Test: each verb has at least 3 concrete places, each place is used by at
  least one verb. The user proofreads the lists together with their tags.
- **German word order** (user, 2026-10-04): time, then place, then an
  indefinite object, bare noun or verb complement ("Nina isst heute zu Hause
  eine Birne", "Am Mittwoch geht Tom in Salzburg schwimmen", "Max trinkt im
  Park Kaffee"); a definite object (das/die/den/dem/der ...) comes before the
  place ("Anna repariert heute das Fahrrad in der Werkstatt"). Derived from
  the start of the object, not marked per block. The "when" question uses the
  same order. English keeps verb, object, place, time.
- **Engine built** (2026-10-04): `lib/content/head_copy_data.dart` (blocks DE
  + EN, same place tags), `head_copy_engine.dart` (sentences, question chain,
  `hcValidate`), test `test/content/head_copy_engine_test.dart`. Wrong "who"
  options never share a name with the right one ("Tom" next to "Eva und Tom"),
  also across the sentences of a round. Each activity has at least four
  concrete places so the "where" question always has three valid wrong ones
  (cook/bake got `stadt`, hike got "im Tal"/"in the valley").
- **Screen built** (2026-10-04): `lib/ui/head_copy_screen.dart` (+ `head_copy_views.dart`),
  entry in the Games hub (first card; easy to move). Phases: setup (content
  language, level, wpm; spacing taken from the Hören profile on first visit, then own steppers) →
  listening (text hidden, replay, sentences with a 1.8 s gap) → questions →
  result (hit rate, sentences, play with the current sentence highlighted).
  Settings in their own `hc.*` profile, pushed to the shared generator before
  every playback (rule 2). Hit rate per round in `hc.results`
  (`content/head_copy_log.dart`, last 200 rounds), shown on the setup screen as
  the rate of recent rounds. The daily goal counts the time through
  `PracticeClock.enter('headcopy')`; the hit rate does not feed the
  adaptive mode or the achievements. The sample tool
  (`test/content/head_copy_samples_tool.dart`) stays for proofreading the blocks.

## Q-groups mode — concept (issue #41)

Agreed with the user before any code (2026-10-05). Third content kind of the
head-copy concept above; a separate mode because Q-groups are special
knowledge on top of the sentence mode.

- **Direction**: hear the group, pick its meaning from four options. The
  reverse (meaning -> hear four groups) is not part of the first version.
- **Statement and question are separate entries**: "QRZ" and "QRZ?" each have
  their own DE and EN meaning; wrong options always have the same form as the
  right one (question next to question).
- **Context by level**: level 1 plays the bare group, higher levels put it in
  a short phrase ("QTH Wien", "QRZ de Tom"), which prepares the mini-QSO (#40).
- **Scope**: about 25 groups in three levels by how common they are. Texts are
  hand-written own text, no list copied from elsewhere (rule 11).
- **Wrong options**: from the same level and form; never two near-synonyms in
  one question (QRM/QRN, QRS/QRQ), kept in a conflict list that a test checks.
- **Round**: 5 or 10 questions, replay allowed, text hidden while playing.
  Hit rate in its own log like head copy; time counts for the daily goal via
  `PracticeClock`; no effect on adaptive mode or achievements.
- **Cheat sheet**: own page with all groups of the chosen level (or all), DE
  and EN, reachable from setup and result. Content language is its own
  setting, independent of the app language.
- **Settings** in their own profile, pushed to the shared generator before
  every playback (rule 2).
- **Group list built and checked** (2026-10-05): `lib/content/q_groups_data.dart`,
  24 groups (8 per level), wording checked against the ITU list and two
  secondary sources. Statements of QRP, QRO, QRS, QRQ and QSY are requests to
  the other station ("Please ..."), as in the ITU list. QRM, QRN and QSB have
  no question form (hardly used on air; `QText.question` is null, the engine
  never asks it). Where ITU and amateur practice differ, the practice wins and
  the ITU reading goes into the manual as an addition: QRL = "frequency is
  busy" (ITU: "I am busy"), QRT = "I am closing down" (ITU: "stop sending"),
  QTH = location (ITU: latitude/longitude), QSP = relay a message (ITU: free
  of charge). `qgValidate` keeps each question fillable with three wrong
  options outside the right one's cluster.
- **Engine built** (2026-10-05): `lib/content/q_groups_engine.dart`, test
  `test/content/q_groups_engine_test.dart`. Levels are **cumulative**: a round
  at level L draws from all groups of level <= L (and wrong options from the
  same pool), so higher levels keep refreshing the common groups instead of
  drilling only the rare ones. Each group once per pass through the pool, never
  twice in a row. Question form is asked with a 50 % chance where it exists.
  "In context" (level >= 2) means a value after the statement ("QTH WIEN",
  `qgTails`, fictional ASCII values, only for groups whose meaning ends in
  "..."); the question form is always the bare "QTH?".
- **Setup wording** (2026-10-05): the choice is called "Stufe" (1/2/3) with a
  line below saying what it means ("Stufe 2: 16 Gruppen, manche mit Wert").
  A first version showed only the group counts (8/16/24) and hid the word
  level, which the user did not understand; the cheat sheet uses the same
  "Stufe N" headings.

## Layout overflow: one test over all screens (2026-10-04, issues #29, #38)
Two settings rows overflowed one after the other (#29 slider header, #38
`ToggleRow` label in a `Row` with a `Spacer`). Fixing single rows did not stop
new ones, so the guard is now general:
- Rule for rows: a label next to a control sits in `Expanded`/`Flexible`
  (wraps), never a bare `Text` + `Spacer`. Use `Wrap` when two items may not fit.
- `test/screen_overflow_test.dart` pumps every no-argument screen in DE and
  EN, at font scale 1.0 and 1.3, on 412x915, 360x640 and a very tall view (so
  lazy lists lay out every row), and fails on any overflow. A new screen is
  added to its `screens` map; known failures are listed there with their issue.
- #39 follow-up: `CharsetHeader` caps itself at 30 % of the screen height and
  scrolls inside (Hören/Echo start screens have fixed paddles, sliders and
  Start below it); Echo idle hint scrolls; decoder status bar and goals rows
  use `Expanded`/`Flexible`. All screens are now in the overflow test.

## Beta builds without a full release (2026-10-04, renamed from "test" 2026-10-06)

`tools/build_release.sh vX.Y.Z-betaN [ref]`: a tag containing `-beta` builds
**APK only** (no AAB) from any committed ref (default `HEAD`; the tag need not
exist), with the same clean-clone build, upload-key signing and
local-identifier scan as a release. `versionName` becomes `<pubspec>-betaN`
(visible in Settings → Info for bug reports); `versionCode` is left as in
`pubspec.yaml`, so a tester can install over any build and later update to the
real release. Renamed from "test" to "beta" (pre-release of the coming version); the older
tag `v1.5.1-test1` stays as is. Distribution: GitHub pre-release with the APK attached; no
manual/HTML/screenshot work (rule 10 still applies to the Markdown text).

`tools/publish_beta.sh vX.Y.Z-betaN [ref]` wraps this: builds the beta APK
and creates a GitHub pre-release at the (pushed) ref. Notes = commit subjects
and issue numbers since the nearest earlier tag (release or beta, via
`git describe`) plus GitHub's generated PR list. `DRY_RUN=1` prints the notes
only. Requested through Claude Code chat; publishing is outward-facing, so
confirm the tag and ref with the user before running it for real.

## Landing page on GitHub Pages (2026-10-04)

`site/` holds a hand-written static landing page (one `index.html`, dark, DE/EN
switch, no external fonts or scripts, so no visitor data leaves the page).
GitHub Pages can only serve the repo root or `/docs`, and `docs/` is internal,
so `.github/workflows/pages.yml` deploys `site/` with the Actions source. The
workflow also copies the newest built manuals (`manual/*.html`, self-contained)
to `manual-en.html` / `manual-de.html`, so the footer links work without
duplicating content. It runs on pushes to `main` that touch `site/` or the
manual HTML. Screenshots in `site/img/` are dark phone shots (WebP, 720 px
wide, status/gesture bar cropped); retake them when the screens change
noticeably, like the store raw shots. Play button stays "coming soon" until
the app is live. Claims on the page come from manual/README/PRIVACY.

Credits on the landing page footer (2026-10-04): besides Willi Kraml/OE1WKL,
Sia, OE1LMR is thanked for the app icon *and* for testing and brainstorming
ideas; README "Credits" says the same. The in-app Info page (`settings_thanks_value`
in `l10n/strings.dart`) and the manual's "Thanks" row were changed to match in
the same change.

## Mini-QSO stage — concept (issue #40)

Agreed with the user (2026-10-05). Second content kind of the head-copy
concept; own mode next to head copy and Q-groups.

- **Radio style**, same abbreviations in DE and EN ("CQ CQ DE OE1ABC K" ->
  "OE1ABC DE DL2XYZ UR 579 QTH BONN NAME TOM RIG K3 BK"). Only the questions
  are translated; content language is its own setting.
- **Two stations, two pitches** (A calls CQ, B answers), so the turn change is
  audible like two signals in the band. Callsigns come from the app's existing
  random callsign generator (`randomCallInfo`), the engine gets them as a list
  (8 per round: two stations, wrong options for the call questions).
- **Facts** (slots): callsign, RST, QTH, name, one extra (RIG, PWR, ANT or WX).
  Questions in order of appearance; stations named by role ("the calling /
  answering station"), never by a fact asked later.
- **Levels by number of facts**: 1 = B's call, QTH, name (3 questions);
  2 = + RST and an extra (5); 3 = full exchange of both sides with closing
  (both callsigns plus 4 random facts of the 8 heard, 6 questions).
- **Telling the sides apart in questions**: levels 1/2 only ask about B, so
  "the answering station" is enough. At level 3 the first two questions ask
  both callsigns ("the calling station", "the answering station"); every
  later question names the station by its callsign ("What is the name of
  DL2XYZ?"), the correct one even after a wrong answer, like the head-copy chain.
- **Engine built**: `lib/content/mini_qso_data.dart`, `mini_qso_engine.dart`,
  test `test/content/mini_qso_engine_test.dart`.
- **Games hub grouping** (2026-10-05): the three listening modes (sentences,
  Q-groups, Mini QSO) sit behind one hub card "Verstehen" / "Head copy"
  (`understand_screen.dart`), like the Zork games behind "Text-Adventure". The
  sentence mode is called "Sätze" / "Sentences" there. The games list got a
  permanently visible scroll bar (it is longer than most screens).

## Length ranges for groups, words, abbreviations (2026-10-05)
Group length, word length and abbreviation length are min–max range sliders.
min = max is the old fixed length; min < max draws a new random length for
every group/word/abbreviation, so the listener can't tell whether it is over.
Storage stays compatible: `groupLength` is the minimum, new `groupLengthMax`
(absent = same as min); `wordLengthMax`/`abbrevLengthMax` keep their meaning
(0 = all, abbrev max in the firmware's 1..5 = length 2..6 encoding), new
`wordLengthMin`/`abbrevLengthMin` hold real lengths (0 = no limit). Words and
abbreviations are filtered from the pool by the range; groups draw the length
per group (`CwGenerator.drawGroupLength`, and `_pickAdaptiveGroup` for the
Dart-side adaptive draw). The Mixed content shows the group slider too, since
Koch-mixed already draws groups. This is an app extension, not in the firmware.


## Swap on-screen paddles affects the touch buttons only (2026-10-05)
Keyer setting `touchPaddlesSwapped` (default off) puts dah left / dit right on
the on-screen paddles (`IambicPaddles`, via `PaddleLayout`). It deliberately
does not touch the learned hardware keys: anyone who taught dit/dah to their
adapter did so on purpose for that device, and a second reversal from this
setting would undo it. The buttons keep their meaning (the DIT button still
sends dit); only their position changes. Hidden for Straight (one button).

## Exam simulation — receive part (issue #42, 2026-10-06)
- Own files only (`content/exam_*.dart`, `l10n/exam_strings.dart`,
  `ui/exam_screen.dart`); the only change to existing code is the menu card in
  the Learn hub. Texts live in `exam_strings.dart`, not `strings.dart`.
- Profiles are data (`exam_profile.dart`): AT 12 WPM, DE 5 WPM Farnsworth
  (characters 9 WPM), DE 5, DE 12. Sources: Fernmeldebüro (AT: 3 min each,
  at least 12 WPM; error limit unpublished, ÖVSV course says 2–3 → 3 used),
  DK5KE description of the BNetzA exam (DE: 3 min, at most 4 errors, one retry
  per part). Not verified against the BNetzA publication itself.
- Farnsworth: the 19 gap units of PARIS are stretched so a word takes 60/wpm s
  with characters at charWpm (5/9 → inter-char 9, inter-word 22 dits).
- Prosigns: only AR, typed as `+` (a bracketed `<KA>` is ambiguous to type);
  KA/SK left out for now.
- Errors = Levenshtein distance on the text without whitespace (substitution,
  omission, extra character each 1), like an examiner. Per-character marks reuse
  `gradeTyped`. Played text is generated from a pool of German sentences
  (`exam_texts.dart`: 100+ fixed sentences incl. short ones for 5 WPM, plus
  generated QSO lines with random call signs, names, towns, reports,
  frequencies; every third sentence is generated), cut at a word boundary near
  wpm×5×minutes characters. No sentence twice in a run and none of the run
  before (in-memory, per app start).
- Flow: 3 s lead-in, one playback via `playOne` (no pause/replay), 30 s
  correction, result. Results in prefs `exam.results` (last 200); "ready" = the
  last three runs of a profile passed. The user's interference settings are not
  overridden.
- Send part (`ui/exam_send_screen.dart`, part `tx`): the shown text is keyed
  with the shared native keyer (mode/CurtisB/ACS from the prefs, keyer speed =
  chosen with a WPM slider on the ready view (paddle modes only; min = exam
  speed, max 40, default = character speed so Farnsworth 5/9 starts at 9, saved
  per profile as `exam.sendWpm.<id>`; the pass check still uses the exam's
  overall speed), word gap 7, pushed on entry — rule 2). Decoded with
  `MorseDecoder`; `ERR` deletes the last character. The text is compared with
  the best-fitting beginning (`gradeExamSend`), so stopping early is allowed.
  Pass = errors <= limit AND at least 80 % of the text reached AND estimated
  speed >= 85 % of the exam speed. The 80 %/85 % are this project's own
  assumptions (no official measurement is known; `kExamSendMinText`,
  `kExamSendMinSpeed`); the speed comes from the time between the first and
  last element (symbol event arrival), so it is an estimate. The verdict is
  stored in the result (`k`), plus the estimated WPM (`m`).
- Open: KA/SK, weak characters into the character statistics, UK/NZ profiles,
  

### Exam simulation: more countries and a custom profile (issue #42, 2026-10-06)
- Profiles are grouped by family (`at de uk nz in us`) plus `custom`; the picker
  is country chips → speed chips (→ text/figures for UK). Sources (public,
  not verified at the authorities): UK RSGB Certificate of Competency (5–30 WPM;
  plain text 3 min ≤4 errors, five-figure groups 1 min ≤3 errors), NZART (5 WPM,
  3 min, ≤4 errors, up to 5 attempts, sending only has to be readable), India
  WPC (5 or 8 WPM, receive 1 min without a mistake, same speed for sending;
  sources disagree, flagged in the app), ARRL Code Proficiency (1 min solid
  copy, receive only; the 10–40 WPM steps are from memory of the W1AW schedule,
  W1AW also has 13 WPM). Ukraine class 1, Belarus class A, Estonia class A and
  Monaco still require Morse but no exam format was found → use the custom
  profile.
- Text length is measured in dit units (`ExamProfile.targetUnits` = wpm × 50 ×
  minutes), not characters: "wpm × 5 characters" is only ~5/6 of the time
  (spaces and E/T are quick; a PARIS word is 5 letters plus a gap). Figure
  groups: ~89 units each, letter/figure groups ~71, so groups = wpm × minutes ×
  50 / units.
- The send speed estimate also uses dit units (`morseUnits`), so a perfectly
  keyed text at the exam speed measures the exam speed for every text kind.
  The pass threshold is now a decimal (85 % of the exam WPM).
- Custom profile: stored as JSON in prefs `exam.custom`; its id encodes all
  settings (`custom:w/c/m/e/retries/kind/flags`), so history, forecast and the send
  speed are per configuration. Clamped: 5–40 WPM, 1–10 min, 0–20 errors.
- Retries (2026-10-06): `ExamProfile.retries` is modelled per screen session and
  part: result shows "attempt n of retries+1"; after a fail with attempts left
  the button is "Retry" (new text, attempt+1); with none left the part counts as
  failed ("New exam" resets to attempt 1). Passing restarts at 1. Not persisted;
  every attempt is still stored as its own result. The rules card in the setup
  now lists receive and send rules (send: minutes, errors, speed, 80 % text).
- Custom profile also has retries (0–5, JSON `r`), same attempt logic as the presets.
- Text language (2026-10-06): plain texts are German only for AT/DE; UK, NZ,
  India and USA use English (`exam_texts_en.dart`: 100+ sentences, QSO lines
  with call signs and towns of the country). The custom profile has a language
  setting (`lang`, JSON `g`, part of the id). Figure and letter groups have no
  language. The home Learn card now names the exam simulation.

## Practice time in the progress view (2026-10-06)

- **Source: the practice log** (`PracticeClock` / `PracticeLog.days`, #30) — the
  same active time the daily goal counts, so the two always agree. Spread
  (5 min sessions, 15 min pause, #33) only matters for the goal; the total
  keeps counting whenever the user practises actively. A first attempt added
  its own estimate to `DayStat` (cap per block/word); it was dropped because it
  duplicated the clock, was less exact and had no history.
- **Per training:** `PracticeDay.modes` (JSON `m`) books every credited second
  to the mode of the screen on top (`hear`, `echo`, `game` …). The Listen tab
  shows `hear`, the Send tab `echo`, next to the total of all trainings. Days
  from before the split have no modes: their time is only in the total
  (`unsplitDays`, announced by a note); days before the practice log have none.
- `buildSeries(..., practice:, track:)` adds each log day's seconds to its
  bucket (the 04:00 day key is read as a plain date).
- Shown as "h min", with days only for the range *All* from 24 h on.

## 2026-10-06: UI font DM Sans, Anonymous Pro only for Morse text

The monospace look (Anonymous Pro for almost all text, Space Grotesk for a few
titles) read as dated. Now `ThemeData.fontFamily` is **DM Sans** (SIL OFL 1.1,
`assets/fonts/DMSans.ttf`, variable font; Space Grotesk removed). `CwMono`
(Anonymous Pro) stays wherever the text *is* Morse content: decoded/typed/sent
text in CW Keyer, Decoder, QSO Bot and WiFi Trx logs and send fields, text
adventure log and input, own-text player, exam texts, characters in Hören/Geben
and the games, alphabet/Koch character grids, Morse tree and chart, key and
paddle labels (DIT/DAH), head copy/Mini QSO/Q-group transcripts. Labels,
titles, hints, buttons, settings, statistics and dialogs use DM Sans.
Per-file helpers (`_mono`) now give the UI font; the Morse variant is `_morse`
(or an explicit `fontFamily: 'CwMono'`). Canvas text (`TextPainter`) does not
inherit the theme font, so such styles must set `fontFamily: 'DMSans'` themselves
(`progress_charts.dart`).

## 2026-10-08: Light theme "navy mist", optional blue light filter

The old light theme (pure white cards on near-white) glared and clashed with the
navy dark theme. `AppColors.light` is now a cool blue-grey family derived from
the dark hues (bg `#DCE1EE`, cards `#EEF1F8`); dark is unchanged. In light mode
the daily-goal ring and week dots are teal (soft teal track, thicker stroke);
dark keeps the blue ring.

Blue light filter (Settings → Appearance, off by default, 10–100 %): a
`ColorFiltered` colour matrix (blue ×(1−0.69t), green ×(1−0.265t); 0.75/0.25 looked yellow-green and too strong at 100 %, 0.5/0.28 too pink, 0.62/0.28 still in between) wrapped around
the whole app in `MaterialApp.builder`, so dialogs and sheets are covered and
both themes use it. The matrix also dims overall brightness by up to 20 % (all channels × (1−0.2t)): the brightest text (stat values, quotas) glared in the warm tone. Chosen over an alpha overlay because a multiply-style
matrix keeps dark backgrounds dark. Off = no extra layer (no cost for the games).
Not covered: Android status/navigation bars. Stored in prefs `blueLightOn`,
`blueLightStrength` (`BlueLightFilter` in `theme_controller.dart`).

Status bar: optional "hide status bar" (Settings → Appearance, off by default,
pref `hideStatusBar`): `SystemUiMode.manual` with only the bottom overlay, so
the 3-button navigation stays; re-applied on app resume (`StatusBarMode`). It
exists because the blue light filter cannot tint the system bars.

## Display name changed to "APEX CW"; internal identifiers stay
User request: new app name "APEX CW". Checked beforehand (TMview over EUIPO,
ÖPA, DPMA, USPTO; Play Store, App Store AT/DE/US, GitHub, domains, 2026-10-08):
no "APEX CW"/"APEXCW" mark or app, none of the 737 live/pending "APEX" marks in
classes 9/41/42 relates to CW/radio. "APEX" alone is a crowded word mark — no
exclusivity claim on it. Not a legal clearance.
Changed: everything a user sees — manifest label, `MaterialApp` title, home
app bar, About dialog, licence page, manual DE+EN, README, PRIVACY, Play
listing, site, store graphics script, pubspec description.
Deliberately **not** changed: `applicationId`/namespace `at.oe1cko.nextcwtrainer`
(changing it makes a new app: no update, no data migration, no Play continuity),
Kotlin package + JNI symbols, Dart package `next_cw_trainer`, channel names,
GitHub repo name and folder. Older entries (this file, `STATUS-ARCHIVE.md`)
keep the old name as history.
Follow-up (same day): GitHub repo renamed `next_cw_trainer` → `apex-cw` (old
repo/issue/release URLs redirect; the Pages site moved to
`ckonecny.github.io/apex-cw/`, the old Pages URL does not redirect). Built
manuals are now `APEXCW_Handbuch_v<version>.*` / `APEXCW_Manual_v<version>.*`
(supersedes the `NextCWTrainer_…` names mentioned further up), release
artefacts `releases/apex-cw-<tag>.{apk,aab}`. The text inside the already built
`manual/APEXCW_*_v1.6.0.html/pdf` still says "Next CW Trainer" until the next
release rebuild.

## 2026-10-08: Weak characters follow the upper success threshold
User report (a learner at 95 % upper threshold): one slip drops a char to 80 %, and 7 correct hits of that char are needed to get back to 95 % — about 84 characters at 12 active chars, because the unlock needs *all* chars above the threshold at once. The automatic boost only started below 88 % (fixed 12 % error), so chars between 88 % and 95 % blocked the unlock without being drilled. Now `weakCharErrorThreshold(high)` = 1 − high, clamped 2–12 % (`char_stats.dart`): a weak char is exactly one that blocks the unlock; never laxer than the old 12 %, and 99 % does not make every imperfect char weak. Used by Adaptive Copy (`AdaptiveCopyBody._weakCharsNow`) and the Echo suggestions. Boost level stays Moderate (3 draws, ≈2.7× for one char at 12 active) — Strong was too extreme (2026-09-23). Min. 8 attempts and max. 5 shown unchanged. No new setting. Manual DE+EN "Schwache Zeichen"/"Weak characters" updated.

## 2026-10-08: Head copy lives under Practice, not Games

Head copy (Verstehen) is a trainer, not a game, so it moved from the Games hub
to a third tile under Practice on Home. The home layout formula in
`home_screen.dart` now counts six cards and two gaps; on small phones or with a
large system font the page scrolls earlier (the existing fallback).

Home tile subtitles are limited to one line (`maxLines: 1`, min card height
58 × text scale) so six cards plus the goal card fit without scrolling on
common phones; the Free, Games and Learn subtitles were shortened to ≤ ~32
characters in both languages.

## 2026-10-09: Frequency-weighted word lists (EN + DE), own build, not the firmware's (#53)

The firmware now draws words from a larger Oxford-5000-based list, weighted by
frequency. We do not copy it: the Oxford list has no licence we can reuse (rule
11), and the firmware list is English only. Instead `android/assets/words/{en,de}.txt`
("word weight" per line) are built from hermitdave/FrequencyWords (content
CC-BY-SA-4.0, OpenSubtitles, one-way compatible with GPL-3.0-or-later; the word
files stay CC-BY-SA, text in `assets/words/CC-BY-SA-4.0.txt`, registered in
`licenses.dart` and `license_compat_test.dart`). Filters (`tools/wordlists/`):
a-z only (German: no umlauts/ß, words with them are left out), no names,
interjections, subtitle artifacts, violence, crime, drugs, sex, swearing;
English in US spelling. English 3500 words (length 2-10), German 2500 (2-12).
`CwGenerator.randomWord()` picks weighted (cumulative sum + binary search) and
keeps the Koch filter, min/max length and the single-character fallback. New
profile setting `wordLanguage` (0 English default, 1 German), sent with the
generator config like `wordLengthMin`. The old 373-word list was removed from
`CwGenerator.kt` (an unreadable asset gives an empty list, the generator then
draws single characters); Morsel's `getWordLists` always returns English.
The Words chip in `CharsetHeader` shows roughly how many different words the
practice can draw from ("Words · ca. 190", `lib/content/word_pool.dart`):
language list filtered by the min/max word length and, for a Koch lesson, by the
unlocked characters (same rule as `CwGenerator.kochQualifies`); rounded to
exact < 10, steps of 5 < 100, 10 < 1000, else 100.

## 2026-10-09: Long press on the Koch / Words chip opens the settings at its section

`showTrainingSettingsSheet(jumpTo:)` scrolls the (unchanged, complete) sheet to
a section via per-section `GlobalKey` + `Scrollable.ensureVisible`; the body is
now a `SingleChildScrollView` + `Column` instead of a lazy `ListView`, so every
section is built and can be found by key. `CharsetHeader` has `onKochLongPress` /
`onWordsLongPress`; Generator and Echo select the chip first (like a tap, saved)
and then open the sheet at `kochSequence` / `wordSelection`. The Koch section
exists only in the Koch Trainer's sheet; elsewhere the sheet opens at the top.

## 2026-10-09: Decoder Chars (#52)

Port of the firmware's post-V9.0 "Decoder Chars" (commit 1013025). The firmware
adds tree nodes 69-72 and a `decodedSymbol()` table keyed by node; here the
table (`lib/keyer/decoder_chars.dart`) is keyed by the dit/dah pattern instead,
so the existing tree in `cw_audio_decoder.dart` is unchanged (the audio decoder
just records the pattern of the current character) and `MorseDecoder` looks the
pattern up before its fixed table. Same result as the firmware, one table for
both decoders. Global pref `decoderChars` (0 Standard, 1 ITU, 2 Fr/Es/Pt,
3 Sv/Fi, 4 Da/No), not part of a training profile or snapshot. Only the CW
Decoder and the CW Keyer set `chars`; `MorseDecoder` defaults to Standard, so
trainers, games and the QSO bot are untouched (they compare keyed text with
their own). The settings text says explicitly where it applies and where not.
Part B (sending these letters) stays out of scope.

## 2026-10-09: Learn from the mistake in Listen → Type (#50)
New profile key `typeOnWrong` (0 repeat, 1 learn; hear profile, in `TrainingProfile._intFields`). In **learn** mode a wrong first answer does not trigger a retry: the word is played again (`_TypeState.learn`) while `MistakeLesson` shows every character with its dit/dah pattern (`morsePattern`, the decoder table inverted) below the letter. The sounding character is highlighted by counting the generator's `elementOn` events against the pattern lengths, so the display follows the audio instead of a timer. After the sound plus 1 s the next word follows; the solution screen is skipped. "Attempts per word" is greyed out in that mode. Grading is unchanged (first attempt only, `gradeTyped`); a pass counts as a mistake: error tone, lesson, all characters red. The lesson's wrong characters (first attempt) are red; the sounding one gets a tinted background. Pauses: 0.9 s after the error tone, 1.8 s after the lesson. Dits/dahs are drawn as dots and bars (thin glyphs were hard to see). Scope: only the Listen typing flow; the Echo trainer is untouched. Pure Dart, shared native engine unaffected (rule 2).

## 2026-10-09: Focus mode: Do Not Disturb while practising (#55)

Optional setting (Settings → General, off by default). While a training screen is open the system interruption filter goes to Priority, so the user's own DND exceptions (e.g. starred callers) still apply and the app has no call logic of its own. Chosen over screen pinning (needs a confirmation every time, blocks too much) and over an own `AutomaticZenRule` (more version dependent; can be added later).
- Needs the special "Do Not Disturb access" grant (`ACCESS_NOTIFICATION_POLICY`, no declaration form in the Play Console). Without it the setting shows a button for the grant and one that opens the DND settings, so the user can switch DND on by hand (fallback).
- Hook: `PracticeClock.onActive` / `onIdle` (first training screen opened or app back in the foreground / last one left or app in the background), not per-screen code (rule 2).
- Native `FocusMode.kt` saves the previous filter in its own prefs and puts it back on release and in `onDestroy`; `configureFlutterEngine` repairs a filter left by a crash or kill. A stricter mode the user chose (Alarms only, Total silence, or Priority already) is never changed.
