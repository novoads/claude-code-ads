#!/usr/bin/env python3
"""Executable test for broll_overlay.py — synthetic fixtures, no credits.

Covers the mechanical evals in EVALS.md: OV1 (duration equals base), OV2 (base
audio passes through byte-identical, overlay audio ignored), OV4 (geometric
validation: overlap, out-of-bounds, short clip), OV5 (the verifier catches a
tampered output). OV3 is a text assertion on a proposed EDL and is not
mechanizable here.

Fixtures are generated with ffmpeg lavfi sources into a temp dir — never into
the repo. Requires ffmpeg/ffprobe on PATH. Python stdlib only, no pytest.

  python3 test_broll_overlay.py [--keep]

Exits 0 only if every case passes.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "broll_overlay.py"

# Must match broll_overlay.py's contract.
DURATION_TOLERANCE = 0.05

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
    path.write_text(json.dumps(
        {"base": str(base), "output": str(output),
         "overlays": [{"file": str(f), "start": s, "end": e,
                       "covers": c} for f, s, e, c in overlays]}, indent=2))
    return path


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

class Fixtures:
    """base: 10s testsrc2 + sine. red: 3s solid, silent. blue: 3s solid WITH
    its own audio track — proof that overlay audio never reaches the output."""

    def __init__(self, d):
        self.dir = d
        self.base = d / "base.mp4"
        self.red = d / "red.mp4"
        self.blue = d / "blue.mp4"

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


# --------------------------------------------------------------------------
# cases — each returns a list of failure strings (empty == pass)
# --------------------------------------------------------------------------

def case1_happy_path(fx, state):
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
    if abs(od - bd) > DURATION_TOLERANCE:
        fails.append(f"duration drift: base {bd:.3f}s vs output {od:.3f}s "
                     f"(tolerance {DURATION_TOLERANCE}s)")

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

    state["good_out"] = out
    return fails


def case2_overlapping_windows(fx, state):
    """OV4 — overlapping windows are a hard error naming every offender."""
    edl = write_edl(fx.dir / "edl_overlap.json", fx.base,
                    fx.dir / "never_overlap.mp4", [
                        (fx.red, 2.0, 5.0, "first"),
                        (fx.blue, 4.0, 6.0, "second, overlapping"),
                    ])
    r = run_script(edl)
    fails = []
    if r.returncode != 2:
        fails.append(f"expected exit 2, got {r.returncode}\nstderr: {r.stderr}")
    if "overlap" not in r.stderr.lower():
        fails.append(f"stderr does not mention overlap: {r.stderr!r}")
    for n in ("2.0", "5.0", "4.0", "6.0"):
        if n not in r.stderr:
            fails.append(f"stderr omits window bound {n}: {r.stderr!r}")
    if (fx.dir / "never_overlap.mp4").exists():
        fails.append("an invalid EDL reached ffmpeg — output file was created")
    return fails


def case3_out_of_bounds(fx, state):
    """OV4 — a window past the end of the base is a hard error."""
    edl = write_edl(fx.dir / "edl_oob.json", fx.base,
                    fx.dir / "never_oob.mp4",
                    [(fx.blue, 8.0, 12.0, "runs off the end of a 10s base")])
    r = run_script(edl)
    fails = []
    if r.returncode != 2:
        fails.append(f"expected exit 2, got {r.returncode}\nstderr: {r.stderr}")
    if "outside" not in r.stderr.lower():
        fails.append(f"stderr does not say the window is outside the base: "
                     f"{r.stderr!r}")
    if "12" not in r.stderr:
        fails.append(f"stderr omits the offending end bound: {r.stderr!r}")
    if (fx.dir / "never_oob.mp4").exists():
        fails.append("an invalid EDL reached ffmpeg — output file was created")
    return fails


def case4_short_clip(fx, state):
    """OV4 — a clip shorter than its window is a hard error with both
    durations named. Never looped, never freeze-framed."""
    edl = write_edl(fx.dir / "edl_short.json", fx.base,
                    fx.dir / "never_short.mp4",
                    [(fx.red, 1.0, 4.8, "3.8s window over a 3s clip")])
    r = run_script(edl)
    fails = []
    if r.returncode != 2:
        fails.append(f"expected exit 2, got {r.returncode}\nstderr: {r.stderr}")

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
    if "loop" not in r.stderr.lower():
        fails.append("stderr should state that looping is not the fallback: "
                     f"{r.stderr!r}")
    if (fx.dir / "never_short.mp4").exists():
        fails.append("an invalid EDL reached ffmpeg — output file was created")
    return fails


def case5_verify_catches_tampering(fx, state):
    """OV5 — --verify-only is a real check, not a rubber stamp."""
    good = state.get("good_out")
    if not good or not Path(good).is_file():
        return ["skipped: case 1 produced no good output to tamper with"]
    fails = []

    # (a) truncated: duration drifts, and the message carries the measurements.
    trunc = fx.dir / "trunc.mp4"
    ffmpeg("-i", good, "-t", "8", "-c", "copy", trunc)
    r = run_script("--verify-only", trunc, "--base", fx.base)
    if r.returncode != 4:
        fails.append(f"truncated: expected exit 4, got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    m = re.search(r"base ([\d.]+)s vs output ([\d.]+)s", r.stderr)
    if not m:
        fails.append("truncated: stderr omits the measured durations: "
                     f"{r.stderr!r}")
    else:
        b, o = float(m.group(1)), float(m.group(2))
        if abs(b - 10.0) > 0.2 or abs(o - 8.0) > 0.2:
            fails.append(f"truncated: measured durations look wrong "
                         f"(base {b}s, output {o}s; expected ~10s and ~8s)")

    # (b) re-encoded audio: same duration, different audio stream.
    reenc = fx.dir / "reenc.mp4"
    ffmpeg("-i", good, "-c:v", "copy", "-c:a", "aac", reenc)
    r = run_script("--verify-only", reenc, "--base", fx.base)
    if r.returncode != 4:
        fails.append(f"re-encoded audio: expected exit 4, got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    if "audio" not in r.stderr.lower():
        fails.append(f"re-encoded audio: stderr does not mention audio: "
                     f"{r.stderr!r}")

    # (c) control: the good output still passes, so the verifier is not
    # failing everything indiscriminately.
    r = run_script("--verify-only", good, "--base", fx.base)
    if r.returncode != 0:
        fails.append(f"the good output failed verification (exit "
                     f"{r.returncode}) — verifier is over-strict\n"
                     f"stderr: {r.stderr}")
    return fails


def case6_dry_run(fx, state):
    """Validate + show the plan, render nothing."""
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
    if "overlay" not in r.stdout:
        fails.append(f"printed command has no overlay filter: {r.stdout!r}")
    if out.exists():
        fails.append("--dry-run created the output file")
    return fails


CASES = [
    ("1 happy path (OV1 duration, OV2 audio, overlays displayed, tail-trim)",
     case1_happy_path),
    ("2 overlapping windows rejected (OV4)", case2_overlapping_windows),
    ("3 out-of-bounds window rejected (OV4)", case3_out_of_bounds),
    ("4 short clip rejected with durations (OV4)", case4_short_clip),
    ("5 verifier catches tampered output (OV5)", case5_verify_catches_tampering),
    ("6 --dry-run renders nothing", case6_dry_run),
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
        state = {}
        for name, fn in CASES:
            try:
                fails = fn(fx, state)
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
