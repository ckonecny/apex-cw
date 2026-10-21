# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.7.0 (2026-10-12; v1.8.0-beta2 in preparation, see below; beta1 published 2026-10-18; tag `v1.7.0` = commit 4fffaa4; exam simulation, learn-from-mistake, word lists, themes, undo bar, focus mode, new logo, DM Sans). Previous: v1.6.0 (2026-10-05), v1.5.0 (2026-10-03); the beta builds v1.6.1-beta1…6 are folded into 1.7.0; older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/apex-cw (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots and graphics rebuilt 2026-10-08 (dark, DE+EN, beta 1.6.1); AAB `releases/apex-cw-v1.7.0.aab` built.
1. User: developer account (identity check passed).
2. Store raw shots, graphics and the landing page retaken 2026-10-21 on beta 1.8.0 (`store/capture/README.md`; `python3 store/make_graphics.py` writes `store/out/`). Still to do: update the listing texts and "What's new" for 1.8.0 and upload (AAB with the release); closed test: 12 testers × 14 days. If the beta changes a shown screen, retake with the same scripts.
3. Production.

## Manual: screenshots (v1.7.0)
All screenshots retaken for v1.7.0 (2026-10-12, light theme, DE+EN, test phone, 12 weeks of statistics seeded; the phone's own data was restored afterwards). Exceptions (accepted by the user, 2026-10-12, no rush): `echo_result2.png` (suggestion ticked, needs a hand-played 100 % block) is still from v1.6.0 and shows the old font; `decoder.png` shows an idle decoder (no sound source at hand). Added: `hear_type_learn`, `keyer_sheet`, `exam_setup`. Not shown: Straight-key-only states (issue #17) and the exam result pages.

## Landing page (live, Pages source "GitHub Actions" set)
Refreshed 2026-10-21 (new shots, themes section, "small things" cards); goes live with the next push to main. Open: replace the disabled "Google Play: coming soon" button with the store
link once the app is live, and set the Play listing's website to the Pages URL.

## New logo (2026-10-06, on main): still to do
Done and checked on the test phone: launcher icons, README, landing page. Pending:
- **Play Store**: graphics, screenshots and texts rebuilt 2026-10-08 (palette now navy, 8 shots per language, `docs/PLAY-LISTING.md` updated). Still to do in the Play Console: upload `store/out/*` (icon_512, feature graphic, shots in order) and paste the texts, for DE and EN.
- **Manual**: checked at v1.7.0 (no old icon in cover/info).

## Manual: pending for next release
Retaken 2026-10-21 (debug build of beta 1.8.0, light theme, DE+EN, 12 weeks of statistics seeded, phone prefs restored afterwards; scripts: `manual/tools/capture/`): all screenshots except the ones below. Notes: `echo_result2` shows "new character unlocked" (caption changed), `qso` was answered via the text field, `char_practice` shows the character E, `adv_map` shows only the start room, `own_*` use the two Wikipedia texts the user added; new `hear_start_compact`, `hear_boost_sheet`, `settings_appearance` are placed in both manuals. Still to do:
- `settings3` (Info card with version/commit) retaken 2026-10-21 from the release build 1.8.0 (Build 435, commit 4329490, installed over the debug build — same upload-key signature, data kept). Retake it once more from the final build: the final release gets a new build number and commit.
- Check: `own_library` (EN) shows "2% heard" on the German text (progress from the screenshot run).

## v1.8.0 (beta1 published 2026-10-18, beta2 2026-10-21; version 1.8.0+9)
Notes: `docs/release-notes-v1.8.0.md` (1.7.1 maintenance folded in). Next: test the beta, then the release (`tools/build_release.sh v1.8.0`, APK + AAB; manual HTML/PDF and screenshots only then). Engine config per screen: `android/test/engine_config_test.dart`; shared config helper: issue #18.

## Phone tests still open (1.8.0)
- Own texts in the background (#21/#22): tried on the test phone with Tozo T6; check other headsets and phones in the beta.
- Mix-up suggestions (#102/#106): over weeks of real use, check that the card appears when pairs recur and that boosting works.
- Send start view (#107), compact row (#109), spaced goal credit, external key everywhere (#116): tried on the test phone; recheck in the beta.

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
