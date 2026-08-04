---
name: broll-overlay
description: >-
  Overlays silent b-roll cutaway clips onto a finished base video — the base
  audio keeps running underneath while the picture cuts away and returns, and
  the final duration always equals the base duration. Use when the user asks to
  add b-roll, add cutaways, or overlay clips on a video: "add b-roll to this",
  "cut away to a product shot here", "overlay these clips on my UGC ad". Entered
  from an approved base video plus its transcript; it never generates the base
  itself (that's the video-generation skills) and it never extends a video.
---

# B-roll overlay

Lays silent cutaway clips **over** a finished base video. The base audio runs
untouched underneath, the picture cuts away and returns, and the final duration
equals the base duration exactly. That last point is the whole contract:
overlay, never concatenation. A previous run concatenated instead and shipped
24s of output for a 15s base, with the voice dead for 12 seconds.

Assembly mechanics live entirely in `scripts/broll_overlay.py`. This file is
judgment only — when to enter, where the overlay windows go, what the user sees
before anything renders.

## Entry condition

Two things must already exist:

1. **A finished, approved base video.** Approved means the user has watched it
   and signed off. B-roll is a polish pass over a locked cut — if the base is
   still moving, every overlay window is provisional.
2. **Its transcript, with timings.** A local whisper pass (`whisper-cli` or
   `openai-whisper`). The novoads captions API cannot supply this — it burns
   subtitles into a new MP4 and returns no caption text or timings (verified
   live 2026-08-04). Placement is read from the transcript, not eyeballed.

This skill never generates the base. If there isn't one yet, say so and stop.

## Workflow

1. **Read the transcript.** Note what is said and when — the words drive every
   decision below.
2. **Generate the b-roll clips, only after base approval.** One clip per moment
   you intend to cover, each rendered silent (`audioEnabled: false`). Overlay
   audio is ignored by the script regardless, and generating before approval
   spends credits on a cut that may still change.
   **Cast the base actor in every cutaway that shows a person:** pass the same
   identity reference (`referenceAssetIds`) the base used — Seedance re-casts
   every render, and a stranger's hands or skin in the cutaways breaks the ad
   (observed live 2026-08-04: Black base actor, five white-cast cutaways).
   If no identity ref exists, keep people fully out of frame — objects and
   environments only, not "face out of frame", which still shows skin.
3. **Propose an EDL.** JSON with `base`, `output`, and an `overlays` list of
   overlay windows (`file`, `start`, `end`, `covers`). Every window carries a
   one-line `covers` rationale **quoting the spoken line it illustrates**. A
   window you can't justify with a quote is a window you're guessing at.
4. **Show the EDL to the user and wait for approval.** Rendering before the user
   has seen the plan is precisely the failure this step prevents.
5. **Render:** `python3 scripts/broll_overlay.py edl.json`
6. **Report the script's verification output verbatim** — the measured durations
   and the audio check, not a paraphrase of them. Then offer 2–3 cut variations
   (different windows, fewer cutaways, a tighter opener) so the user has
   something concrete to react to.

## Placement judgment

Default cadence, measured 2026-08-04 frame by frame from the reference edit this
pack reproduces — ~15.5s, 10–11 shots, a cut every ~1.4s:

- **Alternate A-B-A-B: the face returns between every cutaway.** Never two
  overlay windows back to back; the talking head is the spine.
- **4–6 windows per 15s, ~1–1.5s each, ~40–45% coverage.** Short and frequent.
  This retires the earlier "fewer, longer windows beat many short ones" rule —
  our taste, reversed by measurement. Our own two contrasting renders ran 2
  windows of 2.5s and 2.0s, ~30% coverage, a cut every ~2.1s.
- **The b-roll may travel; the base never does.** The reference visits 4
  distinct b-roll settings across 2–3 rooms; the talking head never moves.
- **Never cover the opening hook beat.** The first beat is a face making a
  claim; cutting away there spends the retention the hook just bought.
- **End on the person, not on b-roll.** The closing beat is the verdict, and it
  only lands if the viewer is looking at whoever delivers it.
- **Put product shots where the product is being spoken about.** B-roll that
  illustrates the current sentence reads as evidence; anything else is filler.

**Default shot plan.** The reference's five cutaways tell one arc: problem →
stress → product macro → dose/usage → relief — 2 product shots, 3 emotional or
lifestyle beats. Adapt the imagery to the script, keep the ratio.

Evidence: one measured edit (n=1) against our own two renders. Strong defaults,
not laws — depart deliberately and say why (EVALS.md OV3, OV6). Every run prints
its own cadence against this envelope; `--stats` prints it without rendering.

## Hard rule: assembly always goes through the script

Never hand-write overlay or concat ffmpeg for this task. `broll_overlay.py` owns
validation, rendering and verification, and it fails loudly on exactly what
fails silently by hand: duration drift, re-encoded audio, overlapping overlay
windows, a clip shorter than its window. Improvised ffmpeg is how the founding
failure happened.

**Escape hatch:** if a request genuinely doesn't fit the EDL model — a speed
ramp, a picture-in-picture inset, audio that actually needs editing — say so and
ask the user how to proceed. Do not improvise around the script.

## Other modes

- `python3 scripts/broll_overlay.py edl.json --dry-run` — validate the EDL and
  print the plan, rendering nothing. Cheap way to check window geometry.
- `python3 scripts/broll_overlay.py edl.json --stats` — window count, lengths,
  coverage, base-return gaps, each marked against the envelope. Never an error.
- `python3 scripts/broll_overlay.py --verify-only FINAL --base BASE` — re-check
  any existing output against its base, including one from an old session.

Exit codes: `2` validation, `3` render, `4` verification. A nonzero exit is a
real failure — surface it, don't retry blindly.

## Evals

`EVALS.md` defines the six scenarios this skill is held to (OV1–OV6).
`scripts/test_broll_overlay.py` implements the mechanical ones against synthetic
fixtures — run it after touching the script.
