# Evals — b-roll overlay

Written **before** the skill, from failures observed in real runs (2026-08-03 stitch
failure, PLAN.md "Minute-27 video-replica findings"; 2026-08-04 video-parity experiment,
`VIDEO-PARITY-EXPERIMENT.md`). This skill implements the contract the UGC-v2 eval file
defines from the outside (its E3): b-roll is a separate skill, entered from a finished
base video, and it **overlays** — it never extends.

OV1, OV2, OV4 and OV5 are mechanical and covered by the executable test
(`scripts/test_broll_overlay.py`, synthetic fixtures, no credits). OV3 is a text
assertion against the EDL the agent proposes. OV6 is half and half: `--stats` computes
the cadence numbers mechanically, and the departure rationale is a text assertion.

---

## OV1 — Final duration equals base duration

**Scenario.** Base video exists (15s). User asks for cutaways. The skill assembles.

**Observed failure (the founding one).** The 2026-08-03 run concatenated three silent
clips after the talking head: 24s output for a 15s base, voice absent for 12s. Frames
and waveform looked normal; only the transcript caught it.

**Assertions.**
- `duration(final) == duration(base)` within 0.05s (~1.5 frames at 30fps; the tolerance
  absorbs re-encode frame rounding, nothing else).
- The script itself verifies this after rendering and exits nonzero on drift — the
  check must not depend on the agent remembering to run it.

**Fails if:** output is longer or shorter than the base beyond tolerance, or the script
reports success without having measured.

## OV2 — Base audio passes through untouched

**Scenario.** Same assembly.

**Why it matters.** The overlay contract is: picture cuts away, voice keeps running.
Any audio re-encode risks desync and quality loss and is unnecessary — the audio track
is not being edited.

**Assertions.**
- The base audio stream is stream-copied (`-c:a copy`), never re-encoded.
- ffprobe on the output shows the same audio codec, sample rate and (within container
  rounding) duration as the base.
- No overlay clip contributes audio, whatever its own tracks contain.

**Fails if:** the output's audio stream was re-encoded, silenced anywhere, or replaced.

## OV3 — Placement is read from the transcript, not guessed

**Scenario.** The agent proposes an EDL for an approved base with a known transcript.

**Reference behavior.** The walkthrough's creator chose placements by reading what was
being said at each second, and kept the person on camera for the hook and the final
verdict beat. A frame-by-frame measurement of that edit on 2026-08-04 also fixed its
cadence: ~15.5s, 10–11 shots, a cut every ~1.4s, 5 cutaways of ~1–1.5s each, ~40–45%
b-roll coverage, strict A-B-A-B alternation, 4 b-roll settings across 2–3 rooms while
the talking-head base never moves.

**Assertions, on the proposed EDL before any rendering:**
- Every overlay window names the spoken line it covers, in one line of rationale.
- No window covers the opening hook beat, and the final beat ends on the person.
- Windows land where the b-roll illustrates the words (product mentioned → product shot).
- Cadence sits in the measured envelope: 4–6 windows per 15s of base, each ≤2s, total
  coverage 35–50%, and the base returns between every pair of windows (never two
  overlay windows adjacent or back to back).
- Composition follows the arc — problem → stress → product macro → dose/usage →
  relief — at roughly 2 product shots to 3 emotional/lifestyle beats, not all product.
- The EDL is shown to the user for approval before the script runs.

**Fails if:** windows are placed without quoting the transcript, the hook or closing
beat is covered, or rendering starts before the user has seen the plan. Cadence outside
the envelope is not a failure of OV3 — it is OV6's business, and only fails there when
the departure goes unstated.

## OV4 — Overlay windows are geometrically valid, with defined mismatch behavior

**Scenario.** An EDL arrives with a clip shorter than its window, overlapping windows,
or a window past the end of the base.

**Assertions.**
- Overlay clip shorter than its window → **hard error** naming the clip, its duration,
  and the window ("1.8s clip, 2.5s window — shorten the window or regenerate"). Never
  auto-loop: looped b-roll reads as broken.
- Overlay clip longer than its window → tail trimmed to the window, silently (that is
  the normal case: generated b-roll comes in fixed durations).
- Overlapping windows, windows outside `[0, duration(base)]`, or end ≤ start → hard
  error listing every offending window, before any ffmpeg runs.
- Validation happens entirely before rendering: a bad EDL costs zero render time.

**Fails if:** any invalid EDL reaches ffmpeg, or a short clip is looped or freeze-framed
to fill a window.

## OV5 — The verifier catches a bad output

**Scenario.** Rendering "succeeded" but the output is wrong (truncated file, dropped
frames, wrong file verified).

**Why it matters.** The founding failure was silent. The verify step exists to make
this class of failure loud, so it must itself be tested — a verifier that always passes
is worse than none.

**Assertions.**
- Given an output whose duration drifts beyond tolerance, verification fails with the
  measured numbers in the message.
- Given an output whose audio stream differs from the base's, verification fails naming
  the difference.
- Verification is a separate, re-runnable mode (`--verify-only`) so a human or a later
  session can re-check any old output against its base.

**Fails if:** a corrupted output passes, or failure messages omit the measured values.

## OV6 — The proposed EDL matches the reference cadence envelope, or departs explicitly

**Scenario.** The agent proposes an EDL. Its cadence either sits inside the envelope
measured from the reference edit, or it doesn't — and the proposal says so.

**Why it matters.** Cadence is style, and style measured once is a default, not a law.
The failure this catches is not "cut differently" — it is drifting outside the only
cadence we have evidence for **without noticing**. Our own two renders did exactly that
(2 windows, 2.5s and 2.0s, ~30% coverage, a cut every ~2.1s) as an unexamined habit,
not a choice.

**Assertions.**
- `broll_overlay.py --stats` computes the numbers — window count, min/mean/max window
  length, coverage in seconds and percent, largest and smallest base-return gap — each
  marked "within envelope" or "outside envelope (reference: …)". The same block prints
  on every render run, before rendering, so no run hides its cadence.
- The envelope: 4–6 windows per 15s of base (scaled to the actual base duration), each
  window ≤2s, coverage 35–50%, a base return between every pair of windows.
- **Deviation never changes the exit code.** `--stats` exits 0 whenever validation
  passes, envelope violations included. A style opinion that can fail a build is a
  style opinion that gets worked around.
- If the EDL falls outside the envelope, the proposal shown to the user names the
  departure and the reason for it (a 6s base, a script with one visual idea, a client
  brief asking for a slow cut).

**Fails if:** the numbers are wrong, a deviation produces a nonzero exit, or an
out-of-envelope EDL is proposed with no acknowledgement that it is out of envelope.

---

## Notes on evidence strength

- OV1 and OV2 are **well-evidenced**: the stitch failure was observed and recorded, and
  the overlay-not-segment reading of the reference video is documented in
  `VIDEO-PARITY-EXPERIMENT.md`.
- OV3 and OV6 rest on **one** reference edit, measured frame by frame on 2026-08-04:
  ~15.5s, 10–11 shots, a cut every ~1.4s, 5 cutaways of ~1–1.5s, ~40–45% coverage,
  strict A-B-A-B alternation, 4 b-roll settings across 2–3 rooms, a 2-product /
  3-emotional shot mix. The only contrast is our own two renders (2 windows, 2.5s and
  2.0s, ~30% coverage). n=1 with a contrast pair is enough for a default, not for a
  law — hence "or departs explicitly" in OV6 rather than a hard bound.
- The hook/closing rule in OV3 predates the measurement and survived it: the reference
  edit covers neither beat.
- **Retired 2026-08-04:** the skill used to teach "fewer, longer overlay windows beat
  many short ones." That was our taste call, never measured, and the measurement
  reversed it — the reference cuts roughly twice as often as we did, with windows about
  half as long. Recorded here so the rule reads as considered and overturned, not
  overlooked. If a second reference edit ever contradicts the envelope, this is the
  entry to update rather than quietly re-tune the numbers.
- OV4's no-loop rule is a taste call made here, once, so behavior is defined rather
  than improvised per run.
- The envelope constants live in `scripts/broll_overlay.py` (`REF_*`) with this
  provenance in a comment beside them, so the numbers can't drift from their source.
- External corroboration for the architecture (plan → validate → execute → verify):
  video-use (April 2026) and the HyperFrames workflow (May 2026) both gate rendering on
  a reviewable plan and verify at cut boundaries.
