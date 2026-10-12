# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.7.0 (2026-10-12, tag `v1.7.0` = commit 4fffaa4; exam simulation, learn-from-mistake, word lists, themes, undo bar, focus mode, new logo, DM Sans). Previous: v1.6.0 (2026-10-05), v1.5.0 (2026-10-03); the beta builds v1.6.1-beta1…6 are folded into 1.7.0; older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/apex-cw (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots home / Hören and Geben statistics retaken for v1.3.0 (2026-10-01,
dark, DE+EN), graphics rebuilt; AAB `releases/apex-cw-v1.7.0.aab` (store raw shots still from v1.3.0).
1. User: developer account (identity check passed).
2. Upload the AAB; closed test: 12 testers × 14 days.
3. Production.
The store raw shots `home` and `games` still show the v1.3.0 screens: retake them
(dark, DE+EN) before uploading the v1.7.0 AAB. Check `qso`, `adventure`, `hear`
for the old home layout/labels too.

## Manual: screenshots (v1.7.0)
All screenshots retaken for v1.7.0 (2026-10-12, light theme, DE+EN, test phone, 12 weeks of statistics seeded; the phone's own data was restored afterwards). Exceptions: `echo_result2.png` (suggestion ticked, needs a hand-played 100 % block) is still from v1.6.0 and shows the old font; `decoder.png` shows an idle decoder (no sound source at hand). Added: `hear_type_learn`, `keyer_sheet`, `exam_setup`. Not shown: Straight-key-only states (issue #17) and the exam result pages.

## Landing page (live, Pages source "GitHub Actions" set)
Open: replace the disabled "Google Play: coming soon" button with the store
link once the app is live, and set the Play listing's website to the Pages URL.

## New logo (2026-10-06, on main): still to do
Done and checked on the test phone: launcher icons, README, landing page. Pending:
- **Play Store**: graphics, screenshots and texts rebuilt 2026-10-08 (palette now navy, 8 shots per language, `docs/PLAY-LISTING.md` updated). Still to do in the Play Console: upload `store/out/*` (icon_512, feature graphic, shots in order) and paste the texts, for DE and EN.
- **GitHub**: upload `android/tool/icon/social_preview.png` (repo Settings →
  Social preview; no API).
- **Manual**: checked at v1.7.0 (no old icon in cover/info).

## Manual: pending for next release
(empty — v1.7.0 screenshots retaken, see above)

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
