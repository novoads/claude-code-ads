# Meta ad deployment patterns

The hard-won mechanics behind `scripts/deploy-ad.py` and `scripts/lib/meta_api.py`.
Read this when a deploy fails, when you need to change the creative spec, or when
you're explaining what the script does. The full API surface is in
[meta-api-cheatsheet.md](meta-api-cheatsheet.md) — this file is the *opinionated subset*
the skill actually relies on.

## The object model

```
Campaign  →  Ad Set  →  Ad  →  Creative
```

The `meta-ad-builder` skill deploys at the **Ad** level: it uploads a creative
asset, builds a Creative object, and creates an Ad inside an **existing ad set**.
Creating campaigns / ad sets is a deliberate, less-frequent action — do that in
Ads Manager or with explicit Graph API calls (see cheatsheet §3–§4), not as a
side effect of a creative deploy.

## Safety invariant: ads are created PAUSED

`create_ad()` always sends `status=PAUSED`. Nothing the skill creates ever
spends money until the user reviews it in Ads Manager and un-pauses it. Do not
add an `--active` flag or override this without an explicit user instruction —
it is the single most important guardrail in the skill.

## Uploading the creative asset

| Asset | Endpoint | Returns | Notes |
|---|---|---|---|
| Image | `POST act_<id>/adimages` (base64 `bytes`) | `hash` | Used as `image_hash` in `link_data`. |
| Video | `POST act_<id>/advideos` (multipart `source`) | `id` | Must finish processing before an ad can reference it. |

**Video processing is asynchronous.** After upload you must poll
`GET /<video_id>?fields=status,thumbnails{uri,is_preferred}` until
`processing_phase.status == complete` and `video_status == ready`. Creating the
ad before then fails with subcode `1487713` ("Video failed to process"). The
preferred thumbnail URI becomes `video_data.image_url` — a video ad requires it.

## The creative object — multi-variant copy

The skill always builds a **multi-variant** creative so Meta can rotate copy.
Three pieces fit together:

1. **`object_story_spec`** — the page identity + the asset:
   - `page_id` (required), `instagram_user_id` (optional but recommended)
   - `link_data` for an image ad (`link`, `image_hash`, `call_to_action`)
   - `video_data` for a video ad (`video_id`, `image_url`, `call_to_action`)
2. **`asset_feed_spec`** — the copy pool Meta rotates:
   - `optimization_type: DEGREES_OF_FREEDOM`
   - `bodies`, `titles`, `descriptions` (each an array of `{"text": ...}`)
   - `call_to_action_types`
   - `link_urls` (image ads only)
3. **`degrees_of_freedom_spec`** — opts the ad into text liquidity + Advantage+:
   - `degrees_of_freedom_type: USER_ENROLLED`
   - `text_transformation_types: ["TEXT_LIQUIDITY"]`
   - `creative_features_spec` — the Advantage+ enhancement enrollment map

`TEXT_LIQUIDITY` lets Meta mix-and-match the supplied bodies/titles/descriptions
and place them where they perform best. Supplying 5 bodies / 5 titles /
3 descriptions is the proven shape — see [copy-guide.md](../prompting/copy-guide.md).

`creative_features_spec` is a fixed enrollment map (`OPT_IN` / `OPT_OUT` per
feature). It lives as a constant in `deploy-ad.py`; the video variant adds
`video_auto_crop`, `video_filtering`, `video_uncrop`. Treat it as a known-good
block — Meta adds features over time, so re-check the cheatsheet §8 if a deploy
warns about an unknown feature.

## Conversion tracking

Pass `--pixel-id` (or set `META_PIXEL_ID`) to attach a `tracking_specs` entry
for offsite-conversion attribution. Without a pixel the ad still deploys; it
just won't be optimized/attributed for conversions.

## Transient errors

Meta's API returns transient `OAuthException`s (often `code 2`,
`is_transient: true`) under load. `create_ad()` retries up to 4 times with
exponential backoff (5s → 10s → 20s, capped at 60s). Non-transient errors fail
fast with the full error JSON. Rate limits (HTTP 429) and 5xx are handled in the
research scripts with `Retry-After` / fixed backoff.

## Common failure modes

| Symptom | Cause / fix |
|---|---|
| `Video failed to process` (1487713) | Ad created before video finished processing — always poll first. |
| `code 2`, transient | Meta load — retry/backoff handles it; if it persists, wait and rerun. |
| Empty response body | Treat as transient; retry. |
| `Creative should not include standard enhancements` (3858504) | `standard_enhancements` is deprecated — use `creative_features_spec` (the skill already does). |
| Image ad has no destination | `link_urls` missing from `asset_feed_spec` — the skill adds it for images. |
| API version errors | Bump `META_API_VERSION` (default `v23.0`); the old Ad Builder Agent used `v21.0`. |
