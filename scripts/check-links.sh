#!/usr/bin/env bash
# Every relative markdown link in the pack must resolve to a file that exists.
#
# Why this exists: skills link to each other, into shared/, and into a sibling
# skill's prompting/ directory. Those are relative paths whose depth changes the
# moment a skill moves — and a skill that tells the agent to read a file which is
# not there fails silently. The agent shrugs and proceeds without the rules that
# file was carrying.
#
# Found the hard way: promoting the video cloner and analyze-video from depth four to
# depth two invalidated ~30 links across two files, including every entry in the
# Seedance prompt library, the transcript-diff doctrine, and both gates.
#
# Checks relative links only. External http(s) links are somebody else's uptime,
# and anchors within a file are not worth the false positives.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
checked=0

# Markdown inline links: [text](path). Strip any #anchor and any "title".
while IFS= read -r file; do
  # Skip the synced copies -- they are generated from these and would double-report.
  case "$file" in ./.claude/*|./.cursor/*|./node_modules/*) continue ;; esac

  dir="$(dirname "$file")"
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    case "$target" in
      http://*|https://*|mailto:*|"#"*) continue ;;
    esac
    clean="${target%%#*}"
    clean="${clean%% *}"
    [ -z "$clean" ] && continue
    checked=$((checked + 1))
    # Existence is not enough: the target must be COMMITTED. A gitignored file
    # a local setup happened to create (MASTER_CONTEXT.md, .env) exists on the
    # author's disk and not in a fresh clone, so a link to it passes locally and
    # breaks for every reader. That exact case shipped to CI from a green local
    # run, which is why this checks git rather than the filesystem.
    if [ ! -e "$dir/$clean" ] || ! git ls-files --error-unmatch "$dir/$clean" >/dev/null 2>&1; then
      reason="missing"
      [ -e "$dir/$clean" ] && reason="exists locally but is NOT COMMITTED"
      printf 'BROKEN  %s\n        -> %s  (%s)\n' "$file" "$target" "$reason"
      fail=$((fail + 1))
    fi
    # Fenced code blocks are stripped first: a regex like ?:["\'\ inside a
    # ```block``` matches the link pattern and is not a link. Excluding the
    # file would hide its real links too, so strip the fences instead.
  done < <(awk '/^[[:space:]]*```/{f=!f; next} !f' "$file" \
           | grep -oE '\]\([^)]+\)' | sed 's/^](//; s/)$//')
done < <(find . -name '*.md' -not -path './.git/*')

echo
if [ "$fail" -gt 0 ]; then
  echo "$checked relative links checked, $fail BROKEN"
  exit 1
fi
echo "$checked relative links checked, all resolve."
