# Novoads API logs

Append-only logs of every generation call the agent makes against the Novoads API.

**These logs are observability, never pricing.** They record what was submitted, how long it took, and what it ended up costing — *after the fact*. They are **not** an input to any quote. Every credit number shown to a user comes from a live `POST /v1/estimates` call in the current session (see `skills/novoads-api/SKILL.md`, gate 2). A past `creditsCharged` value is history, not a rate card, and this repo holds no rate tables anywhere.

## Files

- **`novoads-api.jsonl`** — one JSON object per line, one line per generation call.
  - **Videos are asynchronous:** append the line the moment `POST /v1/videos` returns `202` with a `jobId`, then **update that same line** when polling reaches a terminal status (`succeeded`, `failed`, `blocked`, `canceled`).
  - **Images are synchronous:** `POST /v1/images` returns the finished images in the response body, so the line is written once, complete. It still carries a `jobId` — log it, there is just nothing to poll and nothing to update.

## Entry schema

```json
{
  "timestamp": "2026-08-01T19:18:24.611Z",
  "endpoint": "POST /v1/videos",
  "model": "seedance-2.0",
  "jobId": "gen_9f2c1b7a4e8d",
  "productId": "10b24deb-2ce7-47f7-8cf3-624b844658b8",
  "request": {
    "durationSeconds": 12,
    "aspectRatio": "9:16",
    "language": "en",
    "startImageAssetId": true,
    "referenceAssetIdsCount": 0,
    "promptWordCount": 340
  },
  "response": {
    "status": "succeeded",
    "creditsCharged": 3.2,
    "generationTimeSec": 287,
    "error": null
  }
}
```

Image lines use the same shape with `"endpoint": "POST /v1/images"`, `numImages` in place of `durationSeconds`, and `generationTimeSec` measured as the request round trip. They carry a `jobId` like video lines do; the difference is that the line is complete when written, not that the field is absent. Add `"qaRetryOf": "<timestamp of the original line>"` on a line that is an image QA regeneration, so the extra credits are attributable.

Field notes:

- `status` is the **terminal** value, not the first one polled. A line whose `response` is still absent is a job that never reached a terminal state in that session.
- `creditsCharged` comes off the API response — never computed locally.
- `startImageAssetId` is logged as a boolean and `referenceAssetIds` as a count. Asset ids belong to the user's uploads, not in a log.
- `request` mirrors the body that was actually sent. Log no field the API does not have — `styleFamily` was deleted from the API in spec `2.0.0` and must not appear on a line written after that, or a later reader will infer a request shape that would 400 today.

## How the agent uses this file

- **Before generating:** nothing. Do not read this file to build an estimate — call `POST /v1/estimates`.
- **On submit:** append the request metadata immediately, before polling starts, so a crashed session still leaves a trace of a charge that was incurred.
- **On terminal status:** update the line with the final status and elapsed time. Carry `creditsCharged` over from the `202` you already logged — `GET /v1/generations/{jobId}` does **not** return it (its schema is `createdAt`, `error`, `jobId`, `kind`, `model`, `outputUrl`, `outputUrlExpiresInSeconds`, `prompt`, `status`). Verified live 2026-08-02. If it is missing from your submit line it is gone; never reconstruct it from a rate.
- **Afterwards:** use it to answer "how long did that take", "what did last week cost", and "which config failed" — latency, spend history, and failure patterns.

## What must never be logged

API keys, the `Authorization` header, presigned URLs (`uploadUrl`, `outputUrl` — they expire and they are credentials while they live), and full prompt text. Store a **word count** instead of the prompt.

Logs are **not** gitignored: latency and failure history across sessions is worth keeping. Because they are committed, the exclusion list above is a hard rule, not a preference.
