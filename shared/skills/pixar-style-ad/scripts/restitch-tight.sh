#!/bin/bash
# Trim and concat Seedance clips with audio preserved, removing dead air so the
# VO lands flush on each cut. See the "no dead space" SOP in the guide.
#
# Reads jobs from STDIN:
#   <local-source-mp4>::<output-name>::<duration-seconds>::<start-offset-seconds>
#
# Source paths resolve against $RUN_DIR/clips/.
#
# Example:
#   cat <<EOF | ./restitch-tight.sh
#   pain-cpm-v1.mp4::pain-cpm.mp4::3.5::0
#   pain-capcut-v3.mp4::pain-capcut.mp4::3.5::0.5
#   brent-reveal-v2.mp4::brent-reveal.mp4::6.7::0
#   EOF
#
# Produces $RUN_DIR/tight-cut.mp4
set -euo pipefail

CLIPS_DIR="${CLIPS_DIR:-$RUN_DIR/clips}"
TRIMMED="$RUN_DIR/clips-trimmed"
mkdir -p "$TRIMMED"

JOBS=()
while IFS=$'\n' read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  JOBS+=("$line")
done

for entry in "${JOBS[@]}"; do
  src="${entry%%::*}"; rest="${entry#*::}"
  out="${rest%%::*}"; rest="${rest#*::}"
  dur="${rest%%::*}"; rest="${rest#*::}"
  ss="${rest%%::*}"
  echo "[$out] dur=${dur}s ss=${ss}s  <- $src"
  ffmpeg -y -ss "$ss" -i "$CLIPS_DIR/$src" -t "$dur" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 44100 \
    -loglevel error "$TRIMMED/$out"
done

LIST="$TRIMMED/list.txt"
: > "$LIST"
for entry in "${JOBS[@]}"; do
  out="${entry#*::}"; out="${out%%::*}"
  echo "file '$TRIMMED/$out'" >> "$LIST"
done

OUT="$RUN_DIR/tight-cut.mp4"
ffmpeg -y -f concat -safe 0 -i "$LIST" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ar 44100 \
  -movflags +faststart \
  -loglevel error "$OUT"

ffprobe -v error -show_entries format=duration "$OUT"
echo "wrote $OUT"
