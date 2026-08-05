# Evals — clone-ad (video)

Written **before** the `SKILL.md` edits in this PR, following the evals-first work order
from #13. That ordering lives in this sentence rather than in the commit history, because
the repo squash-merges and commit order does not survive the merge.

Unlike [EVALS-ugc-base-and-broll.md](../prompt-library/EVALS-ugc-base-and-broll.md), which
was written from an observed failing run, these four come from two places: the
deployed-spec verification at the top of this PR (`info.version` **2.8.0**, fetched
2026-08-05) and the beat-by-beat comparison against the chapter this skill replicates. One
assertion in E4 was measured directly against the local script; it says so where it lands.

E1, E2 and E3 are text assertions against the plan and the request bodies — checkable
before a credit is spent. E4 is the same, plus one local behaviour that was run.

---

## E1 — Three scripts, three estimates, one yes

**Scenario.** A ≤15s talking-head UGC source plus one product photo. The user asks for
three variations.

**Observed gap.** Step 11 defines a variation as *"the identical payload fired N times"* —
seed-level variety. The chapter this skill replicates writes **distinct scripts** on the
same beat structure, which is a different thing and the more useful one. And because the
estimate doubles as the per-model length check and the free prompt lint, a variant prompt
that never gets its own estimate is a prompt nobody checked: there is no second chance at
submit time.

**Assertions.**

- The agent asks once, at the variation ask that already exists: *same script rendered N
  times, or N script variants?* The default stays 1 render.
- N variants means N distinct dialogue adaptations — same beat structure, same silent-beat
  placement, per-line word counts within about ±3 of the source.
- All N are presented in **one** gate-1 block (step 7), not one gate per variant.
- One `POST /v1/estimates` **per variant prompt**, fired concurrently, before any render.
- Each variant's `warnings` array is read and judged out loud. Overriding one is also said
  out loud — they are substring matches and they do false-positive.
- One consolidated consent line: per-call number, count, total, balance. One yes covers
  all N.
- The renders fire concurrently, every variant counted against the five-slot cap.

**Fails if:** one estimate is fired and its number reused as the quote for all variants; or
each variant gets its own separate approval gate; or "three variations" silently becomes
the same payload three times.

---

## E2 — Over 15 seconds is a choice, never a default

The one scenario no acceptance run with a ≤15s source can reach, which is why it is here:
this eval is its only regression net.

**Scenario.** A 24s talking-head source, product photo given.

**Observed risk.** Step 5 as written prescribes *"split at natural beat boundaries"* as the
only path. #13 measured the alternative — one render carrying the beats as jump cuts inside
it — at roughly half the spend with the voice present throughout, against a stitched arm
whose voice was absent for half its runtime. That makes one-shot **viable**. It does not
make the series wrong: the stitched arm anchored each clip with `startImageAssetId`, a
different mechanism from this skill's shared-`referenceAssetIds` series. And compressing
drops the source's runtime and pacing, which are themselves transferable traits — the thing
this skill exists to preserve.

**Assertions.**

- Both routes are named before either is picked.
- Each carries its tradeoff in one line: one-shot is roughly half the spend with continuous
  voice, but the clone no longer matches the source's runtime or pacing; the series
  preserves both at roughly twice the spend, and pays any resolution multiplier per clip.
- **No default.** The agent presents the choice and waits. It does not pick one and mention
  the other in passing.
- If it cites the #13 A/B, it states the mechanism caveat in the same breath.
- If it consults [seedance-2-ugc-v2.md](../prompt-library/seedance-2-ugc-v2.md), it takes
  **structure and mode** from v2 and **prompt craft** from v1, and says which is which.
- clone-ad's **source beat map wins** over v2's beat doctrine. v2's "no silent beats in the
  base" must not delete a silent beat the source actually has.

**Fails if:** the agent splits silently (today's text); or compresses silently (v2's
doctrine imported wholesale); or cites the A/B as proof the series is worse; or a silent
beat present in the beat map goes missing from the adapted prompt without anyone being
asked.

---

## E3 — 1080p is a re-price, not a footnote

**Scenario.** Mid-flow, after the beat map is approved, the user asks for the clone at
`1080p`.

**Observed drift.** Step 9's body enumeration omits `resolution`, while the same file's own
resolution paragraph says the tier *"gets priced with `POST /v1/estimates`"* — the file
contradicts itself. The deployed spec calls `resolution` the second price axis and prices
the high tiers as their own credit schedules rather than as a surcharge on the low one. A
1080p clone priced from step 9 as written quotes the 720p number and invoices the 1080p
one, and it lands on the consent beat — the one place this skill promises a number that
holds.

**Assertions.**

- `resolution` is in the estimate body whenever the ask is above the model's default.
- The number shown to the user is the re-priced one, from a live call made in this session.
- The multiplier is never stated from memory as the quote. Approximations orient; the
  estimate decides.
- `480p` is named as saving nothing.
- The key is never sent on `seedance-2.0-mini`, or on the three non-Seedance video models —
  `400 Unrecognized key` on all four.
- On a series, the tier is paid per clip and the total says so.

**Fails if:** a tier above the default is chosen and the estimate body does not carry it; or
the quote is the base number with a multiplier applied in the agent's head.

---

## E4 — A silent clone mutes the render AND says so in the prose

**Scenario.** A silent product-b-roll source: no speech, and in the sharpest case no audio
stream at all.

**Observed contradiction.** The file documents both halves — the flag and the prose — in its
header table and again in its constraints table. The **workflow steps an agent actually
follows** say the opposite: step 5's silent branch ends *"There is no audio switch to turn
off"*, and step 8 opens *"There is no audio switch to set."* An agent following the workflow
writes the prose and never sends the flag, and the user pays for a generated voice track
they then throw away.

**Measured for this PR (2026-08-05).** `extract-frames.sh` against a source with no audio
stream does **not** die: ffmpeg's failure is absorbed by
`|| echo "No audio stream found (silent video)"`, so `set -euo pipefail` never fires, and
the script exits `0` having written the frames and `metadata.txt`. What it does not write is
`audio.wav` — the file is **absent**, not empty. The trap is therefore one step later, in
step 2, which loads that path unconditionally.

**Assertions.**

- `audioEnabled: false` in the `POST /v1/videos` body.
- **And** the silence declared in the prompt prose. The flag mutes the render; the prose is
  what stops the model staging a talking shot. Prose alone is this eval's named failure
  case; flag alone is the other one.
- `audioEnabled` is **not** sent to `POST /v1/estimates` — `400` there — and the agent does
  not expect the price to move. Muting is not a discount.
- Gate 1 is skipped, and the agent says why rather than skipping it silently.
- The flag is never sent on a non-Seedance video model.
- Step 2 checks that `audio.wav` exists before transcribing, and reads its absence as
  "silent source", not as an error.

**Fails if:** the prose declares silence and the body omits the flag; or the body carries the
flag and the prose does not; or `audioEnabled` appears in an estimate body; or step 2 crashes
on a source with no audio stream.

---

## Notes on evidence strength

- **E4's extraction behaviour is measured** — a generated 6s silent mp4 pushed through the
  real script during this PR. Everything else in E4 is read off the deployed spec.
- **E3 is spec-backed**: `CreateEstimateRequestVideo` carries `resolution` in the deployed
  contract, and the drift is a straight comparison against step 9's own text.
- **E1 and E2 are design assertions, not observed failures.** E2's underlying A/B is real and
  measured (#13), but the conclusion drawn here is deliberately narrow — viability, not
  superiority — because the two arms anchored their clips differently. Treat E2 as a strong
  default with its reasoning attached rather than a law, until a same-mechanism A/B is run.
- **No credit figures appear in this file by design.** Ratios and multipliers orient; the
  live estimate quotes. Absolute numbers for the acceptance run live in the PR description
  and in the run log, never in pack docs.
