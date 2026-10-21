# Handbuch-Screenshots per Skript (2026-10-21)

Needs a debug build, `DEVICE` (adb serial) in the environment, and in this
folder a `prefs.orig.xml` (copy of the phone's `FlutterSharedPreferences.xml`).
`setm.sh <theme> <lang>` builds `prefs.seed.xml` from it (run
`../seed_history.py prefs.seed.xml` once first), sets light theme/language,
turns the blue-light filter off and fills today's goal ring (adjust date and
epoch timestamps in it), then restarts the app. `man1..4.sh <lang 0|1>` shoot
static screens into `out/<lang>/`, `install.py [names]` quantizes (128 colours)
and writes them to `../../img/`. Afterwards put `prefs.orig.xml` back (see
`../README.md`). Careful: taps go by accessibility label; a `^Zeichen` regex
once hit the statistics reset button (it only opened the confirm dialog).
