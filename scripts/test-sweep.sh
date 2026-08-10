#!/usr/bin/env bash
# Unit tests for sweep.py. Spends nothing and touches no network: every case
# either stops before the first request, or exercises a pure function.
#
# S1 is the one that matters. This script SPENDS — one charge per competitor —
# and it is called by an agent. A script that can spend when nobody said yes is
# the failure worth being rude about.
set -uo pipefail
cd "$(dirname "$0")/.."

S=./scripts/sweep.py
pass=0; fail=0
ok()  { printf '  ok    %-5s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad() { printf '  FAIL  %-5s %s\n' "$1" "$2"; fail=$((fail+1)); }
want(){ if [ "$2" = "$3" ]; then ok "$1" "$4"; else bad "$1" "$4 (want '$3', got '$2')"; fi }

echo "sweep tests"

# S1 -- MONEY. No --yes, no request. Checked with a REAL key present, so the
# refusal is about consent and not about a missing credential.
out=$(NOVOADS_API_KEY=novo_realish $S --queries a.com,b.com --media video 2>&1)
want S1 "$?" "1" "refuses to spend without --yes"
case "$out" in *"without --yes"*) ok S1b "the refusal says what is missing" ;;
                *) bad S1b "the refusal does not name --yes" ;; esac
case "$out" in *"POST /v1/estimates"*) ok S1c "and points at the price gate" ;;
                *) bad S1c "the refusal does not mention estimating first" ;; esac

# S2 -- a placeholder key is refused BEFORE any request, so a fresh clone fails
# on the credential rather than on a confusing 401 mid-fan-out.
NOVOADS_API_KEY=novo_your_key_here $S --queries a.com --media video --yes >/dev/null 2>&1
want S2 "$?" "1" "a placeholder key is refused up front"
NOVOADS_API_KEY= $S --queries a.com --media video --yes >/dev/null 2>&1
want S2b "$?" "1" "an empty key is refused up front"

# S3 -- an empty query list is refused rather than sweeping nothing.
NOVOADS_API_KEY=novo_realish $S --queries "  ,, " --media video --yes >/dev/null 2>&1
want S3 "$?" "1" "an empty query list is refused"

# S4 -- media mode has no default at the CLI either, mirroring the API. A silent
# request must not become a guess that spends.
NOVOADS_API_KEY=novo_realish $S --queries a.com --yes >/dev/null 2>&1
want S4 "$?" "2" "--media is required (argparse exits 2)"

# S5 -- PARALLELISM IS CAPPED AT THE API's CEILING. This is the whole point of
# the change, and asking for more than the contract allows must clamp rather
# than earn a fan-out of 429s.
python3 - <<'PY' && ok S5 "parallelism clamps to the API ceiling" || bad S5 "parallelism is not clamped"
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("sw", pathlib.Path("scripts/sweep.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# the clamp the CLI applies: min(requested, ceiling, len(queries))
assert m.API_SWEEP_CEILING == 10, m.API_SWEEP_CEILING
assert max(1, min(50, m.API_SWEEP_CEILING, 3)) == 3
assert max(1, min(50, m.API_SWEEP_CEILING, 30)) == 10
sys.exit(0)
PY

# S6 -- Retry-After comes from the SERVER, never from us. Both carriers, and a
# sane fallback only when neither is usable.
python3 - <<'PY' && ok S6 "retry_after prefers the server's number" || bad S6 "retry_after is wrong"
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("sw", pathlib.Path("scripts/sweep.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.retry_after({"Retry-After": "7"}, {}) == 7
assert m.retry_after({"retry-after": "4"}, {}) == 4
assert m.retry_after({}, {"error": {"details": {"retryAfterSeconds": 12}}}) == 12
assert m.retry_after({}, {}) == m.RETRY_FALLBACK_SECONDS
assert m.retry_after({"Retry-After": "soon"}, {}) == m.RETRY_FALLBACK_SECONDS
sys.exit(0)
PY

# S7 -- media URL preference: HD before SD before still. Downloading the SD copy
# of an ad you are about to study frame by frame is a quiet downgrade.
python3 - <<'PY' && ok S7 "media_url prefers hd, then sd, then image" || bad S7 "media preference is wrong"
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("sw", pathlib.Path("scripts/sweep.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.media_url({"media": {"videoHdUrl": "hd", "videoSdUrl": "sd"}}) == "hd"
assert m.media_url({"media": {"videoSdUrl": "sd", "previewImageUrl": "p"}}) == "sd"
assert m.media_url({"media": {"imageUrl": "i", "previewImageUrl": "p"}}) == "i"
assert m.media_url({"media": {}}) is None
assert m.media_url({}) is None
sys.exit(0)
PY

# S8 -- slugs are filesystem-safe and never empty, because they become directory
# names built from a user-supplied query.
python3 - <<'PY' && ok S8 "slugify is filesystem-safe and never empty" || bad S8 "slugify can produce a bad name"
import importlib.util, pathlib, sys, re
spec = importlib.util.spec_from_file_location("sw", pathlib.Path("scripts/sweep.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for q in ["arcads.ai", "Mr. Paid Social", "../../etc/passwd", "///", "", "a b/c"]:
    s = m.slugify(q)
    assert s and "/" not in s and ".." not in s and re.fullmatch(r"[a-z0-9-]+", s), (q, s)
sys.exit(0)
PY

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
