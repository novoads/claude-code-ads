#!/usr/bin/env bash
# Parity guard for skills/novoads-image-to-motion/.
#
# That skill is a PORT. Its craft arrived whole from a vendor-connector skill of
# the same shape and only the transport was rewritten, so it has two failure
# modes that pull in opposite directions and a reviewer reliably only looks for
# one of them:
#
#   drift       a craft section quietly thinned in the move. The port is worth
#               nothing if the part worth porting did not arrive.
#
#   half-port   a retired tool name or a retired API claim left in place. Worse
#               than drift, because it does not read as wrong: the agent follows
#               it and either stalls on a tool that does not exist or spends a
#               render on a 400 this repo already knows about.
#
# So this checks BOTH directions. The judgement half — has the craft been
# softened rather than deleted — is in the skill's evals.md and cannot be
# grepped. This file owns only what a string match can settle, which is the half
# that should never have needed a human.
#
# Costs nothing and touches no network. Usage: ./scripts/test-parity-i2m.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SKILL=skills/novoads-image-to-motion/SKILL.md
EVALS=skills/novoads-image-to-motion/evals.md
fail=0
pass=0

ok()   { pass=$((pass + 1)); }
bad()  { echo "FAIL  $1"; fail=$((fail + 1)); }

[ -f "$SKILL" ] || { echo "FAIL  $SKILL is missing"; exit 1; }
[ -f "$EVALS" ] || { echo "FAIL  $EVALS is missing"; exit 1; }

# ── 1. Half-port: retired names and retired claims ───────────────────────────
# Each pattern is a thing the SOURCE skill said that is false or unreachable on
# /v1. `nbGenerations` and a 1080p ask are both live-verified 400s (2026-08-10);
# the other three name a vendor tool or a vendor behaviour we do not have.
#
# Checked against the whole skill directory, not just SKILL.md, so a reference
# file added later inherits the guard instead of escaping it.
while IFS='|' read -r pattern why; do
  [ -z "$pattern" ] && continue
  # -F: these are literal names, never regexes. A pattern that is accidentally a
  # regex is how a guard silently stops matching what it claims to match.
  if hits=$(grep -rnF -e "$pattern" skills/novoads-image-to-motion/ 2>/dev/null); then
    # evals.md documents the retired names in order to test for them, exactly as
    # the anti-connector evals do. Anything OUTSIDE evals.md is a real hit.
    if real=$(printf '%s\n' "$hits" | grep -v "^$EVALS:"); then
      bad "retired '$pattern' survives ($why)"
      printf '%s\n' "$real" | sed 's/^/        /'
    else
      ok
    fi
  else
    ok
  fi
done <<'PATTERNS'
arcads_|vendor tool name; nothing here can call it
register_image|no analogue on /v1; the warning is meaningless
nbGenerations|not a field; live-verified 400 Unrecognized key
720p or higher|720p is this model's ceiling; 1080p is a live-verified 400
expire quickly|inverted: the assetId is durable, the upload URL expires
PATTERNS

# ── 2. Drift: the craft that the port exists to carry ─────────────────────────
# Seven motion classes and five prompt clauses. Anchored on the distinctive
# phrase rather than a heading, because none of the clauses IS a heading and a
# heading-only check passes on a section emptied of its content.
while IFS='|' read -r needle what; do
  [ -z "$needle" ] && continue
  if grep -qF -e "$needle" "$SKILL"; then ok; else bad "craft lost: $what"; fi
done <<'CRAFT'
UI, app screens, toolbars|motion class 1 of 7 (UI)
Marketing hero|motion class 2 of 7 (hero)
Flat-lay, evidence board|motion class 3 of 7 (flat-lay)
Painted key art|motion class 4 of 7 (key art)
Collage, paper-cut|motion class 5 of 7 (collage)
Product still, object|motion class 6 of 7 (product)
Character, mascot, avatar|motion class 7 of 7 (character)
stagger paired elements|the stagger rule, the single highest-value craft line
accent structure|the accent-structure read in step 1
quote every string|clause 1 of 5 (text fidelity)
including anything that is ABSENT|clause 2 of 5 (the 0.0s frame)
holds completely still|clause 3 of 5 (declared holds)
No fade out|clause 4 of 5 (explicit final hold)
One object per beat|clause 5 of 5 (one beat, one motion, easing named)
add specificity rather than emphasis|the iteration rule
CRAFT

# ── 3. The pack's own invariants, on this file ────────────────────────────────
# The key-gate block is quoted verbatim in every SKILL.md so a solo install
# still refuses to run without a key. check-no-mcp.sh allowlists exactly this
# phrasing, so a reworded copy fails CI there; catching it here reports the
# actual remedy instead of an MCP violation.
grep -qF 'REST key required. A Novoads MCP connector is not a substitute.' "$SKILL" \
  && ok || bad "the canonical key-gate block is missing or reworded"

# The cost gate has to actually run. The first version of this skill showed an
# estimate body with no `prompt`, which is REQUIRED on a strict schema: live, that
# is `400 prompt: Invalid input: expected string, received undefined`. An agent
# following it would have had to improvise past the one guard rail between the
# user and a charge, and the warnings section below it would have had nothing to
# lint. Found by an independent parity review, not by a human reading the file.
if grep -q '"kind":"video"' "$SKILL"; then
  if grep -n '"kind":"video"' "$SKILL" | grep -qv 'prompt'; then
    bad "the estimate example omits the required 'prompt' — that body is a live 400"
  else
    ok
  fi
else
  bad "no {\"kind\":\"video\"} estimate example; the cost gate is unshowable"
fi

# A price written into a skill file rots silently, and this repo's rule is that
# every credit number comes from a live estimate. Digits followed by a credit
# word are the shape that keeps coming back.
if grep -nEi '[0-9]+(\.[0-9]+)?[[:space:]]*(cc|credits?)\b' "$SKILL" | grep -v 'credits?Charged'; then
  bad "a credit figure is written into the skill; price it live instead"
else
  ok
fi

echo
if [ "$fail" -gt 0 ]; then
  echo "$fail FAILURE(S), $pass check(s) passed"
  exit 1
fi
echo "OK: $pass parity checks passed (no half-port, no craft drift)."
