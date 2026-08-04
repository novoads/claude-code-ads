#!/usr/bin/env python3
"""Deterministic music-bed mixing for a finished video.

Lays a music track UNDER a finished video: the video stream is copied packet
for packet, the voice keeps its own level, and the music ducks beneath it. The
output duration always equals the input video's — the music is trimmed and
faded to fit, never looped (see EVALS.md MM1).

Copying the video stream is the whole point of the step's position in the
pipeline: this can run AFTER captions are burned without touching a pixel of
them (MM2).

Usage:
  python3 music_mix.py video.mp4 music.mp3 out.mp4       validate+render+verify
  python3 music_mix.py video.mp4 music.mp3 out.mp4 --dry-run     plan only
  python3 music_mix.py ... --music-gain -20              louder/quieter bed
  python3 music_mix.py ... --no-duck                     flat bed, no ducking
  python3 music_mix.py --verify-only OUT --video INPUT   re-check any output
"""

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

# |duration(output) - duration(video)| tolerance, seconds. ~1.5 frames at 30fps:
# absorbs container rounding on the re-encoded audio track, nothing else.
DURATION_TOLERANCE = 0.05

# Music tail fade, seconds. A bed that stops dead on the last frame reads as a
# dropout; ~2s is long enough to sound deliberate on a 15s ad without eating the
# closing beat. EVALS.md MM1 pins the range at 1.5-2s.
FADE_OUT = 2.0

# Bed level before ducking, dB relative to the track's own level. -18 dB puts a
# normalized music file well under a normal speaking voice; the sidechain then
# moves it further down only while the voice is actually present. Tune per track
# with --music-gain rather than editing this.
DEFAULT_MUSIC_GAIN_DB = -18.0

# Loudness target for vertical social delivery (EVALS.md MM4). TikTok/Reels/
# Shorts all normalize playback: louder than target gets turned DOWN, quieter
# than target just plays quiet and sounds weak in the feed. -14 LUFS integrated
# is the published cluster. +/-2 LU because a 15s integrated measurement is
# noisy over so short a window.
LUFS_TARGET = -14.0
LUFS_TOLERANCE = 2.0

# True-peak ceiling, dBTP. Platform-side lossy transcoding can reconstruct peaks
# above the sample peak; 1 dB of headroom keeps that from clipping.
TRUE_PEAK_CEILING = -1.0

# alimiter bounds the SAMPLE peak; true peak can sit a few tenths of a dB above
# it on intersample peaks. Limit half a dB lower so the dBTP ceiling holds.
LIMITER_HEADROOM_DB = 0.5

# Master gain is clamped to this. A video needing more than 30 dB of correction
# is not quiet, it is broken, and silently amplifying it would hide that.
MAX_MASTER_GAIN_DB = 30.0

EXIT_VALIDATION = 2
EXIT_RENDER = 3
EXIT_VERIFY = 4


def die(code, *lines):
    for l in lines:
        print(f"ERROR: {l}", file=sys.stderr)
    sys.exit(code)


def run(cmd, **kw):
    return subprocess.run([str(c) for c in cmd], capture_output=True,
                          text=True, **kw)


def ffprobe_json(path, *args):
    r = run(["ffprobe", "-v", "error", "-of", "json", *args, str(path)])
    if r.returncode != 0:
        die(EXIT_VALIDATION, f"ffprobe failed on {path}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def probe_duration(path):
    data = ffprobe_json(path, "-show_entries", "format=duration")
    try:
        return float(data["format"]["duration"])
    except (KeyError, ValueError, TypeError):
        die(EXIT_VALIDATION, f"{path}: could not read duration")


def probe_stream(path, kind):
    data = ffprobe_json(
        path, "-select_streams", f"{kind}:0",
        "-show_entries", "stream=codec_name,sample_rate,channels,width,height")
    streams = data.get("streams") or []
    return streams[0] if streams else None


def packet_md5(path, kind):
    """MD5 over one stream's packets, no decode. A stream-copied track survives
    a remux byte-identical, so input and output must hash the same (MM2)."""
    r = run(["ffmpeg", "-v", "error", "-i", str(path),
             "-map", f"0:{kind}:0", "-c", "copy", "-f", "md5", "-"])
    if r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        if line.startswith("MD5="):
            return line.strip()
    return None


def measure_loudness(path):
    """Integrated LUFS and true peak dBTP via ffmpeg's EBU R128 scanner.
    Returns (lufs, true_peak); either may be None if unparseable."""
    r = run(["ffmpeg", "-v", "info", "-nostats", "-i", str(path),
             "-map", "0:a:0", "-af", "ebur128=peak=true", "-f", "null", "-"])
    text = r.stderr
    # The summary block trails the per-frame log:
    #   Integrated loudness:\n    I:  -14.2 LUFS ...
    #   True peak:\n    Peak: -1.3 dBFS
    lufs = tp = None
    m = re.search(r"I:\s*(-?\d+(?:\.\d+)?)\s*LUFS", text[text.rfind("Summary"):]
                  if "Summary" in text else text)
    if m:
        lufs = float(m.group(1))
    m = re.search(r"Peak:\s*(-?(?:\d+(?:\.\d+)?|inf))\s*dBFS",
                  text[text.rfind("True peak"):] if "True peak" in text else text)
    if m:
        tp = -math.inf if m.group(1) == "-inf" else float(m.group(1))
    return lufs, tp


# --------------------------------------------------------------------------
# validate
# --------------------------------------------------------------------------

def validate(video, music, output):
    """Everything checkable before a render runs (EVALS.md MM1). Collects what
    it can so one bad invocation costs one round-trip."""
    errors = []
    video, music, output = Path(video), Path(music), Path(output)

    if not video.is_file():
        die(EXIT_VALIDATION, f"video not found: {video}")
    if not music.is_file():
        die(EXIT_VALIDATION, f"music not found: {music}")
    for src, label in ((video, "video"), (music, "music")):
        if src.resolve() == output.resolve():
            die(EXIT_VALIDATION, f"output must not overwrite the {label}")

    if probe_stream(video, "v") is None:
        errors.append(f"{video} has no video stream")
    if probe_stream(video, "a") is None:
        errors.append(f"{video} has no audio stream — a music bed goes UNDER a "
                      "voice track; a silent video needs a soundtrack, not a bed")
    if probe_stream(music, "a") is None:
        errors.append(f"{music} has no audio stream")
    if errors:
        die(EXIT_VALIDATION, *errors)

    vdur, mdur = probe_duration(video), probe_duration(music)
    if mdur + DURATION_TOLERANCE < vdur:
        die(EXIT_VALIDATION,
            f"music is {mdur:.2f}s, video is {vdur:.2f}s — the track is too "
            f"short by {vdur - mdur:.2f}s. Supply a longer track (never "
            "looped: a loop seam under a short ad is audible and reads as "
            "broken; never silence-padded either).")
    return vdur, mdur


# --------------------------------------------------------------------------
# render
# --------------------------------------------------------------------------

def master_gain_db(video):
    """Static gain that lands the finished mix on LUFS_TARGET.

    Without this the output's loudness is simply whatever the input video
    happened to be, and MM4 could only ever be a hope. It is applied to the
    MIXED bus, so it scales voice and bed by the same factor: the voice is
    still untouched relative to the music, and a static gain cannot change the
    ducking ratio MM3 measures. Deliberately not `loudnorm` — loudnorm's
    single-pass mode is a dynamic compressor and would fight the ducking.

    The bed sits ~18 dB under the voice and adds well under 1 LU to the
    integrated measurement, which is why measuring the voice alone is close
    enough for a +/-2 LU window. The verifier measures the real output anyway.
    """
    lufs, _ = measure_loudness(video)
    if lufs is None or lufs == -math.inf:
        die(EXIT_VALIDATION,
            f"could not measure the loudness of {video}'s audio — is the "
            "track silent?")
    gain = LUFS_TARGET - lufs
    clamped = max(-MAX_MASTER_GAIN_DB, min(MAX_MASTER_GAIN_DB, gain))
    return clamped, lufs


def build_command(video, music, output, vdur, gain_db, duck, master_db):
    """One ffmpeg command. Video copied; audio rebuilt as voice + ducked bed.

    Graph:
      voice: split - one copy into the mix at unity, one as sidechain key
      music: atrim to the video duration, fade the tail, drop to bed level
      duck:  sidechaincompress pulls the music down while the voice is present
      amix:  sum at unity (normalize=0 — normalize=1 would silently halve both)
      master: one static gain onto the delivery loudness target
      alimiter: hard ceiling so MM4's true-peak bound holds
    """
    fade = min(FADE_OUT, vdur / 2.0)
    fade_start = max(0.0, vdur - fade)
    ceiling = 10 ** ((TRUE_PEAK_CEILING - LIMITER_HEADROOM_DB) / 20.0)

    chains = []
    if duck:
        chains.append("[0:a:0]asplit=2[voice][key]")
        voice_lbl, key_lbl = "[voice]", "[key]"
    else:
        chains.append("[0:a:0]anull[voice]")
        voice_lbl, key_lbl = "[voice]", None

    chains.append(
        f"[1:a:0]atrim=duration={vdur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=out:st={fade_start:.3f}:d={fade:.3f},"
        f"volume={gain_db:.2f}dB,"
        f"aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[bed]")

    if duck:
        # threshold/ratio/attack/release: a fast grab (20ms) so the duck lands on
        # the first syllable, a slow release (400ms) so the bed rises between
        # sentences rather than pumping between words.
        chains.append(
            f"[bed]{key_lbl}sidechaincompress="
            "threshold=0.03:ratio=12:attack=20:release=400:makeup=1[ducked]")
        bed = "[ducked]"
    else:
        bed = "[bed]"

    chains.append(
        f"{voice_lbl}aresample=48000,"
        "aformat=sample_fmts=fltp:channel_layouts=stereo[voi]")
    chains.append(
        f"[voi]{bed}amix=inputs=2:duration=first:normalize=0[mixed]")
    # level=0 disables alimiter's auto-level, which would otherwise normalize
    # the result back up to the ceiling and undo the loudness targeting.
    chains.append(
        f"[mixed]volume={master_db:.2f}dB,"
        f"alimiter=limit={ceiling:.4f}:level=0[aout]")

    # No -shortest: it can drop the final video packet, which would break the
    # MM2 packet-identity guarantee. amix=duration=first already bounds the
    # audio to the voice track, i.e. to the video's own length.
    return ["ffmpeg", "-y", "-i", str(video), "-i", str(music),
            "-filter_complex", ";".join(chains),
            "-map", "0:v:0", "-map", "[aout]",
            # -c:v copy is the MM2 contract: the picture is never re-encoded,
            # which is what makes this safe to run after captions are burned.
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-movflags", "+faststart", str(output)]


# --------------------------------------------------------------------------
# verify
# --------------------------------------------------------------------------

def verify(video, output):
    """Loud, measured verification (EVALS.md MM1/MM2/MM4/MM5)."""
    problems = []
    if not Path(output).is_file():
        return [f"output not found: {output}"]

    vdur, odur = probe_duration(video), probe_duration(output)
    delta = abs(odur - vdur)
    if delta > DURATION_TOLERANCE:
        problems.append(
            f"duration drift: video {vdur:.3f}s vs output {odur:.3f}s "
            f"(|d|={delta:.3f}s > {DURATION_TOLERANCE}s) — a music bed must not "
            "change the length of the cut")

    v_md5, o_md5 = packet_md5(video, "v"), packet_md5(output, "v")
    if v_md5 is None or o_md5 is None:
        problems.append(f"could not hash a video stream "
                        f"(input: {v_md5}, output: {o_md5})")
    elif v_md5 != o_md5:
        problems.append(
            f"video stream differs from input: {v_md5} vs {o_md5} — the picture "
            "must be stream-copied (-c:v copy), not re-encoded; re-encoding "
            "after captions are burned softens them for no reason")

    va_md5, oa_md5 = packet_md5(video, "a"), packet_md5(output, "a")
    if va_md5 is not None and va_md5 == oa_md5:
        problems.append(
            f"output audio is packet-identical to the input's ({oa_md5}) — no "
            "music was mixed in; this output is just a copy of the input")

    lufs, tp = measure_loudness(output)
    if lufs is None:
        problems.append("could not measure integrated loudness (ebur128)")
    elif abs(lufs - LUFS_TARGET) > LUFS_TOLERANCE:
        problems.append(
            f"integrated loudness {lufs:.1f} LUFS is outside "
            f"{LUFS_TARGET} +/-{LUFS_TOLERANCE} LUFS — platforms normalize "
            "playback, so too loud gets turned down and too quiet sounds weak")
    if tp is not None and tp > TRUE_PEAK_CEILING:
        problems.append(
            f"true peak {tp:.1f} dBTP exceeds the {TRUE_PEAK_CEILING} dBTP "
            "ceiling — lossy transcoding on the platform side will clip it")
    return problems, lufs, tp


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video", nargs="?", help="finished video (captions burned is fine)")
    ap.add_argument("music", nargs="?", help="music track, >= the video's duration")
    ap.add_argument("output", nargs="?", help="output path")
    ap.add_argument("--music-gain", type=float, default=DEFAULT_MUSIC_GAIN_DB,
                    metavar="DB",
                    help=f"bed level in dB (default {DEFAULT_MUSIC_GAIN_DB})")
    ap.add_argument("--no-duck", action="store_true",
                    help="flat bed: skip sidechain ducking under the voice")
    ap.add_argument("--dry-run", action="store_true",
                    help="validate and print the plan; render nothing")
    ap.add_argument("--verify-only", metavar="OUTPUT",
                    help="verify an existing output (requires --video)")
    ap.add_argument("--video", dest="video_opt",
                    help="input video for --verify-only")
    args = ap.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            die(EXIT_VALIDATION, f"{tool} not on PATH — brew install ffmpeg")

    if args.verify_only:
        if not args.video_opt:
            die(EXIT_VALIDATION, "--verify-only requires --video INPUT")
        if not Path(args.video_opt).is_file():
            die(EXIT_VALIDATION, f"video not found: {args.video_opt}")
        problems, lufs, tp = verify(args.video_opt, args.verify_only)
        if problems:
            die(EXIT_VERIFY, *problems)
        print(f"VERIFY PASS: {args.verify_only} — duration matches "
              f"{args.video_opt} within {DURATION_TOLERANCE}s, video stream "
              f"packet-identical, music present, {lufs:.1f} LUFS / "
              f"{tp:.1f} dBTP")
        return

    if not (args.video and args.music and args.output):
        ap.error("video, music and output are required (or use --verify-only)")

    vdur, mdur = validate(args.video, args.music, args.output)
    duck = not args.no_duck
    master_db, in_lufs = master_gain_db(args.video)
    cmd = build_command(args.video, args.music, args.output, vdur,
                        args.music_gain, duck, master_db)

    fade = min(FADE_OUT, vdur / 2.0)
    print(f"video: {args.video} ({vdur:.2f}s, {in_lufs:.1f} LUFS in)")
    print(f"music: {args.music} ({mdur:.2f}s) — trimmed to {vdur:.2f}s, "
          f"{fade:.1f}s fade-out")
    print(f"bed:   {args.music_gain:+.1f} dB, "
          f"{'ducked under the voice' if duck else 'FLAT (--no-duck)'}")
    print(f"master:{master_db:+.1f} dB onto {LUFS_TARGET} LUFS, "
          f"limited to {TRUE_PEAK_CEILING} dBTP")

    if args.dry_run:
        print("\nDRY RUN — command that would run:")
        print("  " + " ".join(cmd))
        return

    r = run(cmd)
    if r.returncode != 0:
        die(EXIT_RENDER, f"ffmpeg failed:\n{r.stderr[-2000:]}")

    problems, lufs, tp = verify(args.video, args.output)
    if problems:
        die(EXIT_VERIFY, *problems,
            f"the bad output was kept for inspection: {args.output}")
    print(f"OK: {args.output} — duration matches within {DURATION_TOLERANCE}s, "
          f"video stream packet-identical to input (captions untouched), "
          f"loudness {lufs:.1f} LUFS (target {LUFS_TARGET} "
          f"+/-{LUFS_TOLERANCE}), true peak {tp:.1f} dBTP")


if __name__ == "__main__":
    main()
