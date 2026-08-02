#!/bin/bash
# Poll Novoads video jobs until every one reaches a TERMINAL status, then download.
# Usage: ./poll-and-download.sh <out-subdir> <slot1>=<jobId1> <slot2>=<jobId2> ...
# Example: ./poll-and-download.sh clips pain-cpm=f2cd403d-... brent=9a71c8de-...
#
# Outputs land in $RUN_DIR/<out-subdir>/<slot>.mp4
#
# Only video jobs need this. POST /v1/images is synchronous and
# generate-stills.sh has already written those files.
#
# There is ONE polling path for every model: GET /v1/generations/{jobId}.
# Poll for a TERMINAL status, not for 'succeeded' — 'failed', 'blocked' and
# 'canceled' are also final, and waiting for success on a blocked job waits
# forever.
#
# Required env: NOVOADS_API_KEY, RUN_DIR
set -euo pipefail

set -a; source "${ENV_FILE:-$RUN_DIR/.env}" 2>/dev/null || source "$(git rev-parse --show-toplevel 2>/dev/null)/.env"; set +a

BASE="${NOVOADS_BASE_URL:-https://api.novoads.ai}"
AUTH_HDR="Authorization: Bearer $NOVOADS_API_KEY"

SUBDIR="$1"; shift
OUT_DIR="$RUN_DIR/$SUBDIR"
mkdir -p "$OUT_DIR/_resp"

SLOT_NAMES=()
SLOT_IDS=()
SLOT_DONE=()
for kv in "$@"; do
  SLOT_NAMES+=("${kv%%=*}")
  SLOT_IDS+=("${kv#*=}")
  SLOT_DONE+=(0)
done

iter=0
MAX_ITERS="${MAX_ITERS:-90}"       # 90 x 15s = 22.5 min; seedance-2.0 runs 3-8 min
# 15s, not 5s: 5s across 5 concurrent jobs is 60 calls/min, exactly the
# per-key rate limit with zero headroom.
POLL_INTERVAL="${POLL_INTERVAL:-15}"

while :; do
  iter=$((iter+1))
  pending=0
  echo "--- poll iter $iter ---"
  for i in "${!SLOT_NAMES[@]}"; do
    [[ "${SLOT_DONE[$i]}" == "1" ]] && continue
    slot="${SLOT_NAMES[$i]}"
    id="${SLOT_IDS[$i]}"
    resp=$(curl -sS -H "$AUTH_HDR" "$BASE/v1/generations/$id")
    status=$(echo "$resp" | jq -r '.status // "?"')
    echo "  [$slot] $id status=$status"
    case "$status" in
      succeeded)
        echo "$resp" > "$OUT_DIR/_resp/$slot.json"
        # /watch 302s to a URL signed at request time — better than reusing an
        # outputUrl that may have expired while the job was still running.
        out="$OUT_DIR/$slot.mp4"
        echo "    -> downloading"
        curl -sS -L -H "$AUTH_HDR" "$BASE/v1/generations/$id/watch" -o "$out"
        SLOT_DONE[$i]=1
        ;;
      failed|blocked|canceled)
        echo "$resp" > "$OUT_DIR/_resp/$slot.json"
        err=$(echo "$resp" | jq -r '.error.message // .error.code // "(no message)"')
        echo "    !! $status: $err"
        [[ "$status" == "blocked" ]] && echo "    (blocked = moderation refused the prompt; nothing was charged)"
        SLOT_DONE[$i]=1
        ;;
      *)
        # queued / running / finalizing — queued means charged and submitted
        # but not yet rendering. Normal, not a stall.
        pending=$((pending+1))
        ;;
    esac
  done
  if [[ $pending -eq 0 ]]; then
    echo "=== all jobs terminal ==="
    break
  fi
  if [[ $iter -gt $MAX_ITERS ]]; then
    echo "!! still pending after $iter polls — the jobs are not lost."
    echo "!! Re-run with the same jobIds, or list them: GET $BASE/v1/generations"
    break
  fi
  sleep "$POLL_INTERVAL"
done

ls -la "$OUT_DIR" 2>/dev/null | grep -v _resp || true
