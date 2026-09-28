#!/bin/sh
# Builds the release APK and Play App Bundle for a tag from a fresh clone
# under /tmp, so they don't embed this Mac's home path (Flutter compiles the
# absolute path of .dart_tool/.../dart_plugin_registrant.dart into libapp.so;
# --obfuscate doesn't remove it). Refuses to finish if either still contains
# the home path, the user name or any string from .git/info/forbidden-strings.
# Signed with the Play upload key from android/android/key.properties
# (gitignored; copied into the clone, never committed).
#   tools/build_release.sh v1.3.0  ->  releases/next-cw-trainer-v1.3.0.apk
#                                      releases/next-cw-trainer-v1.3.0.aab
set -e
tag="$1"
[ -n "$tag" ] || { echo "usage: $0 vX.Y.Z" >&2; exit 1; }
repo="$(git rev-parse --show-toplevel)"
list="$(git -C "$repo" rev-parse --git-common-dir)"
case "$list" in /*) ;; *) list="$repo/$list" ;; esac
list="$list/info/forbidden-strings"
keyprops="$repo/android/android/key.properties"
[ -f "$keyprops" ] || {
  echo "Missing $keyprops (upload key) — release builds need it." >&2; exit 1; }
work=/tmp/nct-release

rm -rf "$work"
git clone -q --no-recurse-submodules "$repo" "$work"
git -C "$work" -c advice.detachedHead=false checkout -q "$tag"
cp "$keyprops" "$work/android/android/key.properties"
(cd "$work/android" && flutter build apk --release && flutter build appbundle --release)
apk="$work/android/build/app/outputs/flutter-apk/app-release.apk"
aab="$work/android/build/app/outputs/bundle/release/app-release.aab"

patterns="$work/patterns"
{ echo "$HOME"; id -un; [ -s "$list" ] && cat "$list"; } > "$patterns"
for f in "$apk" "$aab"; do
  scan="$work/scan-$(basename "$f")"
  mkdir -p "$scan" && (cd "$scan" && unzip -qo "$f")
  if grep -raF -f "$patterns" "$scan" -l; then
    echo "Blocked: $(basename "$f") contains local identifiers (files above)." >&2
    exit 1
  fi
done

mkdir -p "$repo/releases"
cp "$apk" "$repo/releases/next-cw-trainer-$tag.apk"
cp "$aab" "$repo/releases/next-cw-trainer-$tag.aab"
rm -rf "$work"
echo "OK: releases/next-cw-trainer-$tag.{apk,aab} (no local paths inside)"
