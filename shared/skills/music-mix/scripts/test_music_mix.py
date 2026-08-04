#!/usr/bin/env python3
"""Executable test for music_mix.py — synthetic fixtures, no credits.

Covers the mechanical evals in EVALS.md: MM1 (duration equals input, short
music rejected), MM2 (video stream packet-identical), MM3 (ducking delta, and
--no-duck really skipping it), MM4 (loudness in range), MM5 (the verifier
catches a truncated output and an unmixed copy).

The ducking measurement works because the fixtures are frequency-separated: the
"voice" is a pure 440 Hz sine in on/off bursts, the music is broadband noise.
Highpassing the finished mix well above 440 Hz leaves essentially only music, so
the bed's own level can be measured inside the real output — no re-implementing
the script's filter graph to measure it.

Fixtures are generated with ffmpeg lavfi sources into a temp dir — never into
the repo. Requires ffmpeg/ffprobe on PATH. Python stdlib only, no pytest.

  python3 test_music_mix.py [--keep]

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
SCRIPT = HERE / "music_mix.py"

# Must match music_mix.py's contract.
DURATION_TOLERANCE = 0.05
LUFS_TARGET = -14.0
LUFS_TOLERANCE = 2.0
TRUE_PEAK_CEILING = -1.0

# EVALS.md MM3: music under the voice must be at least this far below music in
# the gaps. One clear halving of perceived level — low enough that any real
# ducking clears it, high enough that measurement noise does not.
DUCK_MIN_DELTA_DB = 6.0

VIDEO_DUR = 12.0
# Voice bursts inside the 12s fixture, and the gaps between them.
VOICE_WINDOWS = [(1.0, 4.0), (6.0, 9.0)]
GAP_WINDOWS = [(4.3, 5.7), (9.3, 10.7)]

# Isolate the noise bed from the 440 Hz "voice": three cascaded 2-pole highpass
# sections at 2 kHz is ~36 dB/octave, putting 440 Hz roughly 80 dB down.
MUSIC_BAND = "highpass=f=2000,highpass=f=2000,highpass=f=2000"


# --------------------------------------------------------------------------
# shell helpers
# --------------------------------------------------------------------------

def sh(cmd):
    return subprocess.run([str(c) for c in cmd], capture_output=True, text=True)


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


def packet_md5(path, kind):
    r = sh(["ffmpeg", "-v", "error", "-i", path,
            "-map", f"0:{kind}:0", "-c", "copy", "-f", "md5", "-"])
    if r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        if line.startswith("MD5="):
            return line.strip()
    return None


def band_rms_db(path, start, end, band_filter):
    """RMS level in dBFS of one time window of `path`, after band filtering."""
    r = sh(["ffmpeg", "-v", "info", "-nostats", "-ss", str(start), "-to",
            str(end), "-i", path, "-map", "0:a:0",
            "-af", f"{band_filter},astats=metadata=1:reset=0",
            "-f", "null", "-"])
    m = re.findall(r"RMS level dB:\s*(-?(?:\d+(?:\.\d+)?|inf))", r.stderr)
    if not m:
        raise RuntimeError(f"no RMS reading for {path} [{start},{end}]:\n"
                           f"{r.stderr[-1500:]}")
    val = m[-1]  # the Overall block is printed last
    return float("-inf") if val == "-inf" else float(val)


def measure_loudness(path):
    r = sh(["ffmpeg", "-v", "info", "-nostats", "-i", path, "-map", "0:a:0",
            "-af", "ebur128=peak=true", "-f", "null", "-"])
    text = r.stderr
    tail = text[text.rfind("Summary"):] if "Summary" in text else text
    lufs = tp = None
    m = re.search(r"I:\s*(-?\d+(?:\.\d+)?)\s*LUFS", tail)
    if m:
        lufs = float(m.group(1))
    m = re.search(r"Peak:\s*(-?(?:\d+(?:\.\d+)?|inf))\s*dBFS",
                  text[text.rfind("True peak"):] if "True peak" in text else text)
    if m:
        tp = float("-inf") if m.group(1) == "-inf" else float(m.group(1))
    return lufs, tp


def mean_of(values):
    finite = [v for v in values if v != float("-inf")]
    return sum(finite) / len(finite) if finite else float("-inf")


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

class Fixtures:
    """video: 12s picture + a 440 Hz "voice" that speaks in two bursts, so the
    mix has unambiguous voice-active windows and unambiguous gaps.
    music_long / music_short: broadband noise, one longer than the video and
    one deliberately too short."""

    def __init__(self, d):
        self.dir = d
        self.video = d / "video.mp4"
        self.music_long = d / "music_long.mp3"
        self.music_short = d / "music_short.mp3"

        bursts = "+".join(f"between(t,{s},{e})" for s, e in VOICE_WINDOWS)
        # The expression is single-quoted: its commas would otherwise read as
        # filterchain separators and split the filtergraph.
        # Voice at ~0.5 amplitude: leaves headroom, and forces the script's
        # master gain to do real work rather than the fixture arriving on target.
        ffmpeg("-f", "lavfi",
               "-i", f"testsrc2=size=720x1280:rate=30:duration={VIDEO_DUR}",
               "-f", "lavfi",
               "-i", f"aevalsrc='0.5*sin(2*PI*440*t)*({bursts})':"
                     f"d={VIDEO_DUR}:s=48000:c=stereo",
               "-c:v", "libx264", "-pix_fmt", "yuv420p",
               "-c:a", "aac", "-b:a", "192k", self.video)

        # Steady noise bed. 20s > 12s video; 8s < 12s video.
        for path, dur in ((self.music_long, 20), (self.music_short, 8)):
            ffmpeg("-f", "lavfi",
                   "-i", f"anoisesrc=d={dur}:c=pink:a=0.5:r=48000",
                   "-af", "aformat=channel_layouts=stereo",
                   "-c:a", "libmp3lame", "-b:a", "192k", path)


# --------------------------------------------------------------------------
# cases — each returns a list of failure strings (empty == pass)
# --------------------------------------------------------------------------

def case1_happy_path(fx, state):
    """MM1 duration, MM2 video packets, MM3 ducking delta, MM4 loudness."""
    fails = []
    out = fx.dir / "mixed.mp4"
    r = run_script(fx.video, fx.music_long, out)
    if r.returncode != 0:
        return [f"expected exit 0, got {r.returncode}\nstderr: {r.stderr}"]
    if not out.is_file():
        return ["script exited 0 but produced no output file"]

    # (a) MM1 — duration is unchanged.
    vd, od = probe_duration(fx.video), probe_duration(out)
    if abs(od - vd) > DURATION_TOLERANCE:
        fails.append(f"duration drift: video {vd:.3f}s vs output {od:.3f}s "
                     f"(tolerance {DURATION_TOLERANCE}s)")

    # (b) MM2 — the picture was stream-copied, packet for packet.
    vm, om = packet_md5(fx.video, "v"), packet_md5(out, "v")
    if vm is None or om is None:
        fails.append(f"could not hash video (input={vm}, output={om})")
    elif vm != om:
        fails.append(f"video packets differ: input {vm} vs output {om} "
                     "— the picture was re-encoded, breaking the MM2 guarantee")

    # (c) MM5 precondition — the audio actually changed (music got mixed in).
    if packet_md5(fx.video, "a") == packet_md5(out, "a"):
        fails.append("output audio is identical to the input's — no music mixed")

    # (d) MM3 — the bed is >= 6 dB lower under the voice than in the gaps.
    voice_lv = [band_rms_db(out, s, e, MUSIC_BAND) for s, e in VOICE_WINDOWS]
    gap_lv = [band_rms_db(out, s, e, MUSIC_BAND) for s, e in GAP_WINDOWS]
    v_mean, g_mean = mean_of(voice_lv), mean_of(gap_lv)
    delta = g_mean - v_mean
    state["duck_delta"] = delta
    state["duck_levels"] = (v_mean, g_mean)
    if delta < DUCK_MIN_DELTA_DB:
        fails.append(
            f"ducking delta {delta:.1f} dB < {DUCK_MIN_DELTA_DB} dB required "
            f"(bed under voice {v_mean:.1f} dB, bed in gaps {g_mean:.1f} dB)")

    # (e) MM4 — loudness and true peak.
    lufs, tp = measure_loudness(out)
    state["lufs"], state["tp"] = lufs, tp
    if lufs is None:
        fails.append("could not measure integrated loudness")
    elif abs(lufs - LUFS_TARGET) > LUFS_TOLERANCE:
        fails.append(f"integrated loudness {lufs:.1f} LUFS outside "
                     f"{LUFS_TARGET} +/-{LUFS_TOLERANCE}")
    if tp is not None and tp > TRUE_PEAK_CEILING:
        fails.append(f"true peak {tp:.1f} dBTP exceeds {TRUE_PEAK_CEILING}")

    state["good_out"] = out
    return fails


def case2_short_music(fx, state):
    """MM1 — music shorter than the video is a hard error naming BOTH
    durations. Never looped, never padded."""
    out = fx.dir / "never_short.mp4"
    r = run_script(fx.video, fx.music_short, out)
    fails = []
    if r.returncode != 2:
        fails.append(f"expected exit 2, got {r.returncode}\nstderr: {r.stderr}")
    m = re.search(r"music is ([\d.]+)s, video is ([\d.]+)s", r.stderr)
    if not m:
        fails.append(f"stderr does not name both durations: {r.stderr!r}")
    else:
        mus, vid = float(m.group(1)), float(m.group(2))
        if abs(mus - 8.0) > 0.2:
            fails.append(f"reported music duration {mus}s, expected ~8.0s")
        if abs(vid - VIDEO_DUR) > 0.2:
            fails.append(f"reported video duration {vid}s, expected "
                         f"~{VIDEO_DUR}s")
    if "loop" not in r.stderr.lower():
        fails.append(f"stderr should rule out looping: {r.stderr!r}")
    if out.exists():
        fails.append("a too-short track reached ffmpeg — output was created")
    return fails


def case3_no_duck(fx, state):
    """MM3 — --no-duck really produces a flat bed."""
    out = fx.dir / "flat.mp4"
    r = run_script(fx.video, fx.music_long, out, "--no-duck")
    fails = []
    if r.returncode != 0:
        return [f"expected exit 0, got {r.returncode}\nstderr: {r.stderr}"]

    voice_lv = [band_rms_db(out, s, e, MUSIC_BAND) for s, e in VOICE_WINDOWS]
    gap_lv = [band_rms_db(out, s, e, MUSIC_BAND) for s, e in GAP_WINDOWS]
    delta = mean_of(gap_lv) - mean_of(voice_lv)
    state["flat_delta"] = delta
    if delta >= DUCK_MIN_DELTA_DB:
        fails.append(f"--no-duck still ducked: delta {delta:.1f} dB >= "
                     f"{DUCK_MIN_DELTA_DB} dB")
    # And the escape hatch must still produce a valid, verifiable output.
    r = run_script("--verify-only", out, "--video", fx.video)
    if r.returncode != 0:
        fails.append(f"--no-duck output failed verification (exit "
                     f"{r.returncode})\nstderr: {r.stderr}")
    return fails


def case4_verify_catches_tampering(fx, state):
    """MM5 — --verify-only is a real check, not a rubber stamp."""
    good = state.get("good_out")
    if not good or not Path(good).is_file():
        return ["skipped: case 1 produced no good output to tamper with"]
    fails = []

    # (a) truncated: duration drifts, and the message carries both measurements.
    trunc = fx.dir / "trunc.mp4"
    ffmpeg("-i", good, "-t", "9", "-c", "copy", trunc)
    r = run_script("--verify-only", trunc, "--video", fx.video)
    if r.returncode != 4:
        fails.append(f"truncated: expected exit 4, got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    m = re.search(r"video ([\d.]+)s vs output ([\d.]+)s", r.stderr)
    if not m:
        fails.append(f"truncated: stderr omits measured durations: {r.stderr!r}")
    else:
        v, o = float(m.group(1)), float(m.group(2))
        if abs(v - VIDEO_DUR) > 0.3 or abs(o - 9.0) > 0.3:
            fails.append(f"truncated: measured durations look wrong "
                         f"(video {v}s, output {o}s; expected ~12s and ~9s)")

    # (b) unmixed copy: the step silently no-opped and just copied the input.
    # This is the sneakiest failure — a perfectly playable file with no music.
    copy = fx.dir / "unmixed.mp4"
    ffmpeg("-i", fx.video, "-c", "copy", copy)
    r = run_script("--verify-only", copy, "--video", fx.video)
    if r.returncode != 4:
        fails.append(f"unmixed copy: expected exit 4, got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    if "no music" not in r.stderr.lower():
        fails.append(f"unmixed copy: stderr should say no music was mixed: "
                     f"{r.stderr!r}")

    # (c) re-encoded picture: same duration, music present, but MM2 broken.
    reenc = fx.dir / "reenc.mp4"
    ffmpeg("-i", good, "-c:v", "libx264", "-crf", "30", "-pix_fmt", "yuv420p",
           "-c:a", "copy", reenc)
    r = run_script("--verify-only", reenc, "--video", fx.video)
    if r.returncode != 4:
        fails.append(f"re-encoded video: expected exit 4, got {r.returncode}\n"
                     f"stderr: {r.stderr}")
    if "video stream differs" not in r.stderr.lower():
        fails.append(f"re-encoded video: stderr should name the video-stream "
                     f"difference: {r.stderr!r}")

    # (d) control: the good output still passes.
    r = run_script("--verify-only", good, "--video", fx.video)
    if r.returncode != 0:
        fails.append(f"the good output failed verification (exit "
                     f"{r.returncode}) — verifier is over-strict\n"
                     f"stderr: {r.stderr}")
    return fails


def case5_dry_run(fx, state):
    """--dry-run validates and prints the plan, creating nothing."""
    out = fx.dir / "never_dry.mp4"
    r = run_script(fx.video, fx.music_long, out, "--dry-run")
    fails = []
    if r.returncode != 0:
        fails.append(f"expected exit 0, got {r.returncode}\nstderr: {r.stderr}")
    if "ffmpeg" not in r.stdout:
        fails.append(f"dry run did not print the ffmpeg command: {r.stdout!r}")
    for needle in ("-c:v", "copy", "sidechaincompress"):
        if needle not in r.stdout:
            fails.append(f"printed command is missing {needle!r}: {r.stdout!r}")
    if out.exists():
        fails.append("--dry-run created the output file")
    return fails


CASES = [
    ("1 happy path (MM1 duration, MM2 video packets, MM3 ducking, MM4 loudness)",
     case1_happy_path),
    ("2 music shorter than video rejected with both durations (MM1)",
     case2_short_music),
    ("3 --no-duck skips ducking (MM3)", case3_no_duck),
    ("4 verifier catches truncation, unmixed copy, re-encoded picture (MM5)",
     case4_verify_catches_tampering),
    ("5 --dry-run renders nothing", case5_dry_run),
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

    tmp = Path(tempfile.mkdtemp(prefix="music-mix-test-"))
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
        if "duck_delta" in state:
            v, g = state["duck_levels"]
            print(f"\nmeasured: ducking delta {state['duck_delta']:.1f} dB "
                  f"(bed under voice {v:.1f} dB, in gaps {g:.1f} dB); "
                  f"--no-duck delta {state.get('flat_delta', float('nan')):.1f} dB")
            print(f"measured: {state.get('lufs')} LUFS, "
                  f"{state.get('tp')} dBTP")
    finally:
        if args.keep or failed:
            print(f"fixtures kept at {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{len(CASES) - failed}/{len(CASES)} cases passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
