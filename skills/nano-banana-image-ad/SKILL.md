---
name: nano-banana-image-ad
description: >-
  Generate one or more standalone Meta image-ad creatives via Nano Banana Pro through the Novoads API. Locks the model, auto-strips platform chrome, enforces edge-safe layouts. Use when the user asks for a "Nano Banana ad", "Gemini image ad", "nano-banana-pro ad creative", "make a static image ad with Gemini", or anchors on a need for photoreal / lifestyle / multi-reference / handheld-object / clay-texture ad creatives (sticky-note flatlays, held-whiteboard signs, lifestyle portraits, ingredient collages, OOH photography). Does NOT trigger on ChatGPT Image cues — use chatgpt-image-ad for those.
---

# nano-banana-image-ad

Generate one or more **standalone Meta ad image creatives** via Novoads' `POST /v1/images`
with `model: "nano-banana-pro"`. Hands the image paths off to your Meta-ad-builder skill —
this skill does not upload to Meta itself.

## Read order

Paths below are **from the repo root**. This skill is copied into `.claude/skills/` and
`.cursor/skills/` by `sync-skill.sh`, so a relative link out of it would break in those
copies — read these from the repo you are working in.

1. **This file** — endpoint, auth, upload flow, workflow phases.
2. `shared/skills/image-ad-prompting/OVERVIEW.md` — the ecosystem hub: which skill, which model, what the family does and doesn't do.
3. `shared/skills/nano-banana-image-ad/prompting/guide.md` — model-specific prompting (what Nano Banana Pro is good/bad at, when to switch to gpt-image-2).
4. `shared/skills/image-ad-prompting/prompting/prompt-library.md` — 37 validated templates with per-model notes.
5. `shared/skills/image-ad-prompting/prompting/safety-suffixes.md` — the 3 always-on guards.
6. `skills/nano-banana-image-ad/scripts/generate_image.py` — the helper script (Python stdlib only).

For anything about the API itself that this file does not answer — error codes, rate limits,
concurrency, the upload contract — the `novoads-api` skill's `reference.md` is the authority.

## Hard rules — never relax

1. **Model is `nano-banana-pro`.** It is the only Nano Banana on this API — there is no `nano-banana-2`, no `nano-banana-edit`, no legacy `nano-banana`. The script refuses anything else. If the user asks for gpt-image-2, point them at `chatgpt-image-ad`.
2. **No platform/screenshot chrome in output.** `NO_CHROME_SUFFIX` is always on (override only with `--allow-chrome`).
3. **Edge-safe + glyph-safety suffixes always on** unless `--no-safe-zone` is explicit.
4. **Max 14 reference images.** `referenceAssetIds` caps at 14 on `nano-banana-pro` (spec 2.7.0; `gpt-image-2` takes 4, `reve-2.1` 8). The script enforces it — and 2-4 well-chosen references usually beat many.
5. **No Meta upload from this skill.** Image generation only. Hand off via filesystem paths.
6. **Always show a live cost estimate before generating, and get an explicit yes.** The price comes from `POST /v1/estimates` in this session — never from memory, never from `logs/novoads-api.jsonl`, never from `MASTER_CONTEXT.md`. There are no credit numbers written down anywhere in this repo, on purpose. Nano Banana Pro costs more per image than gpt-image-2, so the model choice is worth surfacing when you show the quote.

## Prerequisites

- `.env` containing `NOVOADS_API_KEY` (`novo_` + 64 hex, created at <https://novoads.ai/dashboard/settings?tab=api>). Verify with `./scripts/check-novoads-env.sh`.
- Optional: `PRODUCT_ID` in `.env` so generated assets are filed under a specific product. Omit it and the job lands in your default product. `productId` is **organizational only** — it does not influence what is generated.
- Reference images on local disk (PNG/JPG/JPEG/WEBP). The script handles the upload flow internally.

## Configuration

- **Base URL:** `https://api.novoads.ai` (or `NOVOADS_BASE_URL`). That is the **host only** — callers append `/v1/...`.
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`.
- **Endpoint:** `POST /v1/images` — **synchronous**. The call blocks for the render (typically 60–90 seconds) and returns the finished images. There is no job to poll and no asset endpoint to wait on.
- **Reference uploads:** `POST /v1/uploads` with `{contentType, sizeBytes}` returns `{assetId, uploadUrl, method, headers, expiresInSeconds, maxBytes}`. `PUT` the raw bytes to `uploadUrl` **echoing the returned `headers` byte for byte** — Content-Type and Content-Length are both part of the signature, so storage returns 403 if either differs. The resulting `assetId` is **durable and reusable**: upload a character or product shot once and pass the same id on every later call. That is what makes cross-run identity consistency cheap here.

## What this model takes

| Field | Value |
|---|---|
| `model` | `nano-banana-pro` |
| `prompt` | the image prompt — the always-on suffixes count against the model's cap |
| `aspectRatio` | `1:1` `2:3` `3:2` `3:4` `4:3` `4:5` `5:4` `9:16` `16:9` `21:9` — **defaults to `1:1`**, so always set it |
| `referenceAssetIds` | up to **14**, order preserved, addressable positionally from the prompt |
| `numImages` | `1`–`4`, **one call**, charged per image |
| `productId` | optional, organizational only |

This model takes the **full ratio set** — including `3:2`, `3:4`, `4:3` and `5:4`, which
`gpt-image-2` does not. That is the one hard reason to route a bespoke prompt here regardless
of style.

**N variants is one call, not N calls.** Send `numImages: 4` and four images come back in
`images[]`. Do not fan out four parallel requests — that burns four of your five concurrency
slots to get the same result at the same price.

**There is no edit mode.** The Nano Banana inpainting flows the older skill had do not exist
on this API — no `nano-banana-edit`, no `--source`, no mask, no img2img. "Change the background
of this image" is a fresh generation with the original uploaded as a reference. Say that rather
than implying an edit.

## Inputs the user must provide

| Input | Notes |
|---|---|
| Seed prompt | The creative direction in their words. You will rewrite it (see Phase 3). |
| Aspect ratio | One of the ten above. Reject anything else. |
| Reference image(s) | Optional but strongly recommended for a specific product, character or brand mark. Up to 4. |
| Variant count `N` | Default 1. Cap at 4. Each one is charged. |

## Workflow

### Phase 1: Preflight

1. `.env` exists with `NOVOADS_API_KEY`.
2. Health check: `./scripts/check-novoads-env.sh` prints OK (a 401 is a bad key; a 403 with `details.reason: plan_required` is a good key on an account without API access — different fixes).

### Phase 2: Gather inputs

Collect: seed prompt, reference paths (up to 4), variant count, aspect ratio.

### Phase 3: Prompt rewrite

Read `shared/skills/image-ad-prompting/prompting/prompt-library.md`. If the user's brief
matches a template, **check the Model notes block** — only proceed if nano-banana is marked
clean, preferred, or strong. If gpt-image-2 is preferred, suggest switching skills.

Fill `{placeholders}` and show the user the rewritten prompt. Ask for approval before generating.

For fresh prompts (no template match), follow the structure in
`shared/skills/nano-banana-image-ad/prompting/guide.md` § Phase 3b — lean on Nano Banana
strengths (named reference roles, lighting specifics, material specifics).

### Phase 4: Cost confirmation (MANDATORY)

```bash
curl -sS -X POST "$NOVOADS_BASE_URL/v1/estimates" \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"kind":"image","model":"nano-banana-pro","prompt":"<final prompt>","numImages":<N>}'
```

Free, and the only legitimate source of a price. **Name the model in the estimate body** — the
image models' schedules differ by more than 3×, so pricing the wrong one is a quote that
disagrees with the invoice. Show the user `credits`, and whether `sufficient` is true against
their `balance`. If it is false, say so and stop — the response carries `shortBy` and
`topUpUrl`. Wait for an explicit yes before Phase 5.

Three things to know about this call:

- **It says nothing about an image prompt.** `POST /v1/estimates` *does* return an advisory `warnings` array of craft notes, but every rule in it is **video** craft: an image estimate carrying the words that trip the video rules came back with no `warnings` key at all (verified live 2026-08-04). So for this route a weak prompt prices, charges and renders exactly like a strong one, and the rewrite rules in Phase 3 are the only check there is — apply them before you price.
- **The body is strict.** Only `kind`, `prompt`, `model`, `numImages`, `language` are accepted. Sending `aspectRatio` or `referenceAssetIds` is a `400 Unrecognized key` — the estimate never sees them, and neither affects the price.
- **It enforces this model's prompt ceiling.** A prompt over the model's cap is refused here, free, with a message naming the limit. It does **not** run moderation, so a prompt the estimate blessed can still come back `422 content_policy`.

Estimate the **final** prompt — the one the script will send, with the safety suffixes
appended — or the quote will be short by roughly 1,500 characters' worth of prompt.

### Phase 5: Generate

```bash
./skills/nano-banana-image-ad/scripts/generate_image.py \
  --prompt "<rewritten>" \
  --aspect-ratio <ratio> \
  --n <N> \
  --image-ref <product.png> \
  [--image-ref <character.png>] \
  [--image-ref <style.png>] \
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
- Garbled small text (the main Nano Banana weakness — if the ad is text-led, it belongs in `chatgpt-image-ad`)
- Extra fingers / wrong limb count (common Gemini-family failure)
- Wordmark drift (always pass brand wordmarks as `--image-ref` to mitigate)
- Character identity drift across variants — reuse the **same `assetId`** for the character reference on every call, which is what keeps a face consistent across runs

If defective: regenerate with a revised prompt explicitly correcting the issue (see
`shared/skills/nano-banana-image-ad/prompting/guide.md` § Retry mode). **Cap at 2 retries.**
Each retry is a fresh charge — there is no free re-roll — so no re-confirmation is needed
within the cap, but report the extra credits at the end of the run. After the cap, stop and
show the best attempt.

### Phase 7: Confirm and hand off

Show all paths to the user. Ask "Use all / use these specific ones / regenerate / cancel."

Open the output folder (`open` on macOS, `xdg-open` on Linux) so the user sees the results
without hunting for them.

Selected images are ready for the **`meta-ad-builder` skill**. Print the paths. Optionally
write them to `./generated/run-<ts>.jsonl` for downstream consumption.

## Out of scope — fail clearly

- **Meta upload** — the `meta-ad-builder` skill.
- **ChatGPT Image 2 / gpt-image-2 generation** — use `chatgpt-image-ad`.
- **Editing an existing image** — no model on this API has an edit or inpainting path. Offer a fresh generation with the original as a reference.
- **Video, carousel, DCO ads** — image only. Video lives in the `novoads-api` skill.
- **Ad copy writing** — different skill.
- **Editing the shared prompt library** — use `image-ad-clone`.

## Common errors

| What you see | What it means |
|---|---|
| `400 invalid_input` with `details.issues` | A malformed field. Most often more than 4 `referenceAssetIds`, a `numImages` above 4, or a prompt over the model's cap. Nothing was charged. |
| `401 unauthorized` | Missing, malformed or revoked key. Send the user to <https://novoads.ai/dashboard/settings?tab=api>. |
| `402 insufficient_credits` | `details` carries `required` and `available`. Tell the user the gap; do not retry. |
| `403 forbidden` | `details.reason` says which: `plan_required`, `subscription_inactive`, or API access off for the account. |
| `422 content_policy` | Moderation blocked it. The estimate does not run moderation, so this can land on a prompt the estimate priced cleanly. Nothing was charged. Rewrite or stop. |
| `429 rate_limited` | **Branch on `details.reason`.** `key_limit` / `organization_limit` / `client_limit` are paced by slowing down; `concurrency_limit` is not — only waiting frees a slot. Honor `Retry-After`. |
| `403` on the presigned PUT | The signed headers weren't echoed byte for byte. Send the `headers` object from `POST /v1/uploads` exactly as returned. |
| `500 internal_error` | **Do not blindly retry** — there are no idempotency keys, so a retry can double-charge. Check `GET /v1/generations` for a job that already landed. |
| `502 provider_failed` | The model provider failed. Credits are refunded automatically. |

## Files this skill owns

- `skills/nano-banana-image-ad/SKILL.md` — this file
- `skills/nano-banana-image-ad/scripts/generate_image.py` — the nano-banana-pro caller (upload + generate + download)

## See also

- `shared/skills/image-ad-prompting/OVERVIEW.md` — ecosystem hub, read first
- `shared/skills/nano-banana-image-ad/prompting/guide.md` — model-specific prompting, retry playbook
- `shared/skills/image-ad-prompting/prompting/prompt-library.md` — 37 validated templates
- the **`image-ad-clone`** skill — reverse-engineers an existing ad into a reusable library entry
- the **`chatgpt-image-ad`** skill — sibling for typography-heavy / UI-mimicry templates
- the **`novoads-api`** skill — the API contract underneath all of this
