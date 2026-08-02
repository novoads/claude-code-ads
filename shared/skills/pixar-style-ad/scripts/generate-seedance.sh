#!/bin/bash
# Fire Seedance image-to-video jobs, one per (still x variation).
# Reads jobs from STDIN:
#   <slot>::<prompt-text>::<duration-seconds>::<still-slot>
#
# Looks the still's assetId up in $RUN_DIR/references/still-assets.txt
# (produced by upload-stills.sh). Format there: <slot><TAB><assetId>
#
# Example:
#   cat <<EOF | ./generate-seedance.sh clips
#   pain-cpm-v1::3D animated film aesthetic, image-to-video of the start frame...::4::pain-cpm
#   pain-cpm-v2::3D animated film aesthetic, image-to-video of the start frame...::4::pain-cpm
#   brent-reveal-v1::3D animated film aesthetic, image-to-video of the start frame...::8::brent-reveal
#   EOF
#
# Note there is no variation index in the still lookup: every variation of a
# beat passes the SAME durable assetId as startImageAssetId. Variations differ
# by prompt and slot name, not by a re-uploaded copy of the same picture.
#
# POST /v1/videos is ASYNC: it returns a jobId. Poll with poll-and-download.sh.
#
# Required env: NOVOADS_API_KEY, RUN_DIR.  Optional: PRODUCT_ID.
set -euo pipefail

set -a; source "${ENV_FILE:-$RUN_DIR/.env}" 2>/dev/null || source "$(git rev-parse --show-toplevel 2>/dev/null)/.env"; set +a

BASE="${NOVOADS_BASE_URL:-https://api.novoads.ai}"
AUTH_HDR="Authorization: Bearer $NOVOADS_API_KEY"
MODEL="${VIDEO_MODEL:-seedance-2.0}"       # seedance-2.0-mini is half price for drafts
ASPECT="${ASPECT_RATIO:-9:16}"             # Seedance defaults to 16:9 — always send it
LANGUAGE="${LANGUAGE:-en}"
MAX_INFLIGHT="${MAX_INFLIGHT:-4}"          # org ceiling is 5; leave one slot for QA retries

# There is no `resolution` field (720p is fixed) and no `audioEnabled` field:
# Seedance renders audio and lip-sync in the same call, driven by the prompt.
# There is no `projectId` either — the v1 API has no project writes. Use
# productId if you want the job attributable to a product.

SUBDIR="$1"
OUT_DIR="$RUN_DIR/$SUBDIR/_resp"
SF_MAP="$RUN_DIR/references/still-assets.txt"
mkdir -p "$OUT_DIR"

lookup_asset() {
  awk -F'\t' -v k="$1" '$1==k {print $2; exit}' "$SF_MAP"
}

post_one() {
  local slot="$1" prompt="$2" duration="$3" still_key="$4"

  local asset; asset=$(lookup_asset "$still_key")
  if [[ -z "$asset" ]]; then
    echo "[$slot] !! no assetId in $SF_MAP for '$still_key'" >&2
    return 1
  fi

  # durationSeconds is an enum of integers 4..15 on Seedance; out-of-grid
  # values are rejected, never rounded.
  if ! [[ "$duration" =~ ^[0-9]+$ ]] || (( duration < 4 || duration > 15 )); then
    echo "[$slot] !! duration '$duration' outside the 4-15 grid" >&2
    return 1
  fi

  local body
  body=$(jq -n \
    --arg model "$MODEL" --arg p "$prompt" --arg asset "$asset" \
    --arg aspectRatio "$ASPECT" --arg language "$LANGUAGE" \
    --argjson dur "$duration" --arg productId "${PRODUCT_ID:-}" \
    '{model:$model, prompt:$p, durationSeconds:$dur, aspectRatio:$aspectRatio,
      language:$language, startImageAssetId:$asset}
     + (if ($productId|length)>0 then {productId:$productId} else {} end)')

  # No blind retry on failure: there are no idempotency keys, so a resubmit
  # can double-charge. On a 5xx, check GET /v1/generations for a job matching
  # this prompt before firing again.
  local resp
  resp=$(curl -sS --max-time 120 -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -X POST "$BASE/v1/videos" -d "$body")
  echo "$resp" > "$OUT_DIR/$slot.json"

  local err; err=$(echo "$resp" | jq -r '.error.code // empty')
  if [[ -n "$err" ]]; then
    local reason; reason=$(echo "$resp" | jq -r '.error.details.reason // empty')
    echo "[$slot] !! $err${reason:+ ($reason)}: $(echo "$resp" | jq -r '.error.message // ""')" >&2
    if [[ "$reason" == "concurrency_limit" ]]; then
      echo "[$slot]    concurrency_limit is fixed by WAITING for a running job, not by slowing down." >&2
    fi
    return 1
  fi

  local id;      id=$(echo "$resp" | jq -r '.jobId // empty')
  local status;  status=$(echo "$resp" | jq -r '.status // empty')
  local credits; credits=$(echo "$resp" | jq -r '.creditsCharged // "?"')
  echo "[$slot] jobId=$id status=$status credits=$credits dur=${duration}s"
}

export -f post_one lookup_asset
export BASE AUTH_HDR MODEL ASPECT LANGUAGE OUT_DIR SF_MAP PRODUCT_ID

# Throttled fan-out in waves of MAX_INFLIGHT. bash 3.2 safe (no `wait -n`).
rc=0
PIDS=()

drain() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [[ -z "$pid" ]] && continue
    wait "$pid" || rc=1
  done
  PIDS=()
}

n=0
while IFS=$'\n' read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  slot="${line%%::*}"; rest="${line#*::}"
  prompt="${rest%%::*}"; rest="${rest#*::}"
  duration="${rest%%::*}"; still_key="${rest#*::}"
  post_one "$slot" "$prompt" "$duration" "$still_key" &
  PIDS+=($!)
  n=$((n+1))
  if [[ ${#PIDS[@]} -ge $MAX_INFLIGHT ]]; then drain; fi
done
drain

echo "=== issued $n Seedance jobs. Poll with poll-and-download.sh <subdir> <slot>=<jobId> ... ==="
exit $rc
