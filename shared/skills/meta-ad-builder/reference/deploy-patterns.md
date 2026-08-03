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
   - `link_urls` (image ads only — see below)
3. **`degrees_of_freedom_spec`** — opts the ad into text liquidity + Advantage+:
   - `degrees_of_freedom_type: USER_ENROLLED`
   - `text_transformation_types: ["TEXT_LIQUIDITY"]`
   - `creative_features_spec` — the Advantage+ enhancement enrollment map

`TEXT_LIQUIDITY` lets Meta mix-and-match the supplied bodies/titles/descriptions
and place them where they perform best. Supplying 5 bodies / 5 titles /
3 descriptions is the proven shape — see [copy-guide.md](../prompting/copy-guide.md).

### `link_urls` on images but not videos — deliberate

`build_image_creative` includes `link_urls` in `asset_feed_spec`;
`build_video_creative` does not. This asymmetry is **verified working**, not an
oversight: a live video deploy on 2026-08-03 produced an ad whose destination
resolved correctly, carrying the link through
`object_story_spec.video_data.call_to_action.value.link`. Do not "fix" it by
adding `link_urls` to the video path without re-testing a live deploy.

### `TEXT_LIQUIDITY` does not read back

The two `degrees_of_freedom_spec` flags the skill sends —
`text_transformation_types` and `degrees_of_freedom_type` — **do not appear**
when the created creative is read back (verified 2026-08-03). The asset feed
itself does persist: the 5/5/3 pool was present on the live ad. Treat the asset
feed as the evidence and verify it explicitly:

```bash
curl -s -G "https://graph.facebook.com/v23.0/<AD_ID>" \
  --data-urlencode "fields=creative{asset_feed_spec,degrees_of_freedom_spec}" \
  --data-urlencode "access_token=$META_ACCESS_TOKEN" | python3 -m json.tool
```

Report what read back, not what was sent.

### `creative_features_spec`

A fixed enrollment map (`OPT_IN` / `OPT_OUT` per feature). It lives as a
constant in `deploy-ad.py`; the video variant adds `video_auto_crop`,
`video_filtering`, `video_uncrop`. Meta adds features over time, so re-check
cheatsheet §8 if a deploy warns about an unknown feature.

**Several of these enrollments modify the creative itself.** `deploy-ad.py`
defaults to `--burned-in-captions`, which forces the frame-modifying features
(`video_uncrop`, `video_auto_crop`, `video_filtering`, `creative_stickers`,
`reveal_details_over_time`, `show_summary`, `show_destination_blurbs`, and the
`text_extraction` customizations under `enhance_cta` / `text_optimizations`) plus
`text_translation` to `OPT_OUT`. Creatives from this workspace carry text baked
into the pixels, and those features crop, recolour, overlay across or re-derive
copy from it. `--no-burned-in-captions` restores Meta's full enrollment.
`--dry-run` prints the resulting map feature by feature with a reason for every
forced `OPT_OUT`.

## Conversion tracking

Pass `--pixel-id` (or set `META_PIXEL_ID`) to attach a `tracking_specs` entry
for offsite-conversion attribution. Without a pixel the ad still deploys; it
just won't be optimized/attributed for conversions.

## Failure reporting and orphaned assets

`upload_image`, `upload_video`, `wait_for_video_processing` and `create_ad` each
return a **`(value, error)` tuple**. On failure the error carries Meta's `code`,
`error_subcode`, `type`, `message`, `error_user_msg` and `fbtrace_id` verbatim.
`deploy-ad.py` writes each one into `deployment_results.json` under `failures`
and **exits 1**.

This replaced a contract where the helpers printed the error and returned a bare
`None`, and the caller `continue`d past it — which produced
`DONE. 0 ad(s) created PAUSED.` and **exit 0** on a run where the ad was
rejected. Any wrapper reading the exit code saw success, and the reason survived
only in stdout. If you touch these helpers, keep the error in the return value.

Assets upload before the ad is created, so a rejected ad leaves the uploaded
video or image behind. `deploy-ad.py` collects these under `orphans` and prints
each with a ready-to-run `curl -X DELETE` line that reads
`$META_ACCESS_TOKEN` from the environment (no token is ever printed). Assets
that did make it onto an ad are excluded — they are not orphans.

**Cleanup is not automatic.** Deleting objects from a live ad account is a
user decision; the script surfaces them and stops there.

## Transient errors

Meta's API returns transient `OAuthException`s (often `code 2`,
`is_transient: true`) under load. `create_ad()` retries up to 4 times with
exponential backoff (5s → 10s → 20s, capped at 60s). Non-transient errors fail
fast with the full error JSON. Rate limits (HTTP 429) and 5xx are handled in the
research scripts with `Retry-After` / fixed backoff.

## Common failure modes

| Symptom | Cause / fix |
|---|---|
| `Ads creative post was created by an app that is in development mode` (code 100 / subcode **1885183**) | The Meta app is not published. Toggle it to **Live** in the App Dashboard. Allowlisting the ad account under App settings → Advanced → Authorized ad account IDs does **not** help (tested 2026-08-03). |
| `Video failed to process` (1487713) | Ad created before video finished processing — always poll first. |
| `code 2`, transient | Meta load — retry/backoff handles it; if it persists, wait and rerun. |
| Empty response body | Treat as transient; retry. |
| `Creative should not include standard enhancements` (3858504) | `standard_enhancements` is deprecated — use `creative_features_spec` (the skill already does). |
| Image ad has no destination | `link_urls` missing from `asset_feed_spec` — the skill adds it for images. |
| API version errors | Bump `META_API_VERSION` (default `v23.0`); the old Ad Builder Agent used `v21.0`. |
