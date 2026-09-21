# Adaptive Copy Mode — Design Notes

Status: planned, not started. Not a firmware port — this concept has no
`reference/` equivalent; it originates from a separate ESP32 CW-trainer
project and is being added here as a net-new mode. Existing modes/data stay
untouched (per CLAUDE.md hard rules).

Full original concept doc (German, user-provided): see conversation history
for now — worth moving into this file verbatim if a permanent home is
needed. Short version below.

## Concept

User listens to a block of character groups, copies on paper (nothing shown
on screen during sending). App then reveals the sent text; user taps
characters that were wrong. App keeps per-character stats (attempts, errors,
moving error rate) and uses them to adapt future blocks: which characters
get drilled more, and whether char speed / spacing / Koch level should
change. Stage 2 (later): user also says what they wrote instead, building a
confusion-pair matrix.

## Decisions made so far

- **Entry point:** not a new Home-screen card. It's a third axis inside the
  existing `GeneratorScreen` (which today only has the `kochMode` bool) — a
  "Classic"/"Adaptiv" segmented control, switching which internal flow
  renders. Reached via the existing "CW Generator" / "Koch Trainer" Home
  cards, same as today.
  - **Correction (important, was implemented wrong once already):** this is
    NOT a new content-mode entry sitting next to Random/Abbrevs/Words/Mixed
    (the way Echo Trainer's existing "Adapt. Rand." sits next to Random —
    that's pre-existing behavior, not something to imitate here). Classic
    vs. Adaptiv is **orthogonal** to content-mode choice: the user still
    picks Random/Abbrevs/Words/Mixed (Koch-nested) or
    Random/Words/Callsigns/Mixed/Practice Set/Abbrevs (non-Koch) exactly as
    today, and *separately* picks Classic or Adaptiv as the playback/UI
    flow for whichever content mode is active. Toggle placement: either in
    Settings or directly in the training screen — whichever doesn't clutter
    that screen's GUI (open to either, decide at implementation time).
  - **Priority: build the Koch Trainer (`kochMode: true`) side first.** The
    non-Koch CW Generator and later Echo Trainer reuse of the same flow are
    explicitly follow-ups, not part of the first working version.
- **Character stats: shared with Echo Trainer, not a separate model.**
  New `CharStatsStore` (attempts, errors, moving error rate, last-seen
  block) replaces Echo Trainer's current ad-hoc `Map<String,int>`
  `_adaptiveWeight` (`adaptiveWeights` SharedPreferences key, used only by
  "Adapt. Rand." / `_kochModeIndex == 4`). Migrate the old format into the
  new one on first load so existing user data isn't lost.
- **Group/block sizing:** reuse the existing `groupLength` and `maxWords`
  prefs — no new size settings. A "block" = one full exercise pass (send
  `maxWords` groups of `groupLength` chars → reveal → mark → result); no
  fixed session length, user starts as many blocks as they want.
- **No transcript-typing / edit-distance comparison.** Explicitly dropped —
  tap-to-mark only (Stage 1), tap-what-I-wrote-instead only (Stage 2).
- **Thresholds must be user-configurable**, not hardcoded: success-rate
  high/low thresholds (defaults 90%/70%), N for character unlock (default
  20), WPM step size (default 1) — new "Adaptive Mode" section in
  `settings_screen.dart`, persisted like other settings.
- **Adaptive engine must be reusable, not Adaptive-Copy-specific.** The
  weighting/tempo-adjustment logic in the planned
  `adaptive_copy_engine.dart` takes generic inputs (a list of
  `(char, correct)` results, current tempo values) rather than a
  block-shaped object tied to this screen, so Echo Trainer's own "Adaptive
  Speed" (currently a flat every-10-correct bump,
  `echo_trainer_screen.dart:513`) can eventually call into the same logic
  instead of its own parallel implementation.
- **Planned new files:** `lib/content/char_stats.dart` (shared stats store),
  `lib/content/adaptive_copy_engine.dart` (pure-Dart, injectable RNG, unit
  testable per CLAUDE.md/docs testing conventions), `lib/ui/adaptive_copy_screen.dart`
  (or an embedded phase-state inside `GeneratorScreen` — TBD at
  implementation time), optionally a shared `char_grid.dart` widget for the
  mark-errors / mark-confusion grids (≥48dp touch targets).
- **Planned build order (revised):**
  1. ~~`char_stats.dart` + migrate Echo Trainer onto it~~ — done.
  2. ~~Koch Trainer UI skeleton: Classic/Adaptiv toggle + the send → reveal →
     mark → result phase flow, fixed/manual tempo values~~ — done, built,
     installed, user-tested on device, confirmed working
     (`android/lib/ui/adaptive_copy_body.dart`, toggle in
     `generator_screen.dart`). Content mode selection
     (Random/Abbrevs/Words/Mixed) stays exactly as today and just feeds into
     whichever flow is active, as intended.
  3. ~~`adaptive_copy_engine.dart`~~ — done: `AdaptiveCopyEngine` with
     `recordBlock()` (blockquote-EMA-driven spacing/char-speed step
     decision) and `shouldUnlockNextChar()` (per-char EMA + attempts-floor
     unlock decision), per "Decisions: weighting/recency questions" below.
     10 unit tests in `android/test/content/adaptive_copy_engine_test.dart`,
     all passing. **Not yet wired into `AdaptiveCopyBody`** — no RNG
     injection needed (the engine consumes results, it doesn't generate
     content), so that part of the original plan didn't apply. **← current
     step is now 4.**
  4. ~~Settings section for the configurable thresholds~~ — done: "Adaptive
     Mode" section in `settings_screen.dart` (4 sliders: Success Threshold
     High/Low, EMA Smoothing, Occurrences for Unlock; stored as
     `adaptiveHighThresholdPct`/`adaptiveLowThresholdPct`/
     `adaptiveEmaAlphaPct`/`adaptiveUnlockOccurrences` SharedPreferences
     keys, percent/int for slider-friendliness — convert to the 0..1
     doubles `AdaptiveCopyThresholds` expects at the call site). Built,
     installed on `63061JEBF01551`. Not yet exercised on-device beyond
     "sliders move and persist" — no other code reads these values yet;
     that's step 5.
  5. ~~Wire `AdaptiveCopyEngine` into `AdaptiveCopyBody._finishBlock()`~~ —
     done: `_finishBlock()` builds the per-block `List<bool>`, loads
     `AdaptiveCopyThresholds` from the settings above (lazily creates the
     engine, restores `blockEma` from a new `adaptiveBlockEma`
     SharedPreferences key), calls `recordBlock()` and
     `shouldUnlockNextChar()` (against `kochActiveChars(kochLevel,
     activeKochChars)`'s `CharStat`s), and applies the result via three new
     `AdaptiveCopyBody` callbacks (`onWpmChanged`, `onKochLevelChanged`,
     `onSpacingChanged(interCharSpace, interWordSpace)`) that
     `GeneratorScreen` wires to its own `_wpm`/`_kochLevel`/
     `_interCharSpace`/`_interWordSpace` state + `_savePrefs()` (now also
     persists `interCharSpace`/`interWordSpace`, previously never written
     from this screen). Spacing step size is 1 dit per block; char-speed
     step is +1 wpm (docs said "+1..+2" — started at the simpler +1, easy
     to widen later). The spacing "down" floor and "up" floor are enforced
     via `_startInterCharSpace`/`_startInterWordSpace`, captured once from
     the widget's initial values (see "Success-rate high/low thresholds"
     below for the floor rationale). Result screen shows small notice chips
     (spacing tightened/widened, char speed increased, character unlocked)
     — new `ac_spacing_up`/`ac_spacing_down`/`ac_char_speed_up`/
     `ac_char_unlocked` strings. Built, installed on `63061JEBF01551`.
     **Not yet run through a full multi-block session on-device** — only
     confirmed it builds/installs; behavior (does spacing actually tighten,
     does a char actually unlock) still needs a real test run. **← current
     step is now 6.**
  6. **← current step.** On-device test: run several Adaptive Copy blocks
     with intentionally high and low accuracy, confirm spacing/char-speed
     actually step as expected and a character unlocks once its stats clear
     the threshold; verify timing (incl. Farnsworth spacing) sounds right.
  7. Extend Classic/Adaptiv toggle to the non-Koch CW Generator.
  8. Stage 2 (confusion pairs) as a further follow-up.
  9. Echo Trainer reuse of `adaptive_copy_engine.dart`'s tempo logic — later,
     opportunistic.
  10. **Later session, not v1:** replace/extend the EMA (step 3) with real
      trend detection (improving/degrading/flat), per decision 1 below.

## Decisions: weighting/recency questions (answered 2026-09-21)

The three open questions from the previous session are now resolved:

1. **Time window per decision: EMA, not last-block-only, not full trend
   detection (yet).** Char-speed/spacing decisions are driven by an
   exponential moving average of blockquote success rate (and, per
   character, of that character's own hit rate), not just the most recent
   block. Actual trend detection (improving/degrading/flat classification)
   is explicitly deferred — **not** part of the first version.
   - **Follow-up flag for a later session:** replace/extend the EMA with
     real trend detection once the EMA version is working and calibrated.
     Track this as a future step (see build order below) so it isn't lost.
2. **Signal precedence: independent, simultaneous.** Tempo/spacing-step
   decisions (driven by the EMA of overall blockquote success) and
   per-character drill-weight/unlock decisions (driven by each character's
   own last-N-occurrences window, per "N=20 for character unlock" below)
   run independently and do not block or override each other. A block can
   simultaneously raise tempo *and* keep drilling a still-weak character.
  **Confirmed (2026-09-21): content selection for Adaptive Copy is a plain
  uniform draw over the active Koch set** (`CwGenerator.randomKochChars()` →
  `active.random()`, no error-rate weighting — that weighting only exists
  for Echo Trainer's separate "Adapt. Rand." `weight` field, which Adaptive
  Copy never reads). This matters for interpreting step 6 below: with N
  active chars, each gets on average `blockSize/N` occurrences per block, so
  reaching the unlock-occurrence floor (default 20) for the *slowest* of N
  characters (binomial variance, not just the average) can genuinely take
  many blocks — not a sign anything is broken.
3. **Start simple: no.** The user explicitly wants the EMA-based logic
   (per point 1) in the first version, not the flat "threshold × 2
   consecutive blocks" rule from the original concept sketch. The
   consecutive-blocks rule is superseded by the EMA approach below.

### EMA design for v1 (to pin down while implementing)
- Blockquote-level EMA: one EMA over per-block success rate, feeding the
  tempo/spacing step decision (still uses the existing high/low thresholds,
  default 90%/70%, but evaluated against the EMA value instead of two raw
  consecutive blocks).
- Per-character EMA or last-N window: per "N=20 for character unlock" below,
  each character's own last-N-occurrences hit rate drives its unlock
  decision, independently of the blockquote-level EMA.
- EMA smoothing factor (alpha): not yet chosen — needs a sensible default
  (e.g. alpha giving roughly N=5–10 block half-life) exposed the same way as
  the other Adaptive Mode thresholds (user-configurable, per "Thresholds
  must be user-configurable" above), or hardcoded with a comment if the user
  prefers not to expose it. Decide at implementation time; ask if unclear.

## Result-screen transparency (added 2026-09-21, still part of step 5)

After testing questions came up about what the notices actually mean, the
result screen (`AdaptiveCopyBody._buildResult`) now always shows a status
line — `WPM {wpm} · Spacing {interCharSpace}/{interWordSpace} · Trend
{blockEma%} {▲/▼/=}` — plus, on the notice chips themselves, the concrete
before→after values (e.g. "Abstand verkürzt: 4→3 / 8→7") instead of just a
bare label. Design choices made (both per explicit user preference over
alternatives — a block-history list and a sparkline were the other
options):
- Trend shown as the single current blockquote-EMA value with an up/down/
  flat arrow vs. the previous block, not a history list or chart. Simple,
  and it's literally the number the engine's decisions are driven by, so
  it doubles as a way to understand *why* a decision did or didn't fire.
- Current wpm/spacing values always shown, not just on change — so it's
  always clear what the trainer is currently doing, not only when it just
  changed something.
- "Abstand" ("spacing") explicitly means `interCharSpace` AND
  `interWordSpace` together, stepped by 1 dit each per block — this was a
  real point of confusion, worth restating here for the next session too.

This doesn't change the underlying decision logic (still EMA-based, per
"Decisions: weighting/recency questions" above) — it only makes that logic
observable, which is a prerequisite for actually testing/interpreting step
6 below. The "let the user override the suggestion" TODO (see "Flagged
TODOs" below) is still open and is a different, bigger change.

## Starting point for the next session

Steps 1–5 are done and built/installed on `63061JEBF01551`, but **not yet
exercised through a real multi-block session** — that's step 6, and it's a
user/device task, not something verifiable from the source alone:

1. Open Koch Trainer → Adaptiv, run several blocks marking (almost) everything
   correct, and confirm: after ~2+ high-scoring blocks, a spacing-tightened
   notice appears and `interCharSpace`/`interWordSpace` in Settings actually
   move down by 1 each; once spacing reaches 3/7 dits, a further good block
   should show "char speed increased" and bump WPM.
2. Run blocks marking many wrong, confirm a spacing-widened notice appears
   and spacing moves back up (capped at the value it started at when you
   opened the screen — see `_startInterCharSpace`/`_startInterWordSpace` in
   `adaptive_copy_body.dart`).
3. Drill one specific character to ≥20 correct occurrences (or whatever
   "Occurrences for Unlock" is set to in Settings → Adaptive Mode) at a high
   hit rate while keeping others below threshold or below the occurrence
   floor, confirm a "character unlocked" notice appears and the Koch level
   slider in the training screen actually increments.
4. Listen for correct timing throughout, including Farnsworth-style
   spacing if `interCharSpace`/`interWordSpace` were pushed away from
   3/7.
5. Report back what works vs. doesn't — the step sizes (1 dit for
   spacing, +1 wpm for char speed) and the "spacing at char speed" gate in
   `adaptive_copy_body.dart::_finishBlock()` are first-guess values, not
   verified against real training feel yet.

## Open points (to clarify before/while implementing)

### N=20 for character unlock — meaning confirmed
Per-character, not per-block: look at that character's last N (default 20)
*occurrences across blocks*, compute its hit rate over just those. Once
every currently-active character clears the high threshold (default 90%)
over its own last-N window, the next character in the Koch sequence
auto-unlocks (Koch level +1). This would be a new *automatic* alternative
to the existing manual Koch-level slider — needs a decision on whether it
replaces, supplements, or is optional relative to the manual slider.

### Success-rate high/low thresholds — meaning confirmed, evaluation updated
Drive char-speed/spacing only, separate from the N-based unlock:
- Blockquote EMA ≥ high threshold (default 90%) → spacing speed +1 step.
  (Supersedes the original "two consecutive blocks" phrasing — see
  "Decisions: weighting/recency questions" above: evaluated against the EMA,
  not two raw consecutive blocks.)
- Blockquote EMA < low threshold (default 70%) → spacing speed −1 step (not
  below the configured start value).
- Only once spacing speed == char speed does char speed itself step up
  (+1..+2).

### Resolved — weighting/recency question
See "Decisions: weighting/recency questions (answered 2026-09-21)" above:
EMA-based time window, independent/simultaneous signal precedence, full
EMA (not the flat threshold rule) for v1. Trend detection deferred to a
later session (build order step 9).

### Also still open (carried over from the original concept doc, unchanged)
- Whether/how results from this mode ever merge with the pre-existing Koch
  Trainer statistics (currently: no, kept separate at the storage level,
  merged only via the shared `CharStatsStore` character-weighting logic).
- Persistence: confirmed to reuse `SharedPreferences` like everything else;
  exact schema (JSON blob vs. per-key) to be finalized when
  `char_stats.dart` is written.
- Block-protocol logging (timestamp, sent text, marked positions, tempo,
  blockquote) — recommended in the concept doc so stats can be recomputed
  if rules change later; not yet designed.

## Flagged TODOs (2026-09-21, not yet scheduled into the build order)

Raised by the user after step 5 (engine wiring) landed; not yet designed or
estimated, just captured so they aren't lost:

- **User override on the result screen — DONE (2026-09-21, built/installed
  on `63061JEBF01551`, not yet exercised at the device).** `_finishBlock()`
  now only computes the engine's proposals (`_pendingWpm`,
  `_pendingInterChar`/`_pendingInterWord`, `_unlockedThisBlock`) instead of
  applying them. The result screen shows each as a tappable row
  (`_SuggestionRow` in `adaptive_copy_body.dart`) with a checkbox
  (default: accepted, same net effect as the old automatic behavior) and
  +/- steppers to nudge the magnitude (WPM clamped to
  `[widget.wpm, widget.wpm + 5]`; spacing clamped to the existing
  `[3, _startInterCharSpace]` / `[7, _startInterWordSpace]` bounds). Nothing
  is pushed to `GeneratorScreen`'s state until `_applyPendingDecision()`
  runs, called from both "Finish" and "Next Block". "Next Block" passes the
  resolved values straight into `_startBlock()`'s new
  `wpm`/`interCharSpace`/`interWordSpace` overrides rather than rereading
  `widget.*`, since the parent's rebuild from the `on*Changed` callback
  hasn't happened yet at that point in the same synchronous call. Scope
  note: only the three suggestions the engine actually produces today
  (char speed, spacing, unlock) got override controls — "weak-character
  drill weight" isn't a real lever in `AdaptiveCopyEngine` yet, so there
  was nothing to add a control for.
- **Surface adaptive state in Settings, and confirm it survives app
  restarts.** Weak characters / the currently "determined" (adapted) speed
  should be visible in `settings_screen.dart`, not just implicit in
  `AdaptiveCopyBody`'s live state. Note: the underlying persistence mostly
  already exists — `CharStatsStore` saves to SharedPreferences on every
  `_finishBlock()` (`char_stats.dart`), and step 5's `_savePrefs()` now also
  persists the adapted `wpm`/`interCharSpace`/`interWordSpace`/`kochLevel`
  — but this hasn't been verified end-to-end (kill app, reopen, confirm
  nothing reset) and none of it is currently *shown* anywhere in Settings.
  Both parts (verify persistence, add Settings visibility) are open.
- **Echo Trainer needs its own adaptive signal, not a 1:1 reuse.** Per the
  user: sending (copying by ear onto paper, what Adaptive Copy measures)
  and receiving/echoing back (what Echo Trainer measures) can diverge per
  character or per speed — someone can struggle keying a character back
  but hear it fine, or vice versa. The existing "Adaptive engine must be
  reusable" plan (build order step 9: Echo Trainer reuse of
  `adaptive_copy_engine.dart`'s tempo logic) assumed the same weighting
  could drive both. That assumption is now explicitly wrong: Echo Trainer
  needs its own separate stats track (or a separate dimension within
  `CharStatsStore`) rather than sharing Adaptive Copy's numbers outright.
  Revisit step 9's design before implementing it.
- **Threshold sliders let High < Low be set — DONE (2026-09-21, built/
  installed on `63061JEBF01551`, not yet exercised at the device).**
  `settings_screen.dart`'s two independent high/low sliders had no
  cross-validation. Replaced with a single `RangeSlider` (`_LabeledRangeSlider`,
  new widget) showing both thumbs on one track, low always ≤ high with a
  5-point minimum gap enforced in the `onChanged` handler (dragging one
  thumb into the other pushes it along rather than letting them cross).
- **Unlock proposal not visually distinct on the result screen — DONE
  (2026-09-21, built/installed on `63061JEBF01551`, not yet exercised at the
  device).** It already had its own accept/reject checkbox from the override
  UI work above — that part was already done, just easy to miss since all
  three suggestion rows looked identical. Now: unlock row moved first, gets
  a star icon, bold text, thicker/more opaque accent border, and names the
  actual next character (`"$nextChar"` from `widget.activeKochChars[widget.kochLevel]`)
  instead of a generic "New character unlocked" label.
- **High threshold = 100% was a silent, permanent unlock trap — DONE
  (2026-09-21, found via on-device debug logging, built/installed on
  `63061JEBF01551`).** User report: Koch level 5, 5 active chars, "Occurrences
  for Unlock" set to the minimum (5), 7 blocks in a row marked 100% correct —
  never unlocked. Root cause, confirmed via a temporary debug log of
  `CharStat.attempts`/`emaErrorRate`: attempts were all 46-63 (way past the
  floor), but the High Threshold setting had been dragged to 100% while
  testing the new range slider. `CharStat.emaErrorRate` only decays toward 0
  *asymptotically* (`ema = 0.2*0 + 0.8*ema` per correct hit) and is never
  reset across a character's lifetime — so once a character has had even one
  error, ever (including from a previous session, or Echo Trainer usage
  sharing the same `CharStatsStore`), `1 - emaErrorRate` can get arbitrarily
  close to 1.0 but never exactly reach it again. A 100% threshold is
  therefore an invisible permanent trap for any character with error history,
  and both the unlock check and the tempo/spacing check (`recordBlock`) use
  the same high-threshold comparison. Fixed by capping the Settings range
  slider (and, defensively, the value `AdaptiveCopyBody` actually reads out
  of SharedPreferences) at 99% instead of 100%. Same trap doesn't apply
  symmetrically to 0% on the low end — a low threshold just means "spacing
  never widens," a valid (if extreme) choice, not a trap — so only the high
  side was capped.
- **"Spacing widened: 11→11" no-op notice — DONE (2026-09-21, built/
  installed on `63061JEBF01551`).** User report after step 6 testing: a
  spacing suggestion row showed identical before/after values. Root cause:
  `_finishBlock()` checked only `decision.spacingStep != TempoStep.none`
  before proposing a spacing change, not whether the clamp to
  `[3, _startInterCharSpace]`/`[7, _startInterWordSpace]` actually changed
  anything — already at the session's ceiling (or floor), the engine still
  said "widen" (or "tighten"), but `(value ± 1).clamp(...)` clamped straight
  back to the same value. Fixed: both branches now compare the clamped
  result against the current value and only set `_pendingInterChar`/
  `_pendingInterWord` (i.e. only propose a row at all) when it's a real
  change.
- **Weak characters only reflected this block, not the character's actual
  history — DONE (2026-09-21, built/installed on `63061JEBF01551`).** User
  report: a character marked wrong last block dropped off the "weak
  characters" list entirely as soon as a block didn't happen to include it
  (or did, and was right that once) — the display was built from
  `_wrongPositions` of the just-finished block only, not from the
  character's persistent stats. Replaced with `_weakCharsLifetime()`:
  reads `CharStat.emaErrorRate`/`attempts` from the same lifetime-persistent
  `CharStatsStore` the unlock/tempo logic already uses, filtered to the
  active Koch set, requiring `attempts >= 8` (so one unlucky group can't put
  a character on the list) and `emaErrorRate >= 0.12`, sorted worst-first,
  capped at 5 shown. Chips now show the lifetime error-rate percentage
  instead of a raw this-block miss count.
- **User override on which characters get drilled more — DONE (2026-09-21,
  built/installed on `63061JEBF01551`, not yet exercised at the device).**
  This closes the "weak-character drill weight isn't a real lever yet" scope
  note from the override-UI entry above. The weak-character chips on the
  result screen are now tappable: each toggles whether that character is
  included in a boosted draw for the next block (excluded chips show
  grayed-out + struck through). Reuses the existing `practiceChars`/
  `boostLevel` mechanism already wired into
  `CwGenerator.kt randomKochChars()` for CW Generator's "Practice Set" +
  Boost feature and Echo Trainer's "Adapt. Rand." — `AdaptiveCopyBody`
  pushes the accepted weak-char set with `boostLevel=2` ("Strong", same
  tier M32 calls strongest) via `setPracticeChars`/`setBoostLevel` right
  before fetching each block's content, or clears both (`[]`/`0`) when
  nothing is accepted. Per CLAUDE.md rule 2 (shared singleton, nothing
  re-syncs automatically): `AdaptiveCopyBody.dispose()` restores the
  Settings-persisted `practiceChars`/`boostLevel` so switching back to
  Classic mode (or Echo Trainer) within the same `GeneratorScreen` session
  doesn't inherit Adaptive Copy's leftover boost state.
- **Reset character statistics — DONE (2026-09-21, built/installed on
  `63061JEBF01551`).** New `CharStatsStore.reset()` (`char_stats.dart`)
  clears `stats` and removes the SharedPreferences key. Exposed in
  Settings under Adaptive Mode as a red `_ActionButton` ("Reset Character
  Statistics") gated behind an `AlertDialog` confirmation. Affects both
  Adaptive Copy (weak characters, unlock, boost) and Echo Trainer's "Adapt.
  Rand." — the dialog body says so, since it's not obvious from Adaptive
  Mode's settings section alone that this is a shared, cross-mode reset.
