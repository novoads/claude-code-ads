# novoads-image-to-motion evals

This skill is a **port**. Its craft came in whole from an Arcads-connector skill of the
same shape, and only the transport was rewritten. So the cases below split cleanly in two:

- **P-cases** guard the port itself. Each one is a place where a verbatim copy would have
  shipped an instruction that fails on `/v1`. They are the reason the port is not a `cp`.
- **E-cases** guard the craft the port was worth doing for, plus the two gates every
  spending skill in this pack carries.

The mechanical half of the P-cases is automated: `./scripts/test-parity-i2m.sh` greps for
every retired tool name and asserts the craft sections survived. Run it first. What is
left here is the half no grep can hold.

Only E6 costs credits. Everything else is free or is a read of the file.

---

## Routing

The pack now has four skills that a user can reach by handing over a picture, and PR #54
settled the first three on the source's **medium** — a still lands on `clone-image-ad`, a
video on `clone-video-ad`. This skill breaks that rule by construction: it takes a still
and returns a video. So the axis is not the medium. It is **what happens to the pixels the
user handed in**:

| The image they gave you | becomes | Skill |
|---|---|---|
| that exact image, preserved and set in motion | one video of it moving | **novoads-image-to-motion** |
| a reference to reverse-engineer | new stills, and a reusable template | `clone-image-ad` |
| one ingredient in a scene that did not exist | a new video featuring their product | `novoads-api` |
| (a video, not a still) | that ad re-shot for their product | `clone-video-ad` |

Read it as one question: **is the source image the output, or an input to something else?**
Preserved means here. Recomposed means elsewhere.

### R — the routing table

Ten sentences, each with one correct destination. A skill that wins a row it should lose is
as broken as one that never fires. Run this whole block after any edit to any of the four
descriptions, and edit those four in ONE pass — taking them one at a time is exactly how the
collision PR #54 fixed was created.

| # | The user says | Correct | Why not the other |
|---|---|---|---|
| R1 | "animate this" + a dashboard screenshot | **image-to-motion** | The screenshot IS the shot |
| R2 | "I want the cards to pop in" | **image-to-motion** | Motion beats for an existing layout |
| R3 | "make this move" + a hero image | **image-to-motion** | Same |
| R4 | "turn this into a motion graphic" | **image-to-motion** | Names the output |
| R5 | "write me a Seedance prompt for this image" | **image-to-motion** | Prompt craft for a still, no render implied |
| R6 | "clone this ad for my product" + a static ad | `clone-image-ad` | The ad is a reference to rebuild, not a frame to animate |
| R7 | "make static image ads from this photo" | `chatgpt-image-ad` / `nano-banana-image-ad` | Output is stills, and no motion is asked for |
| R8 | "make a UGC video ad with my product photo" | `novoads-api` | The photo seeds a scene that does not exist yet; nobody wants the photo itself to move |
| R9 | "clone this video ad" + an MP4 | `clone-video-ad` | Source is a video |
| R10 | "make a video of a robot dancing" (no file) | `novoads-api` | No source image, so there is nothing to animate |

R8 is the one that actually collides and the one to re-check first. Both skills take a
product photo and return a video, and both are correct English readings of "animate my
photo". The split is whether the user wants **that photograph, moving** (here) or **their
product, in a scene** (`novoads-api`). When a request is genuinely ambiguous, ask in one
line rather than guessing, and name the difference in the same sentence so they answer in
one word.

---

## P-cases: the port

### P1 — no retired tool name survives anywhere

**Why:** this skill was written against a vendor connector and every tool call in it was
renamed. A leftover is not a cosmetic defect: an agent that reads one either calls nothing
and stalls, or worse, reaches for a connector this repo has a standing rule against.

**Check:** `./scripts/test-parity-i2m.sh`. It fails on any hit for the retired
`arcads_*` names, for `register_image`, for `nbGenerations`, and on any un-allowlisted
mention of the connector. `./scripts/check-no-mcp.sh` is the second half of the same
check and runs in CI.

### P2 — `nbGenerations` is four calls, not a field

**Why:** the source skill said four takes on a single call. That field does not exist on
`POST /v1/videos` and the request schema is strict, so sending it is a `400` on an
otherwise valid body — verified against the deployed schema, not inferred:
`Unrecognized key: "nbGenerations"`.

**Check:** ask for four takes. Confirm the skill fires the identical payload four times,
says out loud that four takes is four charges, and puts that multiplication inside the cost
gate rather than after it. Confirm it fires at most five concurrently: a sixth returns
`429` with `details.reason: concurrency_limit`, which is a refusal to wait out, not a
backoff to lengthen.

### P3 — 720p is the ceiling on this model, not a floor

**Why:** the source said `"720p"` or higher. On `/v1`, `seedance-2.5` publishes `480p` and
`720p` and nothing above, so "or higher" is a `400`
(`Invalid option: expected one of "480p"|"720p"`). The wider grid belongs to
`seedance-2.0`, and lending it to 2.5 quotes a tier neither of our providers serves.

**Check:** ask for 1080p. Confirm the skill says 720p is this model's ceiling and offers
the render at 720p, rather than submitting and reporting a failure.

### P4 — the asset is durable, and the old warning was backwards

**Why:** the source warned that uploaded objects die within minutes and told the agent to
upload and generate in one uninterrupted burst. On this API the opposite is true: the
`assetId` is the storage key, it is reusable without limit, and the 900-second expiry
belongs to the **upload URL**, not to the asset. A skill carrying the old warning wastes a
re-upload on every iteration and teaches a false model of the API.

**Check:** run two renders off one image. Confirm exactly one `POST /v1/uploads` and one
PUT, and that the second render reuses the same `assetId`. Confirm the file contains no
claim that the asset expires.

### P5 — the retired escape hatches are gone, not translated

**Why:** the source offered two fallbacks that do not exist here. `omni-flash` was
described as a multi-turn editor for restyles; on `/v1` it is one stateless call with no
edit mode, no `referenceAssetIds`, and a 4/6/8/10 duration grid. There is also no
`register_image` step to warn about. Translating either one sends an agent at a product we
do not sell, and the omni-flash detour burns a paid render on a fresh video nobody asked
for.

**Check:** ask for a restyle of existing footage. Confirm the skill says this API takes no
video input and stops, rather than routing to `omni-flash` or to a "restyle" mode.

### P6 — the craft arrived intact

**Why:** the whole point of a parity port is that the part worth having is not quietly
thinned in the move. A port that drops a motion class or softens a clause has cost more
than it saved.

**Check:** `./scripts/test-parity-i2m.sh` asserts all seven motion classes and all five
prompt clauses are present by name. Then read the file against the original once by hand:
the stagger rule, the accent-structure note and the review checklist are the three most
likely to be lost, because none of them is a heading.

---

## E-cases: the craft and the gates

### E1 — it runs on `.env` and `curl`, with a connector connected

**Why:** this repo has one executable path. The failure is not hypothetical: on 2026-08-08 a
session found a placeholder key, decided a connected connector had its own auth, and
generated over it. The user ended with a working demo and still no key, and every price
they were shown was in the wrong units.

**Check:** with a connector authenticated in the session and `NOVOADS_API_KEY` unset or
still the placeholder, ask for an animation. Confirm the skill stops, gives the key
instructions, and does not generate. Then set a valid key and confirm the same request runs
on `curl`.

### E2 — the estimate happens before the render, every time

**Why:** every credit number a user sees must come from a live `POST /v1/estimates` in the
same session. There is no rate table in this file, in this repo, or in the logs, and a
remembered rate is a lie waiting for the next reprice.

**Check:** confirm exactly one estimate call before the first render, that the announced
number came back from it, that the balance was shown, and that nothing was submitted before
a yes. Confirm the file contains no credit figure anywhere. Note there is **no spoken-line
gate here** — a motion graphic has no dialogue — and confirm the skill does not treat that
absence as permission to skip the cost gate too.

### E3 — the 0.0s frame states what is absent

**Why:** the highest-leverage sentence in the whole skill, and it is logic rather than model
behaviour: if an element is visible in the reference and should appear partway through, the
prompt must say it is **not there** at 0.0s. Otherwise it is present from frame one and the
reveal the user paid for never happens. No model capability fixes this.

**Check:** hand over a reference whose tooltip should appear at 2s. Confirm the 0.0s beat
names the tooltip as absent. A prompt whose first beat only describes what IS there fails
this case even if the render happens to look fine.

### E4 — every string is quoted individually

**Why:** the source skill's own strongest claim. Asking for intact text explicitly beats
leaving it implied, and naming each string beats one general instruction.

**Check:** on an image with a headline and three small labels, confirm all four strings are
transcribed verbatim into the TEXT clause, not just the headline. Then confirm the QA step
reads each one back **at full size** rather than eyeballing the thumbnail.

### E5 — a held region is declared, and the render ends on a hold

**Why:** two failures with one cause. Silence is not an instruction: a region nobody pinned
will drift, and a clip with no final beat gets a model-invented fade or camera move to fill
the runtime.

**Check:** confirm the prompt carries an explicit hold clause for anything that must not
move, and that the last beat pins the final state and says no fade out.

### E7 — the estimate's actor warning is overridden, never satisfied

**Why:** verified live 2026-08-10. A motion-graphic estimate comes back with four
`warnings`, and three are silenceable by clauses you want anyway (silent, label hold,
ratio in words). The fourth, `missing_actor_descriptor`, is **structurally unsatisfiable**:
there is no actor in a motion graphic and no wording exists that clears it. An agent that
takes the rule at face value inserts "a woman in her 20s in a grey zip hoodie" into a
dashboard animation and destroys the render to satisfy a linter. That is the whole failure.

**Check:** price any motion-graphic prompt. Confirm the skill names the four warnings,
adds the three clauses, and **says out loud that it is overriding the actor rule and why**
rather than silently ignoring it or complying with it. Confirm no actor, person, hand or
model appears anywhere in the final prompt unless the source image contains one.

---

### E6 — text actually survives our render (**costs one render**)

**Why:** the parity claim this port cannot make for free. The text-fidelity behaviour was
observed through a different vendor's connector; ours is the same model family routed
through fal or kie, capped at 720p. Same model, different path, and text is exactly what
degrades with resolution.

**Check:** one real render. Upload a UI screenshot with small labels, run the skill's own
prompt template at 720p, then read every string back at full size. If text holds, the
skill may say so and cite the date. If it does not hold at 720p, that is a caveat this file
must carry, and the honest version of this skill states it.

**Until this has been run, the skill must not assert that text holds on our path.** It may
say the clause is what the model responds to, which is craft, and it may not say it was
verified here, which would be a claim.
