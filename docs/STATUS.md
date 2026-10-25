# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Latest: v1.10.0 (pubspec 1.10.0+13, 2026-10-25, notes `docs/release-notes-v1.10.0.md`): everything of the betas `v1.9.1-beta1` and `v1.10.0-beta1` plus the Prosigns set (#156), original Koch sequences, Q-groups tempo only. AAB for the Play upload built; manual, screenshots and Play texts (`docs/PLAY-LISTING.md`) in the release steps below. Previous: v1.9.0 (2026-10-24), v1.8.0 (2026-10-21), v1.7.0 (2026-10-12); older versions in `docs/STATUS-ARCHIVE.md`.

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
(empty; v1.10.0 shots retaken 2026-10-25, `hear_prosigns.png` is new. `chart.png` shows only the letters at the top and did not change.)

## Prosign set (#156, branch `feature/prosign-charset`)
Built, installed on the test phone, not yet checked there: chip order, tiles, typing keyboard row, chart, tree row, audio trainer with the set. The spoken meanings for AR, BT, HH, SOS are in (`res/raw`); still to hear in the app.

## Phone tests still open (1.8.0)
- Confirmation tone choice (#136, PR #137, written in the cloud; CI is green: analyze, tests, debug build): pending install. Check on the test phone: the four choices in Settings → General, the right → wrong preview when picking, Marimba/Gentle level against the sidetone at several volumes, sound in the Echo Trainer, Hören typing flow, Geben and character practice, and that an old "off" setting stayed off.
- App language default (this branch): without a saved choice, German on a German-language phone, English otherwise. Unit-tested; on the test phone only the German case can be seen (try an English phone/tester).
- Own texts in the background (#21/#22): tried on the test phone with Tozo T6; check other headsets and phones in the beta.
- Mix-up suggestions (#102/#106): over weeks of real use, check that the card appears when pairs recur and that boosting works.
- Send start view (#107), compact row (#109), spaced goal credit, external key everywhere (#116): tried on the test phone; recheck in the beta.

## Audio trainer (#139, merged to main, beta 1.9.0-beta1)
Built: voice samples (Kristin, Bryce), flow engine (per group: Morse, think pause, solution) + tests, native sample player (`VoiceSamples.kt`, channel `cw_tone`: loadVoice/playVoiceChar/stopVoice), screen under Free modes (`audio_trainer_screen.dart`, profile `audio` and own Koch sequence `audio.*`, both seeded from Hören once; word/abbrev length, interference button), DE+EN strings, manual chapter DE+EN, tests (engine, `engine_config_test`, `screen_overflow_test`). Installed on the test phone (debug, 2026-10-23): the flow runs group by group (Morse, think pause, solution on screen, pause, counter), no errors in logcat. Not yet judged by ear / still to check: voices audible and the new voice-volume slider (samples re-rendered louder, default 70 %) against the Morse tone, pause/stop, voice switch, Koch level / character set, practice time in the daily goal, release build keeps the `voice_*` raw files (`res/raw/keep.xml`). Romeo/Sierra samples "not optimal" by ear (accepted).
Spoken symbols (#149, merged) and spoken prosigns with a choice of introduction (word, bell, harp, gong, off; merged #150, in `v1.9.1-beta1`): debug build installed on the test phone 2026-10-25; check by ear, both voices, in a character set with punctuation and prosigns (Alle Zeichen · Zufall). Manual DE+EN updated, no screenshot changes.

### Audio trainer background (#140, merged to main, beta 1.9.0-beta1)
Built: foreground service/lock-screen/headset buttons shared with Own texts (play/pause, next = skip group, prev = repeat group), engine `skipGroup`/`repeatGroup`, strings, manual DE+EN, tests. To check on the test phone: runs with the screen off for several groups, notification buttons, headset buttons, call/unplug pauses, notification permission, back ends it. Manual: the Audio-trainer screenshot is still pending (see above).

## Launcher shortcuts (#151, merged #153, beta `v1.10.0-beta1`)
Built: dynamic shortcuts, user's choice and order in Settings → Appearance → App shortcuts (8 on offer, 4 on by default), manual DE+EN, tests. First version (fixed five) checked on the test phone: works, launcher shows four. Settings screen checked on the test phone (2026-10-25).

## Audio trainer lock-screen controls (#152, merged #154, beta `v1.10.0-beta1`)
Built: tempo/spacing −/+ instead of prev/next in the audio trainer's media controls, values in the subtitle, manual DE+EN, test. Checked on the test phone 2026-10-25 (debug build): the four buttons in the shade's media player, tempo/spacing change and the subtitle follows. Lock screen checked by the user. Still to check in the beta: by ear, own texts still with prev/next.

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
