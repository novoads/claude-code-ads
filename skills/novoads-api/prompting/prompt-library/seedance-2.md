# Seedance 2.0 — model guide

The platform rules for `seedance-2.0` and `seedance-2.0-mini`. Read this before any of the four style formulas, and read the formula before writing the prompt.

**Route:** `POST /v1/videos` → `202` with a `jobId` → poll `GET /v1/generations/{jobId}` until a **terminal** status → download from `GET /v1/generations/{jobId}/watch`. The call sequence, the two gates, and the polling loop live in [SKILL.md](../../SKILL.md); every field-level detail lives in [reference.md](../../reference.md). This file is craft plus the model's own grid.

## Request fields

Only `model` and `prompt` are required. The body is **strict** — any key not in this table is a `400` and nothing is charged.

| Field | Value / range | Notes |
|---|---|---|
| `model` | `seedance-2.0`, `seedance-2.0-mini` | Mini is half the price on the same grid. Ask once per workflow; see *Mini-draft tier* below. |
| `prompt` | 1 to **4,000 characters** | Not words — characters, and it is the hard ceiling. Every worked example in this library sits at half of it or less; see *Length* below. |
| `durationSeconds` | any integer **4 to 15** | Continuous range, not an enum. **Defaults to 5**, which is never what an ad wants. Set it. Out-of-grid values are rejected, never rounded. |
| `aspectRatio` | `16:9` `9:16` `1:1` `4:3` `3:4` `21:9` | **Defaults to `16:9`.** Set `9:16` for Reels, TikTok, Stories. |
| `language` | `en` `es` `pt` `fr` `de` `it` `zh` `ja` `ko` `ar` `hi` | The language the ad is rendered in. Write the prompt in it too. |
| `startImageAssetId` | one `assetId` | Animates that image as the **first frame**. |
| `referenceAssetIds` | up to **9** `assetId`s | **Composites** them as visual references. Addressed in the prompt as `@Image1`…`@ImageN`. |
| `productId` | UUID | Optional. What makes `GET /v1/generations?productId=…` a useful history later. |

**`startImageAssetId` and `referenceAssetIds` are two modes, not two fields.** Sending both is a `400` that says so in as many words:

> `startImageAssetId and referenceAssetIds are separate modes and cannot be combined. Pass startImageAssetId to animate one image as the first frame, or referenceAssetIds to composite several references into a new scene.`

References are **images only** (`image/jpeg`, `image/png`, `image/webp`), even though `POST /v1/uploads` also accepts video. Ten references is `referenceAssetIds: Too big: expected array to have <=9 items`. `omni-flash` has no `referenceAssetIds` field at all — offering references on that route is `Unrecognized key`.

**There is no `resolution` field**, and the spec publishes no output size. Seedance measured 720x1280 at `9:16` (2026-08-02); do not carry that number to other models.

### Fields this model does not have

Every one of these comes back `400 (root): Unrecognized keys: …` — verified live, 2026-08-02, in one request each:

`duration` (it is `durationSeconds`) · `resolution` · `referenceImages` (it is `referenceAssetIds`) · `referenceVideos` · `referenceAudios` · `startFrame` / `endFrame` (it is `startImageAssetId`) · `nbGenerations` · `projectId` (the API has products, not projects).

**`audioEnabled` is the one exception, and it is a mute switch, not an audio track.** It arrived in spec `2.2.0` on `seedance-2.0` and `seedance-2.0-mini` only — the other three video models still `400` on it, and so does `POST /v1/estimates` for every model, because it does not move the price. It defaults to `true`. Send `false` for a clip that is meant to be silent (a pipeline laying its own VO in post, a cutaway built to run muted); otherwise leave it alone.

What it does **not** give you is control over the audio. Seedance still renders the dialogue and the lip-sync from the prompt itself, in the same call, at no extra cost — which is why the spoken line has its own approval gate in `SKILL.md` before anything is submitted. The flag decides whether that track exists, not what is in it.

### `@Image1` reference mapping

The four style formulas write `@Image1`, `@Image2`, `@Image3` inline in the prompt text. Those tokens resolve **positionally** against `referenceAssetIds`: `@Image1` is the first `assetId` in the array, `@Image2` the second, in the order you send them. Order is the contract — the array is what binds, the token is how the prompt points at it.

A token pointing past the end of the array is refused **before the charge**, so `@Image2` in a prompt that ships one reference fails free rather than billing a render the provider cannot resolve.

Upload once and reuse: the `assetId` is durable across calls, across models, and across sessions. Re-uploading the same bytes mints a **second** asset and throws away the identity anchor a multi-clip series exists to hold.

Which mode a formula wants:

| Formula | Mode | Why |
|---|---|---|
| UGC selfie review | `startImageAssetId` | The product photo is literally the opening frame. |
| Premium reveal, product hero | `referenceAssetIds` | The product emerges from a void it was never photographed in — the model has to composite it, not animate the flat photo. |
| Studio lookbook, feature walkthrough | `referenceAssetIds` | Two references earn their keep: `@Image1` the product, `@Image2` the actor. |

## Prompt craft

These rules are about how Seedance reads a prompt. None of them is enforced anywhere: the API renders and bills whatever you send. `POST /v1/estimates` flags a subset for free (see *What the estimate flags*), and the rest only you can check.

### Length

**The only hard number is 4,000 characters.** Everything else is craft, and the craft figure the fork's guidance carried — "keep prompts between 100 and 260 words" — describes **none** of the five worked examples in this library. Measured, they are:

| Formula | Shots | Words | Characters |
|---|---|---|---|
| UGC selfie review | 1 | 97 | 585 |
| Feature walkthrough (clip A) | 3 beats | 255 | 1,521 |
| Studio lookbook | 3 shots + VO | 267 | 1,701 |
| Premium reveal | 4 timestamps | 272 | 1,699 |
| Product hero | 4 shots | 332 | 2,001 |

Length follows **shot count**, not a single band. One shot wants roughly **90 to 130 words** — the UGC formula, and the shape 13 shipped production templates use. A 3–4 beat multi-shot prompt wants roughly **250 to 330**, because each beat needs its own framing, action and detail.

What the underlying advice is actually right about: a prompt that is too short leaves the model filling gaps you cared about, and a prompt that keeps piling on adjectives past the point where every shot is specified starts losing the details rather than adding them. Write every beat properly and stop; do not pad to hit a number, and do not cut a beat's framing to stay under one.

At the ~6.3 characters per word these formulas average, even the longest sits at half the ceiling — so length is a craft decision here and not a limit you will hit.

### Structure

Seedance responds best to this order:

```
Subject + Action + Camera + Style + Constraints
```

- **Subject** — who or what is in the scene. Age, wardrobe, expression, posture.
- **Action** — what happens. Present tense, **one** primary movement per shot.
- **Camera** — framing (wide, medium, close-up) and movement (dolly-in, pan, handheld).
- **Style** — the light source, the surface, the grade. Name real things, not moods.
- **Constraints** — "the label stays legible", "steady motion", "no on-screen text".

Write it as flowing prose. A bulleted list or a run of `Label: value` pairs comes back **rendered as literal text on screen** — that is a real failure mode, not a style preference.

### Be explicit about motion

The model cannot infer intensity. Instead of `she picks up the bottle`, write `she slowly picks up the bottle with her right hand, turning it toward the camera`. Degree adverbs — **slowly, gently, quickly, casually, deliberately** — visibly change the render.

Two or three comma-joined cues on **one** action are good. A *second action* strung onto the first with `then` / `and then` / `followed by` renders as a smear, or not at all. Split it into two shots.

### Timestamps for pacing

For multi-beat sequences, timestamps control the rhythm:

```
[00:00] A guy in his 20s sits in his car holding an electrolyte packet. Medium shot, dashboard light.
[00:05] He pours the packet into his water bottle, shakes it. Close-up on hands.
[00:09] He takes a sip, pauses, nods with raised eyebrows. Back to medium shot.
[00:13] He holds the packet up to the camera, half-smile, and says: "Yeah, these are legit."
```

Useful for multi-shot choreography, for stopping the model rushing, and for style or camera changes inside one clip. Keep each block on one main action.

### Consistency anchors

When references are in play, say out loud that they must not drift:

- `The product from @Image1 remains visually unchanged in every shot.`
- `Keep the outfit unchanged across all cuts.`
- **Whenever a label, package, bottle, box or screen is visible**, paste the label hold in:
  > the product label remains perfectly sharp and identical to the reference image with its text unchanged and fully legible

  Seedance preserves logos and destroys printed text. `The Ordinary / Niacinamide 10%` came back as `MAGNANDE 10% ZINC 1%`.

Repeat the actor tag **verbatim** rather than back-referencing it. `the same woman` resolves to nobody — no identity carries across a cut — and an elaborated tag re-casts as readily as a missing one.

### Style anchors

Include at least one: `documentary` (natural, observational), `photorealistic` (grounded, no stylization), `handheld` (reinforces the phone-filmed look), `commercial` (polished — sparingly, and never on UGC).

**Words that pull the render toward plastic:** `cinematic`, `flawless`, `perfect`, `8k`, `4k`, `hyper-detailed`, `beauty lighting`, `ultra-realistic`, `masterpiece`, `award-winning`, and their Spanish and Portuguese equivalents. This is the exact list the estimate flags as `banned_polish`. Delete the word and describe the real thing instead — the light source, the surface, the flaw.

Two words the fork's guidance banned that this API's linter does **not** flag: `studio` and `professional`. They are still worth avoiding on UGC routes, where they cost you the phone-filmed look, and they are the correct word on the studio lookbook route, where the whole premise is a lit studio with the rig in frame. Judge by route, not by word list.

For premium and product-hero styles, reach for `dramatic` or `premium` where you were about to write `cinematic`.

### Iteration

Change **one** element at a time:

1. Action right, framing wrong → adjust the camera description.
2. Pacing rushed → add timestamps or cut dialogue.
3. Product drifts between shots → add a consistency anchor.
4. Motion stiff → add degree adverbs and a second comma-joined cue.

## What the estimate flags

`POST /v1/estimates` is mandatory anyway (it is the only source of a price), and it lints the prompt for free on the way through. Every finding comes back in `warnings` on a `200` as a `{rule, message}` pair whose message is the fix written out.

**Every one of them is advisory.** None blocks, none reprices, and `POST /v1/videos` runs no rules at all — a prompt that trips all eight is charged, rendered, and handed to the provider exactly as written. The skill layer is the only quality gate that exists.

| Rule | What it catches | Applies to |
|---|---|---|
| `banned_polish` | the polish-word list above | every route |
| `back_reference` | `the same woman`, `as before`, `la misma mujer` | any route with a person |
| `missing_actor_descriptor` | no age/gender/wardrobe token | **fires on every no-person route** — see below |
| `chained_motion` | `then`, `and then`, `followed by` | every route |
| `bullety_prompt` | `-` lines, or `Label: value, Label:` runs | every route |
| `no_spoken_line` | no quoted line — satisfied by any double-quoted text, or by the words `silent`, `b-roll`, `voiceover` | every route |
| `label_without_hold` | a visible label/package/bottle/box/screen with no label-hold clause | **the one to act on for product films** |
| `no_aspect_ratio` | no ratio stated in the prompt *text* (the `aspectRatio` field is what binds; the sentence steers composition) | every route |

**`missing_actor_descriptor` on premium reveal and product hero is correct-rule, wrong-route.** Those formulas have no person by design. Ignore the warning — do not invent an actor to silence it, and do not go looking for a field that suppresses it, because none exists any more. The same call applies on the Pixar and claymation routes.

**`label_without_hold` is the one worth acting on**, and it is exactly the one the fork's product formulas never mentioned. Both no-person formulas below now carry the clause in their template.

## Duration and dialogue

Any integer 4 to 15 seconds. Pick it from the spoken word count — a dense product line runs **2.5 to 3 words per second**, a calmer lifestyle line closer to 1.5, and that slack is what leaves room for a silent beat.

| Script word count | Duration |
|---|---|
| 1–8 words | 4–5s |
| 9–15 words | 6–8s |
| 16–25 words | 9–12s |
| 26–35 words | 13–15s |
| **36+ words** | **Too long** — offer to split into multiple clips |

For no-dialogue styles (product hero, premium reveal), default to **15s**.

Embed the line in the prompt with natural attribution: `she says: "…"` or `he speaks: "…"`. It is rendered as audio with lip-sync in the same call, which is why it cannot be changed afterwards without paying for the render again — and why `SKILL.md` gate 1 exists.

## Mini-draft tier

`seedance-2.0-mini` is the same grid, the same fields, and the same formulas at **half the price**, and it returns in 2–3 minutes instead of 3–8. Use it as a draft tier:

1. Ask once per workflow which tier to use (`SKILL.md` makes this an explicit question; no preference means `seedance-2.0`).
2. Upload the reference **once**. The `assetId` is durable, so the final render reuses it with no second upload.
3. Draft on `seedance-2.0-mini` until the prompt is right — wrong framing, a garbled label, or a rushed line costs half as much to discover.
4. Re-price at `POST /v1/estimates` with `model` set to the final tier and re-confirm before the finishing render. **Show both numbers side by side** when the user is choosing; never quote either from memory.

The prompt does not change between tiers. If it renders well on mini, the only thing the full model changes is fidelity.

## Style template directory

Pick the formula that matches the goal, then read its file before composing:

| User goal | Formula | Key trait |
|---|---|---|
| UGC selfie-style product review / testimonial | [seedance-2-ugc.md](seedance-2-ugc.md) | 9-layer formula: person + setting + realism markers + one spoken line |
| Dark-background premium product reveal (no person) | [seedance-2-premium-reveal.md](seedance-2-premium-reveal.md) | Void stage + text narrative + dramatic lighting |
| Elemental product hero — splash, mist, effects (no person) | [seedance-2-product-hero.md](seedance-2-product-hero.md) | Product-only with environmental interaction |
| Studio lookbook with voiceover (polished, multi-look) | [seedance-2-studio-lookbook.md](seedance-2-studio-lookbook.md) | Voiceover narration over styled product shots |
| Fast-paced feature walkthrough / demo | [seedance-2-feature-walkthrough.md](seedance-2-feature-walkthrough.md) | Feature-per-beat physical demos with dialogue |
| **Reverse-engineer a reference video** into a new formula for this library | [../analyze-video/SKILL.md](../analyze-video/SKILL.md) | Frames + transcript locally → a template file that lands in this folder and gets a row in this table |
| **Clone one specific ad** for a different product | [../clone-ad/SKILL.md](../clone-ad/SKILL.md) | The same analysis, but the output is a rendered clip rather than a file |

If none fits, compose a custom prompt directly from the platform rules above, following Subject + Action + Camera + Style + Constraints.

Neighbours worth knowing about: [ugc-selfie-style.md](ugc-selfie-style.md) in this folder is a **cross-model** UGC guide whose formulas target Veo 3.1, Sora 2 and Kling 3.0. Two of those are now live — see [veo-3-1.md](veo-3-1.md) and [sora-2.md](sora-2.md) — but Kling is not, and neither Veo nor Sora takes `referenceAssetIds`, so for Seedance UGC use [seedance-2-ugc.md](seedance-2-ugc.md) rather than porting a cross-model formula across. The other video model here is `omni-flash`: narrower grids, no references, but a 20,000-character prompt ceiling, guide at `shared/skills/gemini-omni-flash/prompting/guide.md`.

## Adaptation checklist (all styles)

- [ ] **Length matches the shot count** — ~90–130 words for one shot, ~250–330 for a 3–4 beat prompt (the hard limit is 4,000 *characters*)
- [ ] **`durationSeconds` set explicitly** — from the dialogue word count, or 15 for no-dialogue. The default is 5.
- [ ] **`aspectRatio` set explicitly** — `9:16` for social. The default is `16:9`.
- [ ] **Ratio restated in the prompt text** — `Vertical 9:16.` at the end. One line, clears `no_aspect_ratio`, steers composition.
- [ ] **Motion specificity** — degree and direction, two or three cues on one action, no `then`
- [ ] **Consistency anchors** — product and wardrobe stated as unchanged across cuts
- [ ] **Label hold** — present whenever a label, package or screen is visible
- [ ] **No polish words** — see the `banned_polish` list
- [ ] **`@Image1` tokens match the array** — every token points at a reference you actually send
- [ ] **One mode only** — `startImageAssetId` **or** `referenceAssetIds`, never both
- [ ] **Style anchor** — at least one (documentary, photorealistic, handheld)
- [ ] **Timestamps** — for multi-beat sequences
- [ ] **Priced live** — `POST /v1/estimates` this session, warnings read out, user said yes
