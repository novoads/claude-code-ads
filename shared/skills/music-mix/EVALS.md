# Evals — music mix

Written **before** the skill. The reference edit this pack reproduces laid a music bed
under the finished video as its last step — its export folder held a `final-mixes`
directory with `lofi-jazzy` and `lofi-warm` versions of the same cut (2026-08-04
video-parity experiment, `VIDEO-PARITY-EXPERIMENT.md`). Nothing in the pack did that
yet. This skill is the missing last step: base video → b-roll overlay → burned captions
→ **music bed**.

Being last is what shapes the whole contract. Everything upstream has already been
rendered and approved, so this step must be able to run over a finished, caption-burned
file without touching a single pixel of it (MM2). That is why the video stream is
stream-copied, exactly inverting the sibling skill — `broll-overlay` copies the audio
and re-encodes the picture; this one copies the picture and re-encodes the audio.

MM1, MM2, MM4 and MM5 are mechanical and covered by the executable test
(`scripts/test_music_mix.py`, synthetic fixtures, no credits). MM3 is mechanical too,
measured on a fixture whose voice track is deliberately gapped. Track *choice* — genre,
mood, how many variants — is judgment and lives in SKILL.md.

---

## MM1 — Output duration equals input video duration, and music is never looped

**Scenario.** A finished 15s vertical ad. The user supplies (or generates) a music
track. The skill lays it underneath.

**Why it matters.** Music is a bed, not content: it may not extend, pad or shorten the
cut. Every upstream step in this pack holds the same invariant (`broll-overlay` OV1),
and it would be absurd for the last step to be the one that breaks it.

**Assertions.**
- `duration(output) == duration(video)` within 0.05s (~1.5 frames at 30fps; the
  tolerance absorbs container rounding on the re-encoded audio track, nothing else).
- Music **longer** than the video → trimmed to the video's duration, with a **1.5–2s
  fade-out** at the tail. A bed that stops dead on the last frame reads as a dropout;
  the fade is what makes the ending sound intentional.
- Music **shorter** than the video → **hard error** naming both durations ("music is
  11.20s, video is 15.00s — supply a longer track"). Never looped, never padded with
  silence. Same no-loop philosophy as `broll-overlay` OV4: a loop seam under a 15s ad
  is audible and reads as broken.
- Validation happens before any ffmpeg render: a too-short track costs zero render time.

**Fails if:** the output is longer or shorter than the input beyond tolerance, a short
track is looped or silence-padded, or the music ends abruptly with no fade.

## MM2 — The video stream is copied, never re-encoded

**Scenario.** The input already has captions burned in (the normal case — music is the
step after captions).

**Why it matters.** This is the entire reason the step is safe to run last. Captions
were burned by re-encoding the picture; re-encoding it a second time to add music would
soften the caption edges and spend generation-quality for nothing, since the picture is
not being edited at all. Copying it makes the guarantee absolute rather than "probably
fine at crf 18".

**Assertions.**
- The render uses `-c:v copy`. No scale, no filter, no encoder touches the video track.
- The output's video packets hash **identical** to the input's — verified by packet MD5,
  the same instrument `broll-overlay` OV2 uses to prove its audio was untouched, pointed
  at the other stream.
- The check runs inside the script after every render, not as an optional extra step.

**Fails if:** the output's video stream differs from the input's by a single packet, or
the script reports success without having hashed it.

## MM3 — Music ducks under the voice

**Scenario.** The bed plays under a talking-head ad. The voice starts, stops between
sentences, and starts again.

**Why it matters.** A flat bed at a fixed level either buries the voice or is inaudible.
The fix is ducking — sidechain compression keyed by the voice — which is what makes the
music feel like it was mixed rather than dropped on top. It is also why this is a script
and not an ffmpeg one-liner a user could plausibly write.

**Assertions.**
- The music is compressed with `sidechaincompress` keyed by the voice track, unless the
  user explicitly passes `--no-duck`.
- Mechanically: measure the music's own level (music-only render of the same graph)
  during voice-active windows and during voice gaps. **Music during voice ≥ 6 dB below
  music during gaps.** 6 dB is one clear halving of perceived level — enough to be
  audible as ducking rather than as measurement noise.
- The voice's own level is not altered: the voice enters the mix at unity gain and only
  the music moves.
- `--no-duck` produces a bed with no such delta — the escape hatch is real, not cosmetic.

**Fails if:** the delta is under 6 dB with ducking on, the voice is attenuated, or
`--no-duck` still ducks.

## MM4 — Loudness lands in the documented target range

**Scenario.** The finished mix is uploaded to TikTok / Reels / Shorts.

**Why it matters, stated once so nobody treats the numbers as voodoo.** Every one of
those platforms normalizes playback loudness: material louder than their target gets
turned **down**, and material quieter than their target is simply played quieter and
sounds weak next to everything else in the feed. So there is a range to hit, and both
directions of missing it cost something. The platforms publish targets clustered around
**−14 LUFS** integrated, which is the target used here, with **±2 LU** of tolerance
because a 15s ad's integrated measurement is noisy over so short a window. True peak is
held at **≤ −1 dBTP** so that lossy transcoding on the platform's side — which can push
reconstructed peaks above the sample peak — does not clip.

**Assertions.**
- Output integrated loudness measured with **ffmpeg `ebur128`** sits in **−14 ±2 LUFS**.
- Output true peak ≤ **−1 dBTP**, enforced in the graph by a limiter, not by luck.
- The measured value is printed on success — the operator sees the number, not a claim.
- The target and its tolerance are named constants in the script with this reasoning
  attached, so a future change is a decision rather than a tweak.

**How the target is actually reached.** Mixing alone cannot satisfy this: a bed added
under a voice leaves the output at whatever loudness the input video happened to be, so
the assertion would pass or fail on the input's mastering rather than on anything this
skill did. The script therefore measures the input's loudness during validation and
applies **one static gain to the mixed bus**. Static is the load-bearing word — it
scales voice and bed by the identical factor, so the voice is still untouched relative
to the music and the MM3 ducking ratio is arithmetically unchanged. `loudnorm` was
rejected for this: in single-pass mode it is a dynamic compressor and would fight the
ducking it is layered on top of.

**Fails if:** integrated loudness falls outside the range, true peak exceeds −1 dBTP, or
the script asserts loudness it did not measure.

## MM5 — The verifier catches a bad or faked output

**Scenario.** The render "succeeded", or a file from an old session is handed over, and
something is wrong: it is truncated, its picture was quietly re-encoded, or no music was
ever mixed in and the file is just a copy of the input.

**Why it matters.** All three failures look fine in a file listing. The last one is the
sneakiest: a step that silently no-ops produces a perfectly playable video, and the only
evidence is that the audio is unchanged. A verifier that cannot catch a no-op is worse
than no verifier, because it certifies it.

**Assertions.**
- `--verify-only OUTPUT --video INPUT` is a separate, re-runnable mode, usable on any
  existing file including one from an earlier session.
- Wrong duration → nonzero exit, message carries **both measured durations**.
- Video packets not identical to the input's → nonzero exit, both hashes named.
- Output audio identical to the input's audio → nonzero exit saying no music was mixed.
- Loudness outside the MM4 range → nonzero exit with the measured LUFS.
- A good output still passes, so the verifier is not failing everything indiscriminately.

**Fails if:** any of the three tampered outputs passes, or a failure message omits the
measured values.

---

## Notes on evidence strength

- MM1 and MM2 are **contract-level**: duration invariance is inherited from the pack's
  founding failure (`broll-overlay` OV1, the 2026-08-03 stitch that shipped 24s for a
  15s base), and video-stream-copy is mechanically verifiable rather than a taste call.
- MM3's **6 dB** threshold is a test threshold, not a mix spec — it is set low enough
  that any real ducking clears it, so the test detects "ducking is wired up", not
  "ducking is tasteful". The mix's actual ratio/threshold defaults are a taste call made
  once here so behavior is defined rather than improvised per run.
- MM4's **−14 LUFS / −1 dBTP** is the widely published consumer-streaming and social
  cluster, not a measurement taken from the reference edit — the reference's export was
  never loudness-analyzed. Documented as a defensible default with the reasoning
  attached; a client with a delivery spec overrides it.
- MM1's no-loop rule and the 1.5–2s fade are taste calls, made once, for the same reason
  the sibling made its no-loop call: defined behavior beats per-run improvisation.
