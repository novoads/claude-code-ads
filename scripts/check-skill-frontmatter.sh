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
#                    registered. The video cloner sat there fully written, with a correct
#                    description naming exactly the right triggers, and none of
#                    them ever reached the router.
#
# The 500-line body used to WARN. It now fails, against a baseline, because a
# warning is something you walk past: spy-competitor-ads was split to 489 lines
# and pushed back to 531 four hours later by the same author who wrote the
# warning, and CI stayed green throughout.
#
# The baseline in scripts/skill-size-baseline.txt lists the files already over
# the line, with the count they were at. A listed file may shrink freely and may
# never grow; an unlisted file may never cross. Forward-only, so today's debt is
# recorded rather than blocking, and tomorrow's is refused.
#
# When you legitimately shrink one, re-run with --update-baseline to lock the
# smaller number in. There is no flag to raise one.
set -uo pipefail
cd "$(dirname "$0")/.."

MAX_DESC=1024
# The warn band. A description is not edited down to the character on the day it
# crosses 1024 — it drifts there one clarifying clause at a time, and the commit
# that finally trips the cap is rarely the one that caused the problem. 900 leaves
# roughly one sentence of runway, which is about what a "NOT for X, use Y" tail
# costs, so the warning arrives while there is still somewhere to put it.
#
# WARN, not fail: a description between 900 and 1024 is correct and shipping. The
# thing being reported is proximity, and reddening CI for proximity teaches people
# to stop reading the output.
WARN_DESC=900
MAX_LINES=500
BASELINE=scripts/skill-size-baseline.txt
UPDATE=0
[ "${1:-}" = "--update-baseline" ] && UPDATE=1

fail=0
warn=0

for dir in skills/*/ shared/skills/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  file="${dir%/}/SKILL.md"

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
  elif [ "$len" -gt "$WARN_DESC" ]; then
    echo "warn  $name: description $len chars, $((MAX_DESC - len)) from the $MAX_DESC cap"
    echo "      the tail is the disambiguation; trim before it is the part that truncates"
    warn=$((warn + 1))
  fi

  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$MAX_LINES" ]; then
    allowed=$(awk -v f="$file" '$2 == f {print $1}' "$BASELINE" 2>/dev/null)
    if [ -z "$allowed" ]; then
      echo "FAIL  $name: SKILL.md is $lines lines, over $MAX_LINES, and not in the baseline"
      echo "      split it — move what is not needed mid-run into references/"
      fail=$((fail + 1))
    elif [ "$lines" -gt "$allowed" ]; then
      echo "FAIL  $name: SKILL.md grew from $allowed to $lines lines"
      echo "      it is already over $MAX_LINES; the baseline may shrink, never grow"
      fail=$((fail + 1))
    elif [ "$lines" -lt "$allowed" ]; then
      echo "warn  $name: shrank $allowed -> $lines. Run --update-baseline to lock it in"
      warn=$((warn + 1))
    fi
  fi
done

# A SKILL.md below a registered skill is dead weight: it is never registered, so
# its description never reaches the router and its triggers never fire.
while IFS= read -r nested; do
  echo "FAIL  nested SKILL.md is never registered: $nested"
  echo "      move it to skills/<name>/SKILL.md or it cannot be invoked"
  fail=$((fail + 1))
done < <(find skills shared/skills -mindepth 3 -name SKILL.md 2>/dev/null)

if [ "$UPDATE" -eq 1 ]; then
  # RATCHET, not a rewrite. The first version of this rewrote the baseline from
  # disk, which silently RAISED clone-video-ad from 836 to 858 the first time it
  # was used — by the author, in the same session that wrote "there is no flag to
  # raise one". A guard with a flag that disarms it is not a guard.
  refused=0
  for dir in skills/*/ shared/skills/*/; do
    f="${dir%/}/SKILL.md"
    [ -f "$f" ] || continue
    n=$(wc -l < "$f" | tr -d ' ')
    [ "$n" -gt "$MAX_LINES" ] || continue
    old=$(awk -v x="$f" '$2 == x {print $1}' "$BASELINE" 2>/dev/null)
    if [ -n "$old" ] && [ "$n" -gt "$old" ]; then
      echo "REFUSED  $f is $n lines, baseline says $old. The baseline only goes down."
      echo "         Cut $((n - old)) lines, or split the file. Not recording this."
      refused=$((refused + 1))
      echo "$old $f"
    else
      echo "$n $f"
    fi
  done | sort -rn > "$BASELINE.tmp"
  grep -v '^REFUSED\|^ ' "$BASELINE.tmp" > "$BASELINE.clean" 2>/dev/null || true
  mv "$BASELINE.clean" "$BASELINE"; rm -f "$BASELINE.tmp"
  echo
  echo "baseline (lowered where the file shrank, unchanged where it grew):"
  sed 's/^/  /' "$BASELINE"
  exit 0
fi

echo
[ "$warn" -gt 0 ] && echo "$warn warning(s)"
if [ "$fail" -gt 0 ]; then
  echo "$fail FAILURE(S)"
  exit 1
fi
echo "OK: every skill has a registered SKILL.md with a description within budget."
