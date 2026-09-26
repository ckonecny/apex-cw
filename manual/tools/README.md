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
