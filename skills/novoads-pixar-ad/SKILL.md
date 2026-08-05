---
name: novoads-pixar-ad
description: >-
  Turn a product (URL and/or product photo) into a finished 15-second stylized 3D animated
  ad on Novoads, with the voice-over and in-scene dialogue generated natively in one call.
  Produces a researched product read, a character sheet, a composition key frame, a
  dual-track script (narrator plus character dialogue), and the exact generation calls.
  Trigger whenever the user wants a Pixar-style, Disney-style, 3D animated or
  animated-film-look ad: "make a Pixar style ad for this", "3D animated ad", "make it look
  like an animated movie", "cute 3D character ad", "15 second animated ad", or pastes a
  product URL or photo asking for an emotional animated spot. Do NOT use for talking-head
  UGC (that is the default Novoads flow), for cloning a specific competitor video (use
  clone-hook), or for a static image ad (use clone-static-ad).
---

# Novoads Pixar Ad

One product in. One 15-second stylized 3D animated ad out, picture and sound, from a
single generation call.

This is a STORY skill, not a render skill. Seedance 2.0 renders this look well by default
— smooth animation is its natural grain, so you are not fighting material physics. What
earns the result is the emotional architecture, the performance constraint on the product,
and the script. Spend your effort there.

## Before anything: this runs on a Novoads account

This skill is a set of instructions. The rendering happens on Novoads, through the MCP
connector, and the file does nothing without it.

1. A Novoads account with credits. https://novoads.ai
2. The connector at `https://novoads.ai/api/mcp`, added to **the surface you are
   actually using**. These are two different setups and having one does not give
   you the other:
   - **Claude Code** — `claude mcp add --transport http novoads https://novoads.ai/api/mcp`,
     then `/mcp` to authenticate, then **restart Claude Code**. Tool lists are
     fixed when a session starts, so the tools stay invisible until you do.
   - **claude.ai** — add it as a connector in settings.
3. That is all. There is no CLI, no API key to export, no ffmpeg.

If the skill loads but the tools are missing, it is almost always step 2 on the
wrong surface, or a session that has not been restarted.

**What one run costs.** Two images at 3 centi-credits each, then one 15-second render at
70. Call it **76 centi-credits** for a finished ad. Check it rather than trust it: this
skill calls `estimate_cost` before it spends anything, and reports the number it gets back.

## Hard constraints

- **15 seconds. One `generate_video` call.** Never chunk, never stitch. The ONE
  permitted post step is compositing the hero card (see Doctrine C) — nothing else.
- **30 to 33 spoken words total**, across narrator and dialogue combined.
- **9:16** unless the operator says otherwise.
- **A spoken line is required.** Not by the server, by this skill: a silent actor is a
  wasted render. Give every prompt a quoted line, or an explicit statement that the shot
  is silent.

**There is no `styleFamily` field.** It was deleted from the whole API, along with the
blocking prompt rules it used to scope. Do not send it: the `/v1` request bodies are
strict, so it is a `400 Unrecognized key`, and the MCP tools drop it silently. Nothing on
the generation path refuses a prompt on style grounds any more — the only prompt refusal
left is content moderation. The craft rules that used to be enforced now live in this
file, and `estimate_cost` reports them for free as advice (see Gate 2).

## Inputs

**Required: a product as text** — a URL, listing copy, or a written description. **Strongly
preferred on top of that: a product photo.**

A photo alone is NOT a sufficient input, and the reason is Gate 1. Price, specs, rating,
rating count and buyer language are the five things that gate asks for, and a photograph
carries none of them. Run on a photo alone and the product read comes out as five lines of
"not available" — which is honest, and is also a research step that never happened.

So if you have only an image, **ask once** for a URL or the listing text, and say why in one
clause. That is the single question this skill is allowed to open with; ask it before
spending anything. If the operator says there is no listing, proceed on the photo and state
plainly in the PRODUCT READ that price and reviews were unavailable rather than implying
they were checked.

Everything else you infer.

## The gates run in order. Do not skip to the render.

### Gate 0 — is this product right for this style?

Stylized 3D animation is good at exactly one thing, and it is not explaining features.

**What it can do:** interiority (large expressive eyes playing a private state — shame,
worry, relief); anthropomorphised objects that hold intent without a face; warm
aspirational realism that reads premium rather than novelty; caricatured physics (squash,
stretch, anticipation).

**What it is bad at:** technical explanation, spec comparison, cutaway logic, and any
pitch whose core is a number.

**The filter. All four must pass:**

- Is the pain **emotional or relational** rather than technical? A styled character can act
  "I can't read to my grandson." It cannot act "the field of view is 110 degrees."
- Is the pain **visible on a face** (or on a mechanism, under Doctrine D)?
- Is there a **relationship**? Two characters beat one. The strongest ads here are about
  someone else, not about the buyer alone.
- Is it **impulse-priced**? Warm animation converts at 15 dollars. At 900 it creates trust
  dissonance.

If the product fails, say so plainly and name what would suit it instead. Do not build a
charming ad for a product that needs a demo.

### Gate 1 — product read, then summarise in under 200 words

Source from the product URL or listing text, with the photo as corroboration. Then state:

1. **Verified facts:** name, price, key specs, rating and rating count. Quote only what the
   source says.
2. **Buyer language:** recurring phrases from real reviews, in the buyer's words.
3. **Who actually buys.** Reviews often reveal the purchaser is not the user — an adult
   child buying for a parent, a spouse for a partner. If so, put the product into the
   purchaser's hand on screen. This is usually worth more than any feature beat.
4. **What you will NOT claim, and why.** Check negative reviews and the fine print. If
   reviews contradict durability, the ad does not say "built to last."
5. **Anything unbuyable.** No buy box, out of stock, region-locked, or a newer model at the
   same price. A perfect ad pointed at a dead listing converts at zero.

### Gate 2 — price it, and say the number out loud

Call `estimate_cost` with the real prompt, `kind: "video"` and `durationSeconds: 15`.
Then announce in one line and proceed:

> Character sheet + key frame + one 15s render ≈ 76 credits (balance: 340). Starting.

This is an announcement, not a question. Two cases change it:

- **`sufficient: false`** — stop. Say exactly what is short and give the `topUpUrl` from
  the response. That is a blocker, not a warning.
- **`balance - credits < credits`** — the balance covers this run and no second one. Say
  so before firing, in one clause: "this covers one render, not a retry." A user who knows
  that reviews the stills properly; a user who does not finds out afterwards.

**The `warnings` array is advice, and it is graded for a different genre.** This is the
only call that lints a prompt, and it lints against the UGC talking-head rules — the
scoping that used to soften them for stylized work went away with `styleFamily`. Nothing
in it refuses anything, here or at the render.

A prompt written the way this file says comes back clean: the worked example below scores
zero warnings under that UGC lint, because the required VOICE STYLE block hands it an actor
descriptor and the prose rules keep it out of the rest. So warnings here are worth reading
— they usually mean you drifted from this file, not that the lint is confused. The four
that fire on this genre's favourite shortcuts are `missing_actor_descriptor` (a terse
narrator line), `bullety_prompt` (the timecoded table), `banned_polish` (the word
"cinematic") and `chained_motion` (two beats joined by "then"). Fix what is real, and do
not rewrite a working prompt to silence the rest.

### Gate 3 — the three-step chain, with a stop in the middle

Never go straight to video. Each step locks one thing so the render only has to invent
motion.

```
upload_asset(product photo) → PUT the bytes with the returned `headers` verbatim
      │
      ▼
generate_image  character sheet   1:1   ref [product]            3 cc
      │
      ▼
generate_image  key frame         9:16  ref [sheet, product]     3 cc
      │
      ▼
╔═══════════════════════════════════════════════════════════════════╗
║  STILL GATE — show both images. Wait for the operator.            ║
║  6 cc spent. The render is 70. A wrong direction caught here      ║
║  costs a twelfth of what it costs after the video.                ║
╚═══════════════════════════════════════════════════════════════════╝
      │  (on approval)
      ▼
generate_video  15s  9:16  startImage=key frame                       70 cc
      │
      ▼
get_generation  poll until succeeded
```

**Step 1: character sheet.** `generate_image`, `1:1`, product photo as reference. On one
canvas: the lead in **three emotional states** readable in the eyes, with the low point as
the most important panel; any secondary character; the product treated per the doctrine
below in 2 to 3 views; a scale line-up at true relative size.

**Step 2: composition key frame.** `generate_image`, `9:16`, referencing the sheet and the
product photo. This is the shot the ad lives in: strict vertical thirds, one named
practical light source, the emotional low point staged. Specify camera height, lens, and
where the shallow focus band sits.

**Step 3: the render.** One `generate_video` call with the key frame as `startImageAssetId`.

## Product treatment — pick one and say why

**Doctrine C: in-world product, real hero card.** The default. The product is recreated
exactly in design but rendered in the animated look, so the character can physically use
it. The real photograph appears only in the final beat as a hero card, outside the styled
world. Recognition comes from design fidelity, not from material.

Always include the lock line, and name specific identifying details — a rivet, a hinge, a
lens shape. Generic descriptions produce generic props.

> The product is exactly as shown in the reference: same shape, same colour, same
> proportions, same finish. Do not redesign or restyle it.

**The hero card is COMPOSITED, never rendered.** This is the one place the no-post rule
bends, and it bends because the alternative is measurably broken. Asking the video model to
draw the final card means asking it to regenerate a wordmark from scratch, and it will get
it wrong: on the first run of this skill `Novoads.ai` came back as **`Novads.ai`** in every
frame, with the labelHold clause present and the key frame spelled correctly. The circular
logo survived perfectly — a mark is a shape the model can carry, and type is not.

So do not treat a rendered hero card as a coin flip to re-roll. Render the ad, then drop the
real photograph over the final beat:

1. Find where the render cuts to the card. A brightness sweep locates it in one pass, and
   expect a short dissolve rather than the hard cut you asked for.
2. Measure the bottle's bounding box in BOTH the rendered card and the real photo, then
   scale and position the real one to match. Matching by eye produces a jump.
3. Fade the real card in on the render's own dissolve curve, reaching full opacity BEFORE
   the wordmark becomes legible. Otherwise the misspelling ghosts through the blend.

**Then read the wordmark at full crop before shipping.** Pull the frame, crop the label,
look at it. A contact sheet at thumbnail size is too small to catch a single missing letter,
which is exactly how the first one shipped.

**Doctrine D: product as character.** Available only when the product's real articulation
is expressive — a pan-tilt head, a hinged lid, a swivelling arm. The product performs
using **only movements the real product makes**. No eyes, no mouth, no eyebrows, no limbs,
no hopping. Head angle and existing mechanisms only.

That constraint is the whole point: every expressive beat doubles as a real feature demo.
State the negatives explicitly, because the model will happily bolt on eyes and turn the
product into a mascot.

**A real product, always.** Use the actual brand and the actual packaging from the photo.
Never invent a brand, and never blank-label the product to avoid the question.

## The script

Two audio tracks. Label every line.

- **VO** — the narrator. Owns the problem, the mechanism, the offer, the brand. This track
  carries the selling.
- **SYNC** — dialogue from characters in the scene. Owns proof that the feeling is real.
  Never give SYNC the offer.

Rules:

1. **One shared budget: 30 to 33 words for 15 seconds.** Count before writing the prompt.
2. **They never overlap.** Write the SYNC lines first, fit VO into the silence.
3. **Pattern:** SYNC states an emotional fact, VO names what it means, SYNC pays it off.
4. **Name the speaker and one word of intent. Never direct the mix.** No reverb notes, no
   mic distance. Dense prompts degrade before sparse ones, and audio engineering crowds out
   visual direction.
5. **Prefer escalating specifics over comparisons.** "Four times. Four and a half. Five.
   All the way to six" argues the same point as "most stop at three" without asserting a
   competitor fact you cannot verify.
6. Sign-off under 6 words. Give the hero card at least 2 seconds.
7. **No em dashes in ad copy.** Commas, periods, parentheses.
8. **Never say "free".** The entry offer is the $1 trial, and the ad should not promise
   otherwise.

### VOICE STYLE block — required in every prompt

Cast the narrator as concretely as the style card casts the look: age, gender, register,
pace, and what it must NOT sound like.

> The NARRATOR is a warm, low, unhurried woman in her forties, close and confessional, the
> tone of someone telling you something true rather than selling. Never bright, never
> announcer-like. The IN-SCENE voices are ordinary and unperformed.

Always include the negative **`no upbeat announcer voice`**. Models drift toward radio-ad
delivery, and that single drift kills the emotional register.

**A measured side effect worth knowing.** Casting the narrator concretely — "a woman in her
forties" — also happens to satisfy the lint's UGC actor rule, because that rule looks for an
age or gender token anywhere in the prompt. So a full VOICE STYLE block is the one thing
that quiets `missing_actor_descriptor` on the estimate. Write it for the render, not for
the lint: a terser casting line costs you a warning and nothing else.

### The 15-second skeleton

Five beats. Worked arcs and examples in `references/story-arcs.md`.

| TC | Beat | Track |
|---|---|---|
| 0:00–0:03 | **Hook.** A character states the want out loud. | SYNC |
| 0:03–0:06 | **Problem.** The attempt fails on screen. | VO names it |
| 0:06–0:08 | **Low point.** The private defeat. The most important 2 seconds. | SYNC |
| 0:08–0:11 | **Turn.** The product arrives, ideally from the purchaser, and is used. | SYNC or silent |
| 0:11–0:15 | **Payoff and offer.** In-scene warmth, hard cut to hero card at 0:13. | VO closes |

The turn needs a **single-frame** change, not a gradual one: a page snapping into focus, a
light coming on. Specify "in a single frame," or the model renders a slow dissolve and the
payoff lands soft.

## Output format

Deliver in this order, no preamble:

1. **PRODUCT READ** — verified facts, buyer language, who actually buys, what you will not
   claim, anything unbuyable.
2. **FIT** — one line confirming Gate 0, or a plain refusal with a better format named.
3. **ANGLE** — the enemy this ad attacks.
4. **DOCTRINE** — C or D, and why.
5. **SCRIPT** — timecoded table: timecode, audio (each line tagged VO or SYNC), visual. One
   SFX line. State the word count against the 30 to 33 budget.
6. **COST** — the `estimate_cost` result, announced in one line.
7. Then generate: character sheet, key frame, **stop at the still gate**, render.

## The calls

```
upload_asset      contentType: "image/jpeg", sizeBytes: <n>
                  → { uploadUrl, assetId, headers } — then HTTP PUT the bytes to
                    uploadUrl, sending `headers` VERBATIM. Content-Type and
                    Content-Length are signed into the URL, so an omitted or
                    library-inferred Content-Type is a 403, not an upload.

estimate_cost     kind: "video", prompt: <the render prompt>, durationSeconds: 15
                  → { credits, balance, sufficient, shortBy?, topUpUrl?, warnings? }
                    `warnings` is craft advice graded against the UGC rules.
                    It refuses nothing. See Gate 2.

generate_image    prompt: <sheet prompt>, aspectRatio: "1:1",
                  referenceAssetIds: [productAssetId]
generate_image    prompt: <key frame prompt>, aspectRatio: "9:16",
                  referenceAssetIds: [sheetAssetId, productAssetId]

generate_video    prompt: <one self-contained block>, durationSeconds: 15,
                  aspectRatio: "9:16", startImageAssetId: <keyFrameAssetId>
                  → { jobId } — not ready yet

get_generation    jobId
                  → { status, progress, outputUrl? }

list_generations  limit: 10, kind: "image" | "video"   (optional)
                  → { generations: [{ jobId, status, kind, creditCost,
                      createdAt, outputUrl?, promptPreview }] }
                  The recovery path when a call times out and you never
                  received the jobId. Reads only, spends nothing.
```

**Polling.** `generate_video` returns immediately with a jobId; the video is not ready.
Poll `get_generation` until `succeeded`. A 15-second render takes minutes, and the poll is
what drives completion — keep the session open until it returns.

**Poll every 3 seconds. Give up at 10 minutes.** Those are Higgsfield's `generate wait`
defaults and they are well-calibrated for this class of job: frequent enough to feel
responsive, patient enough that a slow render is not mistaken for a dead one.

**Write every jobId down the moment it comes back**, before you start waiting — id, what it
was for, and the credits it cost. A job whose id you recorded is a lookup when something
goes wrong. A job whose id you did not is an investigation.

**If a call times out, do NOT generate again.** The work usually completed and was charged;
what timed out was the response carrying its id. Call `list_generations`, find the job by
its timestamp and prompt preview, and take its `outputUrl`. Generating again pays twice for
the same image.

> **Known issue.** `generate_image` currently blocks for the whole render, measured at 66 to
> 74 seconds, which is longer than some clients wait. When it times out the image is still
> produced and still charged. `list_generations` is how you recover it. The fix is tracked;
> until it lands, expect this on the two still calls and do not retry blindly.

### Worked render prompt

A finished **Doctrine D** `generate_video` prompt — product as character, no humans on
screen. `lib/generation/__tests__/pixar-skill-prompts.test.ts` reads this exact block and
runs it through the same rule engine `estimate_cost` lints with, so the worked example
cannot drift into one the lint has real complaints about.

Doctrine D is deliberately the worked example, because it is the harder case: with no human
in the scene there is nothing to lean on, no face carrying the beat, and every expressive
move has to come out of the product's own articulation. A human-led Pixar ad borrows from
the talking-head grammar and hides how much of this is working.

<!-- eval:render-prompt:start -->
```
Stylized 3D animated feature film look, 9:16. A cold blue kitchen before sunrise, one
window as the only light source, strict vertical thirds.

A small copper kettle sits alone at the far end of the counter, spout angled down. The
first light reaches the counter and stops short of it. The kettle's lid lifts a few
millimetres and settles again. Morning light crosses the last of the distance and the
kettle raises its spout in a single frame, steam catching the light. NARRATOR: "Mornings
deserve better than waiting."

The kettle moves only the way the real kettle moves: lid hinge and spout angle. No eyes, no
mouth, no eyebrows, no limbs, no hopping. The kettle is exactly as shown in the reference:
same shape, same colour, same proportions, same finish. Do not redesign or restyle it. Hold
the printed markings on the base sharp and legible.

The NARRATOR is a warm, low, unhurried woman in her forties, close and confessional, the
tone of someone telling you something true rather than selling. Never bright, no upbeat
announcer voice.

no named or copyrighted animated film characters, no photorealistic humans, no uncanny
faces, no dead eyes
```
<!-- eval:render-prompt:end -->

## IP rules

The trademark risk here is higher than for any material-based style, because this aesthetic
belongs to specific studios and models will hand you near-copies of their characters.

- **Never name a studio or franchise in a prompt.** Write "stylized 3D animated feature
  film look."
- Never depict named or recognisable characters. Original designs only.
- Do not reproduce a studio's mascot or signature motifs, even by allusion.
- Add these negatives to every prompt: `no named or copyrighted animated film characters`,
  `no photorealistic humans`, `no uncanny faces`, `no dead eyes`.

## QC, in priority order

1. **The lead's face at the low point.** Everything rides on it. If that beat does not
   land, nothing else matters.
2. **The turn snapped in one frame**, not a slow focus pull.
3. **Voices:** narrator distinct from characters, no overlap, right language, no announcer
   delivery.
4. **Product fidelity** — the specific identifying details survived, and under Doctrine D
   nothing grew eyes or limbs.
5. **The hero card cut** reads as intentional, not as a seam.
6. **Uncanny valley** on any human, especially children.

Fix by subtraction. A failed render gets shorter lines and fewer beats, not more
instructions.

## Failure modes

- **The prompt is rejected.** Only one prompt check can refuse a render: content
  moderation, which answers `content_policy`. There is no rule-id rejection any more, so a
  refusal here is not a wording problem to lint your way out of — read what it says.
  `missing_actor_descriptor` and its neighbours arrive only as `estimate_cost` warnings,
  and warnings never blocked anything.
- **`no_spoken_line` in the estimate's warnings.** Advice, not a refusal — and worth taking
  every time. Add the SYNC line in double quotes, or state that the shot is silent.
- **The label on the product comes back garbled.** Add the labelHold clause — a visible
  label needs it or its printed text is regenerated as noise.
- **Product grew eyes under Doctrine D.** State the negatives explicitly and re-render. If
  it happens twice, switch to Doctrine C.
- **Voices overlap or the narrator sounds like a radio ad.** Add `no upbeat announcer
  voice` and shorten the lines. Word count over 33 is the usual cause.
- **Uncanny children.** Reduce to one child, keep them in profile or partially occluded,
  and shorten the beat. If it survives two attempts, cut the child from the story.
- **`insufficient_credits`.** The error carries `required` and `available`. Report both and
  the top-up path. Do not retry.

## Hard rules

- One product, one 15-second call per run.
- Count the words before writing the prompt.
- Stop at the still gate. The operator approves the spend before the render fires.
- Never invent reviews, ratings, prices, or performance claims.
- Never claim what the reviews contradict.
- On-screen text is short words and numbers only, never sentences.
- If a fact cannot be verified from the source given, leave it out and say so.
