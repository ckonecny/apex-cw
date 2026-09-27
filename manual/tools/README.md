# Screenshot tools

Helpers used to take the manual's screenshots from a real phone over adb
(`ADB` / `DEVICE` env vars override the adb path and device serial).

| Script | What it does |
|---|---|
| `ui.py` | chains UI actions: `dump`, `tap <regex>` (by accessibility label), `tapxy`, `swipe`, `back`, `text`, `wait`, `shot <file>` |
| `crop.py` | strips status/gesture bar and scales to 540 px wide (`crop.py in out [y0 y1]`) |
| `key.sh` | keys Morse through the learned paddle keycodes 113/114 (`key.sh "-.-. --.- /"`), reliable at ~8 WPM only |
| `echo_loop.py` | answers a Send (Echo) block automatically, optionally wrong on chosen words; needs Echo Prompt = Both |
| `insert.py` | (re)inserts all screenshot blocks into both manuals at fixed anchor paragraphs, with DE/EN captions — idempotent |

Workflow used (2026-09-26): theme Light, language per pass, run each screen,
`crop.py` into `../img/<lang>/<name>.png`, quantize to 128 colours (keeps the
repo small), `python3 insert.py`, `../build.sh`. Note the app settings you
change on the phone (theme, language, WPM, Echo Prompt, answer speed) and put
them back afterwards. Playing blocks writes to the phone's statistics.

v1.1.0 (2026-09-27) additions:

- **Keep the user's data clean.** All settings and statistics live in
  `shared_prefs/FlutterSharedPreferences.xml`. Install a debug build of the
  same commit (same signing key, data kept), copy the prefs out with
  `adb exec-out run-as at.oe1cko.nextcwtrainer cat shared_prefs/<file>`,
  play blocks freely, then `am force-stop` and write them back with
  `adb shell "run-as … sh -c 'cat > shared_prefs/<file>'" < file`.
  Reinstall the release APK afterwards, and take `settings3.png` on the
  release build (the debug build shows `-dirty · debug`).
- **On-screen keyboard (Hören → Tippen):** `input tap` on key centres works;
  the word played is unknown, so for the "Gesendet" shot use a two-letter
  Übungsset (e.g. `SE`) and guess — gives a realistic mix of right/wrong.
- **Touch paddles:** a single `input tap` is too short to latch in the
  iambic keyer. Hold instead: `input motionevent DOWN x y; sleep …;
  input motionevent UP x y` (holding a paddle repeats the element). Set
  Gebetempo to 10 WPM first; the Einzelzeichen-üben page and Geben use it.
- Poll `ui.py dump` for status texts ("spielt …", "Geben …", "Gesendet")
  instead of fixed sleeps; `screencap` right after keying catches
  short-lived states (✓ Richtig) that a slower dump misses.
