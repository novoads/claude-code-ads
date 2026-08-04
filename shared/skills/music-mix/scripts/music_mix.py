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

--verify-only is a standalone mode: mixing it with the render arguments is an
error rather than a silent no-op.
"""

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# |duration(output) - duration(video)| tolerance, seconds. ~1.5 frames at 30fps:
# absorbs container rounding on the re-encoded audio track, nothing else.
DURATION_TOLERANCE = 0.05

# A separate, much tighter epsilon for "is the music long enough?". It is NOT
# DURATION_TOLERANCE: allowing 50ms of shortfall there would silently ship 50ms
# of silent tail, which is exactly the "never padded" promise MM1 makes. 0.01s
# is probe rounding (ffprobe reports container duration to ~ms), nothing more.
MUSIC_SHORTFALL_EPSILON = 0.01

# Music tail fade, seconds. A bed that stops dead on the last frame reads as a
# dropout; ~2s is long enough to sound deliberate on a 15s ad without eating the
# closing beat. EVALS.md MM1 pins the range at 1.5-2s.
FADE_OUT = 2.0

# Bed level before ducking, dB relative to the track's own level. -18 dB puts a
# normalized music file well under a normal speaking voice; the sidechain then
# moves it further down only while the voice is actually present. Tune per track
# with --music-gain rather than editing this.
DEFAULT_MUSIC_GAIN_DB = -18.0

# --music-gain is bounded. +/-60 dB is a factor of 1000 in amplitude — past that
# you have the wrong track, not the wrong gain. The bound exists mostly to keep
# nan, inf and fat-fingered values (-1e9) out of the filter graph: ffmpeg
# happily accepts `volume=nandB` and then renders silence, or accepts `infdB`
# and burns a full render before the loudness check catches it.
MAX_MUSIC_GAIN_DB = 60.0

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
# is not quiet, it is broken, and silently amplifying it would hide that. When
# the clamp fires the script says so out loud rather than shipping a mix that
# never reached the target.
MAX_MASTER_GAIN_DB = 30.0

# "Is this file actually silent?" thresholds, LUFS integrated. ebur128 does not
# report -inf for digital silence — it reports a floor of -70.0 LUFS — so a
# None/-inf check is dead code and both of these have to be thresholds.
# -50 for music: any real track, however quiet, measures far above it.
# -60 for the voice: quieter than that is not a voice track, and the master gain
# needed to rescue it would exceed MAX_MASTER_GAIN_DB anyway, so failing here
# gives a message about the actual problem instead of one about loudness.
SILENT_MUSIC_LUFS = -50.0
SILENT_VOICE_LUFS = -60.0

# Audibility floor for the bed, LUFS: the music file's own integrated loudness
# plus every gain that will be applied to it (--music-gain and the master gain).
#
# This exists because verification CANNOT see a missing bed. The output audio is
# always re-encoded, so "the output's audio differs from the input's" is true
# whether or not a single sample of music made it in — silent music and
# --music-gain -300 both produce a file that passes every post-render check.
# The only place the difference is visible is here, before the render.
#
# The delivered mix sits at LUFS_TARGET (-14). A bed 46 LU under that is below
# the noise floor of AAC at 192 kbit/s and of feed playback on a phone speaker:
# not a quiet bed, a no-op. Deliberately generous rather than a taste gate — the
# default -18 dB bed under a loud (-7 LUFS) input lands near -46 LUFS effective,
# which is quiet but genuinely present, so a stricter floor would reject this
# skill's own default. This catches "no music", not "not enough music".
MIN_EFFECTIVE_BED_LUFS = -60.0

# Duck shape. A fast grab so the duck lands on the first syllable, a slow
# release so the bed rises between sentences rather than pumping between words.
# threshold is a linear amplitude on the sidechain KEY, which is why the master
# gain is applied to the voice BEFORE it feeds the key (see build_command):
# keyed off the raw input, a quiet source never crosses 0.03 and the ducking
# silently no-ops while still reporting itself as "ducked".
DUCK_THRESHOLD = 0.03
DUCK_RATIO = 12
DUCK_ATTACK_MS = 20
DUCK_RELEASE_MS = 400
DUCK_MAKEUP = 1  # unity: the master gain owns level, the compressor does not

# Audio delivery format. 48 kHz because every source in this pack is 48 kHz and
# resampling twice is pointless; AAC 192k because it is transparent for a music
# bed under speech and is what every social platform re-encodes from anyway.
SAMPLE_RATE = 48000
AUDIO_CODEC = "aac"
AUDIO_BITRATE = "192k"

# Every branch of the graph is normalized to the same rate/format before it is
# combined with another. Defined once so 48000 cannot drift between branches.
STD_FORMAT = (f"aresample={SAMPLE_RATE},"
              "aformat=sample_fmts=fltp:channel_layouts=stereo")

# Subprocess timeouts, seconds. A probe or a loudness scan is a linear read of
# one file; 120s covers a long track on slow storage and still catches ffmpeg
# blocking on a stalled network URL or a FIFO. The render is one audio encode
# plus a video stream copy, so 900s is minutes of slack for a long input while
# still bounding a wedged process.
PROBE_TIMEOUT_S = 120
RENDER_TIMEOUT_S = 900

EXIT_VALIDATION = 2
EXIT_RENDER = 3
EXIT_VERIFY = 4

# The two failure messages the executable test reads numbers out of. Each is
# kept beside the regex the test greps with, so rewording one without the other
# breaks the test loudly instead of silently disabling the number check.
MSG_MUSIC_TOO_SHORT = (
    "music is {mdur:.2f}s, video is {vdur:.2f}s — the track is too short by "
    "{short:.2f}s. Supply a longer track (never looped: a loop seam under a "
    "short ad is audible and reads as broken; never silence-padded either).")
RE_MUSIC_TOO_SHORT = r"music is ([\d.]+)s, video is ([\d.]+)s"

MSG_DURATION_DRIFT = (
    "duration drift: video {vdur:.3f}s vs output {odur:.3f}s "
    "(|d|={delta:.3f}s > {tol}s) — a music bed must not change the length of "
    "the cut")
RE_DURATION_DRIFT = r"video ([\d.]+)s vs output ([\d.]+)s"


def die(code, *lines):
    for l in lines:
        print(f"ERROR: {l}", file=sys.stderr)
    sys.exit(code)


def warn(*lines):
    for l in lines:
        print(f"WARNING: {l}", file=sys.stderr)


def run(cmd, timeout, exit_code, phase):
    """Every subprocess in this script goes through here, so every subprocess
    has a timeout. An ffmpeg that never returns is a hung agent, not an error."""
    argv = [str(c) for c in cmd]
    try:
        return subprocess.run(argv, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        die(exit_code, f"{phase} timed out after {timeout}s: "
                       f"{' '.join(argv)[:300]}")


def ff_path(p):
    """A path as ffmpeg/ffprobe should receive it: protocol pinned to `file:`.

    `http:evil.mp3` is a perfectly legal local filename, and without this
    prefix ffmpeg reads it as a URL and goes out to DNS and TCP. Pinning the
    protocol makes every path this script passes a local file, always."""
    return f"file:{p}"


def ffprobe_json(path, exit_code, *args):
    r = run(["ffprobe", "-v", "error", "-of", "json", *args, ff_path(path)],
            PROBE_TIMEOUT_S, exit_code, f"ffprobe on {path}")
    if r.returncode != 0:
        die(exit_code, f"ffprobe failed on {path}: {r.stderr.strip()}")
    if not r.stdout.strip():
        die(exit_code, f"ffprobe returned nothing for {path} — is it a media "
                       "file?")
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError as e:
        die(exit_code, f"ffprobe emitted unparseable JSON for {path}: {e}")


def probe_duration(path, exit_code):
    data = ffprobe_json(path, exit_code, "-show_entries", "format=duration")
    try:
        return float(data["format"]["duration"])
    except (KeyError, ValueError, TypeError):
        die(exit_code, f"{path}: could not read duration")


def probe_streams(path, kind, exit_code):
    """Every stream of one type, carrying only fields this script reads back:
    index/codec_name/channels all appear in the multi-audio rejection message.
    The video call reads the count alone."""
    data = ffprobe_json(path, exit_code, "-select_streams", kind,
                        "-show_entries", "stream=index,codec_name,channels")
    return data.get("streams") or []


def packet_md5(path, kind, exit_code):
    """MD5 over one stream's packets, no decode. A stream-copied track survives
    a remux byte-identical, so input and output normally hash the same (MM2).
    Returns None when the stream cannot be read at all."""
    r = run(["ffmpeg", "-v", "error", "-i", ff_path(path),
             "-map", f"0:{kind}:0", "-c", "copy", "-f", "md5", "-"],
            PROBE_TIMEOUT_S, exit_code, f"packet hash of {path}")
    if r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        if line.startswith("MD5="):
            return line.strip()
    return None


def decoded_frame_hashes(path, exit_code):
    """Per-frame MD5s of the DECODED picture.

    The fallback for a packet-MD5 mismatch. Packet hashes are container-
    sensitive: H.264 lives as Annex-B in MPEG-TS and as length-prefixed AVCC in
    MP4, so a faithful `-c:v copy` from a .ts input produces different packet
    bytes for identical pictures. Decoded frames are container-agnostic — if
    every one of them matches, the picture was repackaged, not re-encoded.

    Honest limit: a *lossless* re-encode would also match here. That is an
    accepted trade — it costs nothing real (the pixels are identical) and the
    alternative is failing every correct output from a non-MP4 source."""
    r = run(["ffmpeg", "-v", "error", "-i", ff_path(path),
             "-map", "0:v:0", "-f", "framemd5", "-"],
            PROBE_TIMEOUT_S, exit_code, f"frame hash of {path}")
    if r.returncode != 0:
        return None
    hashes = [ln.rsplit(",", 1)[-1].strip()
              for ln in r.stdout.splitlines()
              if ln.strip() and not ln.startswith("#")]
    return hashes or None


def measure_loudness(path, exit_code):
    """Integrated LUFS and true peak dBTP via ffmpeg's EBU R128 scanner.

    Both values are read out of the trailing Summary block ONLY. The per-frame
    log lines carry an `I:` field too, and matching one of those would report a
    partial measurement — a 400ms window standing in for the whole file — which
    is enough to set the master gain wrong. No Summary, no measurement."""
    r = run(["ffmpeg", "-v", "info", "-nostats", "-i", ff_path(path),
             "-map", "0:a:0", "-af", "ebur128=peak=true", "-f", "null", "-"],
            PROBE_TIMEOUT_S, exit_code, f"loudness scan of {path}")
    text = r.stderr
    if r.returncode != 0:
        die(exit_code, f"could not scan the loudness of {path}: "
                       f"{text.strip()[-800:]}")
    if "Summary" not in text:
        die(exit_code, f"ebur128 produced no Summary block for {path} — the "
                       "measurement is incomplete and must not be trusted")
    tail = text[text.rfind("Summary"):]

    num = r"(-?(?:\d+(?:\.\d+)?|inf))"
    m = re.search(rf"I:\s*{num}\s*LUFS", tail)
    if not m:
        die(exit_code, f"ebur128 reported no integrated loudness for {path}")
    lufs = -math.inf if m.group(1) == "-inf" else float(m.group(1))

    m = re.search(rf"Peak:\s*{num}\s*dBFS", tail)
    tp = None
    if m:
        tp = -math.inf if m.group(1) == "-inf" else float(m.group(1))
    return lufs, tp


# --------------------------------------------------------------------------
# validate
# --------------------------------------------------------------------------

def _same_file(a, b):
    """True when two paths reach the same inode. Catches hardlink aliases and —
    on a case-insensitive filesystem, i.e. every default macOS volume — a
    case-variant spelling, both of which a resolve()-string compare misses."""
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False


def check_output_path(output, inputs):
    """The output must not be able to reach any input file. Getting this wrong
    truncates the user's source video to a few KB, in place, unrecoverably."""
    out = Path(output)
    if str(out).startswith("-"):
        die(EXIT_VALIDATION,
            f"output path starts with '-': {out} — ffmpeg would read it as an "
            "option. Use ./" + str(out) + " if you really mean the filename.")
    if out.is_dir():
        die(EXIT_VALIDATION, f"output is a directory: {out}")
    parent = out.parent if str(out.parent) else Path(".")
    if not parent.is_dir():
        die(EXIT_VALIDATION, f"output directory does not exist: {parent}")
    for src, label in inputs:
        if _same_file(src, out):
            die(EXIT_VALIDATION,
                f"output {out} is the same file as the {label} ({src}) — "
                "same inode, via a hardlink, a symlink or a case-variant "
                "spelling on a case-insensitive filesystem. Refusing: this "
                "would destroy the input.")
        if os.path.normcase(os.path.realpath(src)) == \
           os.path.normcase(os.path.realpath(out)):
            die(EXIT_VALIDATION, f"output must not overwrite the {label}")


def validate(video, music, output, music_gain):
    """Everything checkable before a render runs (EVALS.md MM1). Collects what
    it can so one bad invocation costs one round-trip."""
    errors = []
    video, music, output = Path(video), Path(music), Path(output)

    if not math.isfinite(music_gain):
        die(EXIT_VALIDATION,
            f"--music-gain {music_gain} is not a finite number — ffmpeg would "
            "accept it into the filter graph and render silence or garbage")
    if abs(music_gain) > MAX_MUSIC_GAIN_DB:
        die(EXIT_VALIDATION,
            f"--music-gain {music_gain:+.1f} dB is outside "
            f"+/-{MAX_MUSIC_GAIN_DB} dB — that is a factor of 1000 in "
            "amplitude; at that point the track is wrong, not the gain")

    if not video.is_file():
        die(EXIT_VALIDATION, f"video not found: {video}")
    if not music.is_file():
        die(EXIT_VALIDATION, f"music not found: {music}")
    check_output_path(output, ((video, "video"), (music, "music")))

    if not probe_streams(video, "v", EXIT_VALIDATION):
        errors.append(f"{video} has no video stream")
    vaudio = probe_streams(video, "a", EXIT_VALIDATION)
    if not vaudio:
        errors.append(f"{video} has no audio stream — a music bed goes UNDER a "
                      "voice track; a silent video needs a soundtrack, not a bed")
    elif len(vaudio) > 1:
        # Mixing only 0:a:0 would silently drop the rest and then certify the
        # result OK, which is worse than refusing. The contract is one voice
        # track; anything else is a decision the operator has to make.
        described = ", ".join(
            f"#{s.get('index')} {s.get('codec_name')} "
            f"{s.get('channels')}ch" for s in vaudio)
        errors.append(
            f"{video} has {len(vaudio)} audio streams ({described}) — this "
            "step mixes exactly one voice track and would silently drop the "
            "others. Pick one with ffmpeg first, then run this.")
    if not probe_streams(music, "a", EXIT_VALIDATION):
        errors.append(f"{music} has no audio stream")
    if errors:
        die(EXIT_VALIDATION, *errors)

    vdur, mdur = (probe_duration(video, EXIT_VALIDATION),
                  probe_duration(music, EXIT_VALIDATION))
    if mdur + MUSIC_SHORTFALL_EPSILON < vdur:
        die(EXIT_VALIDATION, MSG_MUSIC_TOO_SHORT.format(
            mdur=mdur, vdur=vdur, short=vdur - mdur))

    music_lufs, _ = measure_loudness(music, EXIT_VALIDATION)
    if music_lufs < SILENT_MUSIC_LUFS:
        die(EXIT_VALIDATION,
            f"music track is silent: {music} measures {music_lufs:.1f} LUFS "
            f"(below {SILENT_MUSIC_LUFS} LUFS). Mixing it would produce a file "
            "that passes every post-render check and contains no music — the "
            "output's audio is re-encoded either way, so nothing downstream "
            "can tell the difference.")
    return vdur, mdur, music_lufs


# --------------------------------------------------------------------------
# render
# --------------------------------------------------------------------------

def master_gain_db(video):
    """Static gain that lands the finished mix on LUFS_TARGET.

    Without this the output's loudness is simply whatever the input video
    happened to be, and MM4 could only ever be a hope. It is applied to the
    VOICE, ahead of both the mix and the sidechain key, so it scales voice and
    bed by the same factor (the bed's own volume carries the same master gain)
    while the key sees a normalized level. Total loudness math is identical to
    applying it to the mixed bus; what changes is that the ducking threshold
    now means something on a quiet source. Deliberately not `loudnorm` —
    loudnorm's single-pass mode is a dynamic compressor and would fight the
    ducking.

    The bed sits well under the voice and adds under 1 LU to the integrated
    measurement, which is why measuring the voice alone is close enough for a
    +/-2 LU window. The verifier measures the real output anyway.

    Returns (applied_db, requested_db, input_lufs); applied != requested means
    the clamp fired.
    """
    lufs, _ = measure_loudness(video, EXIT_VALIDATION)
    if lufs < SILENT_VOICE_LUFS:
        die(EXIT_VALIDATION,
            f"input voice is silent/near-silent: {video} measures "
            f"{lufs:.1f} LUFS (below {SILENT_VOICE_LUFS} LUFS). A music bed "
            "goes UNDER a voice; a silent video needs a soundtrack, not a bed.")
    requested = LUFS_TARGET - lufs
    applied = max(-MAX_MASTER_GAIN_DB, min(MAX_MASTER_GAIN_DB, requested))
    return applied, requested, lufs


def fade_params(vdur):
    """Tail fade length and its start time. One definition, so the printed plan
    and the command that actually runs cannot disagree."""
    fade = min(FADE_OUT, vdur / 2.0)
    return fade, max(0.0, vdur - fade)


def build_command(video, music, output, vdur, gain_db, duck, master_db):
    """One ffmpeg command. Video copied; audio rebuilt as voice + ducked bed.

    Graph:
      voice: master gain FIRST, then split — one copy into the mix, one as the
             sidechain key, both at delivery level
      music: atrim to the video duration, fade the tail, drop to bed level
             (its own --music-gain plus the same master gain)
      duck:  sidechaincompress pulls the music down while the voice is present
      amix:  sum at unity (normalize=0 — normalize=1 would silently halve both)
      alimiter: hard ceiling so MM4's true-peak bound holds

    Gain staging precedes ducking on purpose. With the master gain at the end
    the key carried the RAW input level, so a -33 dBFS voice never crossed
    DUCK_THRESHOLD and the bed did not move — while the script printed
    "ducked" and, in the same run, applied +24 dB of master gain, i.e. it
    already knew the source was quiet.
    """
    fade, fade_start = fade_params(vdur)
    ceiling = 10 ** ((TRUE_PEAK_CEILING - LIMITER_HEADROOM_DB) / 20.0)
    bed_db = gain_db + master_db

    chains = []
    if duck:
        chains.append(f"[0:a:0]volume={master_db:.2f}dB,{STD_FORMAT},"
                      "asplit=2[voice][key]")
    else:
        chains.append(f"[0:a:0]volume={master_db:.2f}dB,{STD_FORMAT}[voice]")

    chains.append(
        f"[1:a:0]atrim=duration={vdur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=out:st={fade_start:.3f}:d={fade:.3f},"
        f"volume={bed_db:.2f}dB,{STD_FORMAT}[bed]")

    if duck:
        chains.append(
            f"[bed][key]sidechaincompress="
            f"threshold={DUCK_THRESHOLD}:ratio={DUCK_RATIO}:"
            f"attack={DUCK_ATTACK_MS}:release={DUCK_RELEASE_MS}:"
            f"makeup={DUCK_MAKEUP}[ducked]")
        bed = "[ducked]"
    else:
        bed = "[bed]"

    chains.append(f"[voice]{bed}amix=inputs=2:duration=first:normalize=0[mixed]")
    # level=0 disables alimiter's auto-level, which would otherwise normalize
    # the result back up to the ceiling and undo the loudness targeting.
    chains.append(f"[mixed]alimiter=limit={ceiling:.4f}:level=0[aout]")

    # No -shortest: it can drop the final video packet, which would break the
    # MM2 packet-identity guarantee. amix=duration=first already bounds the
    # audio to the voice track, i.e. to the video's own length.
    return ["ffmpeg", "-y", "-i", ff_path(video), "-i", ff_path(music),
            "-filter_complex", ";".join(chains),
            "-map", "0:v:0", "-map", "[aout]",
            # -c:v copy is the MM2 contract: the picture is never re-encoded,
            # which is what makes this safe to run after captions are burned.
            "-c:v", "copy", "-c:a", AUDIO_CODEC, "-b:a", AUDIO_BITRATE,
            "-movflags", "+faststart", ff_path(output)]


def render(cmd, output):
    """Run the render into a temp file beside the output, then os.replace it.

    No final path is ever written directly. A half-written render therefore
    cannot leave a plausible-looking file behind, and — the reason this is not
    just tidiness — an output path that turns out to alias an input can only
    ever destroy a temp file the guards already refused to create.
    """
    out = Path(output)
    parent = out.parent if str(out.parent) else Path(".")
    fd, tmp = tempfile.mkstemp(dir=str(parent), prefix=f".{out.name}.tmp-",
                              suffix=out.suffix)
    os.close(fd)
    # mkstemp creates 0600; match what ffmpeg would have written instead.
    mask = os.umask(0)
    os.umask(mask)
    try:
        os.chmod(tmp, 0o666 & ~mask)
    except OSError:
        pass
    # build_command always puts the destination last; swap it for the temp.
    cmd = list(cmd[:-1]) + [ff_path(tmp)]
    try:
        r = run(cmd, RENDER_TIMEOUT_S, EXIT_RENDER, "ffmpeg render")
        if r.returncode != 0:
            os.unlink(tmp)
            die(EXIT_RENDER, f"ffmpeg failed:\n{r.stderr[-2000:]}")
        os.replace(tmp, out)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# --------------------------------------------------------------------------
# verify
# --------------------------------------------------------------------------

def verify(video, output, exit_code=EXIT_VERIFY):
    """Loud, measured verification (EVALS.md MM1/MM2/MM4/MM5).

    Always returns a 3-tuple (problems, lufs, true_peak); lufs/tp are None when
    there was nothing measurable. What this proves: the duration is unchanged,
    the picture was not re-encoded, the audio is not a byte-copy of the input's,
    and the delivered loudness envelope is in range. What it CANNOT prove is
    that music is audible in the mix — the output's audio is re-encoded on every
    path, so it differs from the input's whether or not any music got in. That
    guarantee is enforced before the render instead (MIN_EFFECTIVE_BED_LUFS).
    """
    problems = []
    if not Path(output).is_file():
        return [f"output not found (or not a regular file): {output}"], None, None

    vdur = probe_duration(video, exit_code)
    odur = probe_duration(output, exit_code)
    delta = abs(odur - vdur)
    if delta > DURATION_TOLERANCE:
        problems.append(MSG_DURATION_DRIFT.format(
            vdur=vdur, odur=odur, delta=delta, tol=DURATION_TOLERANCE))

    v_md5 = packet_md5(video, "v", exit_code)
    o_md5 = packet_md5(output, "v", exit_code)
    if v_md5 is None or o_md5 is None:
        problems.append(f"could not hash a video stream "
                        f"(input: {v_md5}, output: {o_md5})")
    elif v_md5 != o_md5:
        v_frames = decoded_frame_hashes(video, exit_code)
        o_frames = decoded_frame_hashes(output, exit_code)
        if v_frames is not None and v_frames == o_frames:
            print(f"note: video packets differ ({v_md5} vs {o_md5}) but all "
                  f"{len(v_frames)} decoded frames are identical — the stream "
                  "was repackaged into a different container, not re-encoded. "
                  "Expected when the input is not already MP4.")
        else:
            problems.append(
                f"video stream differs from input: {v_md5} vs {o_md5}, and the "
                "decoded frames differ too — the picture was re-encoded rather "
                "than stream-copied (-c:v copy); re-encoding after captions are "
                "burned softens them for no reason")

    va_md5 = packet_md5(video, "a", exit_code)
    oa_md5 = packet_md5(output, "a", exit_code)
    if va_md5 is not None and va_md5 == oa_md5:
        problems.append(
            f"output audio is packet-identical to the input's ({oa_md5}) — no "
            "music was mixed in; this output is just a copy of the input")

    lufs, tp = measure_loudness(output, exit_code)
    if abs(lufs - LUFS_TARGET) > LUFS_TOLERANCE:
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

def fmt(v, spec):
    return format(v, spec) if v is not None else "n/a"


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video", nargs="?", help="finished video (captions burned is fine)")
    ap.add_argument("music", nargs="?", help="music track, >= the video's duration")
    ap.add_argument("output", nargs="?", help="output path")
    ap.add_argument("--music-gain", type=float, default=None, metavar="DB",
                    help=f"bed level in dB (default {DEFAULT_MUSIC_GAIN_DB}, "
                         f"range +/-{MAX_MUSIC_GAIN_DB})")
    ap.add_argument("--no-duck", action="store_true",
                    help="flat bed: skip sidechain ducking under the voice")
    ap.add_argument("--dry-run", action="store_true",
                    help="validate and print the plan; render nothing")
    ap.add_argument("--verify-only", metavar="OUTPUT",
                    help="verify an existing output (requires --video); "
                         "standalone — cannot be combined with render args")
    ap.add_argument("--video", dest="video_opt",
                    help="input video for --verify-only")
    args = ap.parse_args()

    # Verify mode and render mode are exclusive. Silently ignoring positionals
    # or --dry-run under --verify-only means an operator who typed both gets a
    # result for a question they did not ask.
    if args.verify_only:
        clash = []
        if args.video or args.music or args.output:
            clash.append("positional video/music/output arguments")
        if args.dry_run:
            clash.append("--dry-run")
        if args.no_duck:
            clash.append("--no-duck")
        if args.music_gain is not None:
            clash.append("--music-gain")
        if clash:
            ap.error("--verify-only is a standalone mode and cannot be "
                     "combined with " + ", ".join(clash))
    elif args.video_opt:
        ap.error("--video only applies to --verify-only; pass the input video "
                 "as the first positional argument instead")

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
              f"identical (not re-encoded), audio rebuilt (not a copy of the "
              f"input's), {fmt(lufs, '.1f')} LUFS / {fmt(tp, '.1f')} dBTP")
        return

    if not (args.video and args.music and args.output):
        ap.error("video, music and output are required (or use --verify-only)")

    music_gain = (DEFAULT_MUSIC_GAIN_DB if args.music_gain is None
                  else args.music_gain)
    vdur, mdur, music_lufs = validate(args.video, args.music, args.output,
                                      music_gain)
    duck = not args.no_duck
    master_db, requested_db, in_lufs = master_gain_db(args.video)
    clamped = abs(requested_db - master_db) > 0.05
    if clamped:
        warn(f"master gain clamped: {requested_db:+.1f} dB is needed to reach "
             f"{LUFS_TARGET} LUFS from {in_lufs:.1f} LUFS, but only "
             f"{master_db:+.1f} dB was applied (MAX_MASTER_GAIN_DB "
             f"{MAX_MASTER_GAIN_DB}). The output will NOT hit the loudness "
             "target and verification is expected to fail — fix the input's "
             "level instead.")

    # The one guarantee verification cannot make (see MIN_EFFECTIVE_BED_LUFS).
    eff_bed = music_lufs + music_gain + master_db
    if eff_bed < MIN_EFFECTIVE_BED_LUFS:
        die(EXIT_VALIDATION,
            f"music inaudible at these gains: the bed would land at "
            f"{eff_bed:.1f} LUFS (track {music_lufs:.1f} LUFS "
            f"{music_gain:+.1f} dB --music-gain {master_db:+.1f} dB master), "
            f"below the {MIN_EFFECTIVE_BED_LUFS} LUFS audibility floor. "
            "Nothing after the render can detect this, so it is refused here.")

    cmd = build_command(args.video, args.music, args.output, vdur,
                        music_gain, duck, master_db)

    fade, _ = fade_params(vdur)
    print(f"video: {args.video} ({vdur:.2f}s, {in_lufs:.1f} LUFS in)")
    print(f"music: {args.music} ({mdur:.2f}s, {music_lufs:.1f} LUFS) — trimmed "
          f"to {vdur:.2f}s, {fade:.1f}s fade-out")
    print(f"bed:   {music_gain:+.1f} dB, "
          f"{'ducked under the voice' if duck else 'FLAT (--no-duck)'}, "
          f"{eff_bed:.1f} LUFS effective")
    print(f"master:{master_db:+.1f} dB onto {LUFS_TARGET} LUFS, "
          f"limited to {TRUE_PEAK_CEILING} dBTP")

    if args.dry_run:
        print("\nDRY RUN — command that would run (the real run writes to a "
              "temp file beside the output and moves it into place):")
        print("  " + " ".join(cmd))
        return

    render(cmd, args.output)

    problems, lufs, tp = verify(args.video, args.output)
    if problems:
        if any(p.startswith("integrated loudness") for p in problems):
            problems = list(problems) + [
                f"the bed was mixed at --music-gain {music_gain:+.1f} dB "
                f"({eff_bed:.1f} LUFS effective) — a loud bed pulls the "
                "integrated measurement with it, so try a lower --music-gain "
                "before anything else"]
            if clamped:
                problems.append(
                    f"and the master gain was clamped ({requested_db:+.1f} dB "
                    f"needed, {master_db:+.1f} dB applied), so this output was "
                    "never going to reach the target")
        die(EXIT_VERIFY, *problems,
            f"the bad output was kept for inspection: {args.output}")
    print(f"OK: {args.output} — duration matches within {DURATION_TOLERANCE}s, "
          f"video stream packet-identical to input (captions untouched), "
          f"loudness {lufs:.1f} LUFS (target {LUFS_TARGET} "
          f"+/-{LUFS_TOLERANCE}), true peak {fmt(tp, '.1f')} dBTP")


if __name__ == "__main__":
    main()
