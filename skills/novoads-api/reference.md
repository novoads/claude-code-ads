# Novoads REST API reference

Companion to `SKILL.md`. Read that first for the call sequence. This file is the field-level detail and the lab notebook.

**The authority is <https://api.novoads.ai/v1/openapi.json>.** Where this file and the spec disagree, the spec wins, except in *Known discrepancies* below, where the spec is wrong and this file says so.

## Base URL and auth

```
https://api.novoads.ai/v1
Authorization: Bearer novo_<64 hex>
```

The key is shown once, at creation, and cannot be retrieved afterward. Create and revoke at <https://novoads.ai/dashboard/settings?tab=api>. Maximum 10 live keys per organization.

API generations draw from the organization's plan credits at the same rate as the dashboard. There is no separate API wallet, no free API tier, and no separate API plan: any live subscription, the $1 trial included, can generate here.

### Use `curl`. A `403` with `error code: 1010` is Cloudflare, not your key

**The API sits behind Cloudflare, and Cloudflare's bot rule refuses `python3-urllib` outright.** A request sent with Python's stdlib `urllib` default `User-Agent` comes back `403` carrying a bare edge page with **`error code: 1010`** — not a Novoads `{"error":{...}}` envelope, no `code`, no `requestId`. The same key, on the same endpoint, over `curl`, succeeds a second later.

It reads exactly like a revoked key or a dead subscription and is **neither**. Two tells:

- **The body is the wrong shape.** Every real Novoads failure is the `{"error":{"code",...,"requestId"}}` envelope in *Errors* below. An HTML-ish page with a numeric Cloudflare code never came from this API's application layer.
- **It hits everything at once.** On 2026-08-02 it took all three estimate calls simultaneously while a `GET /v1/products` issued moments earlier over `curl` had already succeeded. A genuine auth or plan failure would have refused that one too.

**The fix is the client, not the credential.** Use `curl`, as every example in this repo does. If you must call from Python, send a browser-like `User-Agent` — the default is the whole problem. Do not "fix" this by regenerating a key, checking the subscription, or telling the user their plan lapsed.

Ad analysis (reading an existing ad into a structured hook, beats, casting and layout breakdown) is **not** on this API. It lives on the [MCP connector](https://novoads.ai/mcp) as `analyze_ad`. That is deliberate, not a gap to route around.

## Endpoints

| Method | Path | What it does |
|---|---|---|
| `POST` | `/uploads` | Mint a presigned PUT for a reference image or video. |
| `POST` | `/estimates` | Price a generation. Spends nothing. The only endpoint that lints the prompt. |
| `POST` | `/videos` | Submit a video. `202`, charged, asynchronous. |
| `POST` | `/images` | Generate images. Synchronous, images in the response. |
| `GET` | `/generations` | List jobs, filterable and paginated. |
| `GET` | `/generations/{jobId}` | One job, with `outputUrl` once it has succeeded. |
| `GET` | `/generations/{jobId}/watch` | `302` to a freshly signed download URL. |
| `GET` | `/models` | The model catalog, with each model's grid and price. |
| `GET` `POST` | `/products` | List and create products. |
| `GET` `PATCH` `DELETE` | `/products/{productId}` | One product. |
| `GET` | `/products/{productId}/folders` | Folders under a product. Read-only. |

`GET /v1/openapi.json` is public and needs no key. There are **no** folder-creation, project, or add-to-project endpoints on v1.

---

## POST /uploads

Request:

```json
{ "contentType": "image/jpeg", "sizeBytes": 248193 }
```

`contentType` is one of `image/jpeg`, `image/png`, `image/webp`, `video/mp4`, `video/quicktime`, `video/webm`. `sizeBytes` is the exact byte count, maximum 104,857,600 (100 MB).

Response `201`:

| Field | Meaning |
|---|---|
| `assetId` | Use in `startImageAssetId` and `referenceAssetIds`. Scoped to your organization. |
| `uploadUrl` | Presigned. PUT the raw bytes here. |
| `method` | The verb the URL was signed for. |
| `headers` | Send these on the PUT, byte for byte. |
| `expiresInSeconds` | 900. Request a new URL rather than retrying an expired PUT. |
| `maxBytes` | Ceiling this endpoint accepts. |

**`Content-Type` and `Content-Length` are both signed into the URL.** If either differs from what was returned, storage rejects the PUT with a 403 that looks like an auth failure and is not one. `image/jpeg; charset=utf-8` is the classic way to lose an hour here. Measure the file, do not estimate it.

**The `assetId` is durable and reusable, without limit.** It is the storage key itself, resolution is a stateless check plus a fresh presign on every call, and nothing consumes it: the same id works on call one and call one hundred, from `startImageAssetId`, from `referenceAssetIds`, and from the MCP tool. Upload the product photo once and reuse it across every iteration and every model. The **900 second expiry belongs to the upload URL, not to the asset** — that is the distinction most likely to be conflated.

---

## POST /estimates

Discriminated on `kind`, and strict. Any field not listed is a 400.

| Field | `kind: "video"` | `kind: "image"` |
|---|---|---|
| `kind` | required, `"video"` | required, `"image"` |
| `prompt` | required | required |
| `model` | `seedance-2.0` (default), `seedance-2.0-mini`, `omni-flash`, `veo-3.1`, `sora-2` | `gpt-image-2` (default), `nano-banana-pro`, `reve-2.1` |
| `durationSeconds` | 4 to 15 | n/a |
| `numImages` | n/a | 1 to 4 |
| `language` | `en` `es` `pt` `fr` `de` `it` `zh` `ja` `ko` `ar` `hi` | same |

All eight models price here, `veo-3.1` and `sora-2` included (verified live, 2026-08-02).

There is **no `styleFamily`** on either arm. The field was deleted from the whole API in spec `2.0.0`, and both arms are strict, so a body carrying it comes back `400 (root): Unrecognized key: "styleFamily"` (verified live, 2026-08-02).

There is **no `audioEnabled`** on either arm, and that is deliberate rather than an omission: the field does not move the price, and this endpoint takes only fields that do. Sending it is `400 Unrecognized key: "audioEnabled"` even on `seedance-2.0`, where the *generation* call accepts it (verified live, 2026-08-02). Price the render without it; send it on `POST /videos`.

**`durationSeconds` is validated against the *named model's* grid here, not against the 4–15 span in the table.** Same behavior as the prompt ceiling: `{"model":"sora-2","durationSeconds":11}` comes back `400 durationSeconds must be one of 4, 8, 12 for sora-2.` while `8` prices cleanly (verified live, 2026-08-02). So the free call catches an out-of-grid duration before the paid one does — one more reason to run it every time.

Response:

| Field | Meaning |
|---|---|
| `credits` | What the generation would cost. |
| `balance` | Organization balance at read time. A snapshot, not a reservation. |
| `sufficient` | `balance >= credits` at that moment. |
| `shortBy` | Present when short. |
| `topUpUrl` | Present when short. |
| `warnings` | `{rule, message}` pairs from the prompt rules. **Advisory, always**, and this is the only endpoint that returns them. See *Prompt rules* below. |

Pass `model` explicitly. Video schedules differ by 2x across the set, image schedules by more than 3x.

**The schema's 20,000-character `prompt` ceiling is not the one that binds.** The service applies the *named model's* limit here too, so a 5,000-character prompt priced as `seedance-2.0` is rejected at the estimate, for free, exactly as the paid call would reject it. Omit `model` and it is judged as `seedance-2.0`. Only `omni-flash` genuinely accepts 20,000.

This endpoint refuses a churned organization with a 403, on purpose. `sufficient` is a claim that the generation would go through, so answering `true` to an account whose generation would then be refused is a quote that disagrees with the invoice.

**Two things the estimate cannot see.** It never receives `aspectRatio`, `startImageAssetId`, `referenceAssetIds` or `productId`, because none of them moves the price. And it **skips moderation**, deliberately — running it would pay for a moderation call on every estimate for a verdict that almost never differs. So the one gap left is a prompt that prices clean here and fails moderation: `422` at generation. Nothing is charged in that case either.

**What this endpoint does with the prompt, exactly.** The price does not depend on it at all — that comes from the model and the duration or image count. The prompt is checked for one thing (the model's character ceiling, a 400) and **linted** for everything else, with every finding returned in `warnings` on the `200`. None of those findings can refuse anything, here or at generation. The full list is under *Prompt rules* below.

---

## POST /videos

Per-model request bodies, all `.strict()`.

**Shared by all five video models:** `model`, `prompt`, `durationSeconds`, `aspectRatio`, `language`, `startImageAssetId`, `productId`. Only `model` and `prompt` are required. Beyond that the variants differ, and every difference is a `400` rather than a dropped field:

- **`referenceAssetIds`** — the two Seedance variants only. `omni-flash`, `veo-3.1` and `sora-2` have no such field.
- **`audioEnabled`** — the two Seedance variants only. See below.

There is **no `styleFamily`** on any variant. It was deleted from the API in spec `2.0.0` along with the blocking prompt rules it scoped, and the variants are strict, so sending it is a `400`.

| `model` | `durationSeconds` (default) | `aspectRatio` | `refs` | `audio` | Prompt max |
|---|---|---|---|---|---|
| `seedance-2.0` | 4–15, any integer (**5**) | `16:9` (default) `9:16` `1:1` `4:3` `3:4` `21:9` | ≤9 | yes | 4,000 |
| `seedance-2.0-mini` | same (**10**) | same | ≤9 | yes | 4,000 |
| `omni-flash` | 4, 6, 8, 10 (**8**) | `9:16` (default) `16:9` | — | — | 20,000 |
| `veo-3.1` | 4, 6, 8 (**8**) | `9:16` (default) `16:9` | — | — | 4,000 |
| `sora-2` | 4, 8, 12 (**4**) | `9:16` (default) `16:9` | — | — | 4,000 |

Defaults that bite: **Seedance defaults to `16:9`**, alone among the five — every other model already defaults to `9:16`. On duration, `seedance-2.0` defaults to 5 and mini to 10, `omni-flash` to 8, `sora-2` to 4, and **`veo-3.1` to 8, which is also its maximum** — the only model here that defaults to its ceiling. An out-of-grid `durationSeconds` is rejected, never rounded. Set both fields explicitly on any ad.

### `audioEnabled`

A boolean on **`seedance-2.0` and `seedance-2.0-mini` only**, default `true` — omit it and the endpoint renders exactly what it rendered before the field existed. It controls the synchronized sound effects, ambient sound and lip-synced speech the model generates from the prompt.

Send `false` for a clip that is meant to be silent: a pipeline laying its own voice-over in post otherwise pays for a voice track it throws away, and a product cutaway built to run muted comes back with sound effects nobody hears.

**It does not change the price**, the length, or anything else about the grid — both Seedance providers charge the same either way, which is why `POST /estimates` refuses the field.

Verified live 2026-08-02, each probe pinned with an out-of-grid `durationSeconds` so no body could be valid and none could charge:

| Sent to | Result |
|---|---|
| `seedance-2.0`, `seedance-2.0-mini` | accepted — the only complaint was the pinned duration |
| `omni-flash`, `veo-3.1`, `sora-2` | `400 Unrecognized key: "audioEnabled"` |
| `POST /estimates`, any model | `400 Unrecognized key: "audioEnabled"` |

**Keep the prose silence clause in the prompt as well.** The flag mutes the render; the clause (`a silent product film with no spoken dialogue`) stops the model staging a talking shot in the first place, and clears `no_spoken_line` on the estimate. They do different jobs and the belt-and-suspenders pair is deliberate.

Response `202`: `jobId`, `status`, `creditsCharged`, `model`. **No `warnings`** — the job responses carry none, because this endpoint runs no prompt rules. Craft advice exists only on `POST /estimates`.

`creditsCharged` is in the unit the billing page shows. Internally 1 credit is 10 centi-credits; the API has already converted, so echo the number as given.

### `startImageAssetId` and `referenceAssetIds` are two modes, not two fields

Confirmed against the deployed spec `2.0.0` on 2026-08-02 (the `1.2.0`-era note that video took no references is superseded).

| | `startImageAssetId` | `referenceAssetIds` |
|---|---|---|
| What the model does with it | Animates the image as the **first frame** | **Composites** the images as visual references — a character, a product, a wardrobe, a setting |
| How many | 1 | Up to **9** |
| Which models | all five | `seedance-2.0` and `seedance-2.0-mini` only — the `omni-flash`, `veo-3.1` and `sora-2` variants omit the field, and all three are strict (`400 Unrecognized key`, verified live 2026-08-02) |
| Addressed in the prompt | no | yes: `@Image1`, `@Image2` … in the order you send them |

**Sending both is a 400**, not a merge: they select different modes on the provider.

**Images only** — `image/jpeg`, `image/png`, `image/webp`. `POST /uploads` also accepts video, and a video `assetId` here is an error rather than a reference: the providers price video-input renders differently while the credit cost here is a function of duration alone, so accepting one would make the quote disagree with the invoice.

An `@ImageN` token pointing past the end of the array is refused **before the charge** — an unresolvable reference is a content failure at the provider, and a 400 is a better answer than a refunded render.

There is **no `resolution` field** on any variant, and the spec publishes no output size at all — `GET /models` does not carry one either. Output size is fixed per model and you find it out by measuring. What has been measured here, at `9:16`: `seedance-2.0` and `sora-2` both returned **720x1280** (2026-08-02, ffprobe). `omni-flash` and `veo-3.1` are unmeasured — do not quote a number for them, and do not generalise 720p across the set now that Veo is on it.

There are **no idempotency keys.** See the 500 note below.

---

## POST /images

| `model` | `aspectRatio` | `referenceAssetIds` | `numImages` | Prompt max |
|---|---|---|---|---|
| `gpt-image-2` (default) | `1:1` (default) `4:5` `2:3` `9:16` `16:9` `21:9` | up to **4** | 1 to 4 | 4,000 |
| `nano-banana-pro` | `1:1` `2:3` `3:2` `3:4` `4:3` `4:5` `5:4` `9:16` `16:9` `21:9` | up to **4** | 1 to 4 | 4,000 |
| `reve-2.1` | same as Nano Banana Pro | up to **8** | 1 to 4 | 4,000 |

**The reference cap is per model and is not uniform.** `reve-2.1` takes 8; the other two take 4. Do not carry one number across the set — the bodies are strict, so a fifth reference to `gpt-image-2` is `400 Too big: expected array to have <=4 items` rather than a silently dropped image, which is the good outcome: a dropped reference is a paid render missing the product. Verified live 2026-08-02, each probe pinned with an out-of-range `numImages` so no body could be valid: 9 refs on `reve-2.1` → too big, 8 → accepted; 5 refs on `gpt-image-2` and on `nano-banana-pro` → too big.

Synchronous. The response carries `images[]` (`url`, `expiresInSeconds` 3600, `width`, `height`), `jobId`, `status`, `creditsCharged`, and `model`. **No `warnings`**, for the same reason as video: this endpoint runs no prompt rules. Nothing to poll. `numImages` multiplies the price.

Reference order is preserved and can be addressed positionally by the prompt. There is no base64 field: upload first, pass ids.

Images accept **no `startImageAssetId`** — there is no first-frame concept on a still — and **no `styleFamily`**, which no longer exists anywhere on this API.

---

## GET /generations

| Param | Values |
|---|---|
| `limit` | 1 to 50, default 10 |
| `offset` | default 0 |
| `kind` | `video`, `image` |
| `productId` | filter to one product |
| `updatedSince` | ISO 8601. The incremental-sync path: store the highest `updatedAt` you have seen and pass it back. |
| `sortBy` | `createdAt` (default), `updatedAt` |
| `sortOrder` | `desc` (default), `asc` |

Returns `items`, `total`, `limit`, `offset`, `hasMore`. `total` ignores pagination.

This is also the recovery path when a call times out: the work may have run and been charged, and the lost thing is the response carrying the `jobId`.

## GET /generations/{jobId}

`jobId`, `status`, `kind`, `model`, `prompt`, `createdAt`, and once succeeded, `outputUrl` plus `outputUrlExpiresInSeconds` (3600). On failure, `error` carries our own wording, never a provider's raw text, and the credits are already refunded.

## GET /generations/{jobId}/watch

`302` to a URL signed at request time. `curl -L` friendly, and the right thing to hand a video player or an `<img>` tag, because the signature is minted on request rather than read from something that may have expired in your database.

While the job is unfinished this is a `409` naming the current status.

## GET /products, POST /products

`GET` lists the organization's products. `POST` creates one and returns it with its `id` — that id is what goes in `productId` on every generation call.

Request body for `POST`, `.strict()` — `name` is the only required field:

| Field | Type | Limit |
|---|---|---|
| `name` | string | **required**, 1 to 200 chars |
| `description` | string | ≤ 2,000 chars |
| `targetAudience` | string | ≤ 500 chars |
| `mainFeatures` | string[] | ≤ 20 items, each ≤ 200 chars |
| `painPoint` | string | ≤ 500 chars |
| `perceived` | string | perceived value — what a buyer feels it is worth. ≤ 500 chars |

```bash
curl -sS -X POST https://api.novoads.ai/v1/products \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Aurora Sleep Tea",
    "description": "A caffeine-free herbal tea blended for people who fall asleep late.",
    "targetAudience": "Adults 25-45 who work late and struggle to wind down.",
    "mainFeatures": ["Caffeine free", "Valerian and chamomile", "Brews in 3 minutes"],
    "painPoint": "Lying awake for an hour after getting into bed.",
    "perceived": "A nightly ritual worth more than the price of a coffee."
  }'
```

**Every descriptive field is stored verbatim and none of them influence what is generated.** Not one reaches the prompt. Filling them in buys you a readable history — `GET /v1/generations?productId=…` becomes a useful filter — and nothing else. Do not treat a product record as a brief the model will read, and do not paste brand voice in here expecting it to change a render; that belongs in `MASTER_CONTEXT.md`, which the agent actually reads.

`PATCH /products/{productId}` takes the same fields, all optional. `GET /products/{productId}/folders` is read-only, and there is no folder-creation endpoint.

## GET /models

The catalog: per model `id`, `displayName`, `kind`, `endpoint`, `credits`, `representativeOutput`, `aspectRatios`, `durationsSeconds`, `maxPromptCharacters`.

**`credits` prices `representativeOutput`, and that unit is not the same across models** — one model's representative output is 5 seconds of video, another's is 10. Comparing the two `credits` numbers directly compares different things. For a real comparison, price both at `POST /v1/estimates` with the same `durationSeconds`.

## Status lifecycle

```
queued -> running -> finalizing -> succeeded
                                -> failed
                                -> blocked
                                -> canceled
```

`succeeded`, `failed`, `blocked`, `canceled` are terminal. Nothing else will change.

**Poll for terminal, not for `succeeded`.** A loop waiting only on `succeeded` never exits on a failed job.

`queued` means charged and submitted but not yet rendering. It is normal, not a stall.

Measured on production renders (all providers, succeeded only, p10 to p90):

| model | typical wait | median | observed in this repo |
|---|---|---|---|
| `seedance-2.0` | 3 to 8 minutes | ~5 minutes | **~171s, ~171s, ~154s** (2026-08-02/03, n=3) |
| `seedance-2.0-mini` | 2 to 3 minutes | ~2.3 minutes | — |
| `omni-flash` | not published | — | — |
| `veo-3.1` | not published | — | — |
| `sora-2` | not published | — | **~123s** (2026-08-02, n=1) |

The right-hand column is `createdAt` → first observed `succeeded` at 15-second poll granularity, so it is an upper bound on a handful of renders — not a distribution, and not a contradiction of the fleet range next to it. **Quote the fleet range where there is one and say the number is a range.** Both renders anyone here has actually timed came back under three minutes, so "about five minutes" is a promise the API did not make: a user told five who waits nine has been misled, and the p90 says nine happens.

For `omni-flash`, `veo-3.1` and `sora-2` there is no published range at all. Say the wait is unknown rather than borrowing Seedance's.

About 4% of `seedance-2.0` renders run past 10 minutes. Failures are usually reported faster than successes, but their tail is much worse, so a wait that is far past p90 is more likely a slow success than a silent failure.

---

## Limits

| Limit | Value |
|---|---|
| Requests per key | 60 per minute |
| Requests per organization | 180 per minute, across every key it holds |
| Requests per client address, pre-authentication | 1,200 per minute |
| Concurrent generations per organization | 5 (`429`, `error.code` `rate_limited`, `details.reason` `concurrency_limit`, `Retry-After` 15s) |
| JSON request body | 64 KB |
| Upload size | 100 MB |
| Upload URL lifetime | 900 seconds |
| Output URL lifetime | 3,600 seconds, minted at read time |
| Live API keys per organization | 10 |

Every response carries `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset`, and a `429` also carries `Retry-After`. Two caveats an agent that paces itself off those headers needs:

- The headers always describe **your per-key budget**. A `429` from the organization ceiling or from the pre-auth ceiling can arrive while they still show room.
- The pre-auth ceiling reports `Retry-After` and **no** `X-RateLimit-*` headers at all.

Concurrency detail worth knowing: the count covers the organization's **API surface only**, so dashboard renders do not consume an integration's slots, and a row stops counting after 30 minutes unfinished, so a stuck job cannot jam an organization permanently. Reads, estimates and uploads are not affected by it.

Cloudflare's edge timeout of roughly 100 seconds is the real ceiling on any single request, which is why video generation is asynchronous and image generation is not (it fits).

---

## Errors

Envelope, on every failure:

```json
{ "error": { "code": "...", "message": "...", "requestId": "...", "details": { } } }
```

**Branch on `code`.** The wording of `message` can change. `requestId` matches the `x-request-id` response header; quoting it makes the whole server-side trace one lookup.

| `code` | Status | Notes |
|---|---|---|
| `invalid_input` | 400 | **Malformed request only.** `details.issues` names each bad field. Nothing charged. See below. |
| `unauthorized` | 401 | Missing, malformed or revoked key. Carries `WWW-Authenticate: Bearer`. |
| `insufficient_credits` | 402 | `details` has `required` and `available`, in credits. |
| `forbidden` | 403 | `details.reason` is `plan_required` or `subscription_inactive`, or the API is not enabled for that organization. |
| `not_found` | 404 | No such object **for this organization**. Deliberately indistinguishable from someone else's object. |
| `method_not_allowed` | 405 | Real path, wrong verb. Carries an `Allow` header. |
| `conflict` | 409 | Includes `/watch` on an unfinished job. |
| `content_policy` | 422 | Moderation, and the **only** refusal of a prompt for what it says. Nothing charged. |
| `rate_limited` | 429 | **Four causes.** See below. |
| `internal_error` | 500 | **Do not blindly retry.** See below. |
| `provider_failed` | 502 | Credits refunded automatically. |

### A 400 has one shape

It is a schema rejection, and it names the fields:

```json
{ "error": { "code": "invalid_input", "message": "(root): Unrecognized key: \"styleFamily\"",
  "details": { "issues": [ { "field": "(root)", "message": "Unrecognized key: \"styleFamily\"" } ] } } }
```

An out-of-grid `durationSeconds` and a prompt past the model's ceiling land the same way — the
response names the field and the limit.

**There is no second shape.** Until spec `2.0.0` a prompt-rule failure was also a 400, carrying `details.rule` and `details.violations[]`. Those keys no longer appear on any response: the rules do not run on the generation endpoints at all, and on `/estimates` they surface as advisory `warnings` on a `200`. Code that branches on `details.rule` is reading for something that will never arrive.

### The four causes of a 429

Every one carries `details.reason` and a `Retry-After` header. Those two are the documented
contract: sleep on the header, branch on the reason. `error.details` is a free-form object, so a
response may carry more than the spec names — `details.inFlight` on a concurrency refusal is the
only extra it does name. Do not branch on an undocumented `details` key.

| `details.reason` | Cause | What to do |
|---|---|---|
| `concurrency_limit` | 5 generations already in flight for the organization; `details.inFlight` says how many | Wait for one to reach a terminal state, then submit. A longer backoff does not help; a finished job does. Generation endpoints only. |
| `key_limit` | 60 requests per minute on this key | Honor `Retry-After`. The `X-RateLimit-*` trio tracks this ceiling and only this one. |
| `organization_limit` | 180 requests per minute across every key the organization holds | Honor `Retry-After`. `X-RateLimit-*` will still show room on your key — correct, not a broken limiter. Minting another key does not raise it. |
| `client_limit` | 1,200 requests per minute from one address, **pre-authentication** | Honor `Retry-After`. Carries no `X-RateLimit-*` trio. |

An agent that reads only "429 means slow down" backs off on the wrong axis when the real problem is five jobs in flight.

### The 500 rule

The generation endpoints charge credits, and a failure can land **after** the debit committed. A blind retry can pay twice, and there are no idempotency keys yet.

On a 500: call `GET /v1/generations` first. If the job is there, poll it. Only resubmit if it is genuinely absent.

---

## Known discrepancies

Dated. Struck through when fixed, never deleted, because a retraction is more useful than a gap.

- ~~**2026-08-01, the published 422 description is wrong.**~~ **Fixed in the spec; re-read 2026-08-02.** The 422 description was corrected once to name 400 as the prompt-rule status, and corrected again when the rules stopped blocking. It now reads: moderation is the ONLY way a prompt is refused for what it says, and a 400 means malformed, "never that we disliked the writing". The underlying behavior never changed: 422 is moderation only.
- ~~**2026-08-01, the per-operation `429` description names only one of its three causes.**~~ **Fixed in the spec, verified 2026-08-02.** Every operation's `429` now names all four ceilings — `key_limit`, `organization_limit`, `concurrency_limit`, `client_limit` — and says how each is paced, including that waiting is the only fix for concurrency. Live probe: a per-key 429 returns `details: {reason: "key_limit", limit: 60, retryAfterSeconds: 51}`.
- ~~**2026-08-01, `styleFamily` on an image estimate has no counterpart on the paid image call.**~~ **Resolved 2026-08-02 by deleting the field.** `styleFamily` is gone from both estimate arms and from every video variant, so the quote and the invoice now accept exactly the same prompt fields. Both arms are strict: sending it is `400 (root): Unrecognized key: "styleFamily"` (verified live on `kind: "video"` and `kind: "image"`). The rules it used to scope no longer refuse anything, so the divergence it caused — price clean, then 400 — is structurally impossible now.

## Prompt rules

**They advise. They do not enforce.** As of spec `2.0.0` the rules run on `POST /estimates` and nowhere else, every finding comes back in `warnings` on a `200`, and no finding refuses, delays, or reprices anything. `POST /videos`, `POST /images` and the MCP `generate_video` / `generate_image` tools skip the pass entirely: a prompt that trips every rule on this page is charged, rendered, and handed to the provider unmodified.

Read that as a redistribution of responsibility, not as a feature that was switched off. The API used to be the thing that stopped a bad prompt; now the **skill layer is the only thing that does**, which is why gate 2 says to read the warnings out before spending, and why the prompt libraries are mandatory rather than nice to have.

`styleFamily` used to scope which of these ran. It is gone, and so is the scoping — **every video rule now runs against every video prompt**, so a stylized route will collect advice written for live-action UGC. `missing_actor_descriptor` on a Pixar ad whose lead is an appliance is the standard example: correct rule, wrong route, ignore it. Judgement about which advice applies is now the caller's, which is exactly what the field used to buy with a lie.

**Video: 8 rules, all advisory.** Verified live 2026-08-02: one prompt tripping seven of them still priced successfully, returning all seven in `warnings` rather than refusing. (What it cost is deliberately not recorded here — price every call with a live `POST /estimates`.)

| Rule | What it catches |
|---|---|
| `banned_polish` | `cinematic`, `8k`, `flawless`, `award-winning` and their ES/PT equivalents — the words that produce the plastic "looks AI" render |
| `back_reference` | `the same woman`, `as before`, `la misma mujer` — no identity carries across a cut, so the phrase resolves to nobody |
| `missing_actor_descriptor` | No age/gender/wardrobe token, so the model re-casts |
| `chained_motion` | `then`, `and then`, `followed by` — a second action strung onto the first, which renders as a smear |
| `bullety_prompt` | `-` lines or `Label: value` pairs, which come back rendered as literal on-screen text |
| `no_spoken_line` | No quoted line, so an actor mouths nothing in a fully billed render. Saying `silent`, `b-roll` or `voiceover` satisfies it |
| `label_without_hold` | A visible label, package or screen with no label-hold clause. Seedance preserves logos and destroys printed text |
| `no_aspect_ratio` | No ratio stated in the prompt text (the `aspectRatio` field is what binds; the sentence steers composition) |

**Image: 3 rules, all advisory.**

| Rule | What it catches |
|---|---|
| `banned_polish` | The same banned polish words as video |
| `blank_label` | Asking for an unbranded, blank-label or generic-packaging product. Name the real brand and pass the user's photo in `referenceAssetIds` — and note that nothing stops this render anymore, so the warning is the only signal you will get |
| `unfilled_placeholder` | A literal `[USER_PRODUCT]` left in the prompt — a template that was never filled in |

Each `warnings` entry is `{rule, message}`, and the `message` is the fix written out, usually with a rewrite example in English and one in Spanish. The patterns cover English, Spanish and Portuguese, so a Spanish prompt is linted in Spanish; there is no longer any pressure — and never was any benefit — in rewriting an ad into English.

The video rules, with the failure each one prevents and a worked example that collects no warnings at all, are in `prompting/prompt-library/seedance-2-ugc.md`.
