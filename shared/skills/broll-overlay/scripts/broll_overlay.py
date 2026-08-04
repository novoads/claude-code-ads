#!/usr/bin/env python3
"""Deterministic b-roll overlay assembly.

Lays silent cutaway clips OVER a base video: the base audio runs untouched
underneath while the picture cuts away and returns. The final duration always
equals the base duration — that is the contract that separates overlay from
concatenation (see EVALS.md OV1).

Usage:
  python3 broll_overlay.py edl.json              validate + render + verify
  python3 broll_overlay.py edl.json --dry-run    validate only, print the plan
  python3 broll_overlay.py --verify-only FINAL --base BASE
                                                 re-check an existing output

EDL JSON:
  {
    "base": "base.mp4",
    "output": "final.mp4",
    "overlays": [
      {"file": "broll-stir.mp4", "start": 3.2, "end": 5.7,
       "covers": "\"just mix it in\" — hands stirring"}
    ]
  }
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

# |duration(final) - duration(base)| tolerance, seconds. ~1.5 frames at 30fps:
# absorbs x264 frame rounding on the re-encoded video track, nothing else.
DURATION_TOLERANCE = 0.05

# Slack when comparing a clip's probed duration to its window, seconds.
# Covers ffprobe container rounding only — a genuinely short clip still fails.
PROBE_SLACK = 0.05

EXIT_VALIDATION = 2
EXIT_RENDER = 3
EXIT_VERIFY = 4


def die(code, *lines):
    for l in lines:
        print(f"ERROR: {l}", file=sys.stderr)
    sys.exit(code)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def ffprobe_json(path, *args):
    r = run(["ffprobe", "-v", "error", "-of", "json", *args, str(path)])
    if r.returncode != 0:
        die(EXIT_VALIDATION, f"ffprobe failed on {path}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def probe_duration(path):
    data = ffprobe_json(path, "-show_entries", "format=duration")
    try:
        return float(data["format"]["duration"])
    except (KeyError, ValueError):
        die(EXIT_VALIDATION, f"{path}: could not read duration")


def probe_video_stream(path):
    data = ffprobe_json(
        path, "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,codec_name",
    )
    streams = data.get("streams") or []
    return streams[0] if streams else None


def probe_audio_stream(path):
    data = ffprobe_json(
        path, "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,sample_rate,channels",
    )
    streams = data.get("streams") or []
    return streams[0] if streams else None


def audio_packet_md5(path):
    """MD5 over the audio stream's packets (no decode). Stream-copied audio
    survives a remux byte-identical, so base and output must match exactly."""
    r = run(["ffmpeg", "-v", "error", "-i", str(path),
             "-map", "0:a:0", "-c", "copy", "-f", "md5", "-"])
    if r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        if line.startswith("MD5="):
            return line.strip()
    return None


def load_edl(path):
    try:
        edl = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        die(EXIT_VALIDATION, f"cannot read EDL {path}: {e}")
    errors = []
    if not isinstance(edl.get("base"), str):
        errors.append('EDL needs "base": path to the base video')
    if not isinstance(edl.get("output"), str):
        errors.append('EDL needs "output": path for the final video')
    ovs = edl.get("overlays")
    if not isinstance(ovs, list) or not ovs:
        errors.append('EDL needs a non-empty "overlays" list')
        ovs = []
    for i, ov in enumerate(ovs):
        for key in ("file", "start", "end"):
            if key not in ov:
                errors.append(f'overlays[{i}] is missing "{key}"')
    if errors:
        die(EXIT_VALIDATION, *errors)
    return edl


def validate(edl):
    """Full geometric validation before any rendering. Collects every error so
    one bad EDL costs exactly one round-trip (EVALS.md OV4)."""
    errors = []
    base = Path(edl["base"])
    out = Path(edl["output"])
    if not base.is_file():
        die(EXIT_VALIDATION, f"base not found: {base}")
    if base.resolve() == out.resolve():
        die(EXIT_VALIDATION, "output must not overwrite the base")
    if probe_video_stream(base) is None:
        die(EXIT_VALIDATION, f"base has no video stream: {base}")
    if probe_audio_stream(base) is None:
        die(EXIT_VALIDATION, f"base has no audio stream: {base} — "
            "the overlay contract is picture-over-running-voice; "
            "a silent base needs no overlay skill")

    base_dur = probe_duration(base)
    windows = []
    for i, ov in enumerate(edl["overlays"]):
        f = Path(ov["file"])
        tag = f"overlays[{i}] ({f.name})"
        try:
            start, end = float(ov["start"]), float(ov["end"])
        except (TypeError, ValueError):
            errors.append(f"{tag}: start/end must be numbers")
            continue
        if not f.is_file():
            errors.append(f"{tag}: file not found")
            continue
        if probe_video_stream(f) is None:
            errors.append(f"{tag}: no video stream")
            continue
        if end <= start:
            errors.append(f"{tag}: end ({end}) must be after start ({start})")
            continue
        if start < 0 or end > base_dur + PROBE_SLACK:
            errors.append(
                f"{tag}: window [{start}, {end}] outside base [0, {base_dur:.2f}]")
            continue
        clip_dur = probe_duration(f)
        win = end - start
        if clip_dur + PROBE_SLACK < win:
            errors.append(
                f"{tag}: clip is {clip_dur:.2f}s, window needs {win:.2f}s — "
                "shorten the window or regenerate a longer clip (never looped: "
                "looped b-roll reads as broken)")
            continue
        windows.append((start, end, i))

    windows.sort()
    for (s1, e1, i1), (s2, e2, i2) in zip(windows, windows[1:]):
        if s2 < e1:
            errors.append(
                f"overlays[{i1}] [{s1}, {e1}] overlaps overlays[{i2}] [{s2}, {e2}]")

    if errors:
        die(EXIT_VALIDATION, *errors)
    return base_dur


def build_command(edl):
    base = edl["base"]
    v = probe_video_stream(base)
    w, h, fps = v["width"], v["height"], v["r_frame_rate"]

    inputs = ["-i", base]
    filters = []
    prev = "0:v"
    for i, ov in enumerate(edl["overlays"]):
        inputs += ["-i", ov["file"]]
        start, end = float(ov["start"]), float(ov["end"])
        win = end - start
        # trim to the window, conform to base geometry and clock, then shift so
        # the clip's own t=0 lands at the window start. fps=base aligns frame
        # timestamps to the base clock so windows cut on base frame boundaries.
        filters.append(
            f"[{i + 1}:v]trim=duration={win:.3f},"
            f"scale={w}:{h}:force_original_aspect_ratio=decrease,"
            f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps={fps},"
            f"setpts=PTS-STARTPTS+{start:.3f}/TB[ov{i}]")
        label = f"v{i}"
        filters.append(
            f"[{prev}][ov{i}]overlay=eof_action=pass:"
            f"enable='between(t,{start:.3f},{end:.3f})'[{label}]")
        prev = label

    # -c:a copy is the OV2 contract: the base audio stream is never re-encoded.
    # crf 18 = x264's visually transparent point; the base picture is re-encoded
    # exactly once, at assembly.
    return ["ffmpeg", "-y", *inputs,
            "-filter_complex", ";".join(filters),
            "-map", f"[{prev}]", "-map", "0:a:0",
            "-c:v", "libx264", "-preset", "medium", "-crf", "18",
            "-pix_fmt", "yuv420p", "-c:a", "copy",
            "-movflags", "+faststart", edl["output"]]


def verify(base, output):
    """Loud, measured verification (EVALS.md OV1/OV2/OV5). Returns error list."""
    problems = []
    if not Path(output).is_file():
        return [f"output not found: {output}"]
    base_dur, out_dur = probe_duration(base), probe_duration(output)
    delta = abs(out_dur - base_dur)
    if delta > DURATION_TOLERANCE:
        problems.append(
            f"duration drift: base {base_dur:.3f}s vs output {out_dur:.3f}s "
            f"(|Δ|={delta:.3f}s > {DURATION_TOLERANCE}s) — overlay must not "
            "change duration; this smells like concatenation")
    b_md5, o_md5 = audio_packet_md5(base), audio_packet_md5(output)
    if b_md5 is None or o_md5 is None:
        problems.append("could not hash an audio stream "
                        f"(base: {b_md5}, output: {o_md5})")
    elif b_md5 != o_md5:
        ba, oa = probe_audio_stream(base), probe_audio_stream(output)
        problems.append(
            f"audio stream differs from base: {b_md5} vs {o_md5} "
            f"(base {ba}, output {oa}) — audio must be stream-copied, untouched")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("edl", nargs="?", help="EDL JSON file")
    ap.add_argument("--dry-run", action="store_true",
                    help="validate and print the plan; render nothing")
    ap.add_argument("--verify-only", metavar="FINAL",
                    help="verify an existing output (requires --base)")
    ap.add_argument("--base", help="base video for --verify-only")
    args = ap.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            die(EXIT_VALIDATION, f"{tool} not on PATH — brew install ffmpeg")

    if args.verify_only:
        if not args.base:
            die(EXIT_VALIDATION, "--verify-only requires --base")
        problems = verify(args.base, args.verify_only)
        if problems:
            die(EXIT_VERIFY, *problems)
        print(f"VERIFY PASS: {args.verify_only} matches {args.base} "
              f"(duration within {DURATION_TOLERANCE}s, audio stream identical)")
        return

    if not args.edl:
        ap.error("an EDL file is required (or use --verify-only)")

    edl = load_edl(args.edl)
    base_dur = validate(edl)
    cmd = build_command(edl)

    print(f"base: {edl['base']} ({base_dur:.2f}s), "
          f"{len(edl['overlays'])} overlay window(s):")
    for ov in edl["overlays"]:
        covers = f"  — {ov['covers']}" if ov.get("covers") else ""
        print(f"  [{float(ov['start']):6.2f} → {float(ov['end']):6.2f}] "
              f"{ov['file']}{covers}")

    if args.dry_run:
        print("\nDRY RUN — command that would run:")
        print("  " + " ".join(str(c) for c in cmd))
        return

    r = run(cmd)
    if r.returncode != 0:
        die(EXIT_RENDER, f"ffmpeg failed:\n{r.stderr[-2000:]}")

    problems = verify(edl["base"], edl["output"])
    if problems:
        die(EXIT_VERIFY, *problems,
            f"the bad output was kept for inspection: {edl['output']}")
    print(f"OK: {edl['output']} — duration matches base within "
          f"{DURATION_TOLERANCE}s, audio stream identical to base")


if __name__ == "__main__":
    main()
