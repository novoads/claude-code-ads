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
(`scripts/test_music_mix.py`, 15 cases, synthetic fixtures, no credits). MM3 is mechanical
too, measured on fixtures whose voice track is deliberately gapped — at a normal level and
at a quiet one. Track *choice* — genre, mood, how many variants — is judgment and lives in
SKILL.md.

**MM6 is deliberately not mechanical.** It was added 2026-08-04 when music generation
moved onto the Novoads API, and it asserts against the skill's own text plus one live
run: that "add music" reaches a finished mix with `NOVOADS_API_KEY` as the *only*
credential. The mixing script is untouched by that change — it takes an mp3 off the disk
whichever source produced it — so there is nothing in it to assert on.

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
- "Shorter" is **strict**, with its own epsilon (`MUSIC_SHORTFALL_EPSILON`, 0.01s of
  probe rounding) — deliberately *not* the 0.05s output-duration tolerance. Reusing
  that one let a 5.96s track under a 6.00s video pass, which is 40ms of silent tail:
  exactly the padding this assertion forbids. Two different questions, two constants.
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
- Mechanically: measure the bed's own level **inside the real finished output**, during
  voice-active windows and during voice gaps. The fixtures are frequency-separated for
  this — the "voice" is a 440 Hz sine, the music is broadband noise — so highpassing the
  mix at 2 kHz (three cascaded sections, ~36 dB/octave, putting 440 Hz ~80 dB down)
  leaves essentially only the bed. Nothing re-renders the graph to measure it; the file
  that would ship is the file that is measured. **Music during voice ≥ 6 dB below music
  during gaps.** 6 dB is one clear halving of perceived level — enough to be audible as
  ducking rather than as measurement noise.
- The voice's own level is not altered *relative to the bed*: the master gain that lands
  the mix on MM4's target is applied to voice and bed alike, so only the sidechain moves
  the music.
- The duck must engage on a **quiet** source too. `sidechaincompress`'s threshold is a
  linear level on the sidechain key, so keying it off the raw input made the ducking a
  no-op below about −30 dBFS: a −34 dBFS voice measured a 0.98 dB duck — identical to
  `--no-duck` — while the script printed "ducked" and, in the same run, applied +21 dB of
  master gain, i.e. it already knew the source was quiet. The master gain therefore
  reaches the voice **before** the split that feeds the key. Measured after the fix on
  the same fixture: **14.7 dB**.
- `--no-duck` produces a bed with no such delta — the escape hatch is real, not cosmetic.

**Fails if:** the delta is under 6 dB with ducking on (at any input level), the voice is
attenuated relative to the bed, or `--no-duck` still ducks.

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

**What the limiter does and does not guarantee.** `alimiter` bounds the **sample** peak,
not the true peak; intersample peaks can sit a few tenths of a dB above it. The graph
therefore limits `LIMITER_HEADROOM_DB` (0.5 dB) below the ceiling, which covers normal
material — but at extreme gains an overshoot of **+1.5 dBTP** pre-encode was measured, so
the headroom is a margin, not a proof. Two things close that honestly: `--music-gain` is
bounded to a documented finite range (the measured trigger was an out-of-range bed), and
the **post-render `ebur128` check is the true-peak enforcement of record** — a mix that
overshoots fails verification and is never certified. Recorded as a judgment call: the
graph is not changed further, because a second limiter stage would cost dynamics to
defend against an input the validator already refuses.

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

**What verification can and cannot prove — stated plainly, because it was overclaimed.**
It proves four things about the file on disk: the duration is unchanged, the picture was
not re-encoded, the audio is not a byte-copy of the input's, and the delivered loudness
envelope is in range. It **cannot** prove that music is audible in the mix. The output's
audio is re-encoded on every path, so it differs from the input's whether or not a single
sample of music got in — the "audio differs" check is a no-op detector for a *literal
copy*, not evidence of music. Verified: a pure-silence music file and `--music-gain -300`
both produced outputs the old verifier certified `OK … −14.0 LUFS`. The bed-audibility
guarantee therefore lives **before** the render (see below), and the success line no
longer says "music present".

**Assertions.**
- `--verify-only OUTPUT --video INPUT` is a separate, re-runnable mode, usable on any
  existing file including one from an earlier session, and **exclusive** — combining it
  with render arguments is an error, not a silent ignore.
- Wrong duration → nonzero exit, message carries **both measured durations**.
- Video stream not identical to the input's → nonzero exit, both hashes named. Packet
  MD5 is the primary check; on a mismatch the verifier compares **decoded frame hashes**
  before failing, because H.264 is Annex-B in MPEG-TS and AVCC in MP4, so a faithful
  `-c:v copy` out of a `.ts` source has different packet bytes for identical pictures.
  Repackaged-but-identical passes with a note that says so; genuinely re-encoded fails.
- Output audio identical to the input's audio → nonzero exit saying no music was mixed.
- Loudness outside the MM4 range → nonzero exit with the measured LUFS, and the message
  names `--music-gain` (and the master-gain clamp, if it fired) rather than leaving the
  operator to guess which knob moved it.
- Every failure on this path exits with the verification code and a message: a missing
  output, a directory, a 0-byte file and a non-media file all exit 4, never a traceback.
- A good output still passes, so the verifier is not failing everything indiscriminately.

**Where the audibility guarantee actually lives.** Before the render, validation measures
the music file's own integrated loudness and refuses it outright if it is silent
(< `SILENT_MUSIC_LUFS`), then computes the **effective bed level** — the track's loudness
plus `--music-gain` plus the master gain — and refuses anything under
`MIN_EFFECTIVE_BED_LUFS`. That floor is a no-op detector, not a taste gate: it is set 46
LU below the delivery target, i.e. below the noise floor of AAC at 192 kbit/s and of feed
playback, so it catches "there is no bed" without second-guessing a quiet one.

**Fails if:** any of the three tampered outputs passes, a failure message omits the
measured values, or the success line claims something the checks did not establish.

---

## MM6 — "Add music" works on the Novoads key alone

**Scenario.** A user with a fresh clone of this pack has exactly one credential in their
environment: `NOVOADS_API_KEY`. There is no `KIE_API_KEY`, no Suno account, no second
bill. They say "add music to this" over a finished video and expect two mixed variants.

**Why it matters.** This is the one step in the pack that used to break the "one key, one
bill" promise every other skill keeps. Until 2026-08-04 the skill's default sourcing path
told the agent that `$KIE_API_KEY` was "already in the shell env" — true on the machine
the skill was written on, false for every customer, and documented in no prerequisite
list or `.env.example` in this repo. The failure was therefore not a clear "you need a
key" but an agent confidently reaching for a variable that did not exist. This eval is
the check that the first-party path is genuinely reachable from a bare environment.

**This is a text-and-flow eval, not a mechanical one.** `scripts/test_music_mix.py`
cannot cover it: the mixing script is unchanged by this and takes an mp3 from the disk
either way. What changed is *where the mp3 comes from*, and that lives in judgment text.

**Assertions.**
- SKILL.md § "Sourcing the music" names the Novoads endpoint as **(a)**, the default,
  and the only path that needs no second credential. KIE-direct is **(b)**, explicitly
  labelled a fallback with its trigger conditions named (`$NOVOADS_API_KEY` absent, or
  `invalid_input` from a deployment with music off).
- The (a) path routes cost through a live `POST /v1/estimates` `{"kind":"music"}` and an
  approval gate. **No credit or dollar figure for music appears in SKILL.md** — the
  repo's cost policy, and the reason `reference/kie-suno-api.md` keeps its measured
  provider figures behind an explicit "dated measurement, not a quote" banner.
- `reference/kie-suno-api.md` opens by saying it is the fallback and pointing at (a), so
  an agent that lands there first is redirected rather than led into a second signup.
- The endpoint is documented where this pack documents endpoints — `novoads-api`
  skill, `reference.md` § `POST /music` — not only inside this skill. A source the API
  reference does not carry is a source the routing agent cannot find.
- Running the documented (a) flow with `KIE_API_KEY` unset reaches two downloaded tracks
  and then two mixed variants, with the script's verification line reported verbatim.

**Fails if:** any step of the documented default path requires a credential other than
`NOVOADS_API_KEY`, or the skill quotes a music price from markdown instead of from a
live estimate.

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
- MM5's `MIN_EFFECTIVE_BED_LUFS` floor is a **detector, not a spec**. It answers "did any
  music get in?", which nothing after the render can answer, and deliberately not "is the
  bed at a good level?", which is a taste call the operator makes with `--music-gain`. The
  value is set generously on purpose: this skill's own default (−18 dB bed under a −7 LUFS
  input) lands near −46 LUFS effective, so a stricter floor would reject correct runs.
- **Not covered by the test, on purpose:** whether a bed at a legal level sounds *good*,
  and whether the track suits the ad. Both are judgment, both live in SKILL.md. The suite
  proves the mix is mechanically sound, never that it is tasteful.
