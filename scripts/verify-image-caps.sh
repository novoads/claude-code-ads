#!/usr/bin/env bash
# Claims audit for the per-model referenceAssetIds caps.
#
# This repo states API limits in scripts and docs; the API moves without asking us.
# The caps drifted once already (spec 2.7.0 raised nano-banana-pro from 4 to 14 and
# the pack said 4 for two days), so this script is the standing alarm:
#
#   1. Fetches the LIVE openapi.json (public, no key) and extracts each image
#      model's referenceAssetIds maxItems — matched by the schema's `model` enum
#      value, never by schema name, so a schema rename cannot mis-map a cap.
#   2. Asserts the three generator/validator scripts ENFORCE those caps, by
#      running them: cap+1 refs must be refused naming the cap; cap refs must
#      pass the gate (and then die at a nonexistent --env-file, BEFORE any
#      network call — nothing here needs a key and nothing can spend).
#   3. Greps the docs for resurrected universal-cap claims.
#
# Modes:
#   (default)  full audit, hard exit 1 on any mismatch — run before shipping cap
#              or doc changes, paste the output into the PR.
#   --soft     spec-vs-expected only, WARN and always exit 0 — wired into
#              check-novoads-env.sh so every skill preflight surfaces drift
#              without ever blocking an offline machine.
#
# No jq, no API key, no spend. python3 stdlib only.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOFT=0
[[ "${1:-}" == "--soft" ]] && SOFT=1
BASE="${NOVOADS_BASE_URL:-https://api.novoads.ai}"

# The one expected table. Scripts and docs are checked AGAINST this; this is
# checked against the live spec. Update it only from verified spec output.
EXPECTED='gpt-image-2=4 nano-banana-pro=14 reve-2.1=8'

STATUS=0
problem() {
  if [[ $SOFT -eq 1 ]]; then echo "WARN(image-caps): $*" >&2
  else echo "FAIL(image-caps): $*" >&2; STATUS=1; fi
}

# ── 1. live spec vs EXPECTED ─────────────────────────────────────────────────
SPEC_JSON="$(curl -sS -m 15 "$BASE/v1/openapi.json" 2>/dev/null || true)"
if [[ -z "$SPEC_JSON" ]]; then
  problem "could not fetch $BASE/v1/openapi.json — cap claims unverified this run"
else
  MISMATCH="$(printf '%s' "$SPEC_JSON" | python3 -c "
import json, sys
expected = dict(kv.split('=') for kv in '''$EXPECTED'''.split())
expected = {k: int(v) for k, v in expected.items()}
spec = json.load(sys.stdin)
live = {}
for schema in spec.get('components', {}).get('schemas', {}).values():
    props = schema.get('properties') or {}
    model = props.get('model') or {}
    names = model.get('enum') or ([model['const']] if 'const' in model else [])
    refs = props.get('referenceAssetIds') or {}
    for name in names:
        if name in expected and 'maxItems' in refs:
            live[name] = refs['maxItems']
for name, want in sorted(expected.items()):
    got = live.get(name)
    if got != want:
        print(f'{name}: repo says {want}, live spec says {got}')
" 2>/dev/null || echo "spec parse failed")"
  [[ -n "$MISMATCH" ]] && problem "live-spec drift — $MISMATCH"
fi

if [[ $SOFT -eq 1 ]]; then
  exit 0
fi

# ── 2. the scripts enforce EXPECTED (behavior, not constants) ────────────────
check_script() { # <script> <cap> [extra args...]
  local script="$1" cap="$2"; shift 2
  local refs=() i
  for ((i = 0; i <= cap; i++)); do refs+=(--image-ref "/tmp/vc-ref-$i.png"); done
  local out
  # cap+1 refs → must refuse, naming the cap, before anything else happens.
  out="$(python3 "$ROOT/$script" "$@" --prompt probe --aspect-ratio 1:1 \
    --out /tmp/vc-out --env-file /nonexistent/none "${refs[@]}" 2>&1)" \
    && problem "$script accepted $((cap + 1)) refs (expected refusal at $cap)"
  [[ "$out" == *"$cap"* ]] || problem "$script refusal does not name cap $cap: $out"
  # exactly cap refs → the gate must OPEN (script then dies at the fake .env,
  # which proves it got past the cap check without touching the network).
  out="$(python3 "$ROOT/$script" "$@" --prompt probe --aspect-ratio 1:1 \
    --out /tmp/vc-out --env-file /nonexistent/none "${refs[@]:0:$((cap * 2))}" 2>&1)" \
    && problem "$script with $cap refs exited 0 (should die at the fake .env)"
  [[ "$out" == *".env not found"* ]] || problem "$script with $cap refs died before/after the env gate unexpectedly: $out"
}
check_script "skills/chatgpt-image-ad/scripts/generate_image.py" 4
check_script "skills/nano-banana-image-ad/scripts/generate_image.py" 14
check_script "skills/image-ad-clone/scripts/validate_image.py" 4 --model gpt-image-2
check_script "skills/image-ad-clone/scripts/validate_image.py" 14 --model nano-banana-pro
check_script "skills/image-ad-clone/scripts/validate_image.py" 8 --model reve-2.1

# ── 3. docs carry no resurrected universal-cap claim ─────────────────────────
RESIDUE="$(grep -rn "caps at .* on every\|cap is .* on every\|max 4 on every\|cap is the same on every\|cap is the same everywhere" \
  --include="*.md" --include="*.py" "$ROOT/skills" "$ROOT/shared" "$ROOT/README.md" 2>/dev/null || true)"
[[ -n "$RESIDUE" ]] && problem "universal-cap claim resurfaced:
$RESIDUE"

if [[ $STATUS -eq 0 ]]; then
  echo "image-caps audit OK — spec, scripts, and docs agree on: $EXPECTED"
fi
exit $STATUS
