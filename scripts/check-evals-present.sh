#!/usr/bin/env bash
# Every routable skill should carry an evals file. WARNING ONLY, on purpose.
#
# An evals file is where a skill records what "working" means — the cases a human
# runs to decide whether a change improved it or quietly broke it. Ten of the
# sixteen routable skills have one; the rest are the ones nobody can currently
# review a change to, because there is nothing written down to review it against.
#
# This WARNS and never fails, and the reason is the whole design:
#
#   the gap is real but it is not a REGRESSION. Those six skills shipped without
#   evals and are working. Failing here would redden main for pre-existing debt
#   that this check did not cause and cannot fix, and the reliable outcome of a
#   guard that arrives already red is that someone deletes the guard rather than
#   writes six evals files.
#
#   a later node is adding them. Until then the useful thing a check can do is
#   NAME them, every run, so the list is impossible to lose track of and shrinks
#   visibly as they land.
#
# When the list reaches zero, promote this to a failure and delete this comment.
# That is the only edit worth making here: raising the bar once it is already met
# costs nothing and locks the gain in, which is exactly what the SKILL.md line
# baseline does for file size.
#
# Both spellings are accepted — `evals.md` and `EVALS.md`. The pack uses lowercase
# under skills/ and uppercase under shared/skills/, and standardising the case is
# a rename PR, not this guard's business.
#
# Usage: ./scripts/check-evals-present.sh   (always exit 0)
set -uo pipefail
cd "$(dirname "$0")/.."

missing=0
present=0

for dir in skills/*/ shared/skills/*/; do
  # Routable = carries a SKILL.md. shared/skills/ entries that hold only a
  # prompting/ guide are libraries other skills read, never invoked on their own,
  # so there is no run to write evals for.
  [ -f "${dir}SKILL.md" ] || continue
  name="$(basename "$dir")"

  if [ -f "${dir}evals.md" ] || [ -f "${dir}EVALS.md" ]; then
    present=$((present + 1))
  else
    echo "warn  $name has no evals.md — no written definition of what working means"
    missing=$((missing + 1))
  fi
done

echo
if [ "$missing" -gt 0 ]; then
  echo "$present of $((present + missing)) routable skills carry evals; $missing do not (warning only)."
else
  echo "OK: all $present routable skills carry an evals file. Time to make this a failure."
fi
exit 0
