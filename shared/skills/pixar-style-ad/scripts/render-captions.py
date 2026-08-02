#!/usr/bin/env python3
"""Render TikTok-style caption PNGs (one per caption) sized to the video frame
and emit a schedule.tsv that ffmpeg can drive overlay timing from.

Why PNGs instead of subtitles=...ass: Homebrew ffmpeg ships without libass and
drawtext (no compiled-in dependencies), so we sidestep them entirely with
Pillow-rendered transparent PNGs that ffmpeg composites via the overlay filter.

Edit the CAPTIONS list below to match your VO line-for-line. Each tuple is:
    (start_s, end_s, text_lines, style, position)

style:    'normal' | 'cta' | 'url'
position: 'bottom'      — lower-third (default; use when character is upper)
          'top'         — upper-third (use when character fills lower frame)
          'bottom-low'  — very bottom edge (URL ticker; below character body)
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# --- Config ---
OUT_DIR = Path(os.environ.get("RUN_DIR", ".")) / "captions-png"
OUT_DIR.mkdir(parents=True, exist_ok=True)

FRAME_W, FRAME_H = 720, 1280
FONT_PATH = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_BOLD_INDEX = 1   # Helvetica Neue Bold

STYLES = {
    "normal": {"size": 56, "fill": (255, 255, 255), "stroke": (0, 0, 0), "stroke_w": 5},
    "cta":    {"size": 64, "fill": (90, 230, 130), "stroke": (0, 0, 0), "stroke_w": 6},
    "url":    {"size": 60, "fill": (255, 255, 255), "stroke": (0, 0, 0), "stroke_w": 6},
}
MARGIN_BOTTOM = 280       # px from bottom for 'bottom'
MARGIN_BOTTOM_LOW = 90    # px from bottom for 'bottom-low' (tight to edge)
MARGIN_TOP = 90           # px from top for 'top'

# --- Caption schedule (EDIT THIS PER CAMPAIGN) ---
# Times sync to per-clip VO start offsets in your final-assembly.sh.
CAPTIONS = [
    # Replace with your real captions. Each line should match the VO verbatim.
    (0.20, 1.70, ["Listen,", "media buyer..."], "normal", "bottom"),
    (1.70, 3.70, ["Your CPMs", "keep climbing..."], "normal", "bottom"),
    (3.70, 5.80, ["Your creatives", "keep dying..."], "normal", "bottom"),
    (6.20, 8.60, ["Your client keeps", "screaming for", "new ads..."], "normal", "top"),
    (8.90, 11.80, ["And your CapCut", "timeline is begging", "for mercy."], "normal", "top"),
    (12.50, 14.00, ["You need", "to see this."], "normal", "top"),
    (14.00, 16.40, ["People are making", "Pixar ads with AI now."], "normal", "top"),
    (16.40, 18.30, ["Inside one online", "community."], "normal", "top"),
    (19.20, 22.50, ["They literally taught me", "to make this exact ad."], "normal", "top"),
    (22.50, 24.80, ["Yeah. The one you're", "watching right now."], "normal", "top"),
    (24.80, 27.90, ["AI made it. 30 minutes.", "Start to finish."], "normal", "top"),
    (28.80, 29.80, ["Join us at..."], "cta", "bottom-low"),
    (29.80, 32.10, ["yourbrand.com"], "url", "bottom-low"),
    (32.10, 34.20, ["And stop making ads", "that make you cry."], "normal", "bottom-low"),
]


def make_font(size, bold=True):
    return ImageFont.truetype(FONT_PATH, size=size, index=FONT_BOLD_INDEX if bold else 0)


def render_caption(text_lines, style_name, position, out_path):
    style = STYLES[style_name]
    font = make_font(style["size"], bold=True)
    img = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    line_h = int(style["size"] * 1.15)
    total_h = line_h * len(text_lines)

    if position == "top":
        y0 = MARGIN_TOP
    elif position == "bottom-low":
        y0 = FRAME_H - MARGIN_BOTTOM_LOW - total_h
    else:
        y0 = FRAME_H - MARGIN_BOTTOM - total_h

    for i, line in enumerate(text_lines):
        bbox = draw.textbbox((0, 0), line, font=font, stroke_width=style["stroke_w"])
        w = bbox[2] - bbox[0]
        x = (FRAME_W - w) // 2
        y = y0 + i * line_h
        draw.text((x, y), line, font=font, fill=style["fill"],
                  stroke_width=style["stroke_w"], stroke_fill=style["stroke"])

    img.save(out_path)


schedule_lines = []
for idx, (start, end, lines, style, pos) in enumerate(CAPTIONS):
    out = OUT_DIR / f"cap-{idx:02d}.png"
    render_caption(lines, style, pos, out)
    schedule_lines.append(f"{out}\t{start:.2f}\t{end:.2f}\t{style}")
    print(f"[cap-{idx:02d}] {start:>6.2f}-{end:<6.2f} ({style:6}, {pos:11}) {lines}")

(OUT_DIR / "schedule.tsv").write_text("\n".join(schedule_lines) + "\n")
print(f"\nWrote {len(CAPTIONS)} caption PNGs + schedule to {OUT_DIR}")
