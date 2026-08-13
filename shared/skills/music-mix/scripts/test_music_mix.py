#!/usr/bin/env python3
"""Executable test for music_mix.py — synthetic fixtures, no credits.

Covers the mechanical evals in evals.md: MM1 (duration equals input, short
music rejected), MM2 (video stream not re-encoded), MM3 (ducking delta, and
--no-duck really skipping it), MM4 (loudness in range), MM5 (the verifier
catches a truncated output, an unmixed copy and a re-encoded picture) — plus
the pre-landing review's regression cases: the output path can never reach an
input file, a failed render leaves nothing behind, an inaudible bed is refused
before the render, ducking engages on a quiet voice, and every verify-path
failure exits 4 rather than crashing.

The ducking measurement works because the fixtures are frequency-separated: the
"voice" is a pure 440 Hz sine in on/off bursts, the music is broadband noise.
Highpassing the finished mix well above 440 Hz leaves essentially only music, so
the bed's own level can be measured inside the real output — no re-implementing
the script's filter graph to measure it.

Contract constants are imported from music_mix.py rather than restated, so the
test cannot drift from the script it checks.

Fixtures are generated with ffmpeg lavfi sources into a temp dir — never into
the repo. Requires ffmpeg/ffprobe on PATH. Python stdlib only, no pytest.

  python3 test_music_mix.py [--keep]

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
SCRIPT = HERE / "music_mix.py"
sys.path.insert(0, str(HERE))
import music_mix as mm  # noqa: E402  — the module under test, same directory

# The script's contract, imported rather than copied.
DURATION_TOLERANCE = mm.DURATION_TOLERANCE
MUSIC_SHORTFALL_EPSILON = mm.MUSIC_SHORTFALL_EPSILON
LUFS_TARGET = mm.LUFS_TARGET
LUFS_TOLERANCE = mm.LUFS_TOLERANCE
TRUE_PEAK_CEILING = mm.TRUE_PEAK_CEILING
MAX_MUSIC_GAIN_DB = mm.MAX_MUSIC_GAIN_DB
MAX_MASTER_GAIN_DB = mm.MAX_MASTER_GAIN_DB

# TEST-SIDE threshold, deliberately NOT imported: evals.md MM3 says music under
# the voice must be at least this far below music in the gaps. One clear halving
# of perceived level — low enough that any real ducking clears it, high enough
# that measurement noise does not. It belongs to the test, not to the mix.
DUCK_MIN_DELTA_DB = 6.0

# --- fixture geometry -----------------------------------------------------
VIDEO_DUR = 12.0
MUSIC_LONG_DUR = 20.0          # comfortably longer than the video
MUSIC_SHORT_DUR = 8.0          # obviously too short
# Shortfall for the "barely short" track: strictly inside the old duration
# tolerance and strictly outside the probe-rounding epsilon, so it only fails
# if the shortfall check really is the strict one (review finding 13).
MUSIC_BARELY_SHORT_DELTA = 0.03
assert MUSIC_SHORTFALL_EPSILON < MUSIC_BARELY_SHORT_DELTA < DURATION_TOLERANCE

VOICE_AMPLITUDE = 0.5          # normal fixture voice, ~-9 LUFS
QUIET_VOICE_AMPLITUDE = 0.02   # ~-34 dBFS bursts: the ducking-no-op reproducer
FAINT_VOICE_AMPLITUDE = 0.004  # ~-51 LUFS: forces the master-gain clamp
# Bed gains for the two off-normal voices. The bed level is relative to the
# music track's OWN loudness, so under a very quiet voice the default -18 dB
# would leave the bed nearly level with the speech; these keep the mix sane so
# each case tests the one thing it is named for.
QUIET_BED_GAIN_DB = -35.0
FAINT_BED_GAIN_DB = -40.0
# A --music-gain that is a legal number but drops the bed under the audibility
# floor, so the floor is what refuses it rather than the range check.
INAUDIBLE_GAIN_DB = -55.0
assert abs(INAUDIBLE_GAIN_DB) < MAX_MUSIC_GAIN_DB

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
            "-show_entries", "format=duration", f"file:{path}"])
    return float(json.loads(r.stdout)["format"]["duration"])


def packet_md5(path, kind):
    r = sh(["ffmpeg", "-v", "error", "-i", f"file:{path}",
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
            str(end), "-i", f"file:{path}", "-map", "0:a:0",
            "-af", f"{band_filter},astats=metadata=1:reset=0",
            "-f", "null", "-"])
    m = re.findall(r"RMS level dB:\s*(-?(?:\d+(?:\.\d+)?|inf))", r.stderr)
    if not m:
        raise RuntimeError(f"no RMS reading for {path} [{start},{end}]:\n"
                           f"{r.stderr[-1500:]}")
    val = m[-1]  # the Overall block is printed last
    return float("-inf") if val == "-inf" else float(val)


def measure_loudness(path):
    r = sh(["ffmpeg", "-v", "info", "-nostats", "-i", f"file:{path}",
            "-map", "0:a:0", "-af", "ebur128=peak=true", "-f", "null", "-"])
    text = r.stderr
    tail = text[text.rfind("Summary"):] if "Summary" in text else text
    lufs = tp = None
    m = re.search(r"I:\s*(-?\d+(?:\.\d+)?)\s*LUFS", tail)
    if m:
        lufs = float(m.group(1))
    m = re.search(r"Peak:\s*(-?(?:\d+(?:\.\d+)?|inf))\s*dBFS", tail)
    if m:
        tp = float("-inf") if m.group(1) == "-inf" else float(m.group(1))
    return lufs, tp


def mean_of(values):
    finite = [v for v in values if v != float("-inf")]
    return sum(finite) / len(finite) if finite else float("-inf")


def duck_delta(path):
    """How much lower the bed sits under the voice than in the gaps, dB.
    Returns (delta, level_under_voice, level_in_gaps)."""
    voice_lv = [band_rms_db(path, s, e, MUSIC_BAND) for s, e in VOICE_WINDOWS]
    gap_lv = [band_rms_db(path, s, e, MUSIC_BAND) for s, e in GAP_WINDOWS]
    v, g = mean_of(voice_lv), mean_of(gap_lv)
    return g - v, v, g


def expect_verify_failure(video, output, needles=(), want_exit=4):
    """--verify-only must fail cleanly: the right exit code, no traceback, and
    a message that names what went wrong. Returns (result, failures)."""
    r = run_script("--verify-only", str(output), "--video", str(video))
    fails = []
    label = Path(str(output)).name or str(output)
    if r.returncode != want_exit:
        fails.append(f"{label}: expected exit {want_exit}, got {r.returncode}\n"
                     f"        stdout: {r.stdout!r}\n        stderr: {r.stderr!r}")
    if "Traceback" in r.stderr:
        fails.append(f"{label}: crashed with a traceback instead of exiting "
                     f"with a message:\n{r.stderr}")
    for needle in needles:
        if needle.lower() not in r.stderr.lower():
            fails.append(f"{label}: stderr should mention {needle!r}: "
                         f"{r.stderr!r}")
    return r, fails


def expect_validation_failure(args, needles=()):
    """A render invocation that must be refused at validation (exit 2)."""
    r = run_script(*[str(a) for a in args])
    fails = []
    if r.returncode != 2:
        fails.append(f"{args}: expected exit 2, got {r.returncode}\n"
                     f"        stdout: {r.stdout!r}\n        stderr: {r.stderr!r}")
    if "Traceback" in r.stderr:
        fails.append(f"{args}: crashed with a traceback:\n{r.stderr}")
    for needle in needles:
        if needle.lower() not in r.stderr.lower():
            fails.append(f"{args}: stderr should mention {needle!r}: "
                         f"{r.stderr!r}")
    return r, fails


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

def _burst_video(path, amplitude, dur=VIDEO_DUR, bursts=True):
    """A picture plus a 440 Hz "voice". With bursts=True the voice speaks in
    two windows so the mix has unambiguous voice-active and voice-free spans;
    with bursts=False it is continuous (used where only the level matters)."""
    if bursts:
        gate = "*(" + "+".join(f"between(t,{s},{e})"
                               for s, e in VOICE_WINDOWS) + ")"
    else:
        gate = ""
    # The expression is single-quoted: its commas would otherwise read as
    # filterchain separators and split the filtergraph.
    ffmpeg("-f", "lavfi",
           "-i", f"testsrc2=size=720x1280:rate=30:duration={dur}",
           "-f", "lavfi",
           "-i", f"aevalsrc='{amplitude}*sin(2*PI*440*t){gate}':"
                 f"d={dur}:s=48000:c=stereo",
           "-c:v", "libx264", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", f"file:{path}")


class Fixtures:
    """video: 12s picture + a 440 Hz "voice" that speaks in two bursts, so the
    mix has unambiguous voice-active windows and unambiguous gaps.
    The variants cover every input shape the script has to refuse or handle:
    a quiet voice, a faint voice, silence, two audio streams, an MPEG-TS
    container. music_*: broadband noise at several lengths, plus silence."""

    def __init__(self, d):
        self.dir = d
        self.video = d / "video.mp4"
        self.video_quiet = d / "video_quiet.mp4"
        self.video_faint = d / "video_faint.mp4"
        self.video_silent = d / "video_silent.mp4"
        self.video_two_audio = d / "video_two_audio.mp4"
        self.video_ts = d / "video.ts"
        self.music_long = d / "music_long.mp3"
        self.music_short = d / "music_short.mp3"
        self.music_barely_short = d / "music_barely_short.wav"
        self.music_silent = d / "music_silent.wav"
        # A local file whose NAME looks like a URL. ffmpeg would resolve it
        # over the network without an explicit `file:` protocol prefix.
        self.music_protocol = d / "http:evil.mp3"

        # Voice at ~0.5 amplitude: leaves headroom, and forces the script's
        # master gain to do real work rather than the fixture arriving on target.
        _burst_video(self.video, VOICE_AMPLITUDE)
        _burst_video(self.video_quiet, QUIET_VOICE_AMPLITUDE)
        _burst_video(self.video_faint, FAINT_VOICE_AMPLITUDE, bursts=False)

        ffmpeg("-f", "lavfi",
               "-i", f"testsrc2=size=720x1280:rate=30:duration={VIDEO_DUR}",
               "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
               "-t", str(VIDEO_DUR), "-c:v", "libx264", "-pix_fmt", "yuv420p",
               "-c:a", "aac", "-b:a", "192k", f"file:{self.video_silent}")

        ffmpeg("-i", f"file:{self.video}",
               "-f", "lavfi", "-i", f"sine=f=880:d={VIDEO_DUR}:r=48000",
               "-map", "0:v:0", "-map", "0:a:0", "-map", "1:a:0",
               "-c:v", "copy", "-c:a", "aac", "-b:a", "128k",
               f"file:{self.video_two_audio}")

        # Same pictures, different container: packet bytes change (Annex-B vs
        # AVCC) while every decoded frame stays identical.
        ffmpeg("-i", f"file:{self.video}", "-c", "copy", "-f", "mpegts",
               f"file:{self.video_ts}")

        # Steady noise beds.
        for path, dur in ((self.music_long, MUSIC_LONG_DUR),
                          (self.music_short, MUSIC_SHORT_DUR)):
            ffmpeg("-f", "lavfi",
                   "-i", f"anoisesrc=d={dur}:c=pink:a=0.5:r=48000",
                   "-af", "aformat=channel_layouts=stereo",
                   "-c:a", "libmp3lame", "-b:a", "192k", f"file:{path}")
        shutil.copyfile(self.music_long, self.music_protocol)

        # Sample-exact lengths, so the shortfall is exactly what we intend:
        # WAV, not MP3, because MP3 frame padding moves the duration by ~24ms.
        self.vdur = probe_duration(self.video)
        ffmpeg("-f", "lavfi",
               "-i", f"anoisesrc=d={self.vdur - MUSIC_BARELY_SHORT_DELTA}:"
                     "c=pink:a=0.5:r=48000",
               "-af", "aformat=channel_layouts=stereo",
               "-c:a", "pcm_s16le", f"file:{self.music_barely_short}")
        ffmpeg("-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
               "-t", str(MUSIC_LONG_DUR), "-c:a", "pcm_s16le",
               f"file:{self.music_silent}")


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

    # (c) the audio really was rebuilt (a byte-copy would mean a no-op step).
    if packet_md5(fx.video, "a") == packet_md5(out, "a"):
        fails.append("output audio is identical to the input's — no music mixed")

    # (d) MM3 — the bed is >= 6 dB lower under the voice than in the gaps.
    delta, v_mean, g_mean = duck_delta(out)
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
    return fails


def case2_short_music(fx, state):
    """MM1 — music shorter than the video is a hard error naming BOTH
    durations. Never looped, never padded — including a 30ms shortfall, which
    would otherwise ship 30ms of silent tail."""
    fails = []
    out = fx.dir / "never_short.mp4"
    r, f = expect_validation_failure([fx.video, fx.music_short, out],
                                     needles=("loop",))
    fails += f
    m = re.search(mm.RE_MUSIC_TOO_SHORT, r.stderr)
    if not m:
        fails.append(f"stderr does not name both durations: {r.stderr!r}")
    else:
        mus, vid = float(m.group(1)), float(m.group(2))
        if abs(mus - MUSIC_SHORT_DUR) > 0.2:
            fails.append(f"reported music duration {mus}s, expected "
                         f"~{MUSIC_SHORT_DUR}s")
        if abs(vid - VIDEO_DUR) > 0.2:
            fails.append(f"reported video duration {vid}s, expected "
                         f"~{VIDEO_DUR}s")
    if out.exists():
        fails.append("a too-short track reached ffmpeg — output was created")

    # A shortfall inside the old duration tolerance is still a shortfall.
    out2 = fx.dir / "never_barely_short.mp4"
    _, f = expect_validation_failure([fx.video, fx.music_barely_short, out2],
                                     needles=("too short",))
    fails += f
    if out2.exists():
        fails.append(f"a {MUSIC_BARELY_SHORT_DELTA}s-short track was accepted "
                     "— that is silent tail, which MM1 forbids")
    return fails


def case3_no_duck(fx, state):
    """MM3 — --no-duck really produces a flat bed."""
    out = fx.dir / "flat.mp4"
    r = run_script(fx.video, fx.music_long, out, "--no-duck")
    fails = []
    if r.returncode != 0:
        return [f"expected exit 0, got {r.returncode}\nstderr: {r.stderr}"]

    delta, _, _ = duck_delta(out)
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
    """MM5 — --verify-only is a real check, not a rubber stamp. Renders its own
    subject so it does not depend on another case having run."""
    good = fx.dir / "case4_good.mp4"
    r = run_script(fx.video, fx.music_long, good)
    if r.returncode != 0 or not good.is_file():
        return [f"could not produce a good output to tamper with (exit "
                f"{r.returncode})\nstderr: {r.stderr}"]
    fails = []

    # (a) truncated: duration drifts, and the message carries both measurements.
    trunc = fx.dir / "trunc.mp4"
    ffmpeg("-i", f"file:{good}", "-t", "9", "-c", "copy", f"file:{trunc}")
    r, f = expect_verify_failure(fx.video, trunc)
    fails += f
    m = re.search(mm.RE_DURATION_DRIFT, r.stderr)
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
    ffmpeg("-i", f"file:{fx.video}", "-c", "copy", f"file:{copy}")
    _, f = expect_verify_failure(fx.video, copy, needles=("no music",))
    fails += f

    # (c) re-encoded picture: same duration, music present, but MM2 broken.
    # Must survive the container-repackaging fallback: the frames really differ.
    reenc = fx.dir / "reenc.mp4"
    ffmpeg("-i", f"file:{good}", "-c:v", "libx264", "-crf", "30",
           "-pix_fmt", "yuv420p", "-c:a", "copy", f"file:{reenc}")
    _, f = expect_verify_failure(fx.video, reenc,
                                 needles=("video stream differs",))
    fails += f

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


def case6_output_cannot_destroy_an_input(fx, state):
    """The output path must never be able to reach an input file.

    A resolve()-string compare let both of these through, and each one
    truncated the source video in place: 729124 bytes down to 35925."""
    fails = []

    # (a) hardlink alias: a different path, the same inode.
    alias = fx.dir / "alias_of_video.mp4"
    if alias.exists():
        alias.unlink()
    os.link(fx.video, alias)
    size_before = fx.video.stat().st_size
    _, f = expect_validation_failure([fx.video, fx.music_long, alias],
                                     needles=("same file",))
    fails += f
    if fx.video.stat().st_size != size_before:
        fails.append(f"the input video was modified: {size_before} -> "
                     f"{fx.video.stat().st_size} bytes")

    # (b) case-variant spelling on a case-insensitive filesystem (every default
    # macOS volume). Skipped where the filesystem really is case-sensitive.
    probe = fx.dir / "CaseProbe.tmp"
    probe.write_text("x")
    case_insensitive = (fx.dir / "caseprobe.TMP").exists()
    probe.unlink()
    if case_insensitive:
        variant = fx.dir / "VIDEO.MP4"
        _, f = expect_validation_failure([fx.video, fx.music_long, variant],
                                         needles=("same file",))
        fails += f
        if fx.video.stat().st_size != size_before:
            fails.append("the input video was modified by a case-variant "
                         "output path")
    else:
        state["case_variant"] = "skipped (case-sensitive filesystem)"

    # (c) an output that reads as an ffmpeg option. `--` is needed to get it
    # past argparse at all; without it argparse rejects it first, which is
    # also fine, but this exercises the script's own guard.
    _, f = expect_validation_failure(["--", fx.video, fx.music_long,
                                      "-dashed.mp4"],
                                     needles=("starts with '-'",))
    fails += f
    if Path("-dashed.mp4").exists():
        fails.append("a leading-dash output was created")
    return fails


def case7_failed_render_leaves_nothing(fx, state):
    """A render that fails must leave no output file and no temp file.

    An .mp4 video stream cannot be muxed into a WAV container, so ffmpeg fails
    after validation has passed — exactly the window where a partial file used
    to appear at the final path."""
    out = fx.dir / "bad.wav"
    before = set(os.listdir(fx.dir))
    r = run_script(fx.video, fx.music_long, out)
    fails = []
    if r.returncode != 3:
        fails.append(f"expected exit 3 (render), got {r.returncode}\n"
                     f"stderr: {r.stderr[-600:]}")
    if out.exists():
        fails.append(f"a failed render left {out.name} behind "
                     f"({out.stat().st_size} bytes) — it looks like an output")
    leftovers = sorted(set(os.listdir(fx.dir)) - before)
    if leftovers:
        fails.append(f"a failed render left temp files behind: {leftovers}")
    return fails


def case8_inaudible_bed_refused(fx, state):
    """Verification cannot see a missing bed — the output's audio is re-encoded
    either way — so both no-op shapes must be refused before the render."""
    fails = []
    out = fx.dir / "never_silent_music.mp4"
    _, f = expect_validation_failure([fx.video, fx.music_silent, out],
                                     needles=("music track is silent",))
    fails += f
    if out.exists():
        fails.append("silent music produced an output file")

    # In range as a number, but the bed would land below the audibility floor.
    out2 = fx.dir / "never_inaudible.mp4"
    _, f = expect_validation_failure([fx.video, fx.music_long, out2,
                                      "--music-gain", str(INAUDIBLE_GAIN_DB)],
                                     needles=("inaudible",))
    fails += f
    if out2.exists():
        fails.append(f"--music-gain {INAUDIBLE_GAIN_DB} produced an output file")

    # And the absurd value from the review is refused too (by the range check
    # first, which is fine — what matters is that it never reaches a render).
    out3 = fx.dir / "never_minus_300.mp4"
    _, f = expect_validation_failure([fx.video, fx.music_long, out3,
                                      "--music-gain", "-300"])
    fails += f
    if out3.exists():
        fails.append("--music-gain -300 produced an output file")
    return fails


def case9_ducking_on_a_quiet_voice(fx, state):
    """MM3 on a quiet source. sidechaincompress' threshold is a linear level on
    the KEY, so keyed off the raw input a -34 dBFS voice never crossed it: the
    bed did not move while the script printed "ducked" — in the same run where
    it applied +20 dB of master gain, i.e. it already knew the source was quiet.
    The gain must reach the key before the compressor does."""
    out = fx.dir / "quiet_ducked.mp4"
    r = run_script(fx.video_quiet, fx.music_long, out,
                   "--music-gain", str(QUIET_BED_GAIN_DB))
    if r.returncode != 0:
        return [f"expected exit 0, got {r.returncode}\nstdout: {r.stdout}\n"
                f"stderr: {r.stderr}"]
    delta, v_mean, g_mean = duck_delta(out)
    state["quiet_duck_delta"] = delta
    state["quiet_duck_levels"] = (v_mean, g_mean)
    if delta < DUCK_MIN_DELTA_DB:
        return [f"quiet voice: ducking delta {delta:.1f} dB < "
                f"{DUCK_MIN_DELTA_DB} dB required (bed under voice "
                f"{v_mean:.1f} dB, bed in gaps {g_mean:.1f} dB) — the "
                f"sidechain key is not seeing the gain-staged voice"]
    return []


def case10_verify_path_failures(fx, state):
    """Every failure on the verify path exits 4 with a message — not a
    ValueError traceback (exit 1) and not the validation code (exit 2)."""
    fails = []

    missing = fx.dir / "does_not_exist.mp4"
    _, f = expect_verify_failure(fx.video, missing, needles=("not found",))
    fails += f

    a_dir = fx.dir / "a_directory.mp4"
    a_dir.mkdir(exist_ok=True)
    _, f = expect_verify_failure(fx.video, a_dir)
    fails += f

    empty = fx.dir / "empty.mp4"
    empty.write_bytes(b"")
    _, f = expect_verify_failure(fx.video, empty)
    fails += f

    junk = fx.dir / "junk.mp4"
    junk.write_bytes(b"this is not a media file, not even slightly\n" * 40)
    _, f = expect_verify_failure(fx.video, junk)
    fails += f
    return fails


def case11_repackaged_container(fx, state):
    """MM2 without false positives. H.264 is Annex-B in MPEG-TS and AVCC in
    MP4, so a faithful stream copy out of a .ts input has different packet
    bytes for identical pictures. The verifier must fall back to decoded
    frames rather than calling a correct output re-encoded."""
    out = fx.dir / "from_ts.mp4"
    r = run_script(fx.video_ts, fx.music_long, out)
    fails = []
    if r.returncode != 0:
        fails.append(f"a .ts input failed end to end (exit {r.returncode})\n"
                     f"stdout: {r.stdout}\nstderr: {r.stderr}")
        return fails
    if "repackaged" not in r.stdout.lower():
        fails.append("the container-repackaging fallback did not report "
                     f"itself: {r.stdout!r}")
    if packet_md5(fx.video_ts, "v") == packet_md5(out, "v"):
        fails.append("the .ts fixture does not actually exercise the fallback "
                     "— its packet MD5 already matches the MP4 output's")
    return fails


def case12_silent_and_clamped_voice(fx, state):
    """A silent voice track is named as such, and a master gain big enough to
    clamp says so out loud instead of failing later on loudness alone."""
    fails = []
    out = fx.dir / "never_silent_voice.mp4"
    _, f = expect_validation_failure([fx.video_silent, fx.music_long, out],
                                     needles=("silent",))
    fails += f
    if out.exists():
        fails.append("a silent video produced an output file")

    # A faint (not silent) voice needs more correction than the clamp allows.
    out2 = fx.dir / "clamped.mp4"
    r = run_script(fx.video_faint, fx.music_long, out2,
                   "--music-gain", str(FAINT_BED_GAIN_DB))
    if r.returncode != 4:
        fails.append(f"clamped master gain: expected exit 4 (verification), "
                     f"got {r.returncode}\nstdout: {r.stdout}\n"
                     f"stderr: {r.stderr}")
    if "clamp" not in r.stderr.lower():
        fails.append(f"the clamp was silent: {r.stderr!r}")
    else:
        # The warning has to name both numbers, not just complain.
        m = re.search(r"([+-][\d.]+) dB is needed .*? only ([+-][\d.]+) dB "
                      r"was applied", r.stderr, re.S)
        if not m:
            fails.append(f"the clamp warning omits requested vs applied dB: "
                         f"{r.stderr!r}")
        elif abs(float(m.group(2))) != MAX_MASTER_GAIN_DB:
            fails.append(f"clamp applied {m.group(2)} dB, expected "
                         f"+/-{MAX_MASTER_GAIN_DB}")
    if "--music-gain" not in r.stderr:
        fails.append("a loudness failure never mentioned --music-gain, the "
                     f"first knob to reach for: {r.stderr!r}")
    return fails


def case13_music_gain_range(fx, state):
    """--music-gain is validated before anything renders. nan reached the
    filter graph as `volume=nandB`; inf burned a full render first."""
    fails = []
    for value in ("nan", "inf", "-inf", "1e400", "1000", "-1000"):
        out = fx.dir / f"never_gain_{value}.mp4"
        _, f = expect_validation_failure(
            [fx.video, fx.music_long, out, "--music-gain", value])
        fails += f
        if out.exists():
            fails.append(f"--music-gain {value} produced an output file")
    # A value at the edge of the range is still accepted — the bound is the
    # bound, not a suggestion. (The negative edge is separately refused by the
    # audibility floor, which is case 8's subject, so the check uses +.)
    r = run_script(fx.video, fx.music_long, fx.dir / "edge_gain.mp4",
                   "--music-gain", str(MAX_MUSIC_GAIN_DB), "--dry-run")
    if r.returncode != 0:
        fails.append(f"--music-gain {MAX_MUSIC_GAIN_DB} (in range) was "
                     f"rejected: exit {r.returncode}\nstderr: {r.stderr}")
    return fails


def case14_multiple_audio_streams(fx, state):
    """Mixing 0:a:0 out of a two-track video would silently drop the other and
    then certify the result OK. The contract is one voice track."""
    out = fx.dir / "never_two_audio.mp4"
    _, fails = expect_validation_failure(
        [fx.video_two_audio, fx.music_long, out],
        needles=("2 audio streams",))
    if out.exists():
        fails.append("a two-audio-stream video produced an output file")
    return fails


def case15_protocol_and_mode_confusion(fx, state):
    """A local file named like a URL stays local, and --verify-only refuses to
    be mixed with render arguments instead of ignoring them."""
    fails = []
    out = fx.dir / "protocol.mp4"
    r = run_script(fx.video, fx.music_protocol, out, "--dry-run")
    if r.returncode != 0:
        fails.append(f"a local file named {fx.music_protocol.name!r} was not "
                     f"read as a local file (exit {r.returncode})\n"
                     f"stderr: {r.stderr}")
    if "-i file:" not in r.stdout:
        fails.append("inputs are not protocol-pinned with `file:`: "
                     f"{r.stdout!r}")

    good = fx.dir / "case15_good.mp4"
    r = run_script(fx.video, fx.music_long, good)
    if r.returncode != 0:
        return fails + [f"could not render a subject for the mode checks "
                        f"(exit {r.returncode})\nstderr: {r.stderr}"]
    # Each of these was silently ignored before, answering a question the
    # operator did not ask. argparse errors exit 2.
    for extra in (["--dry-run"], ["--no-duck"], ["--music-gain", "-20"],
                  [str(fx.video), str(fx.music_long), str(fx.dir / "x.mp4")]):
        r = sh([sys.executable, SCRIPT, "--verify-only", str(good),
                "--video", str(fx.video), *extra])
        if r.returncode == 0:
            fails.append(f"--verify-only silently accepted and ignored "
                         f"{extra}")
    # --video without --verify-only is equally a mode mix-up.
    r = run_script(fx.video, fx.music_long, fx.dir / "y.mp4",
                   "--video", str(fx.video))
    if r.returncode == 0:
        fails.append("--video was accepted outside --verify-only")
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
    ("6 output path can never reach an input (hardlink, case-variant, dash)",
     case6_output_cannot_destroy_an_input),
    ("7 a failed render leaves no output and no temp file",
     case7_failed_render_leaves_nothing),
    ("8 silent music and an inaudible bed are refused before the render",
     case8_inaudible_bed_refused),
    ("9 ducking engages on a quiet voice (gain staging, MM3)",
     case9_ducking_on_a_quiet_voice),
    ("10 verify-path failures exit 4 with a message, never a traceback",
     case10_verify_path_failures),
    ("11 a repackaged container (MPEG-TS in) passes end to end (MM2)",
     case11_repackaged_container),
    ("12 silent voice refused; a clamped master gain says so",
     case12_silent_and_clamped_voice),
    ("13 --music-gain nan/inf/out-of-range refused before rendering",
     case13_music_gain_range),
    ("14 a video with two audio streams is refused", case14_multiple_audio_streams),
    ("15 URL-shaped filenames stay local; verify mode is exclusive",
     case15_protocol_and_mode_confusion),
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
        if "quiet_duck_delta" in state:
            v, g = state["quiet_duck_levels"]
            print(f"measured: quiet-voice ducking delta "
                  f"{state['quiet_duck_delta']:.1f} dB "
                  f"(bed under voice {v:.1f} dB, in gaps {g:.1f} dB)")
        if "lufs" in state:
            print(f"measured: {state.get('lufs')} LUFS, "
                  f"{state.get('tp')} dBTP")
        if "case_variant" in state:
            print(f"note: case-variant output check {state['case_variant']}")
    finally:
        if args.keep or failed:
            print(f"fixtures kept at {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{len(CASES) - failed}/{len(CASES)} cases passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
