# Seedance 2.0: UGC selfie-style product review

The formula for the format that carries most of the spend in this category: one person, one phone, one honest-sounding sentence about a product.

**Read this before writing any UGC video prompt.** Everything here is craft, and **none of it is enforced**. The API renders and bills whatever you send it: the only thing that refuses a prompt for its content is moderation. Some of what follows is *flagged* for free by `POST /v1/estimates`, which returns each finding in `warnings` on a `200`, and the rest it never looks at. Both are marked — not because one is mandatory and the other optional, but because the first half you can check with one free call and the second half only you can check.

Model: `seedance-2.0` (or `seedance-2.0-mini` at half the price while you iterate).

---

## The nine layers

Write them as flowing prose in one paragraph, in this order. Never as bullets and never as `Label: value` pairs.

| # | Layer | What goes in it |
|---|---|---|
| 1 | **Shot** | `Medium selfie shot`, `close selfie shot`, `handheld waist-up`. Name the frame. |
| 2 | **Setting and light** | The room and the actual light source. `sunlit kitchen, soft window light from camera-left`. Never a mood word. |
| 3 | **Actor** | Age band, gender, wardrobe. `a woman in her 20s in a grey zip hoodie` |
| 4 | **Realism markers** | `natural skin texture with visible pores`, `slight camera shake from a handheld phone`. This is what fights the plastic default. |
| 5 | **Product** | The real brand and product, by name. Pass its photo as `startImageAssetId`. The photo comes from `references/` at the repo root: list that folder before asking, and ask for the file if it is empty. |
| 6 | **Motion** | Two or three cues on one action, comma-joined. `holds the bottle up toward the lens, tilts it slightly, shifts her weight`. One *action*, not one twitch — and never a second action chained onto it. |
| 7 | **Eye-contact break** | `looks just off-lens, comes back to camera`. The single cheapest realism cue in the format. |
| 8 | **The line** | `and says: "..."` in double quotes. Seedance renders the audio and the lip-sync in the same call. |
| 9 | **Clean plate and ratio** | `No on-screen text, no captions, no background music.` then `Vertical 9:16.` at the very end. |

Add a tenth layer, the **label hold**, whenever a label, package, bottle, box, or screen is visible. See below.

---

## What the estimate flags

Six rules the free `POST /v1/estimates` call checks for you. Each one comes back in `warnings` as a `{rule, message}` pair whose message is the fix written out, with the text that tripped it quoted at the end.

**None of them blocks anything.** A prompt that trips all six still renders and still bills — the warning is advice, and acting on it is the whole point of collecting it. Fix them before you spend; nothing downstream will.

### 1. No polish words

Banned: `cinematic`, `flawless`, `perfect`, `8k`, `4k`, `hyper-detailed`, `beauty lighting`, `ultra-realistic`, `masterpiece`, `award-winning`, and their Spanish and Portuguese equivalents.

These produce the plastic "looks AI" render this whole format exists to avoid. Delete the word and describe the real thing in its place: the light source, the surface, the flaw.

- No: `cinematic kitchen`
- Yes: `sunlit kitchen, soft window light from camera-left, natural skin texture with visible pores`

### 2. Every prompt names its actor

Seedance re-casts on every cut. A shot that does not name its actor gets a new person.

The rule itself is satisfied by any age or gender token — `a woman` passes it. What the *model* needs is more than that, and is in "What the model needs anyway" below.

### 3. No back-references

`the same woman`, `as before`, `la misma mujer` all resolve to nobody, because no identity carries across cuts. One render came back with three visibly different women across five beats.

Repeat the actor tag verbatim instead. Do not elaborate on it either: an elaborated tag re-casts as readily as a missing one.

### 4. No chained motion

Banned connectors: `then`, `and then`, `followed by`, `after that`, `while also`, and their Spanish and Portuguese equivalents.

The rule is lexical — it looks for the connector, not for how many things move. Several cues on one action pass it and should be used (layer 6). What fails is a *second action* strung onto the first: Seedance renders one clear action well and a sequence badly, and the second beat usually arrives as a smear or not at all.

- No: `she holds the bottle and then turns to the window`
- Yes: two shots. `she holds the bottle up to camera, tilts it toward the light` / `she turns to the window`

### 5. Prose, not bullets

No `-` or `*` lines, and no `Shot: medium, Lighting: window` pairs. A labelled list comes back rendered as literal on-screen text.

The one colon that stays is the dialogue attribution: `she says: "..."`.

### 6. A spoken line, in double quotes

Without it you get a silent talking head: an actor mouthing nothing, billed in full. Seedance generates the dialogue and lip-sync in the same call, so the line costs nothing extra. Omitting it only loses the audio.

If the shot is genuinely meant to be silent, say so. The words `silent`, `b-roll`, or `voiceover` satisfy the rule.

## Two more the estimate flags

The same shape as the six above — advisory, returned in `warnings` — and worth separating because these two were never fatal even when the others were.

### 7. The label hold

Seedance preserves logos and destroys printed text. `The Ordinary / Niacinamide 10%` came back as `MAGNANDE 10% ZINC 1%`.

Whenever a label, package, bottle, or screen is visible, paste this clause in:

> the product label remains perfectly sharp and identical to the reference image with its text unchanged and fully legible

The warning clears once the clause is present, so an estimate that still warns is telling you the clause did not land.

### 8. State the ratio in the prompt too

`aspectRatio` in the request body is what binds, and you must always set it. Repeating it at the end of the prompt text costs nothing and steers the composition.

`Vertical 9:16.` for Reels, TikTok, and Stories. `1:1` for square feed. `16:9` only for YouTube in-stream.

## What the estimate never checks

No call will flag any of this. All of it is the difference between a render you ship and a render you pay for twice.

- **Establish the actor in roughly 37 to 53 characters** — age band, gender, wardrobe — then repeat a terse **11 to 30 character tag**, word for word, in every later shot. `a woman in her 20s in a grey zip hoodie`, held as `grey zip hoodie woman`.
- **Anchor on wardrobe, never on facial features.** Faces drift between renders. A hoodie does not.
- **Ask for a real person, not a person with skin problems.** `natural skin texture with visible pores` is the goal; `acne`, `blemishes`, `redness` are not. The aim is unretouched, not unflattering.
- **Say `No on-screen text, no captions, no background music.`** No rule looks for it, and Seedance will happily burn captions into a paid render. Every one of our own shipped templates opens with that clause.
- **Keep the prompt in the ad's own language** and set `language` to match. Nothing on the API pushes back on Spanish or Portuguese, and the estimate lints those prompts in their own language, so there has never been anything to gain by writing a Spanish ad in English.

---

## Worked example

Real brand, real product, one action, one line. This exact prompt comes back from the estimate with **zero warnings** — re-verified live against spec `2.0.0` on 2026-08-02.

```
Medium selfie shot in a sunlit kitchen, soft window light from camera-left. A woman in her 20s in a grey zip hoodie holds a bottle of CeraVe Moisturizing Lotion up toward the lens, tilts it slightly, natural skin texture with visible pores, slight camera shake from a handheld phone. She looks just off-lens, comes back to camera, and says: "I stopped buying the expensive stuff after this one." The product label remains perfectly sharp and identical to the reference image with its text unchanged and fully legible. No on-screen text, no captions, no background music. Vertical 9:16.
```

The call:

```json
{
  "model": "seedance-2.0",
  "prompt": "<the prompt above>",
  "durationSeconds": 12,
  "aspectRatio": "9:16",
  "language": "en",
  "startImageAssetId": "<from POST /v1/uploads>"
}
```

Price it at `POST /v1/estimates` first, show the user the number, and confirm the spoken line on its own before generating. The estimate is **not** this body: it takes the pricing fields only, and `aspectRatio` and `startImageAssetId` are a 400 there.

```json
{
  "kind": "video",
  "model": "seedance-2.0",
  "durationSeconds": 12,
  "language": "en",
  "prompt": "<the prompt above>"
}
```

---

## Writing the line

The line is the ad. Everything else is staging.

- **One sentence.** Two sentences in a 12 second clip means both get rushed.
- **Past tense, specific.** `I stopped buying the expensive stuff after this one` outperforms `this product is amazing`, because the first is a thing that happened and the second is a claim.
- **No superlatives and no exclamation marks.** They read as scripted, which is the one thing this format cannot survive.
- **No em dashes.** They read as written rather than spoken.
- **Say a real objection.** The strongest UGC line names the reason someone did not buy, and then answers it.

Match the language to the audience and set `language` accordingly. Write the prompt in that language too. Do not write a Spanish ad in English to make a rule easier to satisfy.

---

## Duration

`durationSeconds` accepts any integer from 4 to 15.

- **4 to 6** for a single line and a single action. Cheapest, and the highest hit rate.
- **8 to 12** for a line with a beat before or after it.
- **15** only when the script genuinely needs it. Longer is not better, and a rushed 15 reads worse than a clean 8.

A dense product line runs about **2.5 to 3 spoken words per second**. A calmer lifestyle line runs closer to 1.5, and that slack is exactly what leaves room for a silent beat. Count the words in your line, plan at 2.5, and pick the duration that fits plus a beat.

**Iterate on `seedance-2.0-mini` first.** Same grid, same flow, half the price. Move to `seedance-2.0` once the prompt is right — the `startImageAssetId` you uploaded is durable and reusable, so the second call reuses it with no second upload.

---

## Failure catalog

| What you see | Why | Fix |
|---|---|---|
| A different person in every shot | No actor tag, or a back-reference | Repeat the 11 to 30 character tag verbatim |
| Actor mouths nothing, no audio | No quoted line | Add `and says: "..."` |
| Garbled text on the packaging | No label hold clause | Paste the clause in |
| Captions burned over the video | No clean-plate clause | Add `No on-screen text, no captions, no background music.` |
| Plastic, over-lit, obviously AI | Polish words | Delete them, name the light source instead |
| Second half of the action is a smear | A second action chained on | Split into two shots |
| The actor barely moves | One bare motion cue | Two or three comma-joined cues on the same action |
| Literal text rendered on screen | Bullets or `Label: value` pairs | Rewrite as one prose paragraph |
| Landscape video | `aspectRatio` omitted | Set it. The default is `16:9` |
