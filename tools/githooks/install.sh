#!/bin/sh
# Installs the forbidden-strings hooks into this clone's .git/hooks.
cd "$(git rev-parse --show-toplevel)" || exit 1
hooks="$(git rev-parse --git-common-dir)/hooks"
cat > "$hooks/pre-commit" <<'H'
#!/bin/sh
exec sh tools/githooks/check-forbidden.sh staged
H
cat > "$hooks/commit-msg" <<'H'
#!/bin/sh
exec sh tools/githooks/check-forbidden.sh msg "$1"
H
cat > "$hooks/pre-push" <<'H'
#!/bin/sh
z=0000000000000000000000000000000000000000
while read -r lref lsha rref rsha; do
  [ "$lsha" = "$z" ] && continue
  if [ "$rsha" = "$z" ]; then range="$lsha --not --remotes"; else range="$rsha..$lsha"; fi
  sh tools/githooks/check-forbidden.sh range "$range" || exit 1
done
H
chmod +x "$hooks/pre-commit" "$hooks/commit-msg" "$hooks/pre-push"
touch "$(git rev-parse --git-common-dir)/info/forbidden-strings"
echo "Hooks installed. Add strings to block to .git/info/forbidden-strings."
