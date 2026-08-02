#!/bin/bash
# Generate per-beat ElevenLabs VO clips. ONE call per visual beat so timing
# can snap precisely to each cut (see the "no dead space" SOP in the guide).
#
# Reads jobs from STDIN:
#   <slot>::<text>
#
# Writes mp3s to $RUN_DIR/vo-beats/<slot>.mp3 and reports duration.
#
# Notes:
# - Spell acronyms with periods: "A.I." reads as fluid letters; "A I" reads as
#   two separated letters with a noticeable gap.
# - Default voice is Brian (warm conversational American male, ~30s).
#   Override with ELEVENLABS_VOICE_ID for a different voice.
set -euo pipefail

set -a; source "${ENV_FILE:-$RUN_DIR/.env}" 2>/dev/null || source "$(git rev-parse --show-toplevel 2>/dev/null)/workspace/.env"; set +a

VOICE_ID="${ELEVENLABS_VOICE_ID:-nPczCjzI2devNBz1zQrb}"   # Brian
MODEL="${ELEVENLABS_MODEL:-eleven_multilingual_v2}"
OUT="$RUN_DIR/vo-beats"
mkdir -p "$OUT"

while IFS=$'\n' read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  slot="${line%%::*}"
  text="${line#*::}"
  body=$(jq -n --arg t "$text" --arg m "$MODEL" \
    '{text:$t, model_id:$m, voice_settings:{stability:0.5, similarity_boost:0.78, style:0.6, use_speaker_boost:true}}')
  curl -sS -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID?output_format=mp3_44100_128" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$body" -o "$OUT/$slot.mp3"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$slot.mp3")
  echo "[$slot] ${dur}s — $text"
done
