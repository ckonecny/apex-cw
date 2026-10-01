# Next CW Trainer — User Manual / Benutzerhandbuch

| | Deutsch | English |
|---|---|---|
| PDF | [NextCWTrainer_Handbuch_v1.3.0.pdf](NextCWTrainer_Handbuch_v1.3.0.pdf) | [NextCWTrainer_Manual_v1.3.0.pdf](NextCWTrainer_Manual_v1.3.0.pdf) |
| HTML | [NextCWTrainer_Handbuch_v1.3.0.html](NextCWTrainer_Handbuch_v1.3.0.html) | [NextCWTrainer_Manual_v1.3.0.html](NextCWTrainer_Manual_v1.3.0.html) |
| Source (Markdown) | [manual_de.md](manual_de.md) | [manual_en.md](manual_en.md) |

The title page states the app version and source commit the manual was built
from; compare it with **Settings → Info** in the app.

## Files

| File | What it is |
|---|---|
| `manual_de.md`, `manual_en.md` | the sources — this is what gets edited, always both together |
| `NextCWTrainer_Handbuch_vX.Y.Z.*`, `NextCWTrainer_Manual_vX.Y.Z.*` | the built manuals (HTML + PDF) of the last release, version in the file name; committed so they can be handed out |
| `build.sh` | builds both, via pandoc + weasyprint; also checks internal links |
| `style.css` | stylesheet for HTML (screen, light/dark) and PDF (print) |
| `img/de/`, `img/en/` | screenshots per language (same file names), light theme, 540 px wide |
| `tools/` | adb helpers to retake the screenshots, see `tools/README.md` |

## Building

Needs `pandoc`, and `weasyprint` plus the Lato font for the PDF
(`brew install pandoc weasyprint`).

```bash
./build.sh              # both languages, HTML + PDF
./build.sh de html      # German, HTML only
./build.sh all epub     # EPUB, not committed
```

## Keeping it current

The manual describes behavior, not code: every setting with its range and
default, and how the adaptive logic decides. Any change that alters what a
user sees or does — a feature, a setting, a default, a label, a threshold —
updates **both** `manual_de.md` and `manual_en.md` in the same change (see
rule 10 in `CLAUDE.md`). The two files keep the same chapter structure so
they can be diffed side by side.

Between releases only the Markdown sources are kept current. The built
HTML/PDF and the screenshots are refreshed **only when an official version
is cut**, so the committed HTML/PDF always match the last release. If a
change alters a screen that is shown in a screenshot, the image is not
retaken right away; it is added to the list *"Manual: pending for next
release"* in `docs/STATUS.md`.

## At release time

1. Bump `version:` in `android/pubspec.yaml`, commit ("Version X.Y.Z"), tag
   `vX.Y.Z`, build the APK with `tools/build_release.sh vX.Y.Z` and install
   it on the phone.
2. Retake every screenshot on that list, in both languages (`tools/`), from
   that release build, so `settings3.png` shows the tagged version and commit.
3. Check that both Markdown files still match the app.
4. With the tag still checked out and only the new screenshots changed, run
   `./build.sh` (title page shows version and tagged commit — changes under
   `img/` don't count as dirty; the script fails on broken internal links).
   If the manual sources changed after the tag (e.g. screenshot blocks), run
   `MANUAL_COMMIT=<tagged hash> ./build.sh` so the title page names the release
   commit, not `-dirty`. The version is taken from `android/pubspec.yaml` and goes into the file
   names (`NextCWTrainer_Handbuch_v1.3.0.pdf`, …); the previous release's
   files are deleted and the links in both READMEs are updated. Attach the
   PDFs to the GitHub release under these versioned names.
5. Clear the list in `docs/STATUS.md` and commit screenshots, built manual
   and README links together ("Manual HTML/PDF built for vX.Y.Z").
