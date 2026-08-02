#!/bin/bash
# Final ffmpeg mix:
#   video (tight-cut.mp4 with original Seedance audio)
#   + N per-beat ElevenLabs VOs, each adelayed to its visual cut
#   + 1 music bed (low)
#   + Seedance original audio (preserved as SFX texture)
#   + caption PNG overlays driven by schedule.tsv
#
# Audio mix balance:
#   VO          100%   (primary)
#   Seedance     28%   (SFX texture — coin chings, droplets, pings, etc.)
#   Music        10%   (subtle bed)
#
# Requires env: RUN_DIR
#
# Per-run customization needed:
# 1) Edit the VO_FILES array (one entry per beat, ordered).
# 2) Edit the VO_OFFSETS_MS array (start-time in ms for each VO at its cut).
# 3) Verify VIDEO and MUSIC paths.
set -euo pipefail

cd "$RUN_DIR"

VIDEO="${VIDEO:-tight-cut.mp4}"
MUSIC="${MUSIC:-music-bed.mp3}"
OUT="${OUT:-FINAL.mp4}"

# Per-beat VO files (ordered) and their start offsets (ms).
# EDIT THESE TO MATCH YOUR CAMPAIGN'S BEAT STRUCTURE.
VO_FILES=(
  "vo-beats/b1-intro.mp3"
  "vo-beats/b1-cpm.mp3"
  "vo-beats/b1-dead.mp3"
  "vo-beats/b1-slack.mp3"
  "vo-beats/b1-capcut.mp3"
  "vo-beats/b2.mp3"
  "vo-beats/b3.mp3"
  "vo-beats/b4.mp3"
)
VO_OFFSETS_MS=(200 1700 3700 6200 8900 12500 19200 28800)

# --- Build cap inputs and filter chain ---
CAP_INPUTS=()
CAP_FILTER=""
i=0
N_VOS=${#VO_FILES[@]}
# Input indices:
#   0           = video (provides video + Seedance audio)
#   1..N_VOS    = VO mp3 files
#   N_VOS+1     = music
#   N_VOS+2..   = caption PNGs
MUSIC_IDX=$((N_VOS + 1))
PNG_IDX_START=$((N_VOS + 2))

PREV="[0:v]"
while IFS=$'\t' read -r png start end style; do
  CAP_INPUTS+=("-i" "$png")
  IDX=$((PNG_IDX_START + i))
  CUR="[bg$i]"
  SEP=";"; [ $i -eq 0 ] && SEP=""
  CAP_FILTER+="${SEP}${PREV}[${IDX}:v]overlay=enable='between(t,${start},${end})':x=0:y=0${CUR}"
  PREV="${CUR}"
  i=$((i+1))
done < captions-png/schedule.tsv
CAP_FILTER+=";${PREV}copy[v]"

# Build VO mix filter
VO_FILTER=""
VO_LABELS=""
for j in "${!VO_FILES[@]}"; do
  off=${VO_OFFSETS_MS[$j]}
  in_idx=$((j + 1))
  VO_FILTER+="[${in_idx}:a]adelay=${off}|${off},volume=1.0[av${j}];"
  VO_LABELS+="[av${j}]"
done
VO_FILTER+="${VO_LABELS}amix=inputs=${N_VOS}:duration=longest:dropout_transition=0:normalize=0[vo];"

# Build VO_INPUT args
VO_INPUT_ARGS=()
for f in "${VO_FILES[@]}"; do
  VO_INPUT_ARGS+=("-i" "$f")
done

echo "=== Inputs: 1 video + $N_VOS VOs + 1 music + $i caption PNGs ==="

ffmpeg -y \
  -i "$VIDEO" \
  "${VO_INPUT_ARGS[@]}" \
  -i "$MUSIC" \
  "${CAP_INPUTS[@]}" \
  -filter_complex "
    ${VO_FILTER}
    [0:a]volume=0.28[sfx];
    [${MUSIC_IDX}:a]volume=0.10[music];
    [vo][sfx][music]amix=inputs=3:duration=longest:dropout_transition=0:normalize=0[mix];
    $CAP_FILTER
  " \
  -map "[v]" -map "[mix]" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ar 44100 \
  -movflags +faststart \
  -shortest \
  "$OUT" 2>&1 | tail -5

echo "=== Done ==="
ls -la "$OUT"
ffprobe -v error -show_entries format=duration "$OUT"
