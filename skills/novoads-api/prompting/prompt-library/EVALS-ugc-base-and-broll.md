# Evals — UGC base video + b-roll overlay

Written **before** the skill edit, from failures observed in a real run (2026-08-03,
Moon Juice Magnesi-Om replica; see PLAN.md "Minute-27 video-replica findings").
Every scenario below is a thing that actually went wrong, or a thing a reference
implementation does that ours did not.

These are **text assertions against the generated plan and prompt**, checkable before
any credit is spent. Only E4 needs a render.

---

## E1 — One generation, not N clips

**Scenario.** User says: *"I want to create a new AI UGC video, but I want to generate
the starting frames for each scene using ChatGPT Image 2 … then the video model will be
Seedance 2.0."*

**Observed failure.** The agent read "a start frame per scene" as one Seedance call per
scene, produced 3 separate clips, and concatenated them. Result: 24s, 13.8 credits, a
15s talking head followed by 12s with no voice. The alternative — one call, 5 beats,
jump cuts — cost 7.0 credits, needed no editing, and is the shape the reference
implementation uses.

**Assertions.**
- The agent names **both** modes before choosing, and states the tradeoff in one line.
- Absent a reason to split, it picks **one generation with N beats** (`referenceAssetIds`).
- It states the exclusivity: `startImageAssetId` XOR `referenceAssetIds` — choosing a
  start frame per scene *forecloses* the multi-beat mode.
- It only chooses stitched mode when a beat genuinely needs a different room, or the
  script exceeds one clip's runtime.

**Fails if:** the plan goes straight to "one clip per scene" with no mode discussion.

---

## E2 — No silent beats inside the base

**Scenario.** Same request. The agent drafts the beat list for the base video.

**Observed failure.** Layer 5 currently states — three times, once in bold — that every
video should include at least one silent action beat. The agent complied: 2 of 3 beats
had no person and no dialogue (hands stirring; a dark lamp). Those became 12 seconds of
sequential dead air. The reference implementation's base video has **4 beats, every one
with the person on camera and a spoken line**; its silent material exists, but as
overlay, not as timeline.

**Assertions.**
- Every beat of the base carries the person on camera **and** a spoken line.
- Default beat count is **4**; the hook / discovery / demo / verdict shape.
- The whole script is speakable at an unhurried pace inside the clip's runtime — read
  aloud, timed, not estimated.
- If the agent wants a silent shot, it routes it to the **b-roll phase** (E3), never
  into the base beat list.

**Fails if:** any base beat is faceless or wordless; or the beat count silently drops
below 4 without the user asking.

---

## E2b — The run ends at a finished base video, and then it OFFERS

**Design decision (Mauricio, 2026-08-03): one skill does not do the whole pipeline.**
The UGC skill's job is finished when a base video is delivered. B-roll, music and
multi-variation cuts are a *separate* skill, invoked only if the user asks for them
after seeing the base. This mirrors the reference implementation, where the creator
watched the finished base video first and only then decided cutaways would improve it.

**Assertions.**
- The run terminates with: the base video downloaded, QA'd, folder opened.
- It then **offers** the next step in one or two lines — b-roll cutaways, music, cut
  variations — and stops. No shot lists, no prompts, no estimates for work not asked for.
- If the user declines or says nothing, the deliverable is complete and correct on its own.
- If the user accepts, control passes to the b-roll skill (E3), which starts from the
  finished base.

**Fails if:** the agent plans or prices b-roll before the base exists; or treats the base
as an intermediate artifact rather than a shippable ad.

---

## E3 — B-roll is a SEPARATE skill, and it overlays

**Scenario.** The base video exists and is approved. The user accepts the offer from E2b,
or asks directly for cutaways.

**Observed failure.** Our pack has exactly one line about b-roll (how to make a clip
silent) and nothing about what it is for or how it is assembled. Every existing pipeline
in the repo concatenates, so the agent concatenated. The reference implementation
generates ~10 silent shots **after** the base exists, then lays them **over** the base:
the base's audio runs continuously underneath while the picture cuts away and returns.

**Assertions.**
- This is its **own skill**, entered from a finished base video — not a phase the UGC
  skill runs on its own initiative. It takes the base file and its transcript as input.
- B-roll is generated only **after** the base is approved — never mixed into the base call.
- Shots are silent (`audioEnabled: false`), short, and each names the moment of the base
  it is meant to cover.
- Assembly is stated as **overlay, not concatenation**: base audio untouched, video track
  replaced for a time range, base picture restored after.
- **The final video's duration equals the base's duration.** This is the cheap mechanical
  check that overlay actually happened.
- Placement is chosen from the base's own transcript (what is being said at that second),
  not guessed.
- The agent offers 2–3 variations of the cut rather than one.

**Fails if:** the output is longer than the base; or audio drops, desyncs, or goes silent
under a cutaway.

---

## E4 — Identity survives the cuts (the one that needs a render)

**Scenario.** A 4-beat single-generation base is rendered.

**Observed risk.** Seedance re-casts on every cut. Our multi-location attempt (bedroom →
nightstand macro → under the duvet) changed room, framing and subject presence at once.
The reference implementation's prompt fixes the location explicitly — same kitchen, same
window as the only light source, same wardrobe — and changes only the framing.

**Assertions, checked in the prompt before firing:**
- The location, light source and wardrobe are stated once and declared unchanged across cuts.
- The actor tag (`grey tee woman`, etc.) repeats verbatim in **every** beat.
- No `the same woman` / `as before` back-references.
- Only framing and camera distance vary between beats.

**Assertions, checked after the render:**
- Frame sweep at each beat midpoint: same person in all 4.
- Whisper transcript: every scripted line present, brand name recognizable.
- No clause spoken twice (the stutter failure mode).

**Fails if:** two beats show visibly different people, or the prompt changes location
mid-beat-list without the user asking for it.

---

## Notes on evidence strength

- E1, E2, E3 are **well-evidenced**: observed in our run and cross-checked against the
  reference implementation's own on-screen prompt and narration.
- E4's single-location rule rests on the reference prompt plus one contrasting render of
  ours. Treat it as a strong default with the reasoning attached, not a law, until a
  same-prompt A/B (fixed vs varying location) is run.
- The ~15s runtime is a Seedance 2.0 ceiling, not a style choice — 4 beats is what fits.
