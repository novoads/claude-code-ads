# Pixar-style ad — pipeline scripts

End-to-end shell + Python pipeline that backs the [guide](../prompting/guide.md). Use these as a starting point; copy them into a per-run directory and edit prompts/timings/durations to fit your campaign.

## Prerequisites

- `NOVOADS_API_KEY` in `.env` (`novo_` + 64 hex) — see the `novoads-api` skill. Verify with `./scripts/check-novoads-env.sh` at the repo root.
- `ELEVENLABS_API_KEY` in `.env`
- `ffmpeg` (Homebrew build is fine for video, but the Pillow caption renderer is used because Homebrew ffmpeg ships without `libass` / `drawtext`)
- `python3` with `Pillow` (`pip install Pillow`)
- `jq` (`brew install jq`)

## Per-run setup

```bash
export RUN_DIR="$HOME/runs/$(date +%Y-%m-%d)-<campaign-slug>"
export PRODUCT_ID="<novoads-product-uuid>"   # optional; GET /v1/products lists them
mkdir -p "$RUN_DIR"/{stills,clips,vo-beats,captions-png,references}
```

There is no project id. The v1 API has no project or folder writes, so the dated-folder ritual that used to wrap a run does not exist here — `productId` is the only grouping key, and `GET /v1/generations?productId=…` is how you list a product's history.

## Pipeline order

0. **Price the run and get a yes.** `POST /v1/estimates` is free and is the only place a credit number may come from. Do this before step 2 — the storyboard loop is where the money goes.
1. **Lock the cast sheet + write the 4-beat script** — see [guide](../prompting/guide.md). Storyboarding is human work; everything below assumes you have approved 5-7 stills' worth of prompts and per-beat VO copy.
2. **`generate-stills.sh`** — `gpt-image-2` calls, up to 4 in flight, optionally with `referenceAssetIds` (max 4) for character continuity. **Images are synchronous: this script downloads them itself.** For N variations of one beat, set `NUM_IMAGES=N` rather than firing N calls — same price, one call, one concurrency slot.
3. (manual) QA the stills. Regenerate any with defects, ≤2 retries per beat.
4. **`upload-stills.sh`** — upload each approved still **once**; writes a `<slot><TAB><assetId>` map. All variations of a beat reuse that one id.
5. **`generate-seedance.sh`** — one `POST /v1/videos` call per (still × variation), passing the still as `startImageAssetId`. Async: returns a `jobId` each.
6. **`poll-and-download.sh`** — poll `GET /v1/generations/{jobId}` every 15s until **terminal**, then download via `/watch`.
7. (manual) QA the clips. Pick favorite take per beat.
8. **`restitch-tight.sh`** — trim each chosen clip to roughly its VO line length (no dead space) and concat with audio preserved.
9. **`generate-vo-elevenlabs.sh`** — generate ONE VO clip per visual beat so timing snaps to cuts. Use `A.I.` (with periods) for fluid acronym pronunciation; `A I` reads as separated letters.
10. **`generate-music-elevenlabs.sh`** — compose a 30-60s instrumental bed. Prompt for the genre that fits your audience, not generic "uplifting." Will be mixed at ~10%.
11. **`render-captions.py`** — emit one transparent PNG per caption with timing in `schedule.tsv`. Edit the `CAPTIONS` array to match VO word-for-word.
12. **`final-assembly.sh`** — final ffmpeg mix: video + per-beat VOs (at their offsets) + music (low) + original Seedance audio as SFX bed + caption PNG overlays.

## Key conventions baked in

- **No dead space:** trim each clip to ~0.5s longer than its VO line. Original 4s Seedance clip becomes ~2.5-3.5s. See [`restitch-tight.sh`](restitch-tight.sh).
- **VO per visual beat, not per script paragraph:** generate one short ElevenLabs file per visual cut and `adelay` each to its cut time. A single long VO file always drifts. See [`generate-vo-elevenlabs.sh`](generate-vo-elevenlabs.sh).
- **Captions per beat, position decided by where the character lives:** if the character fills the lower half of the frame (laptop reveal, full-frame mascot), captions go **top**; if the character lives upper-center (dashboard close-ups), captions go **bottom**. Caption text matches VO verbatim. See [`render-captions.py`](render-captions.py).
- **Audio mix:** VO 100%, Seedance SFX 28%, music 10%. See [`final-assembly.sh`](final-assembly.sh).
- **Caption renderer is Pillow + ffmpeg overlay, not libass.** Homebrew ffmpeg ships without `subtitles` / `drawtext` filters. Pillow + transparent PNGs is the workaround.

## Example prompts

Reference prompts from a real run (community-promo Pixar ad, May 2026 — brand names replaced with `[BRAND]` / `yourbrand.com` placeholders) are in [`example-prompts/`](example-prompts/) — useful as a template for prompt structure, voice/SFX choices, and beat structure.

## Cost

**No numbers live here, deliberately.** Prices come from a live `POST /v1/estimates` in the session that is about to spend them, and nowhere else — not from this file, not from `MASTER_CONTEXT.md`, and not from `logs/novoads-api.jsonl` (that log is observability only). A stale rate table is a quote that disagrees with the invoice.

What is worth knowing about the *shape* of the cost, since it does not change with the schedule:

- A run of this pipeline is roughly `beats × (1 still + variations × 1 clip)` billed generations, plus retries. Variations dominate — 3 takes per beat triples the video half.
- **Video price scales with `durationSeconds`**, so estimate each distinct beat length separately rather than extrapolating from one.
- `seedance-2.0-mini` is half `seedance-2.0` at the same duration. Prototype beat timing on mini, finalize on the full model.
- `numImages` multiplies the image price, so variations of a still cost the same whether you ask for them in one call or four. One call is still better: it uses one concurrency slot instead of four.
- Every QA retry is billed. Report the extra credits at the end of the run.
