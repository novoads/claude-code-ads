#!/usr/bin/env python3
"""Deterministic b-roll overlay assembly.

Lays silent cutaway clips OVER a base video: the base audio runs untouched
underneath while the picture cuts away and returns. The final duration always
equals the base duration — that is the contract that separates overlay from
concatenation (see evals.md OV1).

Usage:
  python3 broll_overlay.py edl.json              validate + render + verify
  python3 broll_overlay.py edl.json --dry-run    validate only, print the plan
  python3 broll_overlay.py edl.json --stats      validate, print cadence stats
  python3 broll_overlay.py --verify-only FINAL --base BASE [--edl EDL]
                                                 re-check an existing output;
                                                 --edl enables the per-window
                                                 content check

EDL JSON:
  {
    "base": "base.mp4",
    "output": "final.mp4",
    "overlays": [
      {"file": "broll-stir.mp4", "start": 3.2, "end": 5.7,
       "covers": "\"just mix it in\" — hands stirring"}
    ]
  }

The base must carry exactly one audio stream: the contract is a single voice
track stream-copied under the picture (`-map 0:a:0`), so a second stream would
be dropped silently. Mix or select one first.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

# |duration(final) - duration(base)| tolerance, seconds. ~1.5 frames at 30fps:
# absorbs x264 frame rounding on the re-encoded video track, nothing else.
DURATION_TOLERANCE = 0.05

# Slack when comparing a clip's probed duration to the window it must fill,
# seconds. Covers ffprobe container rounding only — a genuinely short clip
# still fails.
CLIP_DURATION_SLACK = 0.05

# Slack when comparing a window's end to the base's VIDEO-stream duration,
# seconds. Same rounding argument, different comparison: this one decides
# whether a window would fall off the end of the picture.
BASE_BOUNDS_SLACK = 0.05

# Content check (verify): each window's midpoint frame is sampled from the
# output and from the base and area-averaged to a small RGB grid. A window that
# composited nothing leaves the two frames identical.
CONTENT_SAMPLE_GRID = 16     # NxN RGB thumbnail — encoder noise averages out
CONTENT_DIFF_MIN_MAD = 6.0   # mean |Δ| per channel byte (0-255) that counts as
                             # "a different picture". A re-encode of the same
                             # frame lands near 1-3; a cutaway lands far above.

# Subprocess timeouts, seconds. A hung ffmpeg/ffprobe must fail the run, not
# park it forever. Probes read headers (sub-second in practice; 60s is pure
# headroom for a cold network mount). A render is O(base duration) x2 for
# decode+x264 at preset medium; 600s covers minutes-long bases with margin.
PROBE_TIMEOUT_S = 60
RENDER_TIMEOUT_S = 600

# Encoder settings. crf 18 = x264's visually transparent point; the base
# picture is re-encoded exactly once, at assembly.
VIDEO_CODEC = "libx264"
X264_PRESET = "medium"
X264_CRF = "18"
PIX_FMT = "yuv420p"

# How much of a failed ffmpeg's stderr to quote back — enough for the real
# error line, not the whole banner.
FFMPEG_STDERR_TAIL_CHARS = 2000

# --- Reference cadence envelope -------------------------------------------
# Source: frame-by-frame measurement of the one reference edit this pack
# reproduces (walkthrough at youtu.be/HHGQN9Zqaxo t=2438), taken 2026-08-04.
# That edit: ~15.5s, 10-11 shots, a cut every ~1.4s, 5 cutaways of ~1-1.5s
# each, ~40-45% b-roll coverage, strict A-B-A-B alternation. n=1, contrasted
# against our own two renders (2 windows of 2.5s/2.0s, ~30% coverage).
# These numbers are INFORMATIONAL: cadence is judgment, and deviation never
# changes the exit code (evals.md OV3/OV6).
REF_BASE_SECONDS = 15.0        # the reference ad's runtime, the scaling unit
REF_WINDOWS_MIN = 4            # cutaways per REF_BASE_SECONDS, low end
REF_WINDOWS_MAX = 6            # cutaways per REF_BASE_SECONDS, high end
REF_WINDOW_MAX_SECONDS = 2.0   # reference windows ran ~1-1.5s; 2.0s is the cap
REF_COVERAGE_MIN_PCT = 35.0    # reference coverage was ~40-45%
REF_COVERAGE_MAX_PCT = 50.0
# Float-comparison epsilon so a window computed as 1.9999999999999998 counts
# as 2.0. Not a tolerance on the envelope itself.
EPS = 1e-6

EXIT_VALIDATION = 2
EXIT_RENDER = 3
EXIT_VERIFY = 4


def die(code, *lines):
    for l in lines:
        print(f"ERROR: {l}", file=sys.stderr)
    sys.exit(code)


def run(cmd, timeout=PROBE_TIMEOUT_S, code=EXIT_VALIDATION, what="command",
        binary=False):
    """Run a subprocess under a timeout.

    code=None means "soft": a timeout returns None instead of exiting, so the
    caller can fold the failure into its own collected errors."""
    try:
        return subprocess.run([str(c) for c in cmd], capture_output=True,
                              text=not binary, timeout=timeout)
    except subprocess.TimeoutExpired:
        if code is None:
            return None
        die(code, f"{what} timed out after {timeout}s — aborted")


def file_arg(path):
    """Force the file protocol. Without this a local file literally named
    'http:clip.mp4' is opened as a URL, and ffmpeg goes to the network."""
    return f"file:{path}"


def ffprobe_json(path, *args, code=EXIT_VALIDATION):
    """Parsed ffprobe JSON. code=None returns None instead of exiting."""
    r = run(["ffprobe", "-v", "error", "-of", "json", *args, file_arg(path)],
            timeout=PROBE_TIMEOUT_S, code=code, what=f"ffprobe on {path}")
    if r is None or r.returncode != 0:
        if code is None:
            return None
        die(code, f"ffprobe failed on {path}: {(r.stderr or '').strip()}")
    try:
        return json.loads(r.stdout)
    except (json.JSONDecodeError, TypeError):
        if code is None:
            return None
        die(code, f"{path}: ffprobe returned nothing parsable "
                  "(empty or truncated file?)")


def probe_duration(path, code=EXIT_VALIDATION):
    data = ffprobe_json(path, "-show_entries", "format=duration", code=code)
    if data is None:
        return None
    try:
        return float(data["format"]["duration"])
    except (KeyError, TypeError, ValueError):
        if code is None:
            return None
        die(code, f"{path}: could not read duration")


def probe_streams(path, select, entries, code=EXIT_VALIDATION):
    """The selected streams as a list of dicts. None only on probe failure."""
    data = ffprobe_json(path, "-select_streams", select,
                        "-show_entries", f"stream={entries}", code=code)
    if data is None:
        return None
    return data.get("streams") or []


def probe_clip(path):
    """One soft probe per overlay clip: does it have a picture, how long is it.

    Returns None when the file cannot be read at all — the caller reports that
    as one collected error instead of aborting the whole validation pass."""
    data = ffprobe_json(path, "-show_entries",
                        "stream=codec_type:format=duration", code=None)
    if data is None:
        return None
    streams = data.get("streams") or []
    try:
        duration = float((data.get("format") or {}).get("duration"))
    except (TypeError, ValueError):
        duration = None
    return {
        "has_video": any(s.get("codec_type") == "video" for s in streams),
        "duration": duration,
    }


def parse_rate(value):
    """'30000/1001' -> 29.97. None for 0/0, garbage, or a missing entry."""
    try:
        num, den = str(value).split("/")
        num, den = float(num), float(den)
    except (ValueError, AttributeError):
        return None
    if den <= 0 or num <= 0:
        return None
    rate = num / den
    return rate if math.isfinite(rate) else None


def base_frame_rate(video_stream):
    """(fps as a float, fps as ffmpeg's own rational string) for the base.

    avg_frame_rate first: r_frame_rate is the container *tick* rate and reads
    600/1 on VFR phone captures, which would make the fps filter synthesize 20x
    the frames. Both may be absent or 0/0 — then there is no fps to conform to
    and the caller omits the filter."""
    v = video_stream or {}
    for key in ("avg_frame_rate", "r_frame_rate"):
        rate = parse_rate(v.get(key))
        if rate:
            return rate, str(v.get(key))
    return None, None


def audio_packet_md5(path):
    """MD5 over the audio stream's packets (no decode). Stream-copied audio
    survives a remux byte-identical, so base and output must match exactly."""
    r = run(["ffmpeg", "-v", "error", "-i", file_arg(path),
             "-map", "0:a:0", "-c", "copy", "-f", "md5", "-"],
            timeout=PROBE_TIMEOUT_S, code=None, what=f"audio hash of {path}")
    if r is None or r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        if line.startswith("MD5="):
            return line.strip()
    return None


def sample_frame(path, t):
    """One frame at t, area-averaged to a CONTENT_SAMPLE_GRID square of RGB.

    Small enough that encoder noise averages away, large enough that a cutaway
    cannot hide inside it. Returns bytes, or None if the frame is unreadable."""
    want = CONTENT_SAMPLE_GRID * CONTENT_SAMPLE_GRID * 3
    r = run(["ffmpeg", "-v", "error", "-ss", f"{max(t, 0.0):.3f}",
             "-i", file_arg(path), "-frames:v", "1",
             "-vf", f"scale={CONTENT_SAMPLE_GRID}:{CONTENT_SAMPLE_GRID}:flags=area",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            timeout=PROBE_TIMEOUT_S, code=None, what=f"frame sample of {path}",
            binary=True)
    if r is None or r.returncode != 0 or len(r.stdout) < want:
        return None
    return r.stdout[:want]


def mean_abs_diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / float(len(a))


def strict_number(value):
    """A time in seconds, or None.

    json.loads happily returns NaN/Infinity for bare NaN/Infinity tokens, and
    booleans are ints in Python — both would slide through every ordering
    comparison below and reach the renderer."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    v = float(value)
    return v if math.isfinite(v) else None


def load_edl(path):
    """Read and structurally validate the EDL. Every shape error at once."""
    try:
        raw = Path(path).read_text()
    except OSError as e:
        die(EXIT_VALIDATION, f"cannot read EDL {path}: {e}")
    try:
        edl = json.loads(raw)
    except json.JSONDecodeError as e:
        die(EXIT_VALIDATION, f"cannot read EDL {path}: {e}")
    if not isinstance(edl, dict):
        die(EXIT_VALIDATION,
            f"EDL must be a JSON object, got {type(edl).__name__}")

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
        if not isinstance(ov, dict):
            errors.append(f"overlays[{i}] must be a JSON object with "
                          f'"file"/"start"/"end"/"covers", got '
                          f"{type(ov).__name__}")
            continue
        for key in ("file", "start", "end", "covers"):
            if key not in ov:
                errors.append(f'overlays[{i}] is missing "{key}"')
        covers = ov.get("covers")
        if "covers" in ov and not (isinstance(covers, str) and covers.strip()):
            errors.append(f'overlays[{i}] "covers" must be a non-empty string: '
                          "the one-line rationale quoting the spoken line this "
                          "window illustrates (evals.md OV3)")
    if errors:
        die(EXIT_VALIDATION, *errors)
    return edl


def edl_windows(edl):
    """[(start, end, index)] for a structurally valid EDL, plus any number
    errors. Shared by validation and by --verify-only --edl."""
    windows, errors = [], []
    for i, ov in enumerate(edl["overlays"]):
        start, end = strict_number(ov.get("start")), strict_number(ov.get("end"))
        if start is None or end is None:
            errors.append(
                f"overlays[{i}]: start/end must be finite numbers "
                f"(got start={ov.get('start')!r}, end={ov.get('end')!r})")
            continue
        windows.append((start, end, i))
    return windows, errors


def check_output_path(edl, errors):
    """The output must not be an option, a missing directory, or any input.

    samefile catches hardlinks and symlinks; the normcase comparison catches a
    case variant on a case-insensitive filesystem (APFS, NTFS) where the output
    does not exist yet and samefile has nothing to compare."""
    out_raw = edl["output"]
    if out_raw.startswith("-"):
        errors.append(f'output "{out_raw}" starts with "-" — ffmpeg would parse '
                      f'it as an option; use "./{out_raw}"')
        return
    out = Path(out_raw)
    if not out.parent.is_dir():
        errors.append(f"output directory does not exist: {out.parent} "
                      "(create it first; the render writes a temp file there)")

    inputs = [("base", edl["base"])]
    for i, ov in enumerate(edl["overlays"]):
        if isinstance(ov.get("file"), str):
            inputs.append((f"overlays[{i}]", ov["file"]))
    out_key = os.path.normcase(str(out.resolve()))
    for label, raw in inputs:
        src = Path(raw)
        same = os.path.normcase(str(src.resolve())) == out_key
        try:
            same = same or out.samefile(src)
        except OSError:
            pass  # output (or input) does not exist yet — normcase decides
        if same:
            errors.append(f"output must not overwrite an input: {out_raw} "
                          f"is the same file as {label} ({raw})")


def validate(edl):
    """Everything that can be checked before a frame is rendered, collected.

    No check aborts the pass: a missing file, an unreadable file, a bad number,
    a bad window and an overlap are all reported together, so one bad EDL costs
    exactly one round-trip (evals.md OV4). The only early exits are the EDL's
    own shape (load_edl) and a base with no picture or no voice — with either
    of those missing there is no overlay job left to describe.

    Returns (base_dur, base_video_dur, fps_expr, windows)."""
    errors = []
    check_output_path(edl, errors)

    base = Path(edl["base"])
    base_dur = base_video_dur = frame_period = None
    fps_expr = None
    if not base.is_file():
        errors.append(f"base not found: {base}")
    else:
        vstreams = probe_streams(
            base, "v:0", "width,height,avg_frame_rate,r_frame_rate,duration")
        if not vstreams:
            die(EXIT_VALIDATION, f"base has no video stream: {base}")
        astreams = probe_streams(base, "a", "index,codec_name")
        if not astreams:
            die(EXIT_VALIDATION, f"base has no audio stream: {base} — "
                "the overlay contract is picture-over-running-voice; "
                "a silent base needs no overlay skill")
        if len(astreams) > 1:
            errors.append(
                f"base has {len(astreams)} audio streams: {base} — this skill "
                "stream-copies exactly one voice track under the picture "
                "(-map 0:a:0), so the rest would be dropped silently and the "
                "verifier would still call the output identical. Mix or select "
                "one stream first: ffmpeg -i base -map 0:v -map 0:a:0 -c copy")

        v = vstreams[0]
        base_dur = probe_duration(base)
        # Window bounds are checked against the VIDEO stream, not the
        # container: a base whose audio runs longer than its picture would
        # otherwise accept windows that render zero overlay frames.
        try:
            base_video_dur = float(v.get("duration"))
        except (TypeError, ValueError):
            base_video_dur = base_dur
        fps, fps_expr = base_frame_rate(v)
        frame_period = 1.0 / fps if fps else None

    windows, number_errors = edl_windows(edl)
    errors.extend(number_errors)

    checked = []
    for start, end, i in windows:
        ov = edl["overlays"][i]
        raw = ov.get("file")
        if not isinstance(raw, str):
            errors.append(f'overlays[{i}]: "file" must be a path string, got '
                          f"{type(raw).__name__}")
            continue
        f = Path(raw)
        tag = f"overlays[{i}] ({f.name})"
        if not f.is_file():
            errors.append(f"{tag}: file not found")
            continue
        info = probe_clip(f)
        if info is None:
            errors.append(f"{tag}: unreadable media file — ffprobe could not "
                          "read a stream from it")
            continue
        if not info["has_video"]:
            errors.append(f"{tag}: no video stream")
            continue
        if end <= start:
            errors.append(f"{tag}: end ({end}) must be after start ({start})")
            continue
        win = end - start
        if frame_period is not None and win < frame_period - EPS:
            errors.append(
                f"{tag}: window [{start}, {end}] is {win:.4f}s, shorter than "
                f"one base frame ({frame_period:.4f}s) — it would composite "
                "zero frames and still verify clean")
            continue
        if base_video_dur is not None and (
                start < 0 or end > base_video_dur + BASE_BOUNDS_SLACK):
            errors.append(f"{tag}: window [{start}, {end}] outside base "
                          f"[0, {base_video_dur:.2f}]")
            continue
        if info["duration"] is None:
            errors.append(f"{tag}: could not read duration")
            continue
        if info["duration"] + CLIP_DURATION_SLACK < win:
            errors.append(
                f"{tag}: clip is {info['duration']:.2f}s, window needs "
                f"{win:.2f}s — shorten the window or regenerate a longer clip "
                "(never looped: looped b-roll reads as broken)")
            continue
        checked.append((start, end, i))

    # Running-max sweep, not an adjacent-pair scan: one long window overlapping
    # three later ones has to report all three, not just the first.
    checked.sort()
    run_s = run_e = run_i = None
    for start, end, i in checked:
        if run_e is not None and start < run_e:
            errors.append(f"overlays[{run_i}] [{run_s}, {run_e}] overlaps "
                          f"overlays[{i}] [{start}, {end}]")
        if run_e is None or end > run_e:
            run_s, run_e, run_i = start, end, i

    if errors:
        die(EXIT_VALIDATION, *errors)
    return base_dur, base_video_dur, fps_expr, checked


def scaled_window_bounds(base_dur):
    """The reference's 4-6 cutaways per 15s, scaled to this base's runtime."""
    scale = base_dur / REF_BASE_SECONDS
    lo = max(1, int(REF_WINDOWS_MIN * scale + 0.5))
    hi = max(lo, int(REF_WINDOWS_MAX * scale + 0.5))
    return lo, hi


def format_stats(edl, base_dur):
    """Cadence numbers for the EDL, each compared to the reference envelope.

    Informational only — this never influences an exit code. Style is judgment;
    the numbers exist so a departure is a decision instead of an accident."""
    wins = sorted((float(o["start"]), float(o["end"])) for o in edl["overlays"])
    lens = [e - s for s, e in wins]
    gaps = [nxt[0] - cur[1] for cur, nxt in zip(wins, wins[1:])]
    n = len(wins)
    total = sum(lens)
    pct = 100.0 * total / base_dur if base_dur else 0.0
    lo, hi = scaled_window_bounds(base_dur)

    def mark(ok, reference):
        return "within envelope" if ok else f"outside envelope (reference: {reference})"

    out = ["", f"cadence stats for a {base_dur:.2f}s base "
               "(informational — cadence is judgment, never an exit code):"]
    out.append(f"  cutaway windows:  {n}  —  " + mark(
        lo <= n <= hi,
        f"{lo}-{hi} for a {base_dur:.1f}s base; "
        f"{REF_WINDOWS_MIN}-{REF_WINDOWS_MAX} per {REF_BASE_SECONDS:.0f}s"))
    out.append(f"  window length:    min {min(lens):.2f}s  mean {total / n:.2f}s  "
               f"max {max(lens):.2f}s  —  " + mark(
                   max(lens) <= REF_WINDOW_MAX_SECONDS + EPS,
                   f"each window <= {REF_WINDOW_MAX_SECONDS:.1f}s; reference ran ~1-1.5s"))
    out.append(f"  coverage:         {total:.2f}s of {base_dur:.2f}s = {pct:.1f}%  —  "
               + mark(REF_COVERAGE_MIN_PCT - EPS <= pct <= REF_COVERAGE_MAX_PCT + EPS,
                      f"{REF_COVERAGE_MIN_PCT:.0f}-{REF_COVERAGE_MAX_PCT:.0f}%"))
    if gaps:
        out.append(f"  base returns:     {len(gaps)} gap(s), largest {max(gaps):.2f}s, "
                   f"smallest {min(gaps):.2f}s  —  " + mark(
                       min(gaps) > EPS,
                       "the face returns between every pair of windows (A-B-A-B)"))
    else:
        out.append("  base returns:     n/a — a single window has no gap to measure")
    out.append("  envelope source: frame-by-frame measurement of one reference edit, "
               "2026-08-04 (n=1).")
    out.append("  A strong default, not a law — depart deliberately and say why.")
    return out


def build_command(edl, fps_expr, dest):
    """The ffmpeg command, with every geometry decision left to the graph.

    Nothing here is computed from probed width/height: a phone capture carries
    its rotation in a display matrix (ffmpeg applies it on decode, so the coded
    720x1280 arrives as 1280x720) and an anamorphic capture carries it in the
    SAR. Both make probed numbers lie. Scaling each clip against the base
    branch itself — `scale=w=rw:h=rh` with the base as the reference input —
    reads the geometry ffmpeg actually has. A clip whose aspect ratio does not
    match is fitted inside the frame and centred, base visible around it."""
    n = len(edl["overlays"])
    inputs = ["-i", file_arg(edl["base"])]
    # One reference tap per overlay, plus the chain the overlays composite onto.
    filters = ["[0:v]split=%d[m]%s" % (n + 1, "".join(f"[r{i}]" for i in range(n)))]
    chain = "m"
    for i, ov in enumerate(edl["overlays"]):
        inputs += ["-i", file_arg(ov["file"])]
        start, end = float(ov["start"]), float(ov["end"])
        win = end - start
        # Trim to the window, conform to the base's geometry and clock, then
        # shift so the clip's own t=0 lands at the window start. fps= aligns
        # frame timestamps to the base clock so windows cut on base frames; it
        # is omitted when the base's frame rate is undeterminable.
        conform = f",fps={fps_expr}" if fps_expr else ""
        filters.append(f"[{i + 1}:v]trim=duration={win:.3f},"
                       f"setpts=PTS-STARTPTS[c{i}]")
        filters.append(f"[c{i}][r{i}]scale=w=rw:h=rh:"
                       f"force_original_aspect_ratio=decrease[f{i}]")
        filters.append(f"[f{i}]setsar=1{conform},"
                       f"setpts=PTS-STARTPTS+{start:.3f}/TB[ov{i}]")
        filters.append(
            f"[{chain}][ov{i}]overlay=x=(W-w)/2:y=(H-h)/2:eof_action=pass:"
            f"enable='between(t,{start:.3f},{end:.3f})'[v{i}]")
        chain = f"v{i}"

    # -c:a copy is the OV2 contract: the base audio stream is never re-encoded.
    return ["ffmpeg", "-y", *inputs,
            "-filter_complex", ";".join(filters),
            "-map", f"[{chain}]", "-map", "0:a:0",
            "-c:v", VIDEO_CODEC, "-preset", X264_PRESET, "-crf", X264_CRF,
            "-pix_fmt", PIX_FMT, "-c:a", "copy",
            "-movflags", "+faststart", file_arg(dest)]


def verify(base, output, windows=None):
    """Loud, measured verification (evals.md OV1/OV2/OV5). Returns error list.

    Duration and audio alone cannot tell a finished render from a copy of the
    base — both pass on a plain remux. With `windows`, each one's midpoint frame
    is compared against the base's frame at the same instant: a window that
    composited nothing is a window that never happened."""
    problems = []
    if not Path(output).is_file():
        return [f"output not found: {output}"]
    base_dur = probe_duration(base, code=EXIT_VERIFY)
    out_dur = probe_duration(output, code=EXIT_VERIFY)
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
        ba = probe_streams(base, "a:0", "codec_name,sample_rate,channels", code=None)
        oa = probe_streams(output, "a:0", "codec_name,sample_rate,channels", code=None)
        problems.append(
            f"audio stream differs from base: {b_md5} vs {o_md5} "
            f"(base {ba}, output {oa}) — audio must be stream-copied, untouched")

    for start, end, i in windows or []:
        t = (start + end) / 2.0
        b_frame, o_frame = sample_frame(base, t), sample_frame(output, t)
        if b_frame is None or o_frame is None:
            problems.append(
                f"overlays[{i}] [{start}, {end}]: could not sample the frame at "
                f"t={t:.2f}s from base or output for the content check")
            continue
        mad = mean_abs_diff(b_frame, o_frame)
        if mad < CONTENT_DIFF_MIN_MAD:
            problems.append(
                f"overlays[{i}] [{start}, {end}]: the output frame at "
                f"t={t:.2f}s still shows the base (mean pixel difference "
                f"{mad:.1f} < {CONTENT_DIFF_MIN_MAD}) — nothing was composited "
                "in this window")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("edl", nargs="?", help="EDL JSON file")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true",
                      help="validate and print the plan; render nothing")
    mode.add_argument("--stats", action="store_true",
                      help="validate and print the cadence stats; render nothing. "
                           "Informational: deviation from the reference envelope "
                           "never changes the exit code")
    ap.add_argument("--verify-only", metavar="FINAL",
                    help="verify an existing output (requires --base)")
    ap.add_argument("--base", help="base video for --verify-only")
    ap.add_argument("--edl", dest="verify_edl", metavar="EDL",
                    help="with --verify-only: the EDL that produced FINAL, "
                         "which enables the per-window content check")
    args = ap.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            die(EXIT_VALIDATION, f"{tool} not on PATH — brew install ffmpeg")

    if args.verify_edl and not args.verify_only:
        ap.error("--edl only applies to --verify-only; pass the EDL positionally "
                 "to render")

    if args.verify_only:
        if not args.base:
            die(EXIT_VALIDATION, "--verify-only requires --base")
        windows = None
        if args.verify_edl:
            windows, errors = edl_windows(load_edl(args.verify_edl))
            if errors:
                die(EXIT_VALIDATION, *errors)
        else:
            print("WARNING: content check skipped (no --edl) — duration and "
                  "audio only. A copy of the base passes both; pass "
                  "--edl edl.json to also prove each window composited.")
        problems = verify(args.base, args.verify_only, windows)
        if problems:
            die(EXIT_VERIFY, *problems)
        content = (f", {len(windows)} window(s) composited"
                   if windows else ", content check skipped")
        print(f"VERIFY PASS: {args.verify_only} matches {args.base} "
              f"(duration within {DURATION_TOLERANCE}s, audio stream "
              f"identical{content})")
        return

    if not args.edl:
        ap.error("an EDL file is required (or use --verify-only)")

    edl = load_edl(args.edl)
    base_dur, _base_video_dur, fps_expr, windows = validate(edl)
    dest = Path(edl["output"])

    print(f"base: {edl['base']} ({base_dur:.2f}s), "
          f"{len(edl['overlays'])} overlay window(s):")
    for ov in edl["overlays"]:
        print(f"  [{float(ov['start']):6.2f} → {float(ov['end']):6.2f}] "
              f"{ov['file']}  — {ov['covers']}")

    # Every run surfaces its own cadence, before anything renders.
    for line in format_stats(edl, base_dur):
        print(line)

    if args.stats:
        return

    if args.dry_run:
        print("\nDRY RUN — command that would run:")
        print("  " + " ".join(str(c) for c in
                              build_command(edl, fps_expr, dest)))
        print("  (a real run renders to a hidden temp file beside the output "
              "and renames it only after verification passes)")
        return

    # Render beside the destination, then rename: a failed or unverified render
    # can never truncate or replace an existing output.
    tmp = dest.with_name(f".{dest.stem}.tmp{os.getpid()}{dest.suffix}")
    r = run(build_command(edl, fps_expr, tmp), timeout=RENDER_TIMEOUT_S,
            code=None, what="ffmpeg render")
    if r is None:
        tmp.unlink(missing_ok=True)
        die(EXIT_RENDER, f"ffmpeg did not finish within {RENDER_TIMEOUT_S}s — "
                         f"the partial render was deleted, {dest} is untouched")
    if r.returncode != 0:
        tmp.unlink(missing_ok=True)
        die(EXIT_RENDER, f"ffmpeg failed:\n{r.stderr[-FFMPEG_STDERR_TAIL_CHARS:]}",
            f"the partial render was deleted, {dest} is untouched")

    problems = verify(edl["base"], tmp, windows)
    if problems:
        die(EXIT_VERIFY, *problems,
            f"the unverified render was kept for inspection at {tmp}; "
            f"{dest} is untouched")
    os.replace(tmp, dest)
    print(f"OK: {dest} — duration matches base within {DURATION_TOLERANCE}s, "
          f"audio stream identical to base, {len(windows)} window(s) "
          "composited (frame-checked at each window midpoint)")


if __name__ == "__main__":
    main()
