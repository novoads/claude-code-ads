---
name: novoads-api
description: >-
  Generate AI video ads and image ads through the Novoads REST API
  (api.novoads.ai). Use when the user wants a UGC video, a product video, a
  talking-head ad, an AI actor holding a product, a TikTok or Reels or Shorts
  ad, a static image ad, or asks to "make me an ad", "generate a video",
  "animate this photo", or names a model (Seedance, Seedance Mini, Omni Flash,
  GPT Image 2, Nano Banana Pro, Reve). Handles upload, dialogue approval, cost
  confirmation, generation, polling, and download. Not for editing an existing
  video file and not for publishing to an ad platform.
---

# Novoads REST API

Spend your effort on the prompt and on confirming the spoken line. The HTTP is mechanical and is written out below; the prompt is where the render is won or lost.

## Configuration

- **Base URL:** `https://api.novoads.ai/v1` (host overridable with `NOVOADS_BASE_URL` — host only, you append `/v1`).
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`, read from `.env` at the repo root. The key is `novo_` plus 64 hex.
- **Check:** `./scripts/check-novoads-env.sh`
- **Never** print API keys, commit `.env`, or paste a key into `MASTER_CONTEXT.md`.

### If the key is missing or the API returns 401 or 403

Run `./scripts/setup.sh`, or tell the user to create a key at <https://novoads.ai/dashboard/settings?tab=api>. Prefer the editor: ask them to paste the key **inside `.env`** rather than into chat. If they do paste it in chat, write `.env` for them, confirm "saved to `.env`" **without repeating the key**, and tell them chat history may retain secrets, so the key is worth rotating if that transcript could be shared.

A 401 means the key is wrong, revoked, or from another account. A 403 with `error.details.reason` of `plan_required` or `subscription_inactive` means the key is fine but the account has no live subscription. Those are different problems and you should say which one it is.

### Signup link

If the user does not have a Novoads account, give them this link at any point in a session, in any context where it is useful:

**<https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack>**

The entry offer is a **$1 trial**. Never call it free.

### After the connectivity check passes

When `./scripts/check-novoads-env.sh` returns 200 and the user has not yet said what they want, offer starting points in chat and stop. Nothing is printed by a script for you: a banner cannot see their product, their `references/` folder, or their language, so it suggests nothing.

1. **A UGC video built from their own product photo.** Ask them to drop it into `references/`. Route: `seedance-2.0` plus `startImageAssetId`.
2. **The same idea on `seedance-2.0-mini` first**, to get the prompt right before the final render. Price both at `POST /v1/estimates` and show the difference rather than quoting one from memory.
3. **A static image ad**, when what they need is a still and not a clip. Route: `gpt-image-2` for heavy text or a mimicked UI, `nano-banana-pro` for a photoreal scene.

Offer, do not choose. A first render fired on a guess is a charge the user did not ask for.

## Read order

1. Repo root **`MASTER_CONTEXT.md`** when present: brand voice, default product, accumulated decisions. It carries **no prices** — that is deliberate, see gate 2.
2. This file. It is the router and it covers the full call sequence.
3. **List `references/` at the repo root before you ask the user for a photo.** It is where they keep product shots, actor stills, and style boards, and it is gitignored, so the files are theirs and are not in this skill's folder. A product photo found there becomes `startImageAssetId` (video) or an entry in `referenceAssetIds` (images). If it is empty, ask for the photo rather than inventing the product.
4. **MANDATORY before composing any prompt:** the `prompting/prompt-library/` file for the route you picked in the decision tree. The libraries carry the craft; every HTTP detail comes from this file and `reference.md`, which win whenever the two disagree.
5. `reference.md` when you need a field you do not see here, or when you hit a status code you want to branch on.

## Decision tree

| The user wants | Route |
|---|---|
| A UGC video: a person talking to camera about a product | `seedance-2.0`, and read [seedance-2-ugc.md](prompting/prompt-library/seedance-2-ugc.md) first |
| The same thing, but cheap, to test a prompt before committing | `seedance-2.0-mini`, same grid, same formulas, half the price and back in 2–3 minutes. The draft-then-finalize loop is *Mini-draft tier* in [seedance-2.md](prompting/prompt-library/seedance-2.md) |
| A premium product reveal: dark void, no person, text narrative | `seedance-2.0` + [seedance-2-premium-reveal.md](prompting/prompt-library/seedance-2-premium-reveal.md) |
| A product hero: elemental effects, splash or mist, no person | `seedance-2.0` + [seedance-2-product-hero.md](prompting/prompt-library/seedance-2-product-hero.md) |
| A studio lookbook: polished, voiceover, multi-look | `seedance-2.0` + [seedance-2-studio-lookbook.md](prompting/prompt-library/seedance-2-studio-lookbook.md) |
| A fast-paced feature walkthrough | `seedance-2.0` + [seedance-2-feature-walkthrough.md](prompting/prompt-library/seedance-2-feature-walkthrough.md) |
| A fast vertical clip with no dialogue requirement | `omni-flash`, and read `shared/skills/gemini-omni-flash/prompting/guide.md` first — it is the only model here with a 20,000-character prompt ceiling, and its grids are narrower than Seedance's (`durationSeconds` 4/6/8/10 only, `aspectRatio` `9:16` or `16:9` only, **no `referenceAssetIds`**) |
| A video that starts from a specific photo | any video model plus `startImageAssetId` — it animates that image as the first frame |
| A video built from several photos: the actor **and** the product, a wardrobe, a setting | `seedance-2.0` or mini plus `referenceAssetIds` — up to **9** images, composited rather than animated, addressed in the prompt text as `@Image1`…`@ImageN` in the order you send them. Not on `omni-flash`, whose variant has no such field, and **never alongside `startImageAssetId`**: they are separate modes and a body carrying both is a `400` |
| The same person to hold across several clips of a series | pass that person's photo in every clip's `referenceAssetIds` and repeat the actor tag verbatim. Seedance re-casts on every cut, so a repeated description alone does not hold a face; see [seedance-2-feature-walkthrough.md](prompting/prompt-library/seedance-2-feature-walkthrough.md) |
| A reference video turned into a reusable template: "make videos like this", "deconstruct this" | read [prompting/analyze-video/SKILL.md](prompting/analyze-video/SKILL.md). Frames and transcript are extracted locally with ffmpeg and Whisper, and the output is a new formula file in `prompting/prompt-library/`. Nothing is charged until the optional test render at the end |
| One specific ad cloned for their own product: "make this ad but for my product" | read [prompting/clone-ad/SKILL.md](prompting/clone-ad/SKILL.md). The same local analysis, but the output is a rendered clip and both gates apply. A source longer than 15s becomes a series, held together by passing the same `referenceAssetIds` to every clip — there is no video-to-video on this API |
| A static ad with heavy text or a mimicked UI | `gpt-image-2` |
| A photoreal still: a person, a product in a scene | `nano-banana-pro` |
| A different look on a still, or a second opinion on one | `reve-2.1` |
| A Pixar-style 3D animated ad | read `shared/skills/pixar-style-ad/prompting/guide.md`: storyboard on `gpt-image-2`, animate each beat on `seedance-2.0` + `startImageAssetId`, stitch with ffmpeg. Runnable scripts in `shared/skills/pixar-style-ad/scripts/`. Nothing on the API rejects a stylized prompt; the estimate will still *advise* `missing_actor_descriptor` on a route whose lead is an appliance, and on this route that advice is wrong — ignore it |
| A claymation / Aardman-style ad | read `shared/skills/claymation-ad/prompting/guide.md`, same shape over 8 beats, same note about the estimate's advice |
| Captions burned onto a finished MP4 | read `shared/skills/caption-video/prompting/guide.md`. Out of band — ffmpeg, Whisper and HyperFrames, no Novoads call and no credits |
| Meta image-ad creatives from a brief or a template | read `shared/skills/image-ad-prompting/OVERVIEW.md` first, then `chatgpt-image-ad` or `nano-banana-image-ad` |
| To reverse-engineer an existing image ad into a reusable template | the `image-ad-clone` skill |
| A YouTube thumbnail | the `generate-youtube-thumbnail` skill |
| B-roll, an ambient product clip, a scene | There is no b-roll endpoint. Generate a silent clip: `omni-flash`, or `seedance-2.0` with the word `silent` or `b-roll` in the prompt |
| Sora 2, Veo 3.1, or Kling | Not on this API. Say so plainly; the libraries sit in the repo for when they land |
| To edit an existing MP4 they already have | Not this skill, except captions (row above). Say so |
| To publish the result as an ad on Meta or TikTok | Not this skill. The output is a file. The `meta-ad-builder` skill takes it from there |

Prefer the **shortest** path. If one model answers the request, do not build a pipeline around it.

## Step 0: classify before you call anything

Refusing is a successful result. If the request is to edit a file the user already has, or to publish to an ad platform, say the skill does not do that and stop. Do not improvise a pipeline out of the generation endpoints.

## The two gates

Two separate approvals stand between a request and a charge, and **neither implies the other**. Approving a concept is not approving a sentence, and approving a sentence is not approving a spend.

### Gate 1 — the spoken line (MANDATORY for any video with dialogue)

Seedance renders the audio and the lip-sync in the same call, so the line inside the double quotes is what the actor says, out loud, in the finished video. It cannot be changed afterward without paying for the render again.

1. **Extract the dialogue from the drafted prompt** and show it on its own, separate from the visual description.
2. **Present it as a numbered list** with beat labels (hook / show / demo / verdict, or similar). Mark silent beats `(silent beat — no dialogue)`.
3. **Count the spoken words**, state the target duration, and say whether it fits at a natural pace.
4. **State the `language`** you are going to send, because that is the language the ad is rendered in.
5. **Ask for approval explicitly.** Never infer it from an earlier yes about tone, template, or cost.

Use this structure:

```
📝 Dialogue script (please confirm before I generate)

  1. [HOOK]    "Bro. BRO. Look what just showed up."
  2. [SHOW]    "That colorway? Insane. Like, who greenlit this?"
  3. [DEMO]    (silent beat — thumb brushing the suede, small nod)
  4. [VERDICT] "I'm wearing these to the gym tomorrow. You have to see them in person."

Total spoken words: ~28  |  Target duration: 15s  |  language: en  |  Fits at natural pace: ✅

Approve this dialogue? (yes / edit / rewrite)
```

If they say edit, revise and re-present the block until they approve. The gate applies to every flow where the model speaks. Skip it for silent flows: product hero, premium reveal without voiceover, and images.

### Gate 2 — the cost estimate (MANDATORY)

**Never state a credit cost from memory, and never generate before showing the user a number that came from a live call in this session.** There are no rate tables in this repo, in `MASTER_CONTEXT.md`, or in the logs. Prices come from `POST /v1/estimates` at call time, and that is the whole policy.

`POST /v1/estimates` spends nothing and returns:

```json
{ "credits": 3.2, "balance": 100, "sufficient": true }
```

When it is short it also returns `shortBy` and `topUpUrl`. When the prompt trips a rule it returns `warnings`: craft advice, run for free against the prompt you sent, each entry a `{rule, message}` pair whose message is the fix written out.

**Every warning is advisory.** None of them blocks a generation, none of them changes the price, and a prompt that trips every one of them renders exactly like a prompt that trips none. Read them out before generating anyway — the estimate is the only place these rules run at all, so this is the one chance to see the advice before you pay.

**The estimate body is not the generate body.** It takes only the fields that move the price, plus a `kind` discriminator, and it is strict: any extra key is a 400.

| Estimate accepts | Video | Image |
|---|---|---|
| required | `kind: "video"`, `prompt` | `kind: "image"`, `prompt` |
| optional | `model`, `durationSeconds`, `language` | `model`, `numImages`, `language` |

`aspectRatio`, `startImageAssetId`, `referenceAssetIds`, and `productId` do not belong here. They do not change what you pay, and sending one is a rejected request. **There is no `styleFamily` field** — not here and not on a generation call; it was removed from the API and sending it is a `400 Unrecognized key`.

```bash
curl -sS -X POST https://api.novoads.ai/v1/estimates \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"kind":"video","model":"seedance-2.0","durationSeconds":12,"language":"en","prompt":"..."}'
```

**Pass `model` explicitly.** It defaults to `seedance-2.0`, the schedules differ by 2x across the video set and by more than 3x across the image set, and the per-model prompt ceiling is enforced against whichever model you name. Pricing the wrong model is a quote that disagrees with the invoice.

It runs the same access checks and the same structural validation the paid call runs, which is why it is worth calling every time and not only when you are unsure:

- **The prompt rules run here and nowhere else.** Every finding comes back in `warnings` on a `200`. `POST /v1/videos` and `POST /v1/images` do not run them at all — a prompt that trips five rules is charged, rendered, and handed to the provider exactly as written. So the mandatory cost call is also a free prompt lint: one call, not a new step.
- **What it does still refuse, for free:** a malformed body — it is strict, and any key that does not move the price is a `400` — and a prompt longer than the *named model's* character ceiling (4,000 for `seedance-2.0` and mini, 20,000 for `omni-flash`; name no model and it is judged as `seedance-2.0`).
- A quote it returns cannot disagree with the invoice, with two exceptions worth knowing: it never sees `aspectRatio`, the asset fields, or `productId`, and it **skips moderation**, which the paid call runs. A clean estimate can still come back `422` at generation — moderation is the only thing left that refuses a prompt for what it says.

**Multiply before you show.** N variations is N charges. Show the per-call number, the count, and the total.

**Warn when the total exceeds the balance.** `balance` comes back on the same response: if the batch total is larger, say so before asking for a yes, and quote `shortBy` and `topUpUrl` when the estimate provides them. `sufficient` is a snapshot, not a reservation — another session or a renewal can move the balance between the quote and the call.

Show `credits`, the count, the total, and `balance`. Get a yes. Then generate.

## Choices you make out loud, and choices you infer

**Ask, every time:**

- **Seedance tier, once per workflow.** Before the first Seedance video call: *"Use default `seedance-2.0`, or `seedance-2.0-mini` (half price)?"* No preference means `seedance-2.0`. Whichever they pick goes into the estimate, so the quoted number is the one they pay.
- **How many variations**, for every prompt. Default 1. N variations means N identical calls — there is no batch parameter — and the results come back as a numbered list so they can compare and pick.

**Infer, and state what you inferred rather than asking:**

- **`aspectRatio`: default `9:16`** for anything headed to Reels, TikTok, Stories, or a vertical feed. Seedance defaults to `16:9`, and a landscape ad is a wasted render; `omni-flash` already defaults to `9:16`, and images default to `1:1`. Go landscape only when the user asks. Seedance also accepts `1:1`, `4:3`, `3:4`, and `21:9`.
- **`language`**: the language the script is written in. Set it, and show it in the dialogue gate. Write the prompt in that language too — nothing on the API pushes back on a Spanish or Portuguese prompt, and the estimate's advice covers those patterns as well, with the fix quoted in the prompt's own language.
- **`durationSeconds`**: from the word count, below. No model defaults to its maximum — Seedance defaults to 5 and `omni-flash` to 8 — so always send it.

## Script length → duration

Count the words in the spoken line and round **up**. A dense product script runs about **2.5 to 3 spoken words per second**; a calmer lifestyle line runs closer to 1.5, and that slack is what leaves room for a silent beat. Plan on 2.5 and give the line air.

### `seedance-2.0` and `seedance-2.0-mini` — any integer 4 to 15

| Script length | Duration |
|---|---|
| 1–8 words | 4–5s |
| 9–15 words | 6–8s |
| 16–25 words | 9–12s |
| 26–35 words | 13–15s |
| **36+ words** | **Too long** — offer to split |

For no-dialogue styles (product hero, premium reveal), default to **15s**.

### `omni-flash` — enum 4, 6, 8, 10

| Script length | Duration |
|---|---|
| 1–10 words | 4s |
| 11–15 words | 6s |
| 16–20 words | 8s |
| 21–25 words | 10s |
| **26+ words** | **Too long** — split, or move to Seedance |

There is no `resolution` field on this API. 720p is what you get.

### Splitting a long script

1. **Tell the user** the script is too long for one clip and show the word-and-duration math.
2. **Offer two options:** split at natural sentence boundaries into chunks that each fit, or move to the model with more room (`seedance-2.0` tops out at 15s and is the longest single clip here).
3. If they split, each chunk is its own generation call — and the variation count applies to *each* chunk.
4. **Offer to stitch** with ffmpeg: download the segments, `ffmpeg -f concat -safe 0 -i list.txt -c copy output.mp4`, re-encoding if the codecs differ. Hand back both the stitched file and the individual segments.

## The full sequence

### 0. Resolve the product (once per session)

`GET /v1/products`. Default to the product named in `MASTER_CONTEXT.md` under "My workspace". If no default is set: with exactly one product, auto-populate `MASTER_CONTEXT.md` with its id and name; with several, ask the user once and save the choice. With none, omit `productId` — it is optional.

Pass `productId` on every generation call. It is what makes `GET /v1/generations?productId=…` a useful history later. There is no dated-folder ritual to run here: folders are read-only on this API and there are no projects on it at all.

### 1. Upload the reference or start frame (skip if there is none)

```bash
curl -sS -X POST https://api.novoads.ai/v1/uploads \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"contentType":"image/jpeg","sizeBytes":248193}'
```

Returns `assetId`, `uploadUrl`, `method`, and `headers`.

Then PUT the raw bytes to `uploadUrl`, sending **exactly** the headers it returned:

```bash
curl -sS -X PUT "$UPLOAD_URL" \
  -H "Content-Type: image/jpeg" \
  -H "Content-Length: 248193" \
  --data-binary @product.jpg
```

Both headers are signed into the URL. `image/jpeg; charset=utf-8` is a 403, and so is a `Content-Length` that does not match the bytes you send. `sizeBytes` must be the real file size, so measure it, do not estimate it.

**Upload once, reuse it forever.** The `assetId` is durable and reusable across calls and across models, which is what makes prototyping on `seedance-2.0-mini` and finalizing on `seedance-2.0` cheap. The presigned *upload URL* expires in 900 seconds; the `assetId` does not.

**Start frame or references — not both.** `startImageAssetId` animates one image as the first frame. `referenceAssetIds` (Seedance only, up to **9**, images only) composites the images as visual references, addressed positionally in the prompt text as `@Image1`…`@ImageN` in the order you send them. They select different modes on the model, so a body carrying both is a `400`, and `omni-flash` takes no references at all.

### 2. Price it (gate 2)

`POST /v1/estimates` with `kind`, `prompt`, `model`, and the duration or image count. See gate 2 above for the exact field list, and remember it rejects any field that does not move the price.

### 3. Confirm the spoken line (gate 1)

See gate 1 above. Both gates must be satisfied, in either order, before anything is submitted.

### 4. Generate

```bash
curl -sS -X POST https://api.novoads.ai/v1/videos \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "seedance-2.0",
    "prompt": "...",
    "durationSeconds": 12,
    "aspectRatio": "9:16",
    "language": "en",
    "startImageAssetId": "...",
    "productId": "..."
  }'
```

Returns `202` with `jobId`, `status`, `creditsCharged`, and `model`. **No `warnings`** — the job responses carry none. The craft advice was on the estimate, and this call ran no prompt rules at all.

**Set `aspectRatio` explicitly.** Seedance defaults to `16:9` and an ad that ships landscape is a wasted render. **Set `durationSeconds` explicitly** too: Seedance defaults to 5, `omni-flash` to 8, and neither is the maximum.

For N variations, fire the identical payload N times. **Five generations per organization may be in flight at once** — fire at most five, then start the next as each one reaches a terminal state. A sixth submission comes back `429` with `error.details.reason` of `concurrency_limit`, which is a different problem from a rate limit and takes a different response: wait for a slot, do not lengthen the backoff.

**Log each submission immediately**: one line appended to `logs/novoads-api.jsonl` with the timestamp, endpoint, model, `jobId`, `productId`, and the request config (duration, aspectRatio, language, reference counts, prompt **word count**). Never log the prompt text, the key, or the Authorization header. The log is observability — latency and `creditsCharged` after the fact. **It is never a pricing source.** Prices come from `/v1/estimates`, always.

### 5. Poll

```bash
curl -sS https://api.novoads.ai/v1/generations/$JOB_ID \
  -H "Authorization: Bearer $NOVOADS_API_KEY"
```

`status` is one of `queued`, `running`, `finalizing`, `succeeded`, `failed`, `blocked`, `canceled`. The last four are terminal. `queued` means charged and submitted but not yet rendering, which is normal and not a stall.

**Poll until TERMINAL, not until `succeeded`.** A loop that waits only for `succeeded` never returns on a job that failed, and the user watches a spinner forever on a render that is already dead.

**Poll every 15 seconds.** Not 5: five concurrent jobs at a 5-second interval is 60 calls a minute, exactly the per-key rate limit, with no headroom left for the calls that do real work.

Tell the user the wait up front, per model, so they do not think it hung:

- `seedance-2.0`: usually **3 to 8 minutes**, most often around 5.
- `seedance-2.0-mini`: usually **2 to 3 minutes**.

When `status` is `succeeded`, `outputUrl` is a presigned download URL valid for `outputUrlExpiresInSeconds` (3600). Read the job again for a fresh one rather than storing it. Update that job's log line with the terminal status, `creditsCharged`, and the elapsed time.

### 6. Download and hand it over

```bash
curl -sSL -o ad.mp4 https://api.novoads.ai/v1/generations/$JOB_ID/watch \
  -H "Authorization: Bearer $NOVOADS_API_KEY"
```

`/watch` 302s to a URL signed at request time, so it never hands you an expired link. While the job is unfinished it is a `409` naming the current status.

Save under **`outputs/<descriptive-subfolder>/`** — `outputs/seedance-ugc-cerave/`, not the job id — and name the file for what it is. Then **always open the folder** so the user can review immediately: `open "<dir>"` on macOS, `xdg-open` on Linux, `explorer` on Windows. Try `open` first and fall back silently.

Present multiple variations as a numbered list. If a job came back `failed` or `blocked`, say which, and quote the `error` the job carries.

## Images are synchronous

`POST /v1/images` returns the finished images in the response body. **There is nothing to poll and no `/watch` step.** The response carries `images[]` with `url`, `expiresInSeconds`, `width`, and `height`, plus `jobId`, `status`, `model`, and `creditsCharged`. No `warnings`, and no prompt rules ran here either — price the prompt at `/v1/estimates` first if you want the advice.

- `referenceAssetIds`: up to **4** on the image models, images only, order preserved and addressable positionally by the prompt. Upload each one first — there is no base64 field.
- `numImages`: 1 to 4, and it multiplies the price.
- Images take **no `startImageAssetId`**: there is no first-frame concept on a still.

### Image QA (mandatory)

Images are money already spent, and a defective still is not a deliverable. After each image comes back, **look at it**.

Look for: extra or missing hands or fingers, wrong limb count, distorted or duplicated or merged facial features, melted or fused objects, impossible anatomy, stray limbs, texture and boundary artifacts, and garbled text where text was requested.

If something is wrong, **regenerate with a corrected prompt** that names the defect ("exactly two hands, five fingers each", "a single face, no duplicated features"). Never resend the identical payload expecting a different result.

- **Cap: 2 regenerations per originally requested image**, 3 attempts total. After the cap, stop, show the best attempt, say what still looks wrong, and ask how they want to proceed.
- **No second cost confirmation.** Once the batch is approved, QA retries proceed automatically — the one exception to gate 2.
- **Every retry is billed.** Sum the extra credits and report them when the loop ends.

## The `references/` folder

Check it before asking the user for anything. `references/influencers/` for people, `references/products/` for products, `references/aesthetics/` for style and mood. If a relevant file is already there, offer to use it instead of asking.

Before uploading a reference, if its longest side is under 1024 px, upscale with Lanczos to 1080 px on the long side and re-encode as RGB JPEG at quality 90–95, which strips alpha and keeps the payload sane. (No minimum input size is documented for this API — the practice carries over from a sibling API that answered small images with a 422, and is unverified here.)

## Errors: branch on `error.code`, never on the message

Every error is `{"error":{"code":..., "message":..., "requestId":..., "details":...}}`. Quote `requestId` when reporting a problem; it matches the `x-request-id` response header.

| Status | `code` | What it means | What to do |
|---|---|---|---|
| 400 | `invalid_input` | **The request is malformed** — an unknown key, an out-of-grid `durationSeconds`, a prompt over the model's ceiling. `details.issues` names each bad field. Never a judgement on the writing. | Fix the field. Nothing was charged. |
| 401 | `unauthorized` | Missing, malformed, or revoked key. | Send the user to Settings → Developer. |
| 402 | `insufficient_credits` | `details` carries `required` and `available`. | Tell the user the gap. Do not retry. |
| 403 | `forbidden` | `details.reason` is `plan_required`, `subscription_inactive`, or the API is off for that account. | Say which. These are different fixes. |
| 404 | `not_found` | No such object **for this organization**. | Do not assume it exists elsewhere. |
| 409 | `conflict` | Includes `/watch` on an unfinished job. | Keep polling. |
| 422 | `content_policy` | Moderation blocked it, and this is the **only** way a prompt is refused for what it says. The estimate skips moderation, so it can land on a prompt the estimate priced clean. | Nothing was charged. Rewrite or stop. |
| 429 | `rate_limited` | **Four different causes.** Branch on `details.reason`. | See below. |
| 500 | `internal_error` | | **Do not blindly retry.** See below. |
| 502 | `provider_failed` | A model provider failed. | Credits are refunded automatically. |

**The 400 vs 422 line is simple now, and worth stating because it used to be blurred.** A `400` is a malformed request and nothing else. A `422` is moderation and nothing else. Prompt craft — a missing actor descriptor, no spoken line, a banned polish word — refuses nothing anywhere: those come back as advisory `warnings` on the estimate, and the generation runs regardless. Do not write a retry loop that expects a rule to stop a bad prompt; the only thing that stops it is you, reading the warnings.

**A 429 is not always a rate limit.** `details.reason` names which of four ceilings refused you, and they are paced differently:

- `concurrency_limit` — five generations already in flight for the organization (`details.inFlight` says how many). **Waiting is the only fix**: a longer backoff does nothing, a finished job does. Generation endpoints only; reads, estimates, and uploads never hit it.
- `key_limit` — 60 requests a minute on this key. The `X-RateLimit-*` headers track this one. Honor `Retry-After`.
- `organization_limit` — 180 a minute across every key the organization holds. `X-RateLimit-*` will still show room on your key; that is correct, not a broken limiter. Minting another key does not raise it.
- `client_limit` — 1,200 a minute pre-authentication. Carries no `X-RateLimit-*` trio.

Every 429 carries `details.reason` and a `Retry-After` header — sleep on the header, branch on the reason. `details.inFlight` (concurrency refusals) is the only other key the spec names; do not expect one it does not.

**On a 500, do not retry until you have checked.** The generation endpoints charge credits, and a failure can land after the debit committed, so a blind retry can pay twice. Call `GET /v1/generations` first. If the job is there, poll it instead of resubmitting. There are no idempotency keys.

## Guardrails

Append one line per new failure. Forward only. Every bullet is a real thing that went wrong.

- Never write a credit number into a file, a summary, or `MASTER_CONTEXT.md`. Prices come from `/v1/estimates` at call time.
- Never generate without both gates: the spoken line, and the cost.
- Always set `aspectRatio`. The Seedance default is `16:9`.
- Always set `durationSeconds`. Seedance defaults to 5, `omni-flash` to 8.
- `Content-Type` on the presigned PUT must match byte for byte. Adding `; charset=utf-8` is a 403.
- Never resubmit after a 500 without checking `GET /v1/generations` first.
- A 400 is a malformed request. Read `details.issues`, fix the field, and do not go looking for a prompt rule — none of them can 400 anymore.
- The prompt rules stop nothing. **Nothing on the API will save a weak prompt from being rendered and billed**, so the estimate's `warnings` and the prompt libraries are the whole quality gate. Read the warnings out loud before spending.
- Never send `styleFamily`. The field no longer exists on this API and any body carrying it is a 400.
- Never fire more than five generations at once, and poll at 15 seconds, not 5.
- A QA retry still costs credits. Cap at 2, and report the extras.
- Real brands only in prompts. Do not substitute a blank bottle for a product the user has not given you — the API will happily render it and charge for it, and `blank_label` on the estimate is the only thing that will tell you. Ask for the photo.

## References

- [reference.md](reference.md) — every endpoint, field, limit, and error, plus the dated discrepancy list.
- [prompting/prompt-library/seedance-2-ugc.md](prompting/prompt-library/seedance-2-ugc.md) — the UGC prompt formula, with a worked example that passes validation.
- [prompting/guide.md](prompting/guide.md) — marketing brief → API.
- [prompting/brand-voice-starter.md](prompting/brand-voice-starter.md) — template to copy into `MASTER_CONTEXT.md`.
- The other Seedance formulas: [seedance-2.md](prompting/prompt-library/seedance-2.md) (platform guide), [premium reveal](prompting/prompt-library/seedance-2-premium-reveal.md), [product hero](prompting/prompt-library/seedance-2-product-hero.md), [studio lookbook](prompting/prompt-library/seedance-2-studio-lookbook.md), [feature walkthrough](prompting/prompt-library/seedance-2-feature-walkthrough.md).
- Image and character craft: [ugc-selfie-style.md](prompting/prompt-library/ugc-selfie-style.md), [ugc-product-selfie.md](prompting/prompt-library/ugc-product-selfie.md), [product-showcase.md](prompting/prompt-library/product-showcase.md), [influencer-recreation.md](prompting/prompt-library/influencer-recreation.md), [character-sheet.md](prompting/prompt-library/character-sheet.md), [character-sheet-gpt-image-2.md](prompting/prompt-library/character-sheet-gpt-image-2.md), [nano-banana.md](prompting/prompt-library/nano-banana.md).
- <https://api.novoads.ai/v1/openapi.json> — the spec itself, which is the authority when this file and it disagree.
