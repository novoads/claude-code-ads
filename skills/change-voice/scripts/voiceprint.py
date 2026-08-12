"""Shared audio measurement for the change-voice skill. python3 + ffmpeg only.

Imported by check-speech.py and match-voice.py, which sit beside it (Python puts a
script's own directory on sys.path, so `import voiceprint` works from any cwd).

Everything here is measurement, not judgement: it returns numbers and the callers
decide. The one number that matters most is `f0_median` -- the pitch of the voice
in the source -- because casting a replacement voice by its written description
alone miscasts. That is measured, not guessed.

Method, and why each choice:

* Decode to 16 kHz mono PCM through ffmpeg. One resampler, no format branches, and
  the same numbers whether the input is an .mp4, an .mp3 or a preview URL's .mp3.
* 32 ms frames, 16 ms hop. A pitch period at the bottom of the human range (70 Hz)
  is 14 ms, so a 32 ms frame holds at least two of them, which is the minimum an
  autocorrelation can see a period in.
* NORMALIZED autocorrelation over the overlapping region only. The plain sum falls
  off with lag because fewer terms are added, which biases the peak toward short
  lags -- an octave error that reads as a voice half its real pitch.
* Only frames within 16 dB of the loudest frame are measured. Room tone has no
  pitch and would otherwise contribute noise to the distribution.
* At most 400 frames, spread evenly. This bounds the work at roughly half a second
  of CPU whatever the source's length, and a spread sample is what a distribution
  wants anyway.
"""

import array
import math
import subprocess

SR = 16000
FRAME = 512  # 32 ms
HOP = 256  # 16 ms
MAX_FRAMES = 400
F0_LO, F0_HI = 70.0, 350.0  # the human speaking range, low male to high child
VOICED_R = 0.45  # normalized autocorrelation peak that counts as periodic
LOUD_REL = 0.15  # -16 dB relative to the loudest frame


class NoAudio(Exception):
    """The file has no decodable audio at all."""


class Unreadable(Exception):
    """ffprobe could not open the file at all: it is missing, unreadable, or not
    a container. A DIFFERENT answer from "this has no audio", and kept different
    on purpose -- the two have opposite fixes."""


def require_readable(path):
    """Raise Unreadable unless ffprobe can open `path`. Every entry point calls
    this first.

    Without it a typo'd path is indistinguishable from a real file with nothing
    in it, because ffprobe writes its complaint to stderr and returns an empty
    stdout either way. The three callers each read that emptiness as an answer
    rather than as a failure, and each said something wrong: the speech check
    reported `no audio stream at all` and exit 2 -- which SKILL.md's Gate 1 tells
    the agent to relay as "this file has no talking voice in it" -- while the
    assembly step blamed `--speech-start` for being past a duration of 0.00.
    A wrong diagnosis costs more than a crash: it sends someone to re-record a
    file that was fine.
    """
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=format_name",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        raise Unreadable(
            f"could not read {path} -- check the path, and that it is an audio "
            "or video file ffmpeg can open")


def has_audio_stream(path):
    """True when ffprobe reports at least one audio stream. Cheap, no decode.

    Answers the question honestly only for a file that OPENS: call
    require_readable() first, or a missing path answers False here and reads as
    a file with no audio in it."""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a",
         "-show_entries", "stream=codec_type", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    return "audio" in out.stdout


def duration_seconds(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


def mean_volume_db(path, start=None, end=None):
    """ffmpeg volumedetect mean_volume, in dBFS, over the whole file or one span.
    The endpoint matches loudness on this same measure, so the assembly step
    verifies against the same instrument that produced the take."""
    cmd = ["ffmpeg", "-v", "info"]
    if start is not None:
        cmd += ["-ss", str(start)]
    if end is not None:
        cmd += ["-to", str(end)]
    cmd += ["-i", str(path), "-af", "volumedetect", "-f", "null", "-"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    for line in p.stderr.splitlines():
        if "mean_volume:" in line:
            return float(line.split("mean_volume:")[1].strip().split()[0])
    raise NoAudio(f"volumedetect reported no mean_volume for {path}")


def decode(path, start=None, length=None):
    cmd = ["ffmpeg", "-v", "error"]
    if start is not None:
        cmd += ["-ss", str(start)]
    if length is not None:
        cmd += ["-t", str(length)]
    cmd += ["-i", str(path), "-vn", "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"]
    p = subprocess.run(cmd, capture_output=True)
    samples = array.array("h")
    samples.frombytes(p.stdout)
    if not len(samples):
        raise NoAudio(f"no decodable audio in {path}")
    return samples


def _f0(seg):
    """(hz, peak) for one frame, by normalized autocorrelation. hz is 0 unvoiced."""
    n = len(seg)
    mean = sum(seg) / n
    x = [v - mean for v in seg]
    running = [0.0] * (n + 1)
    for i, v in enumerate(x):
        running[i + 1] = running[i] + v * v
    lag_min, lag_max = int(SR / F0_HI), min(int(SR / F0_LO), n - 1)
    best_r, best_lag = 0.0, 0
    for lag in range(lag_min, lag_max + 1):
        overlap = n - lag
        c = 0.0
        for k in range(overlap):
            c += x[k] * x[k + lag]
        denom = math.sqrt(running[overlap] * (running[n] - running[lag]))
        if denom <= 0:
            continue
        r = c / denom
        if r > best_r:
            best_r, best_lag = r, lag
    return (SR / best_lag if best_lag else 0.0), best_r


def measure(path, start=None, length=None):
    """Every number the two callers need, from one decode.

    Returns a dict: durationSeconds, framesMeasured, voicedFraction, f0Median,
    f0Q1, f0Q3, f0Iqr, peakDb, loudFraction, speechStart, speechEnd.

    `voicedFraction` is the share of measured (loud) frames that are periodic in
    the human speaking range. It is the feature that separates one talking voice
    from a music bed: a voice is periodic almost everywhere it is loud, while a
    mix of instruments has an autocorrelation peak that jumps between notes and
    harmonics and fails the test on a large minority of frames.
    """
    samples = decode(path, start, length)
    total = len(samples)
    starts = list(range(0, max(total - FRAME, 1), HOP))
    rms = []
    for i in starts:
        seg = samples[i:i + FRAME]
        acc = 0
        for v in seg:
            acc += v * v
        rms.append(math.sqrt(acc / len(seg)))
    peak = max(rms) if rms else 0.0
    result = {
        "durationSeconds": round(total / SR, 3),
        "framesMeasured": 0,
        "voicedFraction": 0.0,
        "f0Median": 0.0, "f0Q1": 0.0, "f0Q3": 0.0, "f0Iqr": 0.0,
        "peakDb": -99.0, "loudFraction": 0.0,
        "speechStart": None, "speechEnd": None,
    }
    if peak <= 0:
        return result
    result["peakDb"] = round(20 * math.log10(peak / 32768.0), 1)
    threshold = peak * LOUD_REL
    loud = [i for i, v in enumerate(rms) if v >= threshold]
    result["loudFraction"] = round(len(loud) / len(rms), 3)
    if not loud:
        return result
    step = max(1, len(loud) // MAX_FRAMES)
    sampled = loud[::step]
    voiced_idx, f0s = [], []
    for i in sampled:
        hz, r = _f0(samples[starts[i]:starts[i] + FRAME])
        if r >= VOICED_R and hz:
            voiced_idx.append(i)
            f0s.append(hz)
    result["framesMeasured"] = len(sampled)
    result["voicedFraction"] = round(len(f0s) / len(sampled), 3)
    if len(f0s) >= 4:
        ordered = sorted(f0s)
        q1 = ordered[len(ordered) // 4]
        q3 = ordered[(3 * len(ordered)) // 4]
        result["f0Median"] = round(ordered[len(ordered) // 2], 1)
        result["f0Q1"], result["f0Q3"] = round(q1, 1), round(q3, 1)
        result["f0Iqr"] = round(q3 - q1, 1)
    first = _sustained(samples, starts, voiced_idx)
    last = _sustained(samples, starts, list(reversed(voiced_idx)))
    if first is not None:
        result["speechStart"] = round(_walk(samples, starts, first, -1), 2)
    if last is not None:
        result["speechEnd"] = round(_walk(samples, starts, last, 1) + FRAME / SR, 2)
    return result


RUN_FRAMES = 8  # 128 ms
RUN_MIN_VOICED = 6


def _sustained(samples, starts, candidates):
    """The first candidate that is part of a SUSTAINED voiced run.

    An isolated periodic frame is not speech: a glass-shatter effect, a door slam
    and a synth stab all produce one. A syllable does not -- it holds for at least
    a tenth of a second. Without this the reported onset of a real ad landed at
    0.58s, inside its opening sound effect, instead of at 2.2s where the actor
    starts talking, and an assembly fenced on it would have overwritten the effect
    with converted silence.
    """
    for i in candidates:
        voiced = 0
        for k in range(RUN_FRAMES):
            j = i + k
            if j >= len(starts):
                break
            hz, r = _f0(samples[starts[j]:starts[j] + FRAME])
            if r >= VOICED_R and hz:
                voiced += 1
        if voiced >= RUN_MIN_VOICED:
            return i
    return None


def _walk(samples, starts, index, direction):
    """Walk one frame at a time from a confirmed voiced frame toward the edge of
    its own run, so a coarse sample step does not blur the boundary."""
    i = index
    while 0 <= i + direction < len(starts):
        hz, r = _f0(samples[starts[i + direction]:starts[i + direction] + FRAME])
        if r < VOICED_R or not hz:
            break
        i += direction
    return starts[i] / SR


def semitones(a, b):
    """Distance between two pitches, in semitones. Pitch is heard on a log scale,
    so 40 Hz apart at the bottom of a male range and 40 Hz apart at the top of a
    female one are not the same distance to an ear."""
    if a <= 0 or b <= 0:
        return float("inf")
    return abs(12.0 * math.log(a / b, 2))
