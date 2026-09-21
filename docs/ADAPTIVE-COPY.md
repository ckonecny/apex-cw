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
  3. **← current step.** `adaptive_copy_engine.dart` (pure-Dart, injectable
     RNG, unit tested) — blocked on the weighting/recency question below;
     see "Starting point for the next session".
  4. Settings section for the configurable thresholds.
  5. Rebuild/install + on-device test (timing incl. Farnsworth).
  6. Extend Classic/Adaptiv toggle to the non-Koch CW Generator.
  7. Stage 2 (confusion pairs) as a further follow-up.
  8. Echo Trainer reuse of `adaptive_copy_engine.dart`'s tempo logic — later,
     opportunistic.

## Starting point for the next session

Everything through step 2 is done and confirmed working on-device. Next
up is step 3, `adaptive_copy_engine.dart`, gated on three concrete
questions the user still needs to answer (asked once already, not yet
answered — don't re-derive, just ask again at the start of that session):

1. **Time window per decision.** Should char-speed/spacing decisions look
   only at the most recent block (as the original concept sketch says: "≥90%
   two blocks in a row"), or at a moving average / actual trend across more
   blocks?
2. **Signal precedence.** When multiple signals point different ways in the
   same block (e.g. overall blockquote is good enough to raise tempo, but
   one specific character is still weak) — does one win, or do independent
   signals (tempo/spacing step vs. per-character drill weight) apply
   simultaneously without conflicting?
3. **Start simple?** Is it acceptable to ship the concept doc's original
   simple rule (blockquote-threshold × 2 consecutive blocks for
   tempo/spacing, per-character last-N-occurrences window for char unlock)
   as a first, later-recalibratable version — i.e. don't over-engineer
   question 1/2 up front?

Once answered, `adaptive_copy_engine.dart` takes generic inputs (a list of
`(char, correct)` results per block, current tempo/spacing values, the
configurable thresholds) — see "Adaptive engine must be reusable" above —
and wires into `AdaptiveCopyBody._finishBlock()`
(`android/lib/ui/adaptive_copy_body.dart`), which currently just records
stats and shows a flat result with no tempo/spacing/unlock suggestion yet.

## Open points (to clarify before/while implementing)

### N=20 for character unlock — meaning confirmed
Per-character, not per-block: look at that character's last N (default 20)
*occurrences across blocks*, compute its hit rate over just those. Once
every currently-active character clears the high threshold (default 90%)
over its own last-N window, the next character in the Koch sequence
auto-unlocks (Koch level +1). This would be a new *automatic* alternative
to the existing manual Koch-level slider — needs a decision on whether it
replaces, supplements, or is optional relative to the manual slider.

### Success-rate high/low thresholds — meaning confirmed
Drive char-speed/spacing only, separate from the N-based unlock:
- Blockquote ≥ high threshold (default 90%) in two consecutive blocks →
  spacing speed +1 step.
- Blockquote < low threshold (default 70%) → spacing speed −1 step (not
  below the configured start value).
- Only once spacing speed == char speed does char speed itself step up
  (+1..+2).

### Not yet decided — the actual weighting/recency question
Raised explicitly by the user and deliberately deferred to its own
discussion before writing `adaptive_copy_engine.dart`:
- Given a mix of signals (char speed up/down, spacing up/down, unlock next
  char, drill weak chars harder), what decides which one "wins" in a given
  block, and in what order/precedence?
- What time window matters for each per-character decision: most recent
  block only? Moving average across several? An actual trend (improving vs.
  degrading vs. flat) rather than a flat window average?
- The EMA-only sketch in the original concept doc (Section 5) is a
  starting point, not a final answer — revisit before implementation.

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
