#!/usr/bin/env python3
"""Lay the converted take over the original picture, fencing everything that is
not speech, and verify the result before anyone watches it.

    python3 assemble-voice-change.py --source ad.mp4 --converted take.mp3 \\
        --speech-start 2.19 [--speech-end 14.86] [--out final.mp4] [--json]

WHAT IT BUILDS. One audio timeline, in three pieces:

    [0 .. speech-start)      the ORIGINAL track, untouched
    [speech-start .. end]    the CONVERTED take
    (speech-end .. EOF]      the ORIGINAL track, untouched

then muxes it against the source's video stream, copied bit for bit.

WHY THE FENCE. The endpoint converts every sound in the source, not just the
talking. A sound effect, a music bed or room tone that goes in comes back as
vocal noise -- on this skill's own reference ad, a glass-shatter effect in the
first second and a half. The effect exists in the original track and there is no
reason to re-perform it, so the original supplies it and the converted take
supplies only the speech. Fencing is the difference between a re-voiced ad and a
damaged one.

WHY IT STAYS IN SYNC. Speech-to-speech preserves timing frame-accurately, so the
converted take lies on the same timeline as the source. Every segment is cut and
placed at its own original timestamp, nothing is stretched, and the video stream
is copied rather than re-encoded. A crossfade would be the one thing that breaks
this: `acrossfade` SHORTENS the total by its own duration, sliding every later
word out from under the lips. The seams get 20 ms equal-length fades instead,
which cost no time at all.

LOUDNESS. The endpoint already matches the take to the source's whole-file mean.
This script measures both again over the SPEECH SPAN, which is the finer
comparison the fence makes possible -- a loud effect in the head pulls a
whole-file mean around -- and corrects the take before the mux when the two are
more than the tolerance apart. Then it re-measures the FINISHED file against the
source and fails if the answer is not what it claims. Exit code 2 means the file
was written but is out of tolerance: read the numbers, do not ship it blind.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys

import voiceprint

TOLERANCE_DB = 1.5  # the endpoint's own loudness-match contract
SEAM_FADE = 0.02  # 20 ms, equal in and out, so the total length never moves


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write(p.stderr[-2000:] + "\n")
        raise SystemExit(f"ffmpeg failed: {' '.join(cmd[:6])} ...")
    return p


def has_video(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v",
         "-show_entries", "stream=codec_type", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    return "video" in out.stdout


def audio_duration_seconds(path):
    """Duration of the AUDIO stream, not of the container.

    `format=duration` on a muxed mp4 is driven by the longest stream, and the
    video here is copied from the source bit for bit -- so the container always
    reports the source's length whatever the audio does. Measured: a take short
    by 0.20s (under the note threshold) produced `audio,8.41 / video,8.60` and
    the script printed PASS. This function is what makes the closing check
    measure the object it wrote rather than the picture it copied.

    Falls back to the container when the stream carries no duration of its own,
    which is the honest answer for a raw mp3.
    """
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=duration", "-of", "json", str(path)],
        capture_output=True, text=True,
    ).stdout
    try:
        return float(json.loads(out)["streams"][0]["duration"])
    except (ValueError, KeyError, IndexError, TypeError):
        return voiceprint.duration_seconds(path)


def audio_shape(path):
    """(channels, sample_rate) of the first audio stream.

    Read as JSON and looked up BY NAME. `-of csv` prints the fields in the
    stream's own order, not the order they were asked for, so the csv form
    silently returned (sample_rate, channels) here and built `aresample=2` --
    a graph that ran, produced a file, and measured 12 dB down.
    """
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=channels,sample_rate", "-of", "json", str(path)],
        capture_output=True, text=True,
    ).stdout
    try:
        s = json.loads(out)["streams"][0]
        return int(s["channels"]), int(s["sample_rate"])
    except (ValueError, KeyError, IndexError):
        raise SystemExit(f"could not read an audio stream from {path}")


def conform(take_ch, take_sr, src_ch, src_sr):
    """Filters that put the take in the SOURCE's channel layout and rate, at unity gain.

    This is not housekeeping, it is a 3 dB bug. The endpoint returns MONO; an ad's
    track is usually stereo; and ffmpeg's default mono-to-stereo rematrix drops the
    level by 1/sqrt(2). Measured on the acceptance run: a take that sat 0.6 dB under
    its source came out of the mux 3.4 dB under it, mean AND peak, with every
    segment boundary correct and nothing in the graph asking for a gain change.
    `pan` states the matrix instead of accepting the default, so what goes in comes
    out at the level it was measured at.
    """
    out = []
    if take_sr != src_sr:
        out.append(f"aresample={src_sr}")
    if take_ch == src_ch:
        return out
    if take_ch == 1 and src_ch == 2:
        out.append("pan=stereo|c0=c0|c1=c0")
    elif take_ch == 2 and src_ch == 1:
        out.append("pan=mono|c0=0.5*c0+0.5*c1")
    else:
        out.append(f"aformat=channel_layouts={'mono' if src_ch == 1 else 'stereo'}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True)
    ap.add_argument("--converted", required=True, help="the mp3 POST /v1/voice-changes returned")
    ap.add_argument("--speech-start", type=float, required=True,
                    help="seconds; check-speech.py reports it as speechStart")
    ap.add_argument("--speech-end", type=float, default=None,
                    help="seconds; omit to run the converted take to the end")
    ap.add_argument("--out", default=None)
    ap.add_argument("--tolerance-db", type=float, default=TOLERANCE_DB)
    ap.add_argument("--no-match-loudness", action="store_true",
                    help="report the loudness gap without correcting it")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            raise SystemExit(f"{tool} is not on PATH. This step is local ffmpeg work.")
    for flag, path in (("--source", args.source), ("--converted", args.converted)):
        try:
            voiceprint.require_readable(path)
        except voiceprint.Unreadable as exc:
            raise SystemExit(f"{flag}: {exc}")
        if not voiceprint.has_audio_stream(path):
            raise SystemExit(f"{flag}: {path} has no audio stream, so there is nothing "
                             "to fence or to lay down.")
    for flag, value in (("--speech-start", args.speech_start), ("--speech-end", args.speech_end)):
        if value is not None and not math.isfinite(value):
            raise SystemExit(f"{flag} must be a real number of seconds, not {value}.")

    src_dur = voiceprint.duration_seconds(args.source)
    take_dur = voiceprint.duration_seconds(args.converted)
    video = has_video(args.source)
    out = args.out or os.path.splitext(args.source)[0] + "-revoiced" + (".mp4" if video else ".mp3")
    start = max(0.0, args.speech_start)
    end = args.speech_end if args.speech_end is not None else src_dur
    end = min(end, src_dur)
    notes = []

    if abs(take_dur - src_dur) > 0.25:
        notes.append(
            f"the take is {take_dur:.2f}s against a {src_dur:.2f}s source, a "
            f"{take_dur - src_dur:+.2f}s difference. Speech-to-speech preserves timing, so "
            "a gap this size means the take was made from a different cut. Check before shipping.")
    if start >= end:
        raise SystemExit(f"--speech-start {start} is not before --speech-end {end}")
    # The take is cut at the SOURCE's own timestamps, because speech-to-speech puts
    # both on one timeline. A take that does not reach `end` is therefore not a
    # short take, it is a DIFFERENT timeline -- typically a conversion of a CUT,
    # whose t=0 is the source's speechStart. Laying that in at source timestamps
    # slides every word by the length of the head and desyncs the lips, which is
    # the one thing this skill promises not to do. Refuse before writing anything:
    # convert the whole source, or pass the same cut as --source.
    if take_dur < end - 0.05:
        raise SystemExit(
            f"--converted runs {take_dur:.2f}s but the fence needs it through {end:.2f}s. "
            "The take and the source must be the same timeline: convert the WHOLE source, "
            "or pass the cut you converted as --source too.")

    src_span = voiceprint.mean_volume_db(args.source, start, end)
    take_span = voiceprint.mean_volume_db(args.converted, start, end)
    gap = src_span - take_span
    gain = 0.0
    if abs(gap) > args.tolerance_db and not args.no_match_loudness:
        gain = gap

    # One graph: head and tail from the source's own track, body from the take,
    # each cut at its real timestamp and concatenated in order.
    src_ch, src_sr = audio_shape(args.source)
    take_ch, take_sr = audio_shape(args.converted)
    body = conform(take_ch, take_sr, src_ch, src_sr) + \
        [f"atrim={start}:{end}", "asetpts=N/SR/TB"]
    if gain:
        body.append(f"volume={gain:.2f}dB")
    # A fade belongs to a SEAM, so it is emitted only where a seam exists. The
    # fade-in used to be unconditional: with --speech-start 0 there is no head to
    # join, and the ad opened on a 20 ms ramp up from silence the source never
    # had (measured -17 dB into the first frames).
    has_head = start > 0.01
    has_tail = end < src_dur - 0.01
    if has_head:
        body.append(f"afade=t=in:st=0:d={SEAM_FADE}")
    if has_tail:
        body.append(f"afade=t=out:st={max(0.0, end - start - SEAM_FADE)}:d={SEAM_FADE}")
    parts, labels = ["[1:a]" + ",".join(body) + "[body]"], []
    if has_head:
        parts.append(
            f"[0:a]atrim=0:{start},asetpts=N/SR/TB,"
            f"afade=t=out:st={max(0.0, start - SEAM_FADE)}:d={SEAM_FADE}[head]")
        labels.append("[head]")
    labels.append("[body]")
    if has_tail:
        parts.append(f"[0:a]atrim={end},asetpts=N/SR/TB,"
                     f"afade=t=in:st=0:d={SEAM_FADE}[tail]")
        labels.append("[tail]")
    graph = ";".join(parts) + ";" + "".join(labels) + f"concat=n={len(labels)}:v=0:a=1[a]"

    cmd = ["ffmpeg", "-v", "error", "-y", "-i", args.source, "-i", args.converted,
           "-filter_complex", graph, "-map", "[a]"]
    if video:
        cmd += ["-map", "0:v", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k"]
    else:
        cmd += ["-c:a", "libmp3lame", "-b:a", "192k"]
    cmd += ["-movflags", "+faststart", out] if video else [out]
    run(cmd)

    src_whole = voiceprint.mean_volume_db(args.source)
    out_whole = voiceprint.mean_volume_db(out)
    out_dur = voiceprint.duration_seconds(out)
    out_audio_dur = audio_duration_seconds(out)
    delta = out_whole - src_whole
    ok_loud = abs(delta) <= args.tolerance_db
    ok_dur = abs(out_dur - src_dur) <= 0.05 and abs(out_audio_dur - src_dur) <= 0.05
    if abs(out_audio_dur - src_dur) > 0.05:
        notes.append(
            f"the finished AUDIO runs {out_audio_dur:.2f}s under a {src_dur:.2f}s picture, "
            "so the ad ends on silence. The take did not cover the span it was fenced to.")

    result = {
        "out": out, "hasVideo": video,
        "sourceDurationSeconds": round(src_dur, 3),
        "outputDurationSeconds": round(out_dur, 3),
        "outputAudioDurationSeconds": round(out_audio_dur, 3),
        "speechSpan": [round(start, 2), round(end, 2)],
        "sourceSpanMeanDb": src_span, "takeSpanMeanDb": take_span,
        "gainAppliedDb": round(gain, 2),
        "sourceMeanDb": src_whole, "outputMeanDb": out_whole,
        "loudnessDeltaDb": round(delta, 2), "toleranceDb": args.tolerance_db,
        "loudnessWithinTolerance": ok_loud, "durationPreserved": ok_dur,
        "notes": notes,
    }
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"wrote {out}")
        print(f"  fence         original 0-{start:.2f}s + converted {start:.2f}-{end:.2f}s"
              + (f" + original {end:.2f}-{src_dur:.2f}s" if end < src_dur - 0.01 else ""))
        print(f"  speech span   source {src_span:+.1f} dB, take {take_span:+.1f} dB, "
              f"gain applied {gain:+.2f} dB")
        print(f"  whole file    source {src_whole:+.1f} dB, output {out_whole:+.1f} dB, "
              f"delta {delta:+.2f} dB (tolerance {args.tolerance_db})")
        print(f"  duration      {src_dur:.2f}s -> {out_dur:.2f}s "
              f"(audio stream {out_audio_dur:.2f}s)")
        for n in notes:
            print(f"  NOTE  {n}")
        print("  " + ("PASS" if ok_loud and ok_dur else "OUT OF TOLERANCE"))
    if not (ok_loud and ok_dur):
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
