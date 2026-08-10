---
name: novoads-image-to-motion
description: >-
  Turn any still image into a professional motion graphic through the Novoads API on
  Seedance 2.5. Covers how to read a reference image, motion vocabulary for any image
  type — UI, marketing hero, flat-lay, key art, collage, product, character — the prompt
  clauses that control camera, timing, frozen regions and text fidelity, and the upload
  mechanics. Use whenever the user supplies an image and wants it animated, moving, or
  turned into video — including "animate this", "turn this into a motion graphic", "make
  this move", "この画像動かして", "モーショングラフィックにして", "I want the cards to pop in",
  "I want the bars to slide up", or when they describe motion beats for a static image.
  Also use when asked to write a Seedance prompt for an existing image. Do NOT use for
  text-to-video with no source image, restyling existing footage (this API takes no video
  input), cloning a reference video (use clone-video-ad), or a product photo that should
  seed a new scene rather than move as-is (use novoads-api).
---

# Image → Motion Graphic

Any still can become a professional motion graphic. The work is direction, not damage control: decide what moves, in what order, and say it precisely enough that there is nothing left to interpret.

Vague prompts produce vague motion. Specific prompts produce the shot you pictured. That is the whole discipline.

## Before anything: this runs on a Novoads account

- **Base URL:** `https://api.novoads.ai/v1` (host overridable with `NOVOADS_BASE_URL` — host
  only, you append `/v1`).
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`, read from `.env` at the repo root. The key
  is `novo_` plus 64 hex.
- **Check:** `./scripts/check-novoads-env.sh`; if the key is missing, run `./scripts/setup.sh`.
- **Never** print API keys, commit `.env`, or paste a key into `MASTER_CONTEXT.md`.

> **REST key required. A Novoads MCP connector is not a substitute.** If
> `NOVOADS_API_KEY` is missing or still the placeholder, stop before any
> generation work and tell the user: "Before continuing, create an API key at
> <https://novoads.ai/dashboard/settings?tab=api> and paste it into `.env`."
> That holds even when `mcp__novoads__*` tools are connected and authenticated in
> the session. Never call `mcp__novoads__*` tools from this repo's workflows: they
> are a different surface with different behavior, including the units they quote
> costs in. Repo installs verify with `./scripts/check-novoads-env.sh`; a solo
> install checks `NOVOADS_API_KEY` in the environment.

No account yet? **<https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack>**
The entry offer is a **$1 trial**. Never call it free.

**Every HTTP mechanic here belongs to the pack, not to this skill.** Auth, strict bodies,
status codes, the poll loop, concurrency and error envelopes are written out once in
[`novoads-api/SKILL.md`](../novoads-api/SKILL.md) and its
[`reference.md`](../novoads-api/reference.md). This file carries the craft and the two or
three fields this genre needs.

**The cost gate.** Before the first render, price the exact configuration with
`POST /v1/estimates` (`{"kind":"video","model":"seedance-2.5","durationSeconds":…,"resolution":…}`),
show what came back with the balance, and wait for a yes. The estimate is free and runs the
same structural validation the paid call runs. There are no rates in this file on purpose:
a written price rots silently and a quote that disagrees with the invoice is worse than no
quote. **N takes is N charges** — say the multiplication out loud before it happens.

There is no spoken-line gate here, because nothing speaks. That is one gate fewer, not
permission to skip the cost gate.

### The estimate's warnings are written for talking-head ads. Most do not apply here.

`POST /v1/estimates` returns an advisory `warnings` array. It never refuses a call or
changes a price, and its rules were written for UGC video with an actor in frame. On a
motion graphic they mostly misfire. Measured on this exact genre, 2026-08-10:

| Rule | What to do |
|---|---|
| `missing_actor_descriptor` | **Override it, every time.** There is no actor in a motion graphic and there is no wording that satisfies this rule. Say you are overriding it and why |
| `no_spoken_line` | Satisfied by saying the shot is silent, which you want anyway: `a silent motion graphic with no spoken dialogue` |
| `label_without_hold` | Substring-matched on words like "dashboard". The TEXT clause already does more than the rule asks; adding the vendor's label-hold sentence silences it |
| `no_aspect_ratio` | Genuinely worth fixing. End the prompt with the ratio in words, e.g. `Vertical 9:16.`, even though you also send `aspectRatio` |

Those three clauses take one warning-free run from four warnings down to one. **The one that
remains is permanent.** An agent that "fixes" `missing_actor_descriptor` by inserting
"a woman in her 20s in a grey zip hoodie" into a dashboard animation has destroyed the
render to satisfy a linter.

## Step 1: Read the image

Look at it properly before writing anything. Record:

- **Dimensions and ratio.** If the requested output ratio differs from the source, the layout gets rebuilt rather than cropped — say so, and describe the new arrangement in the prompt rather than hoping for it.
- **Photographic or illustrated.** State this explicitly in the prompt. Omitting it is the most common way a painted reference comes back photoreal, or vice versa.
- **Light direction and quality.** Hard raking light and soft ambient light imply completely different motion. Long shadows moving is a beat; flat light has nothing to reveal.
- **Layer depth.** What sits in front of what. This is where parallax and staggered entrances come from.
- **Every legible string, transcribed verbatim.** You will quote these back in the prompt.
- **The accent structure.** Most strong reference images run on one saturated accent against a restrained field. Whatever draws the eye is what should move last, or move most.

## Step 2: Choose the motion

Match the vocabulary to what the image *is*. This is genre craft — a flat-lay wants different motion from a character render, and reaching for the wrong grammar is what makes AI motion look generic.

**UI, app screens, toolbars, widgets, dashboards**
Panels slide or scale into place and settle. Cursors travel along an arc and click. Press states compress and spring back; hover states lift and deepen their shadow. Tooltips, menus and toasts appear on the interaction that triggers them. Toggles flip, progress fills, counters and badges land. Decide whether screen contents scroll or hold — either is available, but choose deliberately and say which.

**Marketing hero — headline, device, floating cards**
Headline rises and fades in as a block. Device and hand slide in from the frame edge with a slight overshoot and settle. Floating cards pop from slightly under full scale with a bouncy overshoot, staggered rather than together. Progress arcs draw their stroke. Then a gentle out-of-phase idle float so the frame never feels frozen. If figures should count up, say so explicitly; if they should hold, say that instead.

**Flat-lay, evidence board, desk scene**
Items drop in and settle with their shadows catching up a beat late. String, thread and connecting lines draw along their path. Papers can lift and flutter at the corner. A slow light sweep across the surface reads beautifully and costs nothing. Magnifiers and lenses can glide.

**Painted key art, illustrated scene, game art**
The most permissive class. Parallax between depth layers, drifting dust and light shafts, water and cloth movement, slow reveals, ambient particle motion. A slow push-in or drift works here when you want cinematic rather than graphic.

**Collage, paper-cut, halftone**
Assemble-from-empty: elements fly, snap or hinge into place in sequence with slight rotation overshoot. Suits stepped, stop-motion timing rather than smooth easing. Textures can breathe.

**Product still, object, packaging**
Slow turntable rotation, light sweep across the surface, lid lift, pour, unfold, exploded-view separation, hero reveal from shadow.

**Character, mascot, avatar**
Idle breathing, blink, head turn, expression shift, hair and cloth secondary motion, a gesture into a hold.

Across all of them: **stagger paired elements.** Two things entering simultaneously read as one flat sheet; a fifth of a second apart reads as two independent objects with their own weight. That single choice does more for perceived production value than any other.

## Step 3: Write the prompt

Structure the shot as timed beats. Include every clause below — each one removes a decision the model would otherwise make for you.

```
[Shot type] of [subject].

CAMERA: [either "The camera is locked off and never moves: no pan, no tilt, no
zoom, no push-in, no orbit, no drift." — or the specific move you want, with its
speed and direction.] Lighting is [constant / describe the change].

The reference image is the exact composed state — every colour, shadow, layout
position and glyph matches it precisely.

TEXT: all text stays perfectly intact and pixel-identical to the reference image
at every frame — [quote every string individually]. Same font, same weight, same
size, same position, correctly spelled. Text is never redrawn or re-lettered; it
travels rigidly with the object it sits on.

[If any region should not animate:]
[REGION] holds completely still: no scrolling, no swiping, no changing content.

TIMED BEATS:
0.0s — [the opening state, including anything that is ABSENT]
[t–t]s — [one object, one motion, with easing]
...
[final]s — Everything holds. [Any permitted idle drift.] No fade out.

[Negatives:] No film grain, no vignette, no lens flare, no added elements,
no watermark, no extra text.
```

The prompt ceiling on this model is **4,000 characters**. A full beat list fits
comfortably; if you are near it, cut negatives before cutting beats. Compose long prompts
in a file under `prompts/` rather than passing them as a shell argument.

Five clauses that carry most of the weight:

**Say the text should be perfectly intact, and quote every string.** This is the single highest-value line in the prompt. Asking for it explicitly works far better than leaving it implied, and naming each string individually works better than a general instruction.

**State the opening frame including what is absent.** If a tooltip, badge or card is visible in the reference and you want it to appear partway through, the prompt must say it is not there at 0.0s. Otherwise it is present from frame one and the reveal never happens. This is logic, not model behaviour — it applies no matter how capable the model is.

**Declare anything that holds still.** A region that should not move needs saying so. Silence is not an instruction.

**End with an explicit hold.** Without a final beat pinning the last state, models tend to invent a drift, a fade or a camera move to fill the remaining time.

**One object per beat, with easing named.** "The cards pop in" is three possible shots. "Each card scales up from slightly under full size with a soft bouncy overshoot, 0.2s apart" is one.

## Step 4: Run it

`POST /v1/videos` with `"model": "seedance-2.5"` is the default for image-to-motion. The
still goes in as `startImageAssetId`, which animates it as the literal first frame.

- `durationSeconds` — **4 to 30** on this model, an integer from the grid. Match it to the
  beat list and leave a beat of hold at the end. Out-of-grid values are rejected, never
  rounded.
- `aspectRatio` — `16:9` (default), `9:16`, `1:1`, `4:3`, `3:4`, `21:9`.
- `resolution` — `480p` or `720p`. **720p is this model's ceiling**, not a floor: 1080p and
  4k belong to `seedance-2.0` and are a `400` here.
- `audioEnabled` — `false` unless sound is wanted.
- **For several takes, fire the identical payload N times.** There is no
  variations-per-call field. At most **five** generations may be in flight per
  organization; a sixth comes back `429` with `details.reason: concurrency_limit`, which
  means wait for a slot rather than lengthen the backoff. N takes is N charges and belongs
  in the cost gate.

Submit returns `202` with `jobId` and `creditsCharged` — that `202` is the **only** place
the charge appears, so log it now. Poll `GET /v1/generations/{jobId}` every 15 seconds until
a **terminal** status, then `GET /v1/generations/{jobId}/watch` for the file into
`outputs/<descriptive-name>/`. Nothing here has measured a `seedance-2.5` wait: say it is
unknown rather than lending it `seedance-2.0`'s range. Full sequence in
[`novoads-api/SKILL.md`](../novoads-api/SKILL.md).

If the still needs building or rebuilding first, generate it before animating. A crisp, correctly-composed, correctly-lettered source frame is the foundation of the whole shot — the video stage carries forward what it is handed. Use [`chatgpt-image-ad`](../chatgpt-image-ad/SKILL.md) for typography and UI mimicry and [`nano-banana-image-ad`](../nano-banana-image-ad/SKILL.md) for photoreal and lifestyle; the decision tree between them is in [OVERVIEW.md](../../shared/skills/image-ad-prompting/OVERVIEW.md). When it matters, run the same prompt through both and compare rather than assuming. `POST /v1/images` is synchronous, and the `assetId` it returns goes straight into `startImageAssetId` with no download-and-re-upload hop.

**This API takes no video input.** There is no restyle of existing footage and no
multi-turn edit: `omni-flash` here is one stateless call, not the conversational editor its
vendor documentation describes. If the ask is to restyle a clip, say so and stop.

### Uploading the still

```
POST /v1/uploads  {"contentType":"image/png","sizeBytes":<exact bytes>}  → 201
  { assetId, uploadUrl, method, headers, expiresInSeconds: 900, maxBytes }
PUT the raw bytes to uploadUrl with the returned headers, byte for byte  → 200
pass assetId as startImageAssetId
```

Two things worth knowing before they cost a call:

- **`Content-Type` and `Content-Length` are both signed into the URL.** If either differs
  from what was returned, storage rejects the PUT with a `403` that looks like an auth
  failure and is not one. Measure the file, do not estimate it.
- **The `assetId` is durable and reusable without limit** — it is the storage key itself.
  Upload the image once and reuse it across every iteration and every model. The 900-second
  expiry belongs to the **upload URL**, not to the asset. That distinction is the one most
  likely to be conflated, and re-uploading between takes is wasted work.

`startImageAssetId` and `referenceAssetIds` are **separate modes and cannot be combined** —
a body with both is a `400` naming exactly that, before any charge. Start frame animates one
image; references composite several into a new scene. This skill is the start-frame mode.

## Step 5: Review and iterate

Generate several, pick, then refine the prompt rather than rerunning it unchanged. Look at:

- **Did the beats fire in order,** or collapse into one simultaneous move? If collapsed, spread the timings further apart and shorten each one.
- **Is the camera doing what you asked?** Unrequested drift usually means the camera clause was too short — expand it into the explicit no-pan-no-zoom-no-push list.
- **Read every quoted string at full size.** Check the small labels, not just the headline.
- **Did anything hold still that should have moved,** or move that should have held? Both are prompt clarity problems, not model problems.
- **Shadow and light consistency**, especially in flat-lay and product work where one light direction is the only depth cue.

When something is off, add specificity rather than emphasis. Naming the object, the distance, the direction and the easing beats restating the same instruction more forcefully. If a beat keeps coming out wrong, describe it as a rigid transform of a named object — that is almost always clearer than describing the effect you want.

## Hard rules

1. **Price it live before every render**, from `POST /v1/estimates` in this session. No rate
   lives in this file.
2. **N takes is N charges**, said out loud before the first one fires.
3. **720p is the ceiling** on this model. Do not offer or submit higher.
4. **Never send `startImageAssetId` and `referenceAssetIds` together.** Separate modes.
5. **Upload once.** The asset is durable; the URL is what expires.
6. **The 0.0s beat names what is absent**, or the reveal cannot happen.
7. **Quote every string individually** in the TEXT clause, and read every one back at full
   size in QA.
8. **Text fidelity on our render path is unverified.** Write the clause because it is what
   the model responds to. Do not tell a user it has been verified here until eval E6 has
   been run. See [evals.md](evals.md).
9. **Never add an actor to satisfy `missing_actor_descriptor`.** It is a permanent false
   positive on this genre. Override it out loud.
10. Working files go in `outputs/<name>/` and long prompts in `prompts/`. Never invent a new
    top-level directory.
