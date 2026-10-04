#!/bin/sh
# Builds a tester APK (tools/build_release.sh, "-test" mode) and publishes it
# as a GitHub pre-release with release notes since the previous tag (last
# release OR last test build reachable from the ref, whichever is newer).
# Notes: commit subjects since that tag + referenced issues + GitHub's
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
  git log --no-merges --format='- %s' "$prev..$sha"
  issues="$(git log --format=%B "$prev..$sha" | grep -o '#[0-9][0-9]*' | sort -un | tr '\n' ' ')"
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
