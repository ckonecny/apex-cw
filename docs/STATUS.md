# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Next: v1.9.1 (pubspec 1.9.1+11; beta `v1.9.1-beta1` for testers: effective WPM in the progress view, spoken symbols and prosigns in the audio trainer; release notes and the Play upload follow after the beta). Latest release: v1.9.0 (notes `docs/release-notes-v1.9.0.md`; AAB for the Play closed test built, manual and screenshots done). Latest tagged build: v1.8.0 (2026-10-21, build 437, tag `v1.8.0` = commit 039560f; in the Play closed test with 2 testers; manual built for it). Previous: v1.7.0 (2026-10-12), v1.6.0 (2026-10-05); beta builds and older versions in `docs/STATUS-ARCHIVE.md`.

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

## Manual: screenshots (v1.8.0)
All retaken 2026-10-21 (light theme, DE+EN); `settings3` from the Store build 437. Exceptions: `echo_result2.png` (needs a hand-played 100 % block) and `decoder.png` (idle decoder) as before; not shown: Straight-key-only states (#17), exam result pages.

## Landing page (live, Pages source "GitHub Actions" set)
Refreshed 2026-10-21 (new shots, themes section, "small things" cards); goes live with the next push to main. Open: replace the disabled "Google Play: coming soon" button with the store
link once the app is live, and set the Play listing's website to the Pages URL.

## New logo (2026-10-06, on main): still to do
Done and checked on the test phone: launcher icons, README, landing page. Pending:
- **Play Store**: graphics, screenshots and texts rebuilt 2026-10-08 (palette now navy, 8 shots per language, `docs/PLAY-LISTING.md` updated). Still to do in the Play Console: upload `store/out/*` (icon_512, feature graphic, shots in order) and paste the texts, for DE and EN.
- **Manual**: checked at v1.7.0 (no old icon in cover/info).

## Manual: pending for next release
- `hear_progress.png`, `echo_progress.png` (both languages): new KPI "WPM eff." and a second speed curve in the Verlauf tab.

## v1.8.0 (released to the closed test 2026-10-21)
Notes: `docs/release-notes-v1.8.0.md` (1.7.1 maintenance folded in). Next: test the beta, then the release (`tools/build_release.sh v1.8.0`, APK + AAB; manual HTML/PDF and screenshots only then). Engine config per screen: `android/test/engine_config_test.dart`; shared config helper: issue #18.

## Phone tests still open (1.8.0)
- Confirmation tone choice (#136, PR #137, written in the cloud; CI is green: analyze, tests, debug build): pending install. Check on the test phone: the four choices in Settings → General, the right → wrong preview when picking, Marimba/Gentle level against the sidetone at several volumes, sound in the Echo Trainer, Hören typing flow, Geben and character practice, and that an old "off" setting stayed off.
- App language default (this branch): without a saved choice, German on a German-language phone, English otherwise. Unit-tested; on the test phone only the German case can be seen (try an English phone/tester).
- Own texts in the background (#21/#22): tried on the test phone with Tozo T6; check other headsets and phones in the beta.
- Mix-up suggestions (#102/#106): over weeks of real use, check that the card appears when pairs recur and that boosting works.
- Send start view (#107), compact row (#109), spaced goal credit, external key everywhere (#116): tried on the test phone; recheck in the beta.

## Audio trainer (#139, merged to main, beta 1.9.0-beta1)
Built: voice samples (Kristin, Bryce), flow engine (per group: Morse, think pause, solution) + tests, native sample player (`VoiceSamples.kt`, channel `cw_tone`: loadVoice/playVoiceChar/stopVoice), screen under Free modes (`audio_trainer_screen.dart`, profile `audio` and own Koch sequence `audio.*`, both seeded from Hören once; word/abbrev length, interference button), DE+EN strings, manual chapter DE+EN, tests (engine, `engine_config_test`, `screen_overflow_test`). Installed on the test phone (debug, 2026-10-23): the flow runs group by group (Morse, think pause, solution on screen, pause, counter), no errors in logcat. Not yet judged by ear / still to check: voices audible and the new voice-volume slider (samples re-rendered louder, default 70 %) against the Morse tone, pause/stop, voice switch, Koch level / character set, practice time in the daily goal, release build keeps the `voice_*` raw files (`res/raw/keep.xml`). Romeo/Sierra samples "not optimal" by ear (accepted).
Spoken symbols (#149, merged) and spoken prosigns with a choice of introduction (word, bell, harp, gong, off; branch `feature/audio-trainer-prosigns`, not merged): debug build installed on the test phone 2026-10-25; check by ear, both voices, in a character set with punctuation and prosigns (Alle Zeichen · Zufall). Manual DE+EN updated, no screenshot changes.

### Audio trainer background (#140, merged to main, beta 1.9.0-beta1)
Built: foreground service/lock-screen/headset buttons shared with Own texts (play/pause, next = skip group, prev = repeat group), engine `skipGroup`/`repeatGroup`, strings, manual DE+EN, tests. To check on the test phone: runs with the screen off for several groups, notification buttons, headset buttons, call/unplug pauses, notification permission, back ends it. Manual: the Audio-trainer screenshot is still pending (see above).

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
