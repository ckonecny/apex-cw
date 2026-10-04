#!/bin/sh
# Builds a tester APK (tools/build_release.sh, "-test" mode) and publishes it
# as a GitHub pre-release with release notes since the previous tag (last
# release OR last test build reachable from the ref, whichever is newer).
# Notes: commit subjects + bodies since that tag + referenced issues + GitHub's
# generated PR list. The ref must already be pushed (gh creates the tag there).
#   tools/publish_test.sh v1.5.1-test1 [ref]     (ref default: HEAD)
#   DRY_RUN=1 tools/publish_test.sh ...          (print notes only, no build,
#                                                 no publish)
set -e
tag="$1"
case "$tag" in v*-test*) ;; *) echo "usage: $0 vX.Y.Z-testN [ref]" >&2; exit 1 ;; esac
repo="$(git rev-parse --show-toplevel)"
cd "$repo"
sha="$(git rev-parse "${2:-HEAD}")"
git fetch -q --tags origin
git rev-parse -q --verify "refs/tags/$tag" >/dev/null &&
  { echo "Tag $tag already exists." >&2; exit 1; }
[ -n "$(git branch -r --contains "$sha")" ] ||
  { echo "Commit $sha is not pushed to origin — push first." >&2; exit 1; }
prev="$(git describe --tags --abbrev=0 "$sha")"

notes="$(mktemp)"
{
  echo "Tester build \`$tag\` (pre-release) — changes since \`$prev\`:"
  echo
  # subject + message body per commit; bookkeeping commits left out
  git log --no-merges --reverse --format='%x01%s%n%b' "$prev..$sha" | awk '
    BEGIN { RS = "\001"; FS = "\n" }
    NF == 0 || $1 ~ /^(STATUS|Manual HTML|README|Tooling)/ { next }
    { print "- **" $1 "**"
      for (i = 2; i <= NF; i++)
        if ($i != "" && $i !~ /^Co-Authored-By:/) print "  " $i
      print "" }'
  issues="$(git log --format=%B "$prev..$sha" | grep -o '#[0-9][0-9]*' | tr -d '#' | sort -un | sed 's/^/#/' | tr '\n' ' ')"
  [ -z "$issues" ] || { echo; echo "Issues: $issues"; }
} > "$notes"

if [ -n "$DRY_RUN" ]; then
  echo "== DRY RUN: $tag at $sha, notes since $prev =="; cat "$notes"; rm -f "$notes"; exit 0
fi

tools/build_release.sh "$tag" "$sha"
gh release create "$tag" "releases/next-cw-trainer-$tag.apk" \
  --prerelease --target "$sha" --title "$tag" \
  --notes-file "$notes" --generate-notes --notes-start-tag "$prev"
rm -f "$notes"
