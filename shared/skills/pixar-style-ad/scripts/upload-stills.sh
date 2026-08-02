#!/bin/bash
# Upload each approved storyboard still ONCE and write a slot -> assetId map to
# $RUN_DIR/references/still-assets.txt for the generation step.
#
# Usage: ./upload-stills.sh
# Reads the still list from STDIN:
#   <slot>::<local-still-path>
#
# Example:
#   cat <<EOF | ./upload-stills.sh
#   pain-cpm::stills/batch-a/pain-cpm.png
#   brent-reveal::stills/brent-final.png
#   EOF
#
# One upload per still, not one per variation. The assetId is durable and
# reusable without limit, so N variations of a beat all pass the SAME id as
# startImageAssetId. Re-uploading would mint a second asset for identical
# bytes and cost you the identity anchor the storyboard exists to hold.
#
# Map format: <slot><TAB><assetId>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPLOAD="$SCRIPT_DIR/upload-asset.sh"
MAP="$RUN_DIR/references/still-assets.txt"
mkdir -p "$RUN_DIR/references"
: > "$MAP"

n=0
while IFS=$'\n' read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  slot="${line%%::*}"
  path="${line#*::}"
  # Resolve relative paths against RUN_DIR
  [[ "$path" != /* ]] && path="$RUN_DIR/$path"
  echo "uploading $slot..." >&2
  asset_id=$("$UPLOAD" "$path")
  printf '%s\t%s\n' "$slot" "$asset_id" >> "$MAP"
  n=$((n+1))
done

echo "Wrote $MAP ($n stills)"
