#!/usr/bin/env python3
"""Executable test for broll_overlay.py — synthetic fixtures, no credits.

Covers the mechanical evals in EVALS.md: OV1 (duration equals base), OV2 (base
audio passes through byte-identical, overlay audio ignored), OV4 (geometric and
structural validation, every error collected in one round-trip), OV5 (the
verifier catches a tampered output *and* an output that never had an overlay
composited into it), and the mechanical half of OV6 (--stats computes the
cadence numbers and never turns a style deviation into a nonzero exit). OV3, and
OV6's departure rationale, are text assertions on a proposed EDL — not
mechanizable here.

Fixtures are generated with ffmpeg lavfi sources into a temp dir — never into
the repo. Requires ffmpeg/ffprobe on PATH. Python stdlib only, no pytest.

  python3 test_broll_overlay.py [--keep]

Exits 0 only if every case passes.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "broll_overlay.py"

# The contract constants come from the script itself — a test that redeclares
# them can pass while the script drifts.
sys.path.insert(0, str(HERE))
import broll_overlay as bo  # noqa: E402

# A solid-color frame survives the yuv420p round trip with the dominant channel
# far above the other two; testsrc2's area-averaged pixel sits near mid-gray and
# clears neither bar. Wide margins so the test asserts "dominant", not a codec.
DOMINANT_MIN = 150
OTHER_MAX = 100


# --------------------------------------------------------------------------
# shell helpers
# --------------------------------------------------------------------------

def sh(cmd, binary=False):
    return subprocess.run([str(c) for c in cmd], capture_output=True,
                          text=not binary)


def ffmpeg(*args):
    r = sh(["ffmpeg", "-y", "-v", "error", *args])
    if r.returncode != 0:
        raise RuntimeError(f"fixture ffmpeg failed:\n{' '.join(map(str, args))}"
                           f"\n{r.stderr}")


def run_script(*args):
    return sh([sys.executable, SCRIPT, *args])


def probe_duration(path):
    r = sh(["ffprobe", "-v", "error", "-of", "json",
            "-show_entries", "format=duration", path])
    return float(json.loads(r.stdout)["format"]["duration"])


def probe_geometry(path):
    r = sh(["ffprobe", "-v", "error", "-of", "json", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", path])
    s = json.loads(r.stdout)["streams"][0]
    return s["width"], s["height"]


def audio_md5(path):
    """Hash the audio packets without decoding — stream-copied audio survives a
    remux byte-identical, so base and output must produce the same digest."""
    r = sh(["ffmpeg", "-v", "error", "-i", path,
            "-map", "0:a:0", "-c", "copy", "-f", "md5", "-"])
    if r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        if line.startswith("MD5="):
            return line.strip()
    return None


def pixel_rgb(path, t):
    """The whole frame area-averaged down to one RGB triple at time t."""
    r = sh(["ffmpeg", "-v", "error", "-ss", f"{t}", "-i", path,
            "-frames:v", "1", "-vf", "scale=1:1:flags=area",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], binary=True)
    if r.returncode != 0 or len(r.stdout) < 3:
        raise RuntimeError(f"could not sample {path} at t={t}: "
                           f"{r.stderr.decode(errors='replace')}")
    return tuple(r.stdout[:3])


def is_dominant(rgb, channel):
    i = "rgb".index(channel)
    others = [v for j, v in enumerate(rgb) if j != i]
    return rgb[i] >= DOMINANT_MIN and all(v <= OTHER_MAX for v in others)


def write_edl(path, base, output, overlays):
    """overlays: (file, start, end, covers) tuples. `covers` is mandatory in the
    schema (SKILL.md step 3 / OV3) — pass None to build one that omits it."""
    entries = []
    for f, s, e, c in overlays:
        entry = {"file": str(f), "start": s, "end": e}
        if c is not None:
            entry["covers"] = c
        entries.append(entry)
    path.write_text(json.dumps(
        {"base": str(base), "output": str(output), "overlays": entries},
        indent=2))
    return path


def write_raw_edl(path, obj):
    """An EDL of any shape at all, including ones json.dumps writes as NaN."""
    path.write_text(obj if isinstance(obj, str) else json.dumps(obj, indent=2))
    return path


def assert_rejected(label, args, code=bo.EXIT_VALIDATION, must_contain=(),
                    never_created=None):
    """Run the script and assert it refused. Returns (failures, result) so a
    case can keep asserting on the same stderr."""
    r = run_script(*[str(a) for a in args])
    fails = []
    if r.returncode != code:
        fails.append(f"{label}: expected exit {code}, got {r.returncode}\n"
                     f"stdout: {r.stdout}\nstderr: {r.stderr}")
    for needle in must_contain:
        if needle not in r.stderr:
            fails.append(f"{label}: stderr omits {needle!r}: {r.stderr!r}")
    if never_created is not None and Path(never_created).exists():
        fails.append(f"{label}: a rejected run created {never_created}")
    return fails, r


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

class Fixtures:
    """base: 10s testsrc2 + sine. red: 3s solid, silent. blue: 3s solid WITH
    its own audio track — proof that overlay audio never reaches the output.
    rot: the same base tagged 90° in its display matrix (every phone portrait
    capture) with a landscape red clip to match its DISPLAY geometry.
    two_audio: a base carrying two voice tracks. short_video: audio that runs
    longer than the picture."""

    def __init__(self, d):
        self.dir = d
        self.base = d / "base.mp4"
        self.red = d / "red.mp4"
        self.blue = d / "blue.mp4"
        self.rot = d / "rot.mp4"
        self.red_land = d / "red_land.mp4"
        self.two_audio = d / "two_audio.mp4"
        self.short_video = d / "short_video.mp4"

        ffmpeg("-f", "lavfi", "-i", "testsrc2=size=720x1280:rate=30:duration=10",
               "-f", "lavfi", "-i", "sine=frequency=440:duration=10",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
               "-shortest", self.base)
        ffmpeg("-f", "lavfi", "-i", "color=c=red:size=720x1280:rate=30:duration=3",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", self.red)
        ffmpeg("-f", "lavfi", "-i", "color=c=blue:size=720x1280:rate=30:duration=3",
               "-f", "lavfi", "-i", "sine=frequency=880:duration=3",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
               "-shortest", self.blue)
        ffmpeg("-display_rotation", "90", "-i", self.base, "-c", "copy", self.rot)
        ffmpeg("-f", "lavfi", "-i", "color=c=red:size=1280x720:rate=30:duration=3",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", self.red_land)
        ffmpeg("-f", "lavfi", "-i", "testsrc2=size=720x1280:rate=30:duration=6",
               "-f", "lavfi", "-i", "sine=frequency=440:duration=6",
               "-f", "lavfi", "-i", "sine=frequency=660:duration=6",
               "-map", "0:v", "-map", "1:a", "-map", "2:a",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
               "-shortest", self.two_audio)
        ffmpeg("-f", "lavfi", "-i", "testsrc2=size=720x1280:rate=30:duration=4",
               "-f", "lavfi", "-i", "sine=frequency=440:duration=10",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
               self.short_video)


# --------------------------------------------------------------------------
# cases — each returns a list of failure strings (empty == pass)
# --------------------------------------------------------------------------

def case1_happy_path(fx):
    """OV1 + OV2 + tail-trim: both windows are shorter than their 3s clips."""
    fails = []
    out = fx.dir / "good_out.mp4"
    edl = write_edl(fx.dir / "edl_ok.json", fx.base, out, [
        (fx.red, 2.0, 4.5, '"the red part" — 2.5s window from a 3s clip'),
        (fx.blue, 6.0, 8.0, '"the blue part" — 2.0s window from a 3s clip'),
    ])

    r = run_script(edl)
    if r.returncode != 0:
        return [f"expected exit 0, got {r.returncode}\nstderr: {r.stderr}"]
    if not out.is_file():
        return ["script exited 0 but produced no output file"]

    # (a) OV1 — duration is unchanged.
    bd, od = probe_duration(fx.base), probe_duration(out)
    if abs(od - bd) > bo.DURATION_TOLERANCE:
        fails.append(f"duration drift: base {bd:.3f}s vs output {od:.3f}s "
                     f"(tolerance {bo.DURATION_TOLERANCE}s)")

    # (b) OV2 — the audio stream is the base's, untouched, and the blue clip's
    # own sine track contributed nothing.
    bm, om = audio_md5(fx.base), audio_md5(out)
    if bm is None or om is None:
        fails.append(f"could not hash audio (base={bm}, output={om})")
    elif bm != om:
        fails.append(f"audio packets differ: base {bm} vs output {om} "
                     "— audio was re-encoded, replaced, or mixed")

    # (c) the overlays actually DISPLAYED, and only inside their windows.
    # t=5.0 is the tail-trim assertion: the red clip is 3s but its window
    # closed at 4.5, so an untrimmed clip would still be on screen here.
    checks = [
        (3.0, "r", True, "red overlay inside [2.0, 4.5]"),
        (7.0, "b", True, "blue overlay inside [6.0, 8.0]"),
        (1.0, None, False, "base before the first window"),
        (5.0, None, False, "base between the windows (red tail trimmed)"),
        (9.0, None, False, "base after the last window"),
    ]
    for t, channel, want_solid, label in checks:
        rgb = pixel_rgb(out, t)
        if want_solid:
            if not is_dominant(rgb, channel):
                fails.append(f"t={t}s: expected {channel}-dominant "
                             f"({label}), got RGB{rgb}")
        else:
            for c in ("r", "b"):
                if is_dominant(rgb, c):
                    fails.append(f"t={t}s: expected {label}, but frame is "
                                 f"{c}-dominant RGB{rgb} — an overlay leaked "
                                 "outside its window")

    # (d) a normal render surfaces its cadence before rendering.
    if "cadence stats" not in r.stdout:
        fails.append(f"a render run printed no cadence stats block: {r.stdout!r}")

    # (e) the temp render file is renamed into place, never left behind.
    leftovers = [p.name for p in fx.dir.glob(".*tmp*")]
    if leftovers:
        fails.append(f"a successful render left temp files behind: {leftovers}")
    return fails


def case2_overlapping_windows(fx):
    """OV4 — overlapping windows are a hard error naming every offender."""
    never = fx.dir / "never_overlap.mp4"
    edl = write_edl(fx.dir / "edl_overlap.json", fx.base, never, [
        (fx.red, 2.0, 5.0, "first"),
        (fx.blue, 4.0, 6.0, "second, overlapping"),
    ])
    return assert_rejected(
        "overlapping windows", [edl],
        must_contain=("overlaps", "2.0", "5.0", "4.0", "6.0"),
        never_created=never)[0]


def case3_out_of_bounds(fx):
    """OV4 — a window past the end of the base is a hard error."""
    never = fx.dir / "never_oob.mp4"
    edl = write_edl(fx.dir / "edl_oob.json", fx.base, never,
                    [(fx.blue, 8.0, 12.0, "runs off the end of a 10s base")])
    return assert_rejected("out-of-bounds window", [edl],
                           must_contain=("outside", "12"),
                           never_created=never)[0]


def case4_short_clip(fx):
    """OV4 — a clip shorter than its window is a hard error with both
    durations named. Never looped, never freeze-framed."""
    never = fx.dir / "never_short.mp4"
    edl = write_edl(fx.dir / "edl_short.json", fx.base, never,
                    [(fx.red, 1.0, 4.8, "3.8s window over a 3s clip")])
    fails, r = assert_rejected("short clip", [edl], must_contain=("loop",),
                               never_created=never)

    m = re.search(r"clip is ([\d.]+)s, window needs ([\d.]+)s", r.stderr)
    if not m:
        fails.append("stderr does not report the clip and window durations: "
                     f"{r.stderr!r}")
    else:
        clip_s, win_s = float(m.group(1)), float(m.group(2))
        if abs(clip_s - 3.0) > 0.1:
            fails.append(f"reported clip duration {clip_s}s, expected ~3.0s")
        if abs(win_s - 3.8) > 0.01:
            fails.append(f"reported window duration {win_s}s, expected 3.80s")
    return fails


def case5_verify_catches_tampering(fx):
    """OV5 — --verify-only is a real check, not a rubber stamp. Renders its own
    output so a failure here is never someone else's missing prerequisite."""
    fails = []
    good = fx.dir / "verify_src.mp4"
    edl = write_edl(fx.dir / "edl_verify.json", fx.base, good,
                    [(fx.red, 2.0, 4.0, "red"), (fx.blue, 6.0, 7.5, "blue")])
    r = run_script(edl)
    if r.returncode != 0 or not good.is_file():
        return [f"case 5 could not render its own fixture (exit "
                f"{r.returncode})\nstderr: {r.stderr}"]

    # (a) truncated: duration drifts, and the message carries the measurements.
    trunc = fx.dir / "trunc.mp4"
    ffmpeg("-i", good, "-t", "8", "-c", "copy", trunc)
    sub, rt = assert_rejected("truncated", ["--verify-only", trunc, "--base",
                                            fx.base], code=bo.EXIT_VERIFY)
    fails += sub
    m = re.search(r"base ([\d.]+)s vs output ([\d.]+)s", rt.stderr)
    if not m:
        fails.append("truncated: stderr omits the measured durations: "
                     f"{rt.stderr!r}")
    else:
        b, o = float(m.group(1)), float(m.group(2))
        if abs(b - 10.0) > 0.2 or abs(o - 8.0) > 0.2:
            fails.append(f"truncated: measured durations look wrong "
                         f"(base {b}s, output {o}s; expected ~10s and ~8s)")

    # (b) re-encoded audio: same duration, different audio stream.
    reenc = fx.dir / "reenc.mp4"
    ffmpeg("-i", good, "-c:v", "copy", "-c:a", "aac", reenc)
    fails += assert_rejected("re-encoded audio",
                             ["--verify-only", reenc, "--base", fx.base],
                             code=bo.EXIT_VERIFY,
                             must_contain=("audio",))[0]

    # (c) THE no-op case: a plain remux of the base has the base's duration and
    # the base's exact audio packets, so duration+audio alone call it perfect.
    # With the EDL, every window is measured against the base picture.
    remux = fx.dir / "remux_of_base.mp4"
    ffmpeg("-i", fx.base, "-c", "copy", remux)
    fails += assert_rejected(
        "remux of the base", ["--verify-only", remux, "--base", fx.base,
                              "--edl", edl],
        code=bo.EXIT_VERIFY,
        must_contain=("overlays[0]", "overlays[1]", "composited"))[0]

    # ...and without --edl it passes, loudly saying what it did not check.
    r = run_script("--verify-only", remux, "--base", fx.base)
    if r.returncode != 0:
        fails.append(f"remux without --edl: expected exit 0 (duration and "
                     f"audio really do match), got {r.returncode}")
    if "content check skipped" not in r.stdout:
        fails.append("verifying without --edl must say the content check was "
                     f"skipped: {r.stdout!r}")

    # (d) control: the good output passes both ways, so the verifier is not
    # failing everything indiscriminately.
    for extra in ([], ["--edl", str(edl)]):
        r = run_script("--verify-only", good, "--base", fx.base, *extra)
        if r.returncode != 0:
            fails.append(f"the good output failed verification with {extra} "
                         f"(exit {r.returncode}) — verifier is over-strict\n"
                         f"stderr: {r.stderr}")
    if "2 window(s) composited" not in run_script(
            "--verify-only", good, "--base", fx.base, "--edl", edl).stdout:
        fails.append("a passing content check should report how many windows "
                     "it proved")

    # (e) probe failures on the verify path are verify failures, not
    # validation failures, and a missing --base is the reverse.
    zero = fx.dir / "zero_bytes.mp4"
    zero.write_bytes(b"")
    fails += assert_rejected("0-byte output",
                             ["--verify-only", zero, "--base", fx.base],
                             code=bo.EXIT_VERIFY)[0]
    fails += assert_rejected("missing output",
                             ["--verify-only", fx.dir / "nope.mp4",
                              "--base", fx.base],
                             code=bo.EXIT_VERIFY,
                             must_contain=("not found",))[0]
    fails += assert_rejected("no --base", ["--verify-only", good],
                             code=bo.EXIT_VALIDATION)[0]
    return fails


def case6_dry_run(fx):
    """Validate + show the plan, render nothing. --dry-run and --stats are
    different questions and cannot be asked at once."""
    out = fx.dir / "never_dry.mp4"
    edl = write_edl(fx.dir / "edl_dry.json", fx.base, out, [
        (fx.red, 2.0, 4.5, "red"),
        (fx.blue, 6.0, 8.0, "blue"),
    ])
    r = run_script(edl, "--dry-run")
    fails = []
    if r.returncode != 0:
        fails.append(f"expected exit 0, got {r.returncode}\nstderr: {r.stderr}")
    if "ffmpeg" not in r.stdout:
        fails.append(f"dry run did not print the ffmpeg command: {r.stdout!r}")
    if "overlay" not in r.stdout or "overlay=" not in r.stdout:
        fails.append(f"printed command has no overlay filter: {r.stdout!r}")
    if out.exists():
        fails.append("--dry-run created the output file")

    # every input is handed to ffmpeg through the file: protocol
    for path in (fx.base, fx.red, fx.blue):
        if f"file:{path}" not in r.stdout:
            fails.append(f"input {path} is not passed with an explicit file: "
                         f"prefix: {r.stdout!r}")

    fails += assert_rejected("--dry-run with --stats", [edl, "--dry-run",
                                                        "--stats"],
                             code=bo.EXIT_VALIDATION,
                             never_created=out)[0]
    fails += assert_rejected("--edl without --verify-only",
                             [edl, "--edl", edl],
                             code=bo.EXIT_VALIDATION, never_created=out)[0]
    return fails


def _stats_numbers(stdout):
    """Pull the printed cadence numbers back out. Returns a dict or raises."""
    pats = {
        "base": r"cadence stats for a ([\d.]+)s base",
        "count": r"cutaway windows:\s+(\d+)",
        "len_min": r"min ([\d.]+)s\s+mean",
        "len_mean": r"mean ([\d.]+)s\s+max",
        "len_max": r"max ([\d.]+)s",
        "cov_s": r"coverage:\s+([\d.]+)s of",
        "cov_pct": r"of [\d.]+s = ([\d.]+)%",
    }
    got = {}
    for key, pat in pats.items():
        m = re.search(pat, stdout)
        if not m:
            raise RuntimeError(f"stats output has no {key!r} "
                               f"(pattern {pat!r}) in:\n{stdout}")
        got[key] = float(m.group(1))
    return got


def case7_stats(fx):
    """--stats reports arithmetically correct cadence numbers, and stays
    informational: an envelope-violating EDL still exits 0."""
    fails = []
    out_never = fx.dir / "never_stats.mp4"

    # (a) an EDL inside the envelope for this 10s base: 4 windows x 1.0s,
    # 4.0s coverage (~40%), a 1.0s base return between each pair.
    edl = write_edl(fx.dir / "edl_stats_ok.json", fx.base, out_never, [
        (fx.red, 1.0, 2.0, "w1"), (fx.blue, 3.0, 4.0, "w2"),
        (fx.red, 5.0, 6.0, "w3"), (fx.blue, 7.0, 8.0, "w4"),
    ])
    r = run_script(edl, "--stats")
    if r.returncode != 0:
        fails.append(f"--stats: expected exit 0, got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    if out_never.exists():
        fails.append("--stats created the output file")

    # (b) the printed numbers are arithmetically correct for that EDL.
    try:
        g = _stats_numbers(r.stdout)
    except RuntimeError as e:
        return fails + [str(e)]

    base_dur = probe_duration(fx.base)
    expect = {
        "base": base_dur, "count": 4,
        "len_min": 1.0, "len_mean": 1.0, "len_max": 1.0,
        "cov_s": 4.0, "cov_pct": 100.0 * 4.0 / base_dur,
    }
    for key, want in expect.items():
        if abs(g[key] - want) > 0.06:
            fails.append(f"--stats {key}: printed {g[key]}, expected {want:.2f}")

    m = re.search(r"largest ([\d.]+)s, smallest ([\d.]+)s", r.stdout)
    if not m:
        fails.append(f"--stats printed no base-return gaps: {r.stdout!r}")
    else:
        largest, smallest = float(m.group(1)), float(m.group(2))
        if abs(largest - 1.0) > 0.01 or abs(smallest - 1.0) > 0.01:
            fails.append(f"--stats gaps: largest {largest}s / smallest "
                         f"{smallest}s, expected 1.00s / 1.00s")
    if "gap(s)" in r.stdout and "3 gap(s)" not in r.stdout:
        fails.append(f"--stats: expected 3 gaps for 4 windows: {r.stdout!r}")

    # this EDL sits inside the envelope on every metric.
    if "outside envelope" in r.stdout:
        fails.append("--stats flagged an in-envelope EDL as outside:\n"
                     + r.stdout)

    # (c) an envelope-violating EDL: 2 windows of 2.5s. Still exit 0.
    edl_bad = write_edl(fx.dir / "edl_stats_bad.json", fx.base, out_never, [
        (fx.red, 1.0, 3.5, "2.5s window"), (fx.blue, 5.0, 7.5, "2.5s window"),
    ])
    r = run_script(edl_bad, "--stats")
    if r.returncode != 0:
        fails.append(f"--stats on an envelope-violating EDL: expected exit 0 "
                     f"(cadence is never a gate), got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    if "outside envelope" not in r.stdout:
        fails.append("--stats did not flag the violating EDL as outside the "
                     f"envelope: {r.stdout!r}")
    for label in ("cutaway windows", "window length"):
        line = next((l for l in r.stdout.splitlines() if label in l), None)
        if line is None or "outside envelope" not in line:
            fails.append(f"--stats: {label!r} should be outside the envelope "
                         f"(2 windows of 2.5s), got: {line!r}")
    try:
        gb = _stats_numbers(r.stdout)
    except RuntimeError as e:
        return fails + [str(e)]
    if abs(gb["count"] - 2) > 0.01 or abs(gb["len_max"] - 2.5) > 0.01 \
            or abs(gb["cov_s"] - 5.0) > 0.06:
        fails.append(f"--stats numbers wrong for the violating EDL: {gb}")
    if out_never.exists():
        fails.append("--stats created the output file")
    return fails


def case8_malformed_edl(fx):
    """OV4 — every shape a hand-written or model-written EDL can arrive in is a
    collected validation error, never a traceback."""
    fails = []
    never = fx.dir / "never_malformed.mp4"

    def edl_with(name, overlays):
        return write_raw_edl(fx.dir / name, {
            "base": str(fx.base), "output": str(never), "overlays": overlays})

    # top-level shapes
    fails += assert_rejected("top-level array",
                             [write_raw_edl(fx.dir / "edl_arr.json", [])],
                             must_contain=("JSON object",),
                             never_created=never)[0]
    fails += assert_rejected("top-level scalar",
                             [write_raw_edl(fx.dir / "edl_num.json", 42)],
                             must_contain=("JSON object",),
                             never_created=never)[0]
    fails += assert_rejected("not JSON at all",
                             [write_raw_edl(fx.dir / "edl_txt.json", "nope")],
                             must_contain=("cannot read EDL",),
                             never_created=never)[0]

    # entry shapes — all four reported in one run, each tagged with its index
    entries = edl_with("edl_entries.json",
                       [None, 7, "broll.mp4", [1, 2],
                        {"file": str(fx.red), "start": 1.0, "end": 2.0,
                         "covers": "ok"}])
    sub, r = assert_rejected("non-object overlay entries", [entries],
                             never_created=never)
    fails += sub
    for i, kind in ((0, "NoneType"), (1, "int"), (2, "str"), (3, "list")):
        if f"overlays[{i}] must be a JSON object" not in r.stderr:
            fails.append(f"overlays[{i}] ({kind}) not reported as a bad entry: "
                         f"{r.stderr!r}")

    # NaN / Infinity / bool: json.loads accepts all three, float() coerces the
    # bool, and every ordering comparison against NaN is False.
    for label, value in (("NaN", float("nan")), ("Infinity", float("inf")),
                         ("-Infinity", float("-inf")), ("bool", True)):
        edl = write_edl(fx.dir / f"edl_num_{label}.json", fx.base, never,
                        [(fx.red, value, 3.0, "c")])
        fails += assert_rejected(f"start={label}", [edl],
                                 must_contain=("finite numbers",),
                                 never_created=never)[0]
    edl = write_edl(fx.dir / "edl_end_bool.json", fx.base, never,
                    [(fx.red, 1.0, False, "c")])
    fails += assert_rejected("end=false", [edl],
                             must_contain=("finite numbers",),
                             never_created=never)[0]

    # `covers` is mandatory (SKILL.md step 3 / OV3), not decorative.
    edl = write_edl(fx.dir / "edl_nocovers.json", fx.base, never,
                    [(fx.red, 1.0, 3.0, None)])
    fails += assert_rejected("missing covers", [edl],
                             must_contain=('is missing "covers"',),
                             never_created=never)[0]
    edl = edl_with("edl_blankcovers.json",
                   [{"file": str(fx.red), "start": 1.0, "end": 3.0,
                     "covers": "   "}])
    fails += assert_rejected("blank covers", [edl],
                             must_contain=("non-empty string",),
                             never_created=never)[0]

    # a non-string file path is a validation error, not a TypeError
    edl = edl_with("edl_filetype.json",
                   [{"file": 12, "start": 1.0, "end": 3.0, "covers": "c"}])
    fails += assert_rejected("numeric file path", [edl],
                             must_contain=("path string",),
                             never_created=never)[0]
    return fails


def case9_zero_frame_windows(fx):
    """A window that renders no overlay frame is a validation error, because
    the render would otherwise 'succeed' with nothing composited."""
    fails = []
    never = fx.dir / "never_zero.mp4"

    # (a) shorter than one base frame period (1/30s here)
    edl = write_edl(fx.dir / "edl_subframe.json", fx.base, never,
                    [(fx.red, 3.010, 3.020, "10ms window")])
    fails += assert_rejected("sub-frame window", [edl],
                             must_contain=("shorter than one base frame",),
                             never_created=never)[0]

    # (b) inside the container duration but past the end of the PICTURE: this
    # base's audio runs 10s over a 4s video stream.
    if abs(probe_duration(fx.short_video) - 10.0) > 0.3:
        fails.append("fixture short_video should have a ~10s container "
                     f"duration, got {probe_duration(fx.short_video):.2f}s")
    edl = write_edl(fx.dir / "edl_pastvideo.json", fx.short_video, never,
                    [(fx.red, 5.0, 7.0, "past the picture, inside the audio")])
    sub, r = assert_rejected("window past the video stream", [edl],
                             must_contain=("outside",), never_created=never)
    fails += sub
    if "[0, 4.0" not in r.stderr:
        fails.append("the bound should be the video stream's 4s, not the "
                     f"container's 10s: {r.stderr!r}")
    return fails


def case10_rotated_base(fx):
    """A display-matrix-rotated base (any phone portrait capture) composites at
    the base's DISPLAY geometry. Coded 720x1280, displayed 1280x720: geometry
    read from the probe instead of the filter graph pillarboxes the cutaway."""
    fails = []
    out = fx.dir / "rot_out.mp4"
    edl = write_edl(fx.dir / "edl_rot.json", fx.rot, out,
                    [(fx.red_land, 3.0, 5.0, "full-frame red cutaway")])
    r = run_script(edl)
    if r.returncode != 0:
        return [f"rotated base: expected exit 0, got {r.returncode}\n"
                f"stderr: {r.stderr}"]

    if probe_geometry(fx.rot) != (720, 1280):
        fails.append(f"fixture rot.mp4 should be coded 720x1280, got "
                     f"{probe_geometry(fx.rot)}")
    if probe_geometry(out) != (1280, 720):
        fails.append(f"output should carry the base's display geometry "
                     f"1280x720, got {probe_geometry(out)}")

    rgb = pixel_rgb(out, 4.0)
    if not is_dominant(rgb, "r"):
        fails.append(f"t=4.0s: the cutaway should fill the frame, got RGB{rgb} "
                     "— the overlay was scaled to the coded geometry and "
                     "letterboxed inside the rotated frame")
    rgb = pixel_rgb(out, 1.0)
    if is_dominant(rgb, "r"):
        fails.append(f"t=1.0s: the base should be on screen, got RGB{rgb}")
    if abs(probe_duration(out) - probe_duration(fx.rot)) > bo.DURATION_TOLERANCE:
        fails.append("rotated render changed the duration")
    return fails


def case11_output_safety(fx):
    """The output never destroys an input, and a failed render never destroys
    the previous output."""
    fails = []

    # (a) a case variant of an overlay input, on a case-insensitive filesystem
    (fx.dir / "CaseProbe").write_text("x")
    case_insensitive = (fx.dir / "caseprobe").exists()
    (fx.dir / "CaseProbe").unlink()
    if case_insensitive:
        edl = write_edl(fx.dir / "edl_case.json", fx.base,
                        fx.dir / "RED.mp4", [(fx.red, 1.0, 3.0, "c")])
        fails += assert_rejected("output as a case variant of an overlay",
                                 [edl],
                                 must_contain=("must not overwrite an input",
                                               "overlays[0]"))[0]
    else:
        print("      (note: case-sensitive filesystem — case-variant output "
              "check not applicable here)")

    # (b) a hardlink alias of the base
    alias = fx.dir / "base_alias.mp4"
    if not alias.exists():
        os.link(fx.base, alias)
    edl = write_edl(fx.dir / "edl_alias.json", fx.base, alias,
                    [(fx.red, 1.0, 3.0, "c")])
    fails += assert_rejected("output as a hardlink of the base", [edl],
                             must_contain=("must not overwrite an input",
                                           "base"))[0]
    if alias.stat().st_size != fx.base.stat().st_size:
        fails.append("the hardlinked base was modified by a rejected run")

    # (c) an output that argparse/ffmpeg would read as an option
    edl = write_raw_edl(fx.dir / "edl_dash.json", {
        "base": str(fx.base), "output": "-out.mp4",
        "overlays": [{"file": str(fx.red), "start": 1.0, "end": 3.0,
                      "covers": "c"}]})
    fails += assert_rejected("output starting with a dash", [edl],
                             must_contain=('starts with "-"',))[0]

    # (d) a missing output directory is a validation error — nothing renders
    edl = write_edl(fx.dir / "edl_nodir.json", fx.base,
                    fx.dir / "no_such_dir" / "out.mp4",
                    [(fx.red, 1.0, 3.0, "c")])
    fails += assert_rejected("missing output directory", [edl],
                             must_contain=("output directory does not exist",))[0]

    # (e) a directory that exists but rejects writes fails at render (exit 3),
    # and the previous output survives byte-identical.
    ro = fx.dir / "ro"
    ro.mkdir(exist_ok=True)
    dest = ro / "out.mp4"
    dest.write_text("previous output, must survive")
    before = dest.read_text()
    edl = write_edl(fx.dir / "edl_ro.json", fx.base, dest,
                    [(fx.red, 1.0, 3.0, "c")])
    os.chmod(ro, 0o555)
    try:
        writable = True
        try:
            probe = ro / ".writeprobe"
            probe.write_text("x")
            probe.unlink()
        except OSError:
            writable = False
        if writable:
            print("      (note: this process can write to a 0555 directory — "
                  "render-failure check not applicable here)")
        else:
            sub, r = assert_rejected("read-only output directory", [edl],
                                     code=bo.EXIT_RENDER,
                                     must_contain=("ffmpeg failed",
                                                   "is untouched"))
            fails += sub
            if dest.read_text() != before:
                fails.append("a failed render overwrote the previous output")
            leftovers = [p.name for p in ro.glob(".*tmp*")]
            if leftovers:
                fails.append(f"a failed render left temp files: {leftovers}")
    finally:
        os.chmod(ro, 0o755)
    return fails


def case12_base_contract(fx):
    """The base must be one picture with exactly one voice track under it."""
    never = fx.dir / "never_base.mp4"
    edl = write_edl(fx.dir / "edl_2audio.json", fx.two_audio, never,
                    [(fx.red, 1.0, 3.0, "c")])
    fails = assert_rejected("two-audio base", [edl],
                            must_contain=("2 audio streams", "0:a:0"),
                            never_created=never)[0]

    silent = fx.dir / "silent.mp4"
    ffmpeg("-f", "lavfi", "-i", "color=c=green:size=720x1280:rate=30:duration=6",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", silent)
    edl = write_edl(fx.dir / "edl_silent.json", silent, never,
                    [(fx.red, 1.0, 3.0, "c")])
    fails += assert_rejected("silent base", [edl],
                             must_contain=("no audio stream",),
                             never_created=never)[0]
    return fails


def case13_collects_every_error(fx):
    """OV4 — one bad EDL costs exactly one round-trip. Nothing short-circuits:
    not an unreadable file mid-loop, not a second overlap behind a long
    window."""
    fails = []
    never = fx.dir / "never_collect.mp4"

    unreadable = fx.dir / "unreadable.mp4"
    unreadable.write_bytes(b"")
    edl = write_edl(fx.dir / "edl_collect.json", fx.base, never, [
        (fx.dir / "missing.mp4", 1.0, 2.0, "a"),
        (unreadable, 2.5, 3.5, "b"),
        (fx.red, 8.0, 12.0, "c"),
    ])
    sub, r = assert_rejected("three independent errors", [edl],
                             never_created=never)
    fails += sub
    for needle in ("overlays[0] (missing.mp4): file not found",
                   "overlays[1] (unreadable.mp4): unreadable media file",
                   "overlays[2] (red.mp4): window [8.0, 12.0] outside"):
        if needle not in r.stderr:
            fails.append(f"stderr omits {needle!r} — an earlier error "
                         f"short-circuited the pass: {r.stderr!r}")

    # one long window swallowing two later ones: an adjacent-pair scan sees
    # only the first, because [1.0, 2.0] and [2.1, 2.4] do not touch.
    edl = write_edl(fx.dir / "edl_overlaps.json", fx.base, never, [
        (fx.red, 0.0, 2.5, "long"),
        (fx.blue, 1.0, 2.0, "inside it"),
        (fx.red, 2.1, 2.4, "also inside it, but not adjacent to the last"),
    ])
    sub, r = assert_rejected("every overlap", [edl], never_created=never)
    fails += sub
    for needle in ("overlaps overlays[1]", "overlaps overlays[2]"):
        if needle not in r.stderr:
            fails.append(f"stderr omits {needle!r} — the overlap scan stopped "
                         f"at adjacent pairs: {r.stderr!r}")
    return fails


def case14_protocol_prefix(fx):
    """A local file named like a URL is opened as a file. Without an explicit
    file: prefix, ffmpeg treats 'http:clip.mp4' as a network address."""
    evil = fx.dir / "http:evil.mp4"
    shutil.copy(fx.red, evil)
    out = fx.dir / "proto_out.mp4"
    edl = write_edl(fx.dir / "edl_proto.json", fx.base, out,
                    [(evil, 2.0, 4.0, "a local file that looks like a URL")])
    r = run_script(edl)
    fails = []
    if r.returncode != 0:
        return [f"a local file named http:evil.mp4 should render normally, "
                f"got exit {r.returncode}\nstderr: {r.stderr}"]
    rgb = pixel_rgb(out, 3.0)
    if not is_dominant(rgb, "r"):
        fails.append(f"t=3.0s: the URL-named clip did not composite: RGB{rgb}")
    return fails


CASES = [
    ("1 happy path (OV1 duration, OV2 audio, overlays displayed, tail-trim)",
     case1_happy_path),
    ("2 overlapping windows rejected (OV4)", case2_overlapping_windows),
    ("3 out-of-bounds window rejected (OV4)", case3_out_of_bounds),
    ("4 short clip rejected with durations (OV4)", case4_short_clip),
    ("5 verifier catches tampered and un-overlaid output (OV5)",
     case5_verify_catches_tampering),
    ("6 --dry-run renders nothing, --stats is exclusive", case6_dry_run),
    ("7 --stats reports correct numbers, never gates (OV6)", case7_stats),
    ("8 malformed EDLs are validation errors, not tracebacks (OV4)",
     case8_malformed_edl),
    ("9 zero-frame windows rejected (sub-frame, past the picture)",
     case9_zero_frame_windows),
    ("10 rotated base composites at display geometry", case10_rotated_base),
    ("11 output never overwrites an input; failed render is atomic",
     case11_output_safety),
    ("12 base contract: one picture, exactly one audio stream",
     case12_base_contract),
    ("13 every validation error in one round-trip (OV4)",
     case13_collects_every_error),
    ("14 URL-looking local filenames stay local", case14_protocol_prefix),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--keep", action="store_true",
                    help="keep the temp fixture dir for inspection")
    args = ap.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            print(f"FATAL: {tool} not on PATH — brew install ffmpeg",
                  file=sys.stderr)
            return 1
    if not SCRIPT.is_file():
        print(f"FATAL: {SCRIPT} not found", file=sys.stderr)
        return 1

    tmp = Path(tempfile.mkdtemp(prefix="broll-overlay-test-"))
    print(f"fixtures: {tmp}")
    failed = 0
    try:
        fx = Fixtures(tmp)
        for name, fn in CASES:
            try:
                fails = fn(fx)
            except Exception as e:  # a crashing case is a failing case
                fails = [f"case raised {type(e).__name__}: {e}"]
            if fails:
                failed += 1
                print(f"FAIL: {name}")
                for f in fails:
                    print(f"      {f}")
            else:
                print(f"PASS: {name}")
    finally:
        if args.keep or failed:
            print(f"fixtures kept at {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{len(CASES) - failed}/{len(CASES)} cases passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
