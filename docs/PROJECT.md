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

## Versioning: git and Play Store match (user, 2026-10-21)
Every build that goes to the Play Store (closed test included) is a normal
numbered version with its tag and GitHub release: **bug fix → patch**
(1.8.0 → 1.8.1), **feature → minor** (1.8.x → 1.9.0). Bump `version:` in
`android/pubspec.yaml`, tag `vX.Y.Z`, build with `tools/build_release.sh`,
create the GitHub release (APK + manual PDFs) so "Latest" is the version in
the store. Not every version has to reach the store, but the store never has
a version git doesn't know. Re-uploading the same versionName with a higher
build number (as with 1.8.0 build 435 → 437) is a one-off, not the schema.
Betas for testers outside the store stay `vX.Y.Z-betaN` pre-releases.

## F-Droid goes with every release (user, 2026-11-10)
Once the app is in F-Droid (#188), every release `vX.Y.Z` is handled for both
stores in the same step, to keep the overhead low. Signatures stay completely
separate (`docs/DECISIONS.md`, "F-Droid distribution"). Betas
(`vX.Y.Z-betaN`) are not offered on F-Droid.
- After tagging: versionCode of the tag = `git rev-list --count vX.Y.Z`
  (it is the commit count, F-Droid cannot read it); add the build entry
  (`versionName`, `commit`, `versionCode`) to our fdroiddata metadata
  (`fdroid/at.oe1cko.apexcw.yml` is the template) and open the MR.
- Changed the build (new native code, Gradle/Flutter/NDK version, new
  dependency)? Re-run the local `fdroid build` and `fdroid scanner` first, and
  keep `srclibs: flutter@` and `ndk:` in step with `FLUTTER_VERSION` in CI
  and `flutter.ndkVersion`.
- The F-Droid app id is `at.oe1cko.apexcw` (gradle property `appId` set in
  the entry's `prebuild`); never change the default `at.oe1cko.nextcwtrainer`
  (Play, permanent). After touching `applicationId`/manifest placeholders
  compare `signingReport` and the merged manifests with/without the property.
- Keep `build.gradle.kts` `signingConfig` lines single-line (F-Droid strips
  them by regex) and check `./gradlew :app:signingReport` is unchanged.
- Changed the Play texts or screenshots? Update `fastlane/metadata/android/`
  too (changelog per release: `changelogs/<versionCode>.txt`, max 500 bytes).

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
- F-Droid (once listed): `fastlane/metadata/android/` and the fdroiddata
  entry match the release (see "F-Droid goes with every release").
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
