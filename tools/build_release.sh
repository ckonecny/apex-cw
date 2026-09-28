#!/bin/sh
# Builds the release APK for a tag from a fresh clone under /tmp, so the
# APK doesn't embed this Mac's home path (Flutter compiles the absolute path
# of .dart_tool/.../dart_plugin_registrant.dart into libapp.so; --obfuscate
# doesn't remove it). Refuses to finish if the APK still contains the home
# path, the user name or any string from .git/info/forbidden-strings.
#   tools/build_release.sh v1.2.0   ->  releases/next-cw-trainer-v1.2.0.apk
set -e
tag="$1"
[ -n "$tag" ] || { echo "usage: $0 vX.Y.Z" >&2; exit 1; }
repo="$(git rev-parse --show-toplevel)"
list="$(git -C "$repo" rev-parse --git-common-dir)"
case "$list" in /*) ;; *) list="$repo/$list" ;; esac
list="$list/info/forbidden-strings"
work=/tmp/nct-release

rm -rf "$work"
git clone -q --no-recurse-submodules "$repo" "$work"
git -C "$work" -c advice.detachedHead=false checkout -q "$tag"
(cd "$work/android" && flutter build apk --release)
apk="$work/android/build/app/outputs/flutter-apk/app-release.apk"

scan="$work/scan"
mkdir -p "$scan" && (cd "$scan" && unzip -qo "$apk")
patterns="$scan/patterns"
{ echo "$HOME"; id -un; [ -s "$list" ] && cat "$list"; } > "$patterns"
if grep -raF -f "$patterns" "$scan" --exclude=patterns -l; then
  echo "Blocked: the APK contains local identifiers (files above)." >&2
  exit 1
fi

mkdir -p "$repo/releases"
cp "$apk" "$repo/releases/next-cw-trainer-$tag.apk"
rm -rf "$work"
echo "OK: releases/next-cw-trainer-$tag.apk (no local paths inside)"
