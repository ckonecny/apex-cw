# CLAUDE.md — Next CW Trainer

Read automatically at session start. Keep this short — depth lives in
`docs/`, loaded on demand, not here.

## What this is

Android port (Flutter + native Kotlin/C++) of the Morserino-32's CW training
modes. Independent project with no connection to Willi Kraml/OE1WKL or the
Morserino-32 team beyond reusing algorithms and training logic read out of
their firmware source; full credit for that design goes to Willi Kraml/
OE1WKL. Details: `docs/PROJECT.md`. Current state, next steps, open
questions: `docs/STATUS.md`. Read `docs/STATUS.md` before starting new work.

## Layout

- `android/` — the actual Flutter/Kotlin/C++ project. `cd` here to run
  `flutter` commands.
- `reference/` — read-only git submodule of the original firmware
  (`oe1wkl/Morserino-32`), pinned at tag `V9.0`. Never edit; `git submodule
  update` only if deliberately re-pinning (record why in `docs/DECISIONS.md`
  if so).
- `docs/STATUS.md`, `docs/DECISIONS.md`, `docs/PORTING-MAP.md` — see
  `docs/PROJECT.md` for what each holds.

## Hard rules (each has caused a real bug already — see docs/DECISIONS.md)

1. **Verify against `reference/`, not memory or the user manuals.** This
   project's entire value is behavioral fidelity to the actual firmware
   source, not to how it's documented or remembered.
2. **The native engine (`CwGenerator.kt`/`CwKeyer.kt`) is a shared
   singleton, not per-screen.** Nothing re-syncs wpm/pitch/spacing/mode/etc.
   automatically — every screen that uses it must push its own config on
   entry. Forgetting this is the single most common bug class so far
   (hit and fixed repeatedly: wpm, pitch, spacing, keyer mode, CurtisB).
3. **Prosigns are two-character mnemonic keys** ("KA", "KN", "SK", "AS",
   "VE", "BK"), not the firmware's single-uppercase-letter convention —
   `playWord()` uppercases all text before parsing, so the firmware's
   case-based trick isn't available here. In text to be played they must be
   bracketed (`<KA>`); a bare letter pair is always two letters.
4. **Rebuild and reinstall on-device before calling a fix done.** A code
   change with no reinstall has burned real user time before; say
   explicitly if a fix is pending install.
5. **Never `git commit` or `git push` unless explicitly asked**, even after
   finishing a chunk of work — ask or wait to be told.
6. **Never modify anything under `reference/`.** It's a pinned, read-only
   submodule; re-pin only deliberately, and record why in
   `docs/DECISIONS.md` if you do.
7. **One module per session**, per `docs/PORTING-MAP.md` — pick a row, do
   that, don't sprawl into unrelated modules in the same session.
8. **After finishing a task, update `docs/STATUS.md`** — done items, current
   next-3-steps, open questions.
9. **Record new or changed architecture decisions in `docs/DECISIONS.md`**
   as they're made, not after the fact.

## Build / run

From `android/`: `flutter build apk --debug`, then
`adb install -r build/app/outputs/flutter-apk/app-debug.apk`. Last known
test device: `63061JEBF01551` (may not still be the one connected).
