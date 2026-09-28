#!/bin/sh
# Blocks local identifiers (device serials etc.) from reaching GitHub.
# The strings themselves live only in .git/info/forbidden-strings (one per
# line, never committed), so this script doesn't publish them either.
#   check-forbidden.sh staged        -> staged changes (pre-commit)
#   check-forbidden.sh msg <file>    -> commit message (commit-msg)
#   check-forbidden.sh range <a..b>  -> commits about to be pushed (pre-push)
list="$(git rev-parse --git-common-dir)/info/forbidden-strings"
[ -s "$list" ] || exit 0
case "$1" in
  staged) text=$(git diff --cached -U0 --no-color | grep '^+') ;;
  msg)    text=$(cat "$2") ;;
  range)  text=$(git log --format=%B $2; git log -p --no-color --format= $2 | grep '^+') ;;
  *)      exit 0 ;;
esac
hits=$(printf '%s\n' "$text" | grep -F -f "$list" | head -5)
if [ -n "$hits" ]; then
  echo "Blocked: text from .git/info/forbidden-strings found ($1):" >&2
  printf '%s\n' "$hits" >&2
  exit 1
fi
