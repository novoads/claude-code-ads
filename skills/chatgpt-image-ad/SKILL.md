---
name: chatgpt-image-ad
description: >-
  Generate one or more standalone Meta image-ad creatives via ChatGPT Image 2 (gpt-image-2) through the Novoads API. Locks the model, auto-strips platform chrome, enforces edge-safe layouts and glyph-safety inside body text. Use when the user asks for a "gpt-image-2 ad", "ChatGPT Image ad", "Image 2 ad creative", "make a static image ad with GPT", or anchors on a need for typography-heavy / dense-text / UI-mimicry ad creatives (chat threads, comparison tables, fake search results, iOS dialogs, Slack snapshots, ChatGPT-conversation ads, Apple Notes lists). Does NOT trigger on Nano Banana cues — use nano-banana-image-ad for those.
---

# chatgpt-image-ad

Generate one or more **standalone Meta ad image creatives** via Novoads' `POST /v1/images`
with `model: "gpt-image-2"`. Hands the image paths off to your Meta-ad-builder skill — this
skill does not upload to Meta itself.

## Read order

Paths below are **from the repo root**. This skill is copied into `.claude/skills/` and
`.cursor/skills/` by `sync-skill.sh`, so a relative link out of it would break in those
copies — read these from the repo you are working in.

1. **This file** — endpoint, auth, upload flow, workflow phases.
2. `shared/skills/image-ad-prompting/OVERVIEW.md` — the ecosystem hub: which skill, which model, what the family does and doesn't do.
3. `shared/skills/chatgpt-image-ad/prompting/guide.md` — model-specific prompting (what gpt-image-2 is good/bad at, when to switch to nano-banana-pro).
4. `shared/skills/image-ad-prompting/prompting/prompt-library.md` — 37 validated templates with per-model notes.
5. `shared/skills/image-ad-prompting/prompting/safety-suffixes.md` — the 3 always-on guards.
6. `skills/chatgpt-image-ad/scripts/generate_image.py` — the helper script (Python stdlib only).

For anything about the API itself that this file does not answer — error codes, rate limits,
concurrency, the upload contract — the `novoads-api` skill's `reference.md` is the authority.

## Hard rules — never relax

1. **Model is `gpt-image-2`.** The script refuses any other value. If the user asks for Nano Banana, point them at `nano-banana-image-ad`.
2. **No platform/screenshot chrome in output.** `NO_CHROME_SUFFIX` is always on (override with `--allow-chrome` only when the ad's concept *requires* chrome — rare).
3. **Edge-safe + glyph-safety suffixes always on** unless `--no-safe-zone` is explicit. They fix real failures; don't remove silently.
4. **Max 4 reference images.** `referenceAssetIds` caps at 4 on every Novoads image model. The script enforces it.
5. **No Meta upload from this skill.** Image generation only. Hand off via filesystem paths.
6. **Always show a live cost estimate before generating, and get an explicit yes.** The price comes from `POST /v1/estimates` in this session — never from memory, never from `logs/novoads-api.jsonl`, never from `MASTER_CONTEXT.md`. There are no credit numbers written down anywhere in this repo, on purpose.

## Prerequisites

- `.env` containing `NOVOADS_API_KEY` (`novo_` + 64 hex, created at <https://novoads.ai/dashboard/settings?tab=api>). Verify with `./scripts/check-novoads-env.sh`.
- Optional: `PRODUCT_ID` in `.env` so generated assets are filed under a specific product. Omit it and the job lands in your default product. `productId` is **organizational only** — it does not influence what is generated.
- Reference images on local disk (PNG/JPG/JPEG/WEBP). The script handles the upload flow internally — you pass local paths.

## Configuration

- **Base URL:** `https://api.novoads.ai` (or `NOVOADS_BASE_URL`). That is the **host only** — callers append `/v1/...`.
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`.
- **Endpoint:** `POST /v1/images` — **synchronous**. The call blocks for the render (typically 60–90 seconds) and returns the finished images. There is no job to poll and no asset endpoint to wait on.
- **Reference uploads:** `POST /v1/uploads` with `{contentType, sizeBytes}` returns `{assetId, uploadUrl, method, headers, expiresInSeconds, maxBytes}`. `PUT` the raw bytes to `uploadUrl` **echoing the returned `headers` byte for byte** — Content-Type and Content-Length are both part of the signature, so storage returns 403 if either differs. The resulting `assetId` is **durable and reusable**: upload a product shot once and pass the same id on every later call.

## What this model takes

| Field | Value |
|---|---|
| `model` | `gpt-image-2` (also the API default) |
| `prompt` | the image prompt — the always-on suffixes count against the model's cap |
| `aspectRatio` | `1:1` `4:5` `2:3` `9:16` `16:9` `21:9` — **defaults to `1:1`**, so always set it |
| `referenceAssetIds` | up to **4**, order preserved, addressable positionally from the prompt |
| `numImages` | `1`–`4`, **one call**, charged per image |
| `productId` | optional, organizational only |

`3:2`, `3:4`, `4:3` and `5:4` are **not** on this model — they exist on `nano-banana-pro` and
`reve-2.1`. The request schema is strict, so sending one is a `400` before anything is charged.
No template in the shared library needs them.

**N variants is one call, not N calls.** Send `numImages: 4` and four images come back in
`images[]`. Do not fan out four parallel requests — that burns four of your five concurrency
slots to get the same result at the same price.

**There is no edit mode.** Novoads has no image-editing, inpainting, masking or img2img path
on any model. If the user wants "the same ad but change the background", that is a fresh
generation with the original uploaded as a reference — say so rather than implying an edit.

## Inputs the user must provide

| Input | Notes |
|---|---|
| Seed prompt | The creative direction in their words. You will rewrite it (see Phase 3). |
| Aspect ratio | One of the six above. Reject anything else. |
| Reference image(s) | Optional but strongly recommended when the ad features a specific product. Up to 4. |
| Variant count `N` | Default 1. Cap at 4. Each one is charged. |

## Workflow

### Phase 1: Preflight

1. `.env` exists with `NOVOADS_API_KEY`.
2. Health check: `./scripts/check-novoads-env.sh` prints OK (a 401 is a bad key; a 403 with `details.reason: plan_required` is a good key on an account without API access — different fixes).

### Phase 2: Gather inputs

Collect: seed prompt, reference paths, variant count, aspect ratio.

### Phase 3: Prompt rewrite

Read `shared/skills/image-ad-prompting/prompting/prompt-library.md`. If the user's brief maps
onto a template, **check the Model notes block** — only proceed if `gpt-image-2` is marked
clean or preferred. If nano-banana-pro is preferred, suggest switching skills before generating.

Fill the `{placeholders}` and show the user the rewritten prompt. Ask "Use this, edit it, or
start over?" Loop until approved.

For fresh prompts (no template match), follow the structure in
`shared/skills/chatgpt-image-ad/prompting/guide.md` § Phase 3b.

### Phase 4: Cost confirmation (MANDATORY)

```bash
curl -sS -X POST "$NOVOADS_BASE_URL/v1/estimates" \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"kind":"image","model":"gpt-image-2","prompt":"<final prompt>","numImages":<N>}'
```

Free, and the only legitimate source of a price. Show the user `credits`, and whether
`sufficient` is true against their `balance`. If it is false, say so and stop — the response
carries `shortBy` and `topUpUrl`. Wait for an explicit yes before Phase 5.

Three things to know about this call:

- **It also lints the prompt for free.** Anything it finds comes back in `warnings`, each entry `{rule, message}`. These are **advice, not blockers** — nothing in there will stop the generation. Read them anyway: the message names the problem and ships the fix inline, in the prompt's own language. A clean prompt omits the `warnings` key entirely.
- **The body is strict.** Only `kind`, `prompt`, `model`, `numImages`, `language` are accepted. Sending `aspectRatio` or `referenceAssetIds` is a `400 Unrecognized key` — the estimate never sees them, and neither affects the price.
- **It enforces this model's prompt ceiling.** A prompt over the model's cap is refused here, free, with a message naming the limit — the same refusal the paid call would give. It does **not** run moderation, so a prompt the estimate blessed can still come back `422 content_policy`.

Estimate the **final** prompt — the one the script will send, with the safety suffixes
appended — or the quote will be short by roughly 1,500 characters' worth of prompt.

### Phase 5: Generate

```bash
./skills/chatgpt-image-ad/scripts/generate_image.py \
  --prompt "<rewritten>" \
  --aspect-ratio <ratio> \
  --n <N> \
  --image-ref <product.png> \
  [--image-ref <style-board.png>] \
  --out ./generated \
  --env-file .env
```

Each line on stdout is one JSON image (`variant`, `path`, `job_id`, `width`, `height`,
`prompt`, `aspect_ratio`, `model`, `credits_charged`).

Log the call to `logs/novoads-api.jsonl` per `logs/README.md` — images are written **once,
complete** (sync endpoint, no `jobId` to poll back). Record `creditsCharged` from the response,
never an estimate. Observability only, never a pricing source.

### Phase 6: Visual QA (MANDATORY)

For each image, **read it** and inspect for:
- Garbled small text (most common gpt-image-2 failure on dense body text)
- Wordmark drift (if a brand wordmark wasn't passed as `--image-ref`)
- Wrong text count (e.g. 4 Slack messages instead of 3)
- iOS dialog / UI proportion drift

If defective: regenerate with a revised prompt explicitly correcting the issue (see
`shared/skills/chatgpt-image-ad/prompting/guide.md` § Retry mode). **Cap at 2 retries.**
Each retry is a fresh charge — there is no free re-roll — so no re-confirmation is needed
within the cap, but report the extra credits at the end of the run. After the cap, stop and
show the best attempt.

### Phase 7: Confirm and hand off

Show all paths to the user. Ask "Use all / use these specific ones / regenerate / cancel."

Open the output folder (`open` on macOS, `xdg-open` on Linux) so the user sees the results
without hunting for them.

Selected images are ready for the **`meta-ad-builder` skill**. Print the paths so the user can
pipe them. Optionally write them to `./generated/run-<ts>.jsonl` for downstream consumption.

## Out of scope — fail clearly

- **Meta upload** — the `meta-ad-builder` skill.
- **Nano Banana image generation** — use `nano-banana-image-ad`.
- **Editing an existing image** — no model on this API has an edit path. Offer a fresh generation with the original as a reference.
- **Video, carousel, DCO ads** — image only. Video lives in the `novoads-api` skill.
- **Ad copy writing** — different skill.
- **Editing the shared prompt library** — use `image-ad-clone`.

## Common errors

| What you see | What it means |
|---|---|
| `400 invalid_input` with `details.issues` | A malformed field. Most often an `aspectRatio` this model doesn't take, more than 4 `referenceAssetIds`, or a prompt over the model's cap. Nothing was charged. |
| `401 unauthorized` | Missing, malformed or revoked key. Send the user to <https://novoads.ai/dashboard/settings?tab=api>. |
| `402 insufficient_credits` | `details` carries `required` and `available`. Tell the user the gap; do not retry. |
| `403 forbidden` | `details.reason` says which: `plan_required`, `subscription_inactive`, or API access off for the account. |
| `422 content_policy` | Moderation blocked it. The estimate does not run moderation, so this can land on a prompt the estimate priced cleanly. Nothing was charged. Rewrite or stop. |
| `429 rate_limited` | **Branch on `details.reason`.** `key_limit` / `organization_limit` / `client_limit` are paced by slowing down; `concurrency_limit` is not — only waiting frees a slot. Honor `Retry-After`. |
| `403` on the presigned PUT | The signed headers weren't echoed byte for byte. Send the `headers` object from `POST /v1/uploads` exactly as returned. |
| `500 internal_error` | **Do not blindly retry** — there are no idempotency keys, so a retry can double-charge. Check `GET /v1/generations` for a job that already landed. |
| `502 provider_failed` | The model provider failed. Credits are refunded automatically. |

## Files this skill owns

- `skills/chatgpt-image-ad/SKILL.md` — this file
- `skills/chatgpt-image-ad/scripts/generate_image.py` — the gpt-image-2 caller (upload + generate + download)

## See also

- `shared/skills/image-ad-prompting/OVERVIEW.md` — ecosystem hub, read first
- `shared/skills/chatgpt-image-ad/prompting/guide.md` — gpt-image-2 strengths/limits, retry playbook
- `shared/skills/image-ad-prompting/prompting/prompt-library.md` — 37 validated templates
- `shared/skills/image-ad-prompting/prompting/template-format.md` — entry skeleton for new templates
- `shared/skills/image-ad-prompting/prompting/safety-suffixes.md` — the 3 always-on guards
- the **`image-ad-clone`** skill — reverse-engineers an existing ad into a reusable library entry
- the **`nano-banana-image-ad`** skill — sibling for photoreal / lifestyle / multi-ref templates
- the **`novoads-api`** skill — the API contract underneath all of this
