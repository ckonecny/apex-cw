# Store/landing-page screenshots from the phone

Retakes every store raw shot (`store/raw/{de,en}`) and landing-page image
(`site/img/*.webp`) from the test phone, in the Dark theme, DE and EN, with
tidy test data. Needs a **debug build** installed (`run-as` reads the prefs),
the phone unlocked and awake, and `adb`.

```
export DEVICE=<adb serial of the test phone>
export BACKUP=<folder>      # holds prefs.orig.xml: a copy of
                            # shared_prefs/FlutterSharedPreferences.xml
adb -s $DEVICE exec-out run-as at.oe1cko.nextcwtrainer cat shared_prefs/FlutterSharedPreferences.xml > $BACKUP/prefs.orig.xml
./cap.sh 2 1 en; ./cap.sh 2 0 de          # theme 2 = Dark; lang 1 = EN, 0 = DE
./cap2.sh 2 1 en; ./cap2.sh 2 0 de        # Mini QSO question (slow, ~2 min)
./bot.sh 2 1 en; ./bot.sh 2 0 de          # QSO Bot exchange (needs the bot to answer in time)
./themes.sh 1; ./themes.sh 0              # home screen in themes 1..7 (EN, DE)
python3 process.py                        # crop, write store/raw + site/img
python3 ../make_graphics.py               # store/out + the theme fans
```

`setp.sh` rewrites the prefs from `prefs.orig.xml` before every shot (theme,
language, blue-light filter off, status bar shown, and a made-up practice day
so the goal ring is partly filled; **change the date and the epoch
timestamps in it to today**). Afterwards put the original prefs back:
`adb -s $DEVICE shell "run-as at.oe1cko.nextcwtrainer sh -c 'cat > shared_prefs/FlutterSharedPreferences.xml'" < $BACKUP/prefs.orig.xml`
after `am force-stop`. Taps use the DE/EN accessibility labels; if a label
changes, adjust the regexes. Never write the serial into tracked files.
