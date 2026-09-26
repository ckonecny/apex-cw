# Project

Next CW Trainer: an Android app (Flutter + native Kotlin/C++) that ports the
Morserino-32's CW **training** modes (Keyer, Generator, Koch Trainer, Echo
Trainer) to a phone. Independent project, not affiliated with the original —
its only connection to Willi Kraml/OE1WKL or the Morserino-32 team is that
its algorithms and training logic were read out of their firmware source;
full credit for that design/curriculum goes to Willi Kraml, OE1WKL, and the
Morserino-32 team. See `README.md` for the full intent statement,
scope/hardware-distinction, and the paddle-adapter note (vband etc.).

## Repo layout
- `android/` — the Flutter/Kotlin/C++ target project (the actual app).
- `reference/` — read-only git submodule of the original firmware
  (`oe1wkl/Morserino-32`), pinned at tag `V9.0`. Grep here for ground truth
  before assuming firmware behavior; never edit.
- `manual/` — end-user manual, German + English (Markdown sources, built
  HTML/PDF via `manual/build.sh`). Kept in sync with every user-visible
  change (CLAUDE.md rule 10).
- `docs/` — this folder. `STATUS.md` (current state, next steps, open
  questions), `DECISIONS.md` (why things are built the way they are),
  `PORTING-MAP.md` (firmware module -> Android module -> status).
- `CLAUDE.md` (repo root) — session-start rules; read that first, it's short
  on purpose and points here for depth.

## Ground rule
Verify against `reference/`, not memory or the firmware's own docs/manuals —
those can lag the source. This project's whole value is fidelity to the
actual firmware behavior.
