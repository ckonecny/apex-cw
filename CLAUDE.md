# CLAUDE.md — APEX CW

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
8. **After finishing a task, update `docs/STATUS.md`** — current state, next
   steps, organisational open points. Move what is done to
   `docs/STATUS-ARCHIVE.md` (rule 13).
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

11. **Licences: everything must fit GPL-3.0-or-later** (the app ports GPL
    firmware code). Before using *anything* from outside — pub package,
    Gradle/native library, font, image, sound, data, text, code snippet,
    ported content — find its licence. Incompatible or unclear (non-commercial,
    no licence, "all rights reserved", source-available, GPL-2.0-only, CC
    ND/NC, ...): **stop and warn the user before using it**, even if they asked
    for it. Compatible: in the same change keep every licence reference
    current — `android/lib/licenses.dart` (licence page; pub packages are
    added by Flutter itself, but bundled sub-libraries and assets are not),
    README "License", manual Info "Lizenzen/Licences" (DE+EN), credits where
    due, `docs/DECISIONS.md`. `test/license_compat_test.dart` fails on new
    unchecked packages, assets or Gradle libraries — never silence it without
    that check.

12. **Feature ideas and deferred bugs live in GitHub issues, not in local
    files.** Every potential feature, and every bug reported by others or
    deferred instead of fixed at once, is a GitHub issue in
    `ckonecny/next_cw_trainer`, written in English, using the templates in
    `.github/ISSUE_TEMPLATE/` (feature: "What would you like? / What is it
    for?"; bug: what happened, how to reproduce, app version/phone/Android).
    End each issue Claude writes with
    `---\n_Generated by [Claude Code](https://claude.ai/code)_`. No device
    serials or local paths (public repo). Don't keep the same item in
    `docs/STATUS.md` as well — no duplicates. Name the issue in the commit
    (`Closes #N`). `docs/STATUS.md` holds only the current state and
    organisational topics (release steps, test status, open decisions, hints
    for the next session).

13. **Done items go to `docs/STATUS-ARCHIVE.md`.** Whenever something in
    `docs/STATUS.md` is finished, move it to the archive in the same change
    (move, don't delete). **Keep `STATUS.md` as lean as possible**: only
    what is open or current, short entries, details belong in `DECISIONS.md`,
    the archive or the issue. Aim for well under 150 lines.

14. **No deprecated APIs, stay future-proof.** Don't write deprecated
    Flutter/Dart/Android/Gradle APIs in new or changed code, and don't copy
    them from existing code. If you notice a deprecation (analyzer hint,
    build warning), use the replacement right away (e.g. `withValues(alpha:)`
    instead of `withOpacity`) instead of leaving it for later. `flutter
    analyze` should stay at zero issues.

15. **New screen or row layout: keep it overflow-proof.** Labels beside
    controls go in `Expanded`/`Flexible`, never bare `Text` + `Spacer`; add
    every new screen to `android/test/screen_overflow_test.dart` (DE+EN,
    scale 1.3, small phone). Details: `docs/DECISIONS.md`.
16. **Preparing any version (beta or release): check the project docs for
    consistency first, and fix what drifted in the same change.** Checklist:
    `docs/PROJECT.md` "Release consistency check". Report the result to the
    user (what was checked, what was fixed, what stays open).

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
