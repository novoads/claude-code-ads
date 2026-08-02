#!/bin/bash
# Upload one local file to Novoads and echo its assetId.
#
# Usage: ./upload-asset.sh <local-file> [mime-type]
# Example: ./upload-asset.sh stills/brent.png image/png
#
# The mime type is inferred from the extension when omitted.
#
# ONE upload per file, ever. The returned assetId is durable and reusable
# without limit — the same id works on call one and call one hundred, from
# startImageAssetId, from referenceAssetIds, and across sessions. The 900s
# expiry on the response belongs to the *upload URL*, not to the asset.
#
# (The previous version of this script uploaded N copies of one file because
# that API's temp uploads were single-use. Here that is not a shortcut to
# skip, it is a defect: a fresh id is a fresh asset, and chaining continuity
# through a new id each time loses the identity anchor.)
#
# Required env: NOVOADS_API_KEY
set -euo pipefail

set -a; source "${ENV_FILE:-$RUN_DIR/.env}" 2>/dev/null || source "$(git rev-parse --show-toplevel 2>/dev/null)/.env"; set +a

BASE="${NOVOADS_BASE_URL:-https://api.novoads.ai}"
AUTH_HDR="Authorization: Bearer $NOVOADS_API_KEY"

LOCAL_FILE="$1"
MIME="${2:-}"

if [[ ! -f "$LOCAL_FILE" ]]; then
  echo "!! no such file: $LOCAL_FILE" >&2
  exit 1
fi

if [[ -z "$MIME" ]]; then
  case "$LOCAL_FILE" in
    *.png|*.PNG)            MIME="image/png" ;;
    *.jpg|*.jpeg|*.JPG)     MIME="image/jpeg" ;;
    *.webp|*.WEBP)          MIME="image/webp" ;;
    *) echo "!! cannot infer mime for $LOCAL_FILE — pass it explicitly" >&2; exit 1 ;;
  esac
fi

# Content-Type and Content-Length are BOTH signed into the presigned URL.
# Measure the file, do not estimate it: a mismatch comes back as a 403 from
# storage that looks like an auth failure and is not one.
SIZE=$(wc -c < "$LOCAL_FILE" | tr -d ' ')

resp=$(curl -sS -H "$AUTH_HDR" -H "Content-Type: application/json" \
  -X POST "$BASE/v1/uploads" \
  -d "$(jq -n --arg ct "$MIME" --argjson sb "$SIZE" '{contentType:$ct, sizeBytes:$sb}')")

ASSET_ID=$(echo "$resp" | jq -r '.assetId // empty')
UPLOAD_URL=$(echo "$resp" | jq -r '.uploadUrl // empty')

if [[ -z "$ASSET_ID" || -z "$UPLOAD_URL" ]]; then
  echo "!! upload request failed: $(echo "$resp" | jq -c '.error // .')" >&2
  exit 1
fi

# Send the signed headers back byte for byte.
HDR_ARGS=()
while IFS=$'\t' read -r k v; do
  [[ -z "$k" ]] && continue
  HDR_ARGS+=(-H "$k: $v")
done < <(echo "$resp" | jq -r '(.headers // {}) | to_entries[] | "\(.key)\t\(.value)"')

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$UPLOAD_URL" \
  "${HDR_ARGS[@]}" --data-binary "@$LOCAL_FILE")

if [[ "$code" != "200" && "$code" != "204" ]]; then
  echo "!! PUT to storage returned $code (Content-Type / Content-Length must match what was signed)" >&2
  exit 1
fi

echo "$ASSET_ID"
