# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.7.0 (2026-10-12, tag `v1.7.0` = commit 4fffaa4; exam simulation, learn-from-mistake, word lists, themes, undo bar, focus mode, new logo, DM Sans). Previous: v1.6.0 (2026-10-05), v1.5.0 (2026-10-03); the beta builds v1.6.1-beta1…6 are folded into 1.7.0; older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/apex-cw (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots and graphics rebuilt 2026-10-08 (dark, DE+EN, beta 1.6.1); AAB `releases/apex-cw-v1.7.0.aab` built.
1. User: developer account (identity check passed).
2. Waiting until all testers are collected (user, 2026-10-12). Then: retake the store raw shots (dark, DE+EN; the phone must stay unlocked), `python3 store/make_graphics.py`, update the listing texts and "What's new" for 1.7.0, upload the AAB; closed test: 12 testers × 14 days.
3. Production.
Since 2026-10-08 the Home tiles (Head copy under Practice, Listen trend), the Listen start (weak chars in the outlook card) and the themes changed: retake all eight raw shots before uploading.

## Manual: screenshots (v1.7.0)
All screenshots retaken for v1.7.0 (2026-10-12, light theme, DE+EN, test phone, 12 weeks of statistics seeded; the phone's own data was restored afterwards). Exceptions (accepted by the user, 2026-10-12, no rush): `echo_result2.png` (suggestion ticked, needs a hand-played 100 % block) is still from v1.6.0 and shows the old font; `decoder.png` shows an idle decoder (no sound source at hand). Added: `hear_type_learn`, `keyer_sheet`, `exam_setup`. Not shown: Straight-key-only states (issue #17) and the exam result pages.

## Landing page (live, Pages source "GitHub Actions" set)
Open: replace the disabled "Google Play: coming soon" button with the store
link once the app is live, and set the Play listing's website to the Pages URL.

## New logo (2026-10-06, on main): still to do
Done and checked on the test phone: launcher icons, README, landing page. Pending:
- **Play Store**: graphics, screenshots and texts rebuilt 2026-10-08 (palette now navy, 8 shots per language, `docs/PLAY-LISTING.md` updated). Still to do in the Play Console: upload `store/out/*` (icon_512, feature graphic, shots in order) and paste the texts, for DE and EN.
- **Manual**: checked at v1.7.0 (no old icon in cover/info).

## Manual: pending for next release
(empty — v1.7.0 screenshots retaken, see above)

## CI / security automation (merged 2026-10-12, PR #64)
Open (user, GitHub settings): enable Secret Protection (Advanced Security), Dependabot security updates and private vulnerability reporting; create a ruleset for `main` requiring `analyze-test` + `build-debug` (admin bypass). Watch the first Dependabot PRs; `flutter_soloud` updates touch the native audio engine, so test on the phone (rule 2, rule 4).

## Fidelity audit (started 2026-10-12)
Order: keyer (PR #67), generator (branch `audit/generator`, stacked on #67), echo evaluation, JNI tone engine, audio decoder, Koch prosign extension. Findings per module in DECISIONS ("Keyer audit", "Generator audit"). **Pending install + try on the test phone** (rule 4): keyer modes by feel (Iambic A now forgets short opposite taps during an element, as on the device); generator gaps are now 3/7 dits at the default spacing (were 2/6): everything sounds a little slower, check Hören, Geben prompts and WiFi Trx playback. Release note when shipped: letter and word gaps were one dit too short in all earlier versions. Native tests: `./gradlew :app:testDebugUnitTest` in `android/android` (CI job `native-test`); locally Gradle needs `JAVA_HOME` of Android Studio's JBR.

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
