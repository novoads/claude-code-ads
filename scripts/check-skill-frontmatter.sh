#!/usr/bin/env bash
# Every registered skill's frontmatter must be valid and within budget.
#
# The description is the ROUTER — it is the only thing preloaded for every skill,
# and it is what the model matches a user's sentence against. Two things silently
# break it:
#
#   over 1024 chars  the platform's cap. The tail is dropped, and the tail is
#                    where the "NOT for X, use Y instead" disambiguation lives —
#                    so a truncated description makes a skill quietly steal
#                    sentences that belong to its neighbour. Found in the house
#                    repo at 1140 and 1152 chars, both already shipped.
#
#   nested SKILL.md  a skill at skills/<name>/prompting/<other>/SKILL.md is never
#                    registered. clone-ad sat there fully written, with a correct
#                    description naming exactly the right triggers, and none of
#                    them ever reached the router.
#
# The 500-line body is a guideline, not a cap, so it warns rather than fails:
# past that, move what is not needed mid-run into references/.
set -uo pipefail
cd "$(dirname "$0")/.."

MAX_DESC=1024
WARN_LINES=500

fail=0
warn=0

for dir in skills/*/ shared/skills/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  file="$dir/SKILL.md"

  # shared/skills/ holds guide-only packs with no SKILL.md by design.
  if [ ! -f "$file" ]; then
    case "$dir" in shared/skills/*) continue ;; esac
    echo "FAIL  $name: no SKILL.md"
    fail=$((fail + 1))
    continue
  fi

  len=$(python3 - "$file" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
parts = text.split("---")
if len(parts) < 2:
    print(-1); raise SystemExit
m = re.search(r"description:\s*>-?\s*\n(.*?)(?=\n[a-z_]+:|\Z)", parts[1], re.S)
if not m:
    m = re.search(r"description:\s*(.+)", parts[1])
    print(len(m.group(1).strip()) if m else -1); raise SystemExit
print(len(" ".join(l.strip() for l in m.group(1).strip().splitlines())))
PY
)

  if [ "$len" -lt 0 ]; then
    echo "FAIL  $name: no parsable description in frontmatter"
    fail=$((fail + 1))
  elif [ "$len" -gt "$MAX_DESC" ]; then
    echo "FAIL  $name: description $len chars, over the $MAX_DESC cap (it will truncate)"
    fail=$((fail + 1))
  fi

  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$WARN_LINES" ]; then
    echo "warn  $name: SKILL.md is $lines lines, over the ~$WARN_LINES guideline"
    warn=$((warn + 1))
  fi
done

# A SKILL.md below a registered skill is dead weight: it is never registered, so
# its description never reaches the router and its triggers never fire.
while IFS= read -r nested; do
  echo "FAIL  nested SKILL.md is never registered: $nested"
  echo "      move it to skills/<name>/SKILL.md or it cannot be invoked"
  fail=$((fail + 1))
done < <(find skills shared/skills -mindepth 3 -name SKILL.md 2>/dev/null)

echo
[ "$warn" -gt 0 ] && echo "$warn warning(s)"
if [ "$fail" -gt 0 ]; then
  echo "$fail FAILURE(S)"
  exit 1
fi
echo "OK: every skill has a registered SKILL.md with a description within budget."
