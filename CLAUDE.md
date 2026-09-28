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
- `manual/` — end-user manual (DE + EN Markdown sources, built HTML/PDF);
  see `manual/README.md`.
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
10. **Keep the user manual text current, in both languages, in the same
    change.** Anything a user can see or do differently (feature, setting,
    default, range, label, adaptive threshold/rule) updates
    `manual/manual_de.md` **and** `manual/manual_en.md` together — same
    structure, same facts. Describe behavior from the code, not from memory.
    A change isn't done while the Markdown still describes the old behavior.
    **Do not** rebuild HTML/PDF or retake screenshots per change — that
    happens only when cutting an official release (`vX.Y.Z`). Instead, if a
    change alters a screen shown in a screenshot, add that image to the list
    "Manual: pending for next release" in `docs/STATUS.md` (file name + why).
    At release: retake every listed screenshot in both languages
    (`manual/img/{de,en}/`, helpers in `manual/tools/`), run
    `manual/build.sh` (fails on broken links), clear the list.

## Build / run

From `android/`: `flutter build apk --debug`, then
`adb install -r build/app/outputs/flutter-apk/app-debug.apk`. The test
phone's serial is in `CLAUDE.local.md` (gitignored, local only). Release
APKs only via `tools/build_release.sh vX.Y.Z` (builds the tag outside the
home directory, so no Mac path ends up in the APK).

**Never write device serials or other local identifiers into tracked files,
commit messages or release notes** — say "the test phone". Strings listed in
`.git/info/forbidden-strings` are blocked by local git hooks
(`tools/githooks/`, installed with `tools/githooks/install.sh`).
