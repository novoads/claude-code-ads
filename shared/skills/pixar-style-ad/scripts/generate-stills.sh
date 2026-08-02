#!/bin/bash
# Generate storyboard stills on POST /v1/images.
#
# Reads jobs from STDIN, one per line:
#   <slot>::<prompt-text>::<optional-comma-separated-reference-assetIds>
#
# Example:
#   cat <<EOF | ./generate-stills.sh stills/batch-a
#   pain-cpm::Pixar-style anthropomorphic character...::
#   brent-reveal::Pixar-style mid-30s man holding laptop...::asset_abc,asset_def
#   EOF
#
# THIS ENDPOINT IS SYNCHRONOUS. The image comes back on the response — there
# is no job to poll and no asset id to look up afterwards. Files land in
# $RUN_DIR/<subdir>/<slot>.png directly.
#
# referenceAssetIds: max 4, images only, order preserved, addressable in the
# prompt as @Image1..@Image4. Get ids from upload-asset.sh.
#
# For N variations of ONE prompt use NUM_IMAGES=N (1-4) rather than firing N
# calls: it is the same price, one call, and it does not burn N concurrency
# slots. Variations land as <slot>-1.png .. <slot>-N.png.
#
# Required env: NOVOADS_API_KEY, RUN_DIR.  Optional: PRODUCT_ID.
set -euo pipefail

set -a; source "${ENV_FILE:-$RUN_DIR/.env}" 2>/dev/null || source "$(git rev-parse --show-toplevel 2>/dev/null)/.env"; set +a

BASE="${NOVOADS_BASE_URL:-https://api.novoads.ai}"
AUTH_HDR="Authorization: Bearer $NOVOADS_API_KEY"
MODEL="${IMAGE_MODEL:-gpt-image-2}"        # or nano-banana-pro, reve-2.1
ASPECT="${ASPECT_RATIO:-9:16}"             # gpt-image-2 defaults to 1:1 — always send it
NUM_IMAGES="${NUM_IMAGES:-1}"              # 1-4
MAX_INFLIGHT="${MAX_INFLIGHT:-4}"          # org ceiling is 5; leave one slot for QA retries

SUBDIR="$1"
OUT_DIR="$RUN_DIR/$SUBDIR"
mkdir -p "$OUT_DIR/_resp"

post_one() {
  local slot="$1" prompt="$2" refs_csv="$3"

  local refs_json='[]'
  if [[ -n "$refs_csv" ]]; then
    refs_json=$(echo "$refs_csv" | tr ',' '\n' | sed '/^$/d' | jq -R . | jq -s .)
    local n; n=$(echo "$refs_json" | jq 'length')
    if (( n > 4 )); then
      echo "[$slot] !! $n references — the cap is 4. Trim to [hero, N-1, N-2, N-3]." >&2
      return 1
    fi
  fi

  local body
  body=$(jq -n \
    --arg model "$MODEL" --arg prompt "$prompt" --arg aspectRatio "$ASPECT" \
    --argjson numImages "$NUM_IMAGES" --argjson refs "$refs_json" \
    --arg productId "${PRODUCT_ID:-}" \
    '{model:$model, prompt:$prompt, aspectRatio:$aspectRatio, numImages:$numImages}
     + (if ($refs|length)>0   then {referenceAssetIds:$refs} else {} end)
     + (if ($productId|length)>0 then {productId:$productId} else {} end)')

  # Images are synchronous and can take a while to come back. Do not use a
  # short timeout here and do not blind-retry on failure: there are no
  # idempotency keys, so a retry can double-charge. On a 5xx, check
  # GET /v1/generations before resubmitting.
  local resp
  resp=$(curl -sS --max-time 300 -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -X POST "$BASE/v1/images" -d "$body")
  echo "$resp" > "$OUT_DIR/_resp/$slot.json"

  local err; err=$(echo "$resp" | jq -r '.error.code // empty')
  if [[ -n "$err" ]]; then
    echo "[$slot] !! $err: $(echo "$resp" | jq -r '.error.message // ""')" >&2
    return 1
  fi

  local credits; credits=$(echo "$resp" | jq -r '.creditsCharged // "?"')
  local count;   count=$(echo "$resp" | jq -r '.images | length')

  local i=1
  while IFS= read -r url; do
    local out
    if (( count > 1 )); then out="$OUT_DIR/$slot-$i.png"; else out="$OUT_DIR/$slot.png"; fi
    curl -sS -L "$url" -o "$out"
    i=$((i+1))
  done < <(echo "$resp" | jq -r '.images[].url')

  echo "[$slot] $count image(s) credits=$credits -> $OUT_DIR"
}

export -f post_one
export BASE AUTH_HDR MODEL ASPECT NUM_IMAGES OUT_DIR PRODUCT_ID

# Throttled fan-out, in waves of MAX_INFLIGHT. Written for bash 3.2 (the
# system bash on macOS): no `wait -n`, no associative arrays.
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

while IFS=$'\n' read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  slot="${line%%::*}"; rest="${line#*::}"
  prompt="${rest%%::*}"; refs="${rest#*::}"
  [[ "$refs" == "$rest" ]] && refs=""
  post_one "$slot" "$prompt" "$refs" &
  PIDS+=($!)
  if [[ ${#PIDS[@]} -ge $MAX_INFLIGHT ]]; then drain; fi
done
drain

echo "=== stills written to $OUT_DIR — QA them before uploading as start frames ==="
exit $rc
