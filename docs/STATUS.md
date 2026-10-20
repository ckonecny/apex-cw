# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.7.0 (2026-10-12; v1.8.0-beta1 in preparation, see below; tag `v1.7.0` = commit 4fffaa4; exam simulation, learn-from-mistake, word lists, themes, undo bar, focus mode, new logo, DM Sans). Previous: v1.6.0 (2026-10-05), v1.5.0 (2026-10-03); the beta builds v1.6.1-beta1…6 are folded into 1.7.0; older versions in `docs/STATUS-ARCHIVE.md`.

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
- `hear_progress2.png`, `echo_progress.png` (DE+EN): heatmap character labels are now coloured by kind (letter/digit/other).
- `tree_letters.png`, `tree_digits.png` (DE+EN), if they show the intro text: it has a new sentence about walking the tree with an external key (#117).
- `hear_char_detail.png`, `echo_char_detail.png` (DE+EN): the detail view shows a "Mix-ups" section (Listen, #92) and now trend arrows plus a weekly mix-up curve (#101).
- New shot (DE+EN): the "Trends" tab of the character statistics, e.g. `hear_trends.png`, `echo_trends.png` (#101); the segmented button above all statistics shots now has three segments (`hear_stats.png`, `echo_stats.png`, `hear_progress*.png`, `echo_progress.png`).
- `hear_start.png`, `hear_result.png`, `echo_result*.png` (DE+EN): a card "Recurring mix-ups: practice these?" appears next to the weak characters once pairs recur (#102).
- `settings1.png` (DE+EN): the Keyer card has a new row "Hide touch keys when an adapter is detected" (#95).
- Hören ⚙ sheet, Abstände section: new note under the sliders (word gap only applies to paper mode).
- Hören start and result screens (paper and typing) and the Sätze, Mini-QSO and Q-Groups setup screens: new shared tempo + spacing block (`hear_result.png`, `*_setup.png`, Hören start view); effective speed now in brackets behind the WPM.
- Geben start and result screens: same block with the give slider on top, no touch paddles on the start screen, result buttons side by side, Stop in the app bar and paddles at the very bottom while a block runs (`echo_start.png`, `echo_answer.png`, Geben result).
- `hear_start.png` (DE+EN): the weak-characters card now appears only with random character groups (not Koch words/abbreviations/mixed); check that the shot still shows it.
- `chart.png` (DE+EN): new section "Umlauts and CH" in the character chart.
- `echo_sheet.png` (DE+EN): Send ⚙ sheet, Echo Trainer section now has Denkzeit/Antwortpause with help lines; Abstände has only the character spacing.
- `settings2.png`, `settings3.png` (DE+EN): sections moved (USB CW adapter + key events below Keyer, call signs gone from the global settings); `hear_sheet2.png` (Word selection with call sign rows, content Call signs) in both languages.

- `settings3.png` (DE+EN): USB CW adapter card shows the adapter name/USB id with the active/inactive key symbol.
- `echo_result.png`, `echo_result2.png`, `echo_answer.png` (DE+EN): Send result page and running view now look like Listen (no word list, no mix-up line, status pill, dots) (#107).
- Koch lesson screens (#72): the character tile rows (`hear_start.png`, `echo_start.png`, DE+EN) now end with the six prosign tiles (SK AS KN KA VE BK); `settings_koch*` if the sequence list is shown.
- Many screenshots with an app bar (#116): new keyer symbol; Send result page: "." and "-" on the buttons with a key detected. `echo_start.png` (DE+EN): with Koch · Random, the start view now shows the weak characters and mix-up pairs card (#107).
- New shots (DE+EN), e.g. `hear_start_compact.png`, `hear_boost_sheet.png`: the compact row and its sheet when space is tight (#109).

## v1.8.0-beta1 (in preparation, version 1.8.0+9)
Notes: `docs/release-notes-v1.8.0.md` (1.7.1 maintenance folded in). Next: tag/publish `tools/publish_beta.sh v1.8.0-beta1` after merge of the release PR, then the release (`tools/build_release.sh v1.8.0`, APK + AAB; manual HTML/PDF and screenshots only then). Engine config per screen: `android/test/engine_config_test.dart`; shared config helper: issue #18.

## Phone tests still open (1.8.0)
- Mix-up suggestions (#102/#106): over weeks of real use, check that the card appears when pairs recur and that boosting works.
- Send start view (#107), compact row (#109), spaced goal credit, external key everywhere (#116): tried on the test phone; recheck in the beta.

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
