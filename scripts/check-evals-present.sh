#!/usr/bin/env bash
# Every routable skill carries an evals file. FAILS, as of the run that made it true.
#
# An evals file is where a skill records what "working" means — the cases a human
# runs to decide whether a change improved it or quietly broke it. Without one,
# a skill is the thing nobody can review a change to, because there is nothing
# written down to review it against.
#
# This WARNED for as long as the list was non-empty, and the reasoning was that
# a guard which arrives already red gets deleted rather than satisfied: those
# skills shipped without evals and were working, so failing would have reddened
# main for pre-existing debt this check did not cause and could not fix. What a
# warning could usefully do was NAME them, every run, so the list was impossible
# to lose track of and shrank visibly as they landed.
#
# It reached zero. Raising the bar once it is already met costs nothing and locks
# the gain in — the same move `scripts/skill-size-baseline.txt` makes for file
# size — so the warning is now a failure and the only way past it is to write the
# file. A new skill arrives with its evals or it does not arrive.
#
# ONE spelling: `evals.md`, lowercase, in the skill's own directory. The pack used
# lowercase under skills/ and uppercase under shared/skills/ until the rename that
# came with this change; accepting both was a courtesy to that split and there is
# no split left to be courteous to.
#
# The name is matched against the real directory entry rather than with `[ -f ]`,
# and that is not fussiness. macOS ships a case-INSENSITIVE filesystem, so
# `[ -f "${dir}evals.md" ]` is true for a file actually named `EVALS.md` — this
# check would pass on the contributor's laptop and fail on the Linux runner,
# which is the worst arrangement available. `ls | grep -x` reads the name as
# recorded and answers the same on both.
#
# Usage: ./scripts/check-evals-present.sh   (exit 0 clean, 1 if any skill has none)
set -uo pipefail
cd "$(dirname "$0")/.."

missing=0
present=0

for dir in skills/*/ shared/skills/*/; do
  # Routable = carries a SKILL.md. shared/skills/ entries that hold only a
  # prompting/ guide are libraries other skills read, never invoked on their own,
  # so there is no run to write evals for. They may still carry an evals.md —
  # image-ad-prompting does — and it is simply not required here.
  [ -f "${dir}SKILL.md" ] || continue
  name="$(basename "$dir")"

  if ls -1 "$dir" 2>/dev/null | grep -qx 'evals\.md'; then
    present=$((present + 1))
  else
    if [ "$missing" -eq 0 ]; then
      echo "FAIL: a routable skill has no evals.md." >&2
      echo "" >&2
      echo "An evals file is what a reviewer reads to decide whether a change to" >&2
      echo "this skill improved it or quietly broke it. Without one there is" >&2
      echo "nothing to review the change against." >&2
      echo "" >&2
      echo "Write ${dir}evals.md — scenarios from real failures, not" >&2
      echo "hypotheticals. skills/novoads-pixar-ad/evals.md and" >&2
      echo "skills/clone-video-ad/evals.md are the house pattern: scenario, what" >&2
      echo "the agent should do, what failure looks like, how to check it." >&2
      echo "" >&2
      echo "The name is 'evals.md', lowercase. 'EVALS.md' is a different file on" >&2
      echo "a case-sensitive filesystem and does not count." >&2
      echo "" >&2
    fi
    echo "  $name has no evals.md — no written definition of what working means" >&2
    missing=$((missing + 1))
  fi
done

echo
if [ "$missing" -gt 0 ]; then
  echo "$present of $((present + missing)) routable skills carry evals; $missing do not." >&2
  exit 1
fi

echo "OK: all $present routable skills carry an evals.md."
