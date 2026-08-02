#!/bin/bash
# Compose a background music bed via ElevenLabs Music API.
# Tune the prompt to your audience, not generic descriptors. "Modern lo-fi
# electronic, the kind of track a 30-year-old tech founder plays in their
# AirPods while running Meta ads at 2am" produces a better result than
# "uplifting indie acoustic".
#
# Usage: ./generate-music-elevenlabs.sh "<prompt>" <length-ms>
# Example: ./generate-music-elevenlabs.sh "Modern lo-fi electronic..." 45000
set -euo pipefail

set -a; source "${ENV_FILE:-$RUN_DIR/.env}" 2>/dev/null || source "$(git rev-parse --show-toplevel 2>/dev/null)/workspace/.env"; set +a

PROMPT="$1"
LENGTH_MS="${2:-45000}"
OUT="${OUT_FILE:-$RUN_DIR/music-bed.mp3}"

body=$(jq -n --arg p "$PROMPT" --argjson L "$LENGTH_MS" '{prompt:$p, music_length_ms:$L}')
curl -sS -X POST "https://api.elevenlabs.io/v1/music/compose" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$body" -o "$OUT" \
  -w "HTTP %{http_code} | %{size_download} bytes\n"

ffprobe -v error -show_entries format=duration "$OUT"
echo "wrote $OUT"
