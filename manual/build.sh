#!/bin/bash
#
# Builds the Next CW Trainer user manual from the Markdown sources
# (manual_de.md, manual_en.md) into HTML and PDF, the way the Morserino-32
# manual is built: pandoc -> HTML -> weasyprint -> PDF.
#
# Requirements: pandoc; weasyprint (brew install weasyprint) and the Lato font
# for the PDF (falls back to a system sans-serif without it).
#
# Usage:
#   ./build.sh              # both languages, HTML + PDF
#   ./build.sh de           # German only
#   ./build.sh en html      # English, HTML only
#   ./build.sh all epub     # both languages, EPUB (not committed)
#
# The app version on the title page comes from android/pubspec.yaml
# (versionName) plus the current git commit, so a rebuild always states which
# app state the manual describes. The version is also in the file names
# (NextCWTrainer_Handbuch_v1.2.0.pdf, ...), so a copy handed out on its own
# still shows which release it belongs to. Built files of other versions are
# removed, and the links in README.md and ../README.md are pointed at the new
# names.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
set -o pipefail

LANGS=${1:-all}
FORMATS=${2:-both}
[ "$LANGS" = all ] && LANGS="de en"

VERSION=$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' ../android/pubspec.yaml)
COMMIT=$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
# Screenshots don't count: at release they are taken from the tagged build
# (Settings → Info shows its commit) and committed afterwards with the manual.
[ -n "$(git status --porcelain --untracked-files=no -- . ':!img' ../android 2>/dev/null)" ] && COMMIT="$COMMIT-dirty"
YEAR=$(date +%Y)
MONTH_EN=$(LC_ALL=C date +%B)
case "$MONTH_EN" in
  January) MONTH_DE=Jänner ;; February) MONTH_DE=Februar ;; March) MONTH_DE=März ;;
  May) MONTH_DE=Mai ;; June) MONTH_DE=Juni ;; July) MONTH_DE=Juli ;;
  October) MONTH_DE=Oktober ;; December) MONTH_DE=Dezember ;;
  *) MONTH_DE=$MONTH_EN ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

title_block() {   # $1 = lang
  if [ "$1" = de ]; then
    cat <<HTML
<div class="title-page" data-title="Next CW Trainer – Handbuch">
<p class="t-name">Next CW Trainer</p>
<p class="t-sub">Benutzerhandbuch</p>
<p class="t-author">Christian Konecny, OE1CKO</p>
<p class="t-ver">App-Version $VERSION · Stand $MONTH_DE $YEAR · $COMMIT</p>
</div>
<div class="edition">
<p><strong>Next CW Trainer – Benutzerhandbuch</strong>, für App-Version $VERSION
(Quellstand $COMMIT), $MONTH_DE $YEAR. Autor: Christian Konecny, OE1CKO.
App-Icon: Sia, OE1LMR.</p>
<p>Next CW Trainer ist ein unabhängiges Projekt. Trainingskonzept und Algorithmen
stammen aus der Firmware des Morserino-32 von Willi Kraml, OE1WKL, und dem
Morserino-32-Team; es besteht keine weitere Verbindung zu ihnen.</p>
<p>Dieses Handbuch gibt es auch auf Englisch.</p>
</div>
HTML
  else
    cat <<HTML
<div class="title-page" data-title="Next CW Trainer – User Manual">
<p class="t-name">Next CW Trainer</p>
<p class="t-sub">User Manual</p>
<p class="t-author">Christian Konecny, OE1CKO</p>
<p class="t-ver">App version $VERSION · $MONTH_EN $YEAR · $COMMIT</p>
</div>
<div class="edition">
<p><strong>Next CW Trainer – User Manual</strong>, for app version $VERSION
(source $COMMIT), $MONTH_EN $YEAR. Author: Christian Konecny, OE1CKO.
App icon: Sia, OE1LMR.</p>
<p>Next CW Trainer is an independent project. Its training concept and
algorithms come from the Morserino-32 firmware by Willi Kraml, OE1WKL, and the
Morserino-32 team; there is no other connection to them.</p>
<p>This manual is also available in German.</p>
</div>
HTML
  fi
}

stem() { [ "$1" = de ] && echo NextCWTrainer_Handbuch || echo NextCWTrainer_Manual; }

build() {   # $1 = lang
  local lang=$1 base title toc f
  base="$(stem "$lang")_v$VERSION"
  if [ "$lang" = de ]; then
    title="Next CW Trainer – Handbuch"; toc=Inhalt
  else
    title="Next CW Trainer – User Manual"; toc=Contents
  fi
  # Only the current version's build is kept here; older ones are attached
  # to their GitHub releases.
  for f in "$(stem "$lang")".* "$(stem "$lang")"_v*.*; do
    [ -e "$f" ] && [ "${f%.*}" != "$base" ] && rm -f "$f"
  done
  title_block "$lang" > "$TMP/title_$lang.html"
  local common=(manual_$lang.md --from markdown --toc --toc-depth=2
    --number-sections --metadata "title=$title" --metadata "lang=$lang"
    --metadata "toc-title=$toc" --metadata "author=Christian Konecny, OE1CKO" --variable "pagetitle=$title"
    --include-before-body "$TMP/title_$lang.html")

  if [ "$FORMATS" = both ] || [ "$FORMATS" = html ] || [ "$FORMATS" = pdf ]; then
    echo "[$lang] HTML"
    # No pandoc title block: the title page above replaces it.
    pandoc "${common[@]}" --standalone --embed-resources --css style.css \
      --variable title= -o "$base.html" || { echo "pandoc failed ($lang)"; exit 1; }
  fi
  if [ "$FORMATS" = both ] || [ "$FORMATS" = pdf ]; then
    echo "[$lang] PDF"
    weasyprint "$base.html" "$base.pdf" 2>&1 | grep -v "^WARNING: \(Ignored\|Expected a media\|Invalid media\)\|^$" || true
    [ -s "$base.pdf" ] || { echo "weasyprint failed ($lang)"; exit 1; }
    [ "$FORMATS" = pdf ] && rm -f "$base.html"
  fi
  if [ "$FORMATS" = epub ]; then
    echo "[$lang] EPUB"
    pandoc "${common[@]}" --css style.css \
      -o "$base.epub" || { echo "pandoc failed ($lang epub)"; exit 1; }
  fi
}

for l in $LANGS; do build "$l"; done

# Internal links: every #anchor must exist in the same document.
for l in $LANGS; do
  f="$(stem "$l")_v$VERSION.html"
  [ -f "$f" ] || continue
  python3 - "$f" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding='utf-8').read()
ids = set(re.findall(r'\sid="([^"]+)"', s))
bad = sorted({html.unescape(h) for h in re.findall(r'href="#([^"]+)"', s)} - {html.unescape(i) for i in ids})
if bad:
    print(f"BROKEN LINKS in {sys.argv[1]}: " + ", ".join(bad)); sys.exit(1)
PY
  [ $? -eq 0 ] || exit 1
done
# Point the links in the READMEs at the versioned file names.
sed -E -i '' "s/(NextCWTrainer_(Handbuch|Manual))(_v[0-9]+\.[0-9]+\.[0-9]+)?\.(pdf|html)/\1_v$VERSION.\4/g" \
  README.md ../README.md
echo "Done: version $VERSION, $COMMIT"
