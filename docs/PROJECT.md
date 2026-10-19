# Project

APEX CW: an Android app (Flutter + native Kotlin/C++), a CW trainer
in its own right. It ports the Morserino-32's CW training modes (keyer,
generator/Koch trainer, echo trainer, decoder, WiFi Trx, QSO bot, games) to a
phone and adds app-only features (e.g. typing mode, text adventure, character
statistics). Independent project, not affiliated with the original —
its only connection to Willi Kraml/OE1WKL or the Morserino-32 team is that
its algorithms and training logic were read out of their firmware source;
full credit for that design/curriculum goes to Willi Kraml, OE1WKL, and the
Morserino-32 team. See `README.md` for the full intent statement,
scope/hardware-distinction, and the paddle-adapter note (vband etc.).

## Repo layout
- `android/` — the Flutter/Kotlin/C++ target project (the actual app).
- `reference/` — read-only git submodule of the original firmware
  (`oe1wkl/Morserino-32`), pinned at tag `V9.0`. Grep here for ground truth
  before assuming firmware behavior; never edit.
- `manual/` — end-user manual, German + English (Markdown sources, built
  HTML/PDF via `manual/build.sh`). Markdown kept in sync with every
  user-visible change; HTML/PDF and screenshots refreshed per release
  (CLAUDE.md rule 10).
- `docs/` — this folder. `STATUS.md` (current state, next steps,
  organisational open points), `STATUS-ARCHIVE.md` (finished items, moved out
  of STATUS.md), `DECISIONS.md` (why things are built the way they are),
  `PORTING-MAP.md` (firmware module -> Android module -> status),
  `ADAPTIVE-COPY.md` (how the adaptive Hören block works),
  `PLAY-LISTING.md` (Play Store texts and console answers),
  `archive/` (concept and phase specs of the finished training rework, history only).
- `PRIVACY.md` (repo root) — privacy policy, linked from the Play listing.
- `store/`, `tools/` — Play Store graphics script; release build and git hooks.
- `CLAUDE.md` (repo root) — session-start rules; read that first, it's short
  on purpose and points here for depth.

## Ground rule
Verify against `reference/`, not memory or the firmware's own docs/manuals —
those can lag the source. This project's whole value is fidelity to the
actual firmware behavior.

## Recurring maintenance
Two scheduled Claude tasks (Claude desktop app, "Scheduled"; they run while the
app is open) report read-only, without committing or merging anything:
- `apex-cw-monthly-check`, 1st of each month: open Dependabot PRs with risk
  and a merge order, Dependabot/CodeQL/secret alerts, CI state of `main`, a
  quick docs check, whether a release or beta is due.
- `apex-cw-quarterly-tech-debt`, 2nd of Jan/Apr/Jul/Oct: tech-debt scan,
  per-screen engine config (rule 2), licences, unused dependencies, docs, all
  test suites.
Alerts also arrive by e-mail (GitHub notification settings). Build
tooling (Gradle, Android Gradle Plugin) updates are merged one group at a time
and tried on the test phone first.

## Release consistency check
Run before every beta or release (CLAUDE.md rule 16); fix drift right away.
- `docs/STATUS.md`: latest tag/version line, "Manual: pending" list, open
  steps all still true; finished items moved to `STATUS-ARCHIVE.md`; no item
  duplicated in a GitHub issue (rule 12); well under 150 lines.
- `docs/DECISIONS.md`: every architecture change since the last tag is
  recorded (compare `git log <last tag>..HEAD`); tool/script names current.
- `docs/PORTING-MAP.md`, `docs/PLAY-LISTING.md`, `docs/ADAPTIVE-COPY.md`:
  features, names, counts and screens match the code.
- `manual/manual_de.md` vs `manual/manual_en.md`: same structure and facts,
  and both match the app (rule 10).
- `README.md`, `site/index.html`, `PRIVACY.md`: feature list, version/manual
  links, screenshots, licence section current.
- Licences (rule 11): `android/lib/licenses.dart`, README, manual Info
  cover everything new; `flutter test` incl. `license_compat_test.dart` green.
- `CLAUDE.md`, `manual/README.md`, `tools/` comments: script names, tag
  patterns (`vX.Y.Z`, `vX.Y.Z-betaN`) and paths still exist and are correct.
- `flutter analyze` zero issues, `flutter test` green; the `CI` workflow is
  green on the release branch (GitHub Actions).
- Automated review gate (release only; for a beta at your discretion):
  `/code-review high` on the diff since the last tag, `/security-review` on
  the same diff, and a look at the open GitHub Security tab (Code scanning,
  Dependabot, Secret scanning alerts). Triage every finding: fix it, or
  dismiss it with a reason; deferred bugs become GitHub issues (rule 12).
  Extra focus for a diff touching `CwGenerator.kt`, `CwKeyer.kt` or
  `cw_tone_jni.cpp`: shared-singleton state (rule 2), thread safety, bounds.
Not part of a beta (only at a release, or at store launch): retaking
screenshots, building manual HTML/PDF, Play Store graphics and listing. Their
pending lists in `docs/STATUS.md` must be complete, though.
