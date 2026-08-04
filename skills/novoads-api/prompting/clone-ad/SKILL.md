---
name: clone-ad
description: >
  Clone an existing video ad for a different product or offer on the Novoads API. Analyzes
  the source video's style, pacing, camera work, dialogue and tone, then adapts it into a
  new Seedance 2.0 prompt and renders it for the user's product. End to end: input video →
  analysis → adapted prompt → estimate → generation → delivery. Use when someone says
  "clone this ad", "make this ad but for my product", "recreate this video for my brand",
  or hands over a video ad plus a product photo and asks for something similar.
---

# Clone ad — Seedance 2.0

Clone an existing video ad for a different product. You analyze the source frame by frame,
transcribe the dialogue, extract the visual style and beat structure, then generate a new
`seedance-2.0` video adapted for the user's product.

**How this differs from analyze-video:**

- **analyze-video** → the output is a reusable markdown formula saved to `prompt-library/`.
- **clone-ad** → the output is a rendered video delivered to the user.

Steps 1 to 3 are the same local analysis in both, and they cost nothing. Everything from
step 9 on spends credits.

## What this API changes about cloning

The analysis half of this skill is untouched — frames, transcript and beat structure are
local work on the user's file. The generation half has three differences worth knowing
before you promise anything, all three verified live against the deployed spec `2.0.0`
(2026-08-02) with free `400` probes that reject before any charge:

| The old shape | Here |
|---|---|
| Chain clip 1 → clip 2 → clip 3 as reference **videos**, so each clip inherits the last | **There is no video-to-video path.** `referenceVideos` is `400 (root): Unrecognized key`, and references are images only. What holds a series together is passing the **same image `assetId`s to every clip** plus repeating the actor tag verbatim — see step 5 |
| `audioEnabled: true` to switch speech on, `false` for a silent clone | **`audioEnabled` exists here now, on the two Seedance variants only** (added in spec `2.2.0`; `400 Unrecognized key` on `omni-flash`, `veo-3.1` and `sora-2`). It defaults to `true`, so a clone with dialogue needs nothing. Send `false` only for a deliberately silent clone — and **still write the silence into the prose**, because the flag mutes the render while the prose is what stops the model staging a talking shot. It does not change the price, and `POST /v1/estimates` refuses the field |
| Upload the source audio as `referenceAudios` to clone the voice | **There is no voice cloning on this API** (`400 Unrecognized key`). Describe the voice in the prompt — age, accent, pace, energy — and accept that it is a different person's voice. Do not offer the user a voice match you cannot deliver |

Also gone, in the same probe: `endFrame`, `projectId` (this
API has products, not projects), `duration` (it is `durationSeconds`) and `referenceImages`
(it is `referenceAssetIds`).

**`resolution` was on that list and has come back.** It is a real field on `seedance-2.0` as of spec 2.6.0 — `480p`, `720p`, `1080p`, `4k`, default `720p` (verified live 2026-08-04). A clone should normally match the source's tier, which for a social ad is `720p`; going above it is a **spend** decision (`1080p` ≈2.5x the base, `4k` ≈5x) that gets priced with `POST /v1/estimates` and approved like any other. `480p` costs the same as `720p`. **A clone rendered as a series pays the multiplier on every clip** — check the tier before you fan out. Never send the key on `seedance-2.0-mini`, which renders 720p only.

**And one the old shape got wrong in the other direction:** aspect ratio is not
`9:16`-or-`16:9`. Seedance takes `16:9` `9:16` `1:1` `4:3` `3:4` `21:9` — probed live, `1:1`
and `4:3` both pass validation — so a square or landscape source clones at its own ratio
instead of being letterboxed into a vertical frame.

## Prerequisites

```bash
which ffmpeg || echo "MISSING — run: brew install ffmpeg"
python3 -c "import whisper; print('whisper OK')" 2>/dev/null || echo "MISSING — run: pip3 install openai-whisper"
./scripts/check-novoads-env.sh
```

`extract-frames.sh` and whisper both need ffmpeg. The env check has to return 200 before
step 9, and it is worth running first: discovering a bad key after the user has approved a
dialogue script is a bad look.

## Workflow

### Step 0: Gather inputs

| Input | Required | Notes |
|---|---|---|
| **Source video** | yes | The ad to clone. `.mp4`, `.mov`, `.webm` |
| **Product photo** | strongly recommended | Becomes `startImageAssetId` or `@Image1` in `referenceAssetIds`. Without it Seedance invents its own product design, renders it, and charges for it |
| **Product / offer description** | if no photo | Features, audience, selling points. Used to rewrite the dialogue and the product references |
| **A photo of the person** | optional | Only if the clone is a series — it is what holds one face across clips |
| **Brand voice** | optional | Check `MASTER_CONTEXT.md` first. If its brand blocks are empty, ask for tone and audience |

**Check `references/` at the repo root before asking.** `references/products/` for product
shots, `references/influencers/` for people, `references/aesthetics/` for style boards. If
the photo is already there, offer to use it.

If they hand over only a video and say "clone this for my product", ask for a photo or a
description before going any further. Cloning a style onto a product you cannot see is
guesswork the user pays for.

### Step 1: Extract frames and audio

Reuse the analyze-video script. Do not duplicate it.

```bash
bash "skills/novoads-api/prompting/analyze-video/scripts/extract-frames.sh" \
  "<source_video_path>" "/tmp/clone-ad-analysis" <num_frames>
```

| Source duration | Frames |
|---|---|
| Under 10s | 8 |
| 10–20s | 12 |
| 20–30s | 16 |
| Over 30s | 20 |

Outputs: `frame_001.jpg` … `frame_NNN.jpg`, `audio.wav` (16 kHz mono, whisper-ready), and
`metadata.txt` with duration, resolution and fps. Read the duration — step 5 branches on it.

### Step 2: Transcribe the audio

```python
import whisper
model = whisper.load_model("base")
result = model.transcribe("/tmp/clone-ad-analysis/audio.wav")
```

Record the full transcript, the per-segment timestamps and text (`result["segments"]`), the
total word count, and the detected language. The language matters twice: it is what you
send as `language`, and it is what you write the adapted prompt in.

If no speech is detected, note it and skip the dialogue work in step 7 — the clone is a
visual-style clone, and it has to **declare its own silence** in the prompt text (step 6).

### Step 3: Compressed analysis

Read **all** the extracted frames. For each, note:

**Structure and pacing** — how many beats, what the arc is (hook → demo → verdict? reveal →
detail → CTA?), how long each beat lasts against the segment timestamps.

**Camera and framing** — POV (selfie, handheld, tripod, propped phone, over-the-shoulder),
framing per beat (wide, medium, close-up, macro), movement (static, pan, dolly, handheld
shake), and any signature move: "leans into camera", "tilts the product toward the lens".

**Edit style** — transition type, visual rhythm, recurring motifs ("every other beat is an
extreme close-up").

**Dialogue and script structure** — hook format, speech pattern (casual or formal, filler
words, trailing thoughts, mid-sentence cuts), how many spoken lines, how many silent beats,
CTA style.

**Tone and energy** — emotion words, the energy arc, the speaker's relationship to the
viewer: friend, expert, skeptic, fan.

**Lighting and technical quality** — light source and direction, camera class, deliberate
flaws, audio character.

**Product references** — how the product is physically shown, which claims are called out,
what labels and text are visible on screen.

**What makes this ad distinctive** — the 2–3 traits that make it recognisable. These are the
ones that MUST transfer; everything else is negotiable.

This analysis stays in the conversation. It is not saved as a template file — that is
[analyze-video](../analyze-video/SKILL.md)'s job.

### Step 4: Present the analysis, and make it a contract

Show the breakdown before doing anything else, and derive the payload from it **out loud**,
so the user can correct a wrong reading before it costs anything:

```
📋 Source video analysis

Duration: 13.6s | Beats: 4 | Dialogue: 31 words (en) | Style: skeptic-converted UGC

Beat map:
  [00:00–00:03]  HOOK     — close-up, deadpan, "opening line"
  [00:03–00:07]  SHOW     — tilts product to camera, "feature call-out"
  [00:07–00:10]  DEMO     — (silent) applies the product, close-up on texture
  [00:10–00:13]  VERDICT  — back to medium, "closing line + CTA"

Defining traits (must transfer):
  1. [trait] — because [what it does for the ad]
  2. [trait] — because […]
  3. [trait] — because […]

What transfers to your product:
  ✅ Beat structure, pacing, camera angles, edit style, tone, energy
  ✅ Dialogue pattern, adapted to your product
  ✅ Lighting and technical-quality cues

What gets swapped:
  🔄 [source product] → your product
  🔄 [source claim] → your claim
  🔄 [source brand mention] → your brand

What that means for the call:
  • 13.6s ≤ 15s          → single clip, durationSeconds: 14
  • vertical source       → aspectRatio: "9:16"
  • speech detected (en)  → language: "en", dialogue gate applies
  • product photo given   → referenceAssetIds: ["@Image1 = your product"]

Proceed with the adaptation? (yes / adjust)
```

Wait for the answer. This is a reading of their video, not an approval to spend.

### Step 5: Decide the generation mode

```
┌─ Source ≤ 15 seconds?
│   YES → one clip. durationSeconds = the source duration, rounded to an integer in 4–15.
│   NO  → split at natural beat boundaries, each piece ≤ 15s.
│         Take the split points from the beat map, not from arithmetic.
│         Every clip is its own call and its own charge.
│
├─ Did they give a product photo?
│   YES → upload it, and pick one mode:
│           startImageAssetId  — the ad opens ON the product, held up or on a surface.
│                                It animates that photo as the literal first frame.
│           referenceAssetIds  — the ad builds a scene the product was never photographed
│                                in. It composites the references instead, and the prompt
│                                addresses them as @Image1, @Image2 … by array position.
│         Never both: a body carrying both is a 400 that says they are separate modes.
│   NO  → describe the product in the prompt text and say so to the user: Seedance will
│         invent a design, render it, and charge for it.
│
├─ Is it a series (source > 15s)?
│   YES → referenceAssetIds, and pass the SAME ids to every clip:
│           @Image1 = the product, @Image2 = the person if one is on screen.
│         Repeat the actor tag verbatim in every clip. Never "the same woman".
│   NO  → either mode.
│
└─ Does the source speak?
    YES → the line is rendered and lip-synced in this same call. Gate 1 (step 7) applies.
    NO  → declare the silence in the prompt prose: "silent b-roll, no spoken dialogue".
          There is no audio switch to turn off.
```

**A series is held by references, not by chaining.** The old pattern — render clip 1, feed
its output in as clip 2's reference video — has no path here: references are images only.
That is not a downgrade. This repo's own animation rule says the same thing on its own
merits: *"Don't chain by using an animated end-frame as the next beat's anchor — drift
compounds"* (`shared/skills/claymation-ad/prompting/animate-seedance-2.md`). Every clip
anchoring to the same approved stills is the more stable pattern, and because the `assetId`
is **durable across calls, models and sessions**, it costs one upload for the whole series.
Re-uploading the same bytes mints a second asset and throws away the anchor.

**Fire the clips of a series concurrently, not sequentially** — nothing downstream depends
on an earlier clip's output any more. Five generations per organization may be in flight at
once; a sixth comes back `429` with `details.reason` of `concurrency_limit`, which is
solved by waiting for a slot and not by backing off harder.

**Offer the mini draft.** `seedance-2.0-mini` is the same grid, the same fields and the same
prompt at half the price, back in 2–3 minutes instead of 3–8. A clone is exactly the case
for it: the first render is where you find out whether your reading of the source survived
into the prompt. Draft on mini, re-price with `model` set to the final tier, and show both
numbers side by side. `SKILL.md` makes the tier an explicit question, asked once per
workflow.

Tell the user which mode you picked and why.

### Step 6: Adapt for the user's product

The creative core. Working from step 3:

**Dialogue adaptation** (if the source speaks):

- Keep the **same conversational pattern**. Question hook in, question hook out. If the
  source runs on filler — "like", "okay so" — keep the filler; it is the style.
- Keep the **same number of spoken lines** and the **same silent-beat placement**.
- Keep the **same energy arc**: excited → calm, flat, or building.
- Replace product-specific references with the user's product name, features and claims.
- Match each line's **word count within about ±3 words** so the pacing survives.
- Read it back at a natural pace against the target duration: 2.5 to 3 words per second for
  a dense product line, closer to 1.5 for a calm one.

**Visual adaptation:**

- Keep the camera work, the framing per beat, and the edit style you analysed.
- Replace the product description: physical appearance, colours, materials, label details.
- Keep the setting, the lighting and the atmosphere.
- Keep the person description, unless the user wants a different persona.
- Keep the technical-flaw cues — phone quality, mic character, imperfect light. They are
  what makes it read as real.

**Prompt composition.** Read [seedance-2.md](../prompt-library/seedance-2.md) before
composing, and the closest formula for structure —
[seedance-2-ugc.md](../prompt-library/seedance-2-ugc.md) for a talking-head source,
[seedance-2-feature-walkthrough.md](../prompt-library/seedance-2-feature-walkthrough.md) for
a fast demo, [seedance-2-premium-reveal.md](../prompt-library/seedance-2-premium-reveal.md)
or [seedance-2-product-hero.md](../prompt-library/seedance-2-product-hero.md) for a
product-only source, [seedance-2-studio-lookbook.md](../prompt-library/seedance-2-studio-lookbook.md)
for a polished voiceover source. Then:

- **Order:** Subject + Action + Camera + Style + Constraints, written as flowing prose.
  A bulleted prompt or a run of `Label: value` pairs comes back **rendered as literal text
  on screen**.
- **Keep prompts between 100 and 260 words.** Shorter prompts produce vague results; longer
  ones overwhelm the model and cause it to lose focus on key details.
- **Timestamps** — `[00:00]`, `[00:05]` — for multi-beat pacing, one main action per block.
- **`@Image1`** wherever the prompt points at a reference, matching the array order you will
  send. A token past the end of the array is refused before the charge. If the mode is
  `startImageAssetId`, use no tokens.
- **Consistency anchors:** *the product from `@Image1` remains visually unchanged in every
  shot*, *keep the outfit unchanged across all cuts*.
- **The label hold, whenever a label, package, bottle, box or screen is visible:** *the
  product label remains perfectly sharp and identical to the reference image with its text
  unchanged and fully legible*.
- **One primary action per shot**, two or three comma-joined cues on it. `then` /
  `and then` / `followed by` renders as a smear — split it into two shots.
- **No forbidden words:** `cinematic`, `professional`, `stunning`, `8k`, `studio`,
  `perfect`. Nothing on the API rejects or reports them — this is craft advice, and the
  reason to drop them is the render. Describe the real thing instead: the light source,
  the surface, the flaw.
- **Write it in the source's language** if that is what the user wants rendered. Nothing on
  the API pushes back on a Spanish or Portuguese prompt.

**Duration:** source ≤ 15s → match it, rounded to an integer in 4–15. Source > 15s → split.
Validate against the spoken word count; `SKILL.md` carries the table.

### Step 7: Dialogue confirmation gate

**Mandatory** for any clone that speaks. The line inside the double quotes is what the
actor says out loud in the finished file, and it cannot be changed afterwards without
paying for the render again. Use the format from [SKILL.md](../../SKILL.md):

```
📝 Dialogue script (please confirm before I generate)

  1. [HOOK]    "adapted line matching the source's hook pattern"
  2. [SHOW]    "adapted feature call-out for the user's product"
  3. [DEMO]    (silent beat — physical demonstration, no dialogue)
  4. [VERDICT] "adapted closing line / CTA"

Total spoken words: ~N  |  Target duration: Xs  |  language: en  |  Fits at natural pace: ✅

Approve this dialogue? (yes / edit / rewrite)
```

Rules:

- This gate is **separate** from the cost gate, and neither implies the other. Approving the
  analysis is not approving the sentences, and approving the sentences is not approving the
  spend.
- Never infer approval from an earlier yes about tone, beat map or mode.
- If they say edit, revise and re-present until they approve.
- Skip it only when the source is silent — and in that case check that the prompt itself
  says so in prose, because nothing else will.
- On a series, the gate covers **every clip**, presented together.

### Step 8: Language and audio

There is no audio switch to set. What you decide here:

1. **`language`** — the language the ad is rendered in, defaulted from what whisper
   detected. State it in the gate above and write the prompt in it.
2. **Whether the clone speaks at all.** A silent source clones silent, and the prompt has
   to say so: `silent b-roll, no spoken dialogue`. Quoting on-screen text in the prompt is
   not enough — the model reads a quoted string as a line to speak, which is the opposite
   of what you asked for.
3. **The voice.** It will not be the source's voice — there is no voice cloning here. If
   voice matters, describe it in the prompt (age, accent, pace, energy) and tell the user
   plainly that it is a soundalike, not a match.

### Step 9: Price it — the cost gate

**Never state a credit cost from memory, and never generate before showing a number that
came from a live call in this session.** There are no rate tables in this repo, in
`MASTER_CONTEXT.md`, or in the logs.

```bash
curl -sS -X POST https://api.novoads.ai/v1/estimates \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"kind":"video","model":"seedance-2.0","durationSeconds":14,"language":"en","prompt":"<the adapted prompt>"}'
```

Returns `credits`, `balance`, `sufficient`, and `shortBy` plus `topUpUrl` when it is short.
The body is strict and takes only what moves the price: `kind`, `prompt`, `model`,
`durationSeconds`, `language`. `aspectRatio`, the asset fields and `productId` are a `400`
here.

- **Pass `model` explicitly.** It defaults to `seedance-2.0`, and mini is half the price —
  pricing the wrong tier is a quote that disagrees with the invoice.
- **It says nothing about the prompt.** No endpoint here reads a prompt for craft, so a
  weak clone prices, charges and renders exactly like a good one. The checklist in step 6
  is the only thing standing between the two.
- **Price every clip and every variation.** A 3-clip series at 2 variations is 6 charges.
  Show the per-call number, the count, and the total.
- **Warn when the total exceeds `balance`**, and quote `shortBy` and `topUpUrl` when they
  come back. `sufficient` is a snapshot, not a reservation.

Show the number, the count, the total and the balance. Get a yes. Then generate.

### Step 10: Resolve the product and upload the references

1. `GET /v1/products` → `productId`. Default to the product named in `MASTER_CONTEXT.md`
   under "My workspace"; with exactly one product, save it there; with none, omit the field
   — it is optional. There is no folder or project ritual to run: folders are read-only on
   this API and there are no projects at all.

2. Upload each reference **once**:

   ```bash
   curl -sS -X POST https://api.novoads.ai/v1/uploads \
     -H "Authorization: Bearer $NOVOADS_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"contentType":"image/jpeg","sizeBytes":248193}'
   ```

   Returns `assetId`, `uploadUrl`, `method` and `headers`. PUT the raw bytes to `uploadUrl`
   with **exactly** those headers:

   ```bash
   curl -sS -X PUT "$UPLOAD_URL" \
     -H "Content-Type: image/jpeg" \
     -H "Content-Length: 248193" \
     --data-binary @product.jpg
   ```

   Both are signed into the URL: `image/jpeg; charset=utf-8` is a `403`, and so is a
   `Content-Length` that does not match the bytes. Measure `sizeBytes`, do not estimate it.

3. **Keep the `assetId`.** It is durable across calls, models and sessions — the whole
   series, the mini draft and the final render all reuse it. The presigned *upload URL*
   expires in 900 seconds; the id does not.

4. If a reference's longest side is under 1024 px, upscale with Lanczos to 1080 px on the
   long side and re-encode as RGB JPEG at quality 90–95. (No minimum is documented for this
   API; the practice carries over from a sibling API and is unverified here.)

References are **images only** — `image/jpeg`, `image/png`, `image/webp` — even though
`POST /v1/uploads` will also take a video. The source ad itself is never uploaded; it is
input to your eyes, not to the model.

### Step 11: Generate

```bash
curl -sS -X POST https://api.novoads.ai/v1/videos \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "seedance-2.0",
    "prompt": "<the adapted prompt>",
    "durationSeconds": 14,
    "aspectRatio": "9:16",
    "language": "en",
    "referenceAssetIds": ["<product assetId>"],
    "productId": "<uuid>"
  }'
```

`startImageAssetId` instead of `referenceAssetIds` when that is the mode. Never both.

- Returns `202` with `jobId`, `status`, `creditsCharged` and `model`. No `warnings` on any
  response, here or on the estimate.
- **Set `aspectRatio` and `durationSeconds` explicitly.** Seedance defaults to `16:9` and to
  5 seconds, and neither is what a cloned ad wants.
- **Ask how many variations**, default 1. N variations is the identical payload fired N
  times — there is no batch parameter — and N charges.
- **At most five in flight** across the organization, counting every clip and every
  variation. Fire five, then start the next as each reaches a terminal state.
- **Log each submission immediately** — one line appended to `logs/novoads-api.jsonl` with
  the timestamp, endpoint, model, `jobId`, `productId` and the request config: duration,
  aspect ratio, language, reference count, prompt **word count**. Never the prompt text,
  never the key, never a presigned URL. The log is observability, never a pricing source.

### Step 12: Poll, download, hand over

```bash
curl -sS https://api.novoads.ai/v1/generations/$JOB_ID \
  -H "Authorization: Bearer $NOVOADS_API_KEY"
```

- **Poll every 15 seconds until TERMINAL** — `succeeded`, `failed`, `blocked` or `canceled`
  — not until `succeeded`. A loop waiting only for success never returns on a job that
  already died. `queued` means charged and submitted but not yet rendering; it is normal.
- Tell the user the wait up front: `seedance-2.0` is usually **3 to 8 minutes**, most often
  around 5. `seedance-2.0-mini` is **2 to 3**.
- Update each job's log line with the terminal status and elapsed time, carrying `creditsCharged`
  over from the `202` — the poll response does **not** carry it. Never reconstruct it from a rate.

Download through `/watch`, which 302s to a URL signed at request time, so it never hands
you an expired link:

```bash
curl -sSL -o clone-01.mp4 https://api.novoads.ai/v1/generations/$JOB_ID/watch \
  -H "Authorization: Bearer $NOVOADS_API_KEY"
```

While the job is unfinished that endpoint is a `409` naming the current status.

Then:

1. Save under `outputs/<descriptive-subfolder>/` — `outputs/clone-northbrook-balm/`, not the
   job id — and name the files for what they are.
2. **Open the folder** so they can watch immediately: `open "<dir>"` on macOS, `xdg-open` on
   Linux, `explorer` on Windows. Try `open` first and fall back silently.
3. Present variations as a numbered list so they can compare and pick.
4. For a series, present each clip, then offer to stitch with ffmpeg using **absolute
   paths**:

   ```bash
   printf "file '%s'\n" "$(pwd)/clip1.mp4" "$(pwd)/clip2.mp4" "$(pwd)/clip3.mp4" > /tmp/stitch-list.txt
   ffmpeg -y -f concat -safe 0 -i /tmp/stitch-list.txt -c copy stitched-clone.mp4
   ```

   Re-encode if the codecs differ. Hand back both the stitched file and the individual clips.
5. Report the total spend by summing the `creditsCharged` values the API returned — those,
   never a number you calculated from a rate.
6. If a job came back `failed` or `blocked`, say which and quote the `error` it carries.

Next steps worth offering: iterate the one beat that missed rather than re-firing the whole
set, hand the file to the `meta-ad-builder` skill to publish it as a Meta creative, or burn
captions on out of band with `shared/skills/caption-video/prompting/guide.md` — that one
makes no Novoads call and costs no credits.

## Seedance 2.0 constraints that bite during a clone

Full detail in [reference.md](../../reference.md).

| Constraint | What it means here |
|---|---|
| `startImageAssetId` **XOR** `referenceAssetIds` | Separate modes on the model. A body with both is a `400` whose message says exactly that. Nothing is charged |
| `referenceAssetIds` ≤ **9**, images only | Ten is `Too big: expected array to have <=9 items`. A video asset id is refused: references are images |
| No `referenceVideos`, no `referenceAudios`, no `endFrame`, no `projectId` | All `400 Unrecognized key`. Nothing is charged, and no clone workflow can depend on them |
| `resolution` — **`seedance-2.0` only**, `480p` `720p` `1080p` `4k`, default `720p` | Real as of spec 2.6.0 (verified live 2026-08-04). **It multiplies the bill** — `1080p` ≈2.5x the base, `4k` ≈5x, and a series pays it per clip. Price the tier at `POST /v1/estimates`; `480p` saves nothing. `400 Unrecognized key` on `seedance-2.0-mini` and the three non-Seedance models |
| `audioEnabled` — **Seedance only**, optional, default `true` | Send `false` for a silent clone. `400 Unrecognized key` on the three non-Seedance video models, and on `POST /estimates` for every model |
| `durationSeconds` 4–15, integer | Out-of-grid values are rejected, never rounded. Default is **5** |
| `aspectRatio` `16:9` `9:16` `1:1` `4:3` `3:4` `21:9` | Default is **`16:9`**. Set it, or a vertical clone ships landscape |
| Prompt within the model's cap | Enforced on the estimate too, against whichever `model` you name |
| Audio is rendered from the prompt | The spoken line is lip-synced in this same call at no extra cost, which is why gate 1 exists. `audioEnabled: false` mutes the render; it does not give you a separate audio track to direct |
| There are no prompt rules | No endpoint reads a prompt for craft, and none returns advice about one. A weak prompt renders and bills exactly like a strong one |
| Moderation is `422 content_policy` | The only refusal of a prompt for what it says, and the estimate skips it, so a clean quote can still be blocked. **Nothing is charged** |
| Five generations in flight per organization | A sixth is `429` with `details.reason: concurrency_limit`. Wait for a slot; backing off harder does nothing |
| No idempotency keys | Which is why a 500 is never blindly retried — see below |

## Error recovery

Branch on `error.code`, never on the message. Every error is
`{"error":{"code":…,"message":…,"requestId":…,"details":…}}`, and `requestId` is what to
quote when reporting a problem.

| Status / code | What happened | What to do |
|---|---|---|
| `400 invalid_input` | The request is **malformed** — an unknown key, an out-of-grid duration, a prompt over the model's ceiling. `details.issues` names each bad field. Never a judgement on the writing | Fix the field. Nothing was charged. Do not go looking for a prompt rule: none of them can 400 |
| `400` naming the two modes | `startImageAssetId` and `referenceAssetIds` were both sent | Pick one. Start frame to animate a photo, references to composite a scene |
| `401 unauthorized` | Missing, malformed or revoked key | `./scripts/check-novoads-env.sh`, then a new key at <https://novoads.ai/dashboard/settings?tab=api> |
| `402 insufficient_credits` | `details` carries `required` and `available` | Tell the user the gap. Do not retry |
| `403 forbidden` | `details.reason` is `plan_required` or `subscription_inactive` — the key is fine, the plan is not | Say which one it is; they are different fixes |
| `409 conflict` | `/watch` on a job that has not finished | Keep polling |
| `422 content_policy` | Moderation blocked the prompt. Nothing was charged | Rewrite the flagged idea or stop. Do not resend the same payload |
| `429 rate_limited` | Four causes; branch on `details.reason` | `concurrency_limit` → wait for a slot. `key_limit` (60/min) and `organization_limit` (180/min) → honour `Retry-After`. `client_limit` → pre-auth ceiling |
| `500 internal_error` | Possibly charged | **Do not retry blindly.** `GET /v1/generations` first: if the job is there, poll it instead of resubmitting |
| `502 provider_failed` | The model provider failed | Credits are refunded automatically |
| Job `status: failed` or `blocked` | Read the `error` on the job | If it is content-related, rewrite. If it is a provider failure, credits are already refunded |
| The clone looks nothing like the source | The reading was wrong, not the render | Go back to the beat map with the user before spending again. Change **one** element per iteration — framing, or pacing, or the anchor — never three |
| The label came back garbled | Seedance preserves logos and destroys printed text | Say in the prompt that the label stays sharp and unchanged, and check the reference photo actually shows it sharp |
| Source longer than 15s | Not a failure | Split at beat boundaries, generate each clip, offer to stitch |

## Related files

- [analyze-video/SKILL.md](../analyze-video/SKILL.md) — the template-making cousin: same
  analysis, output is a reusable formula instead of a video.
- [analyze-video/scripts/extract-frames.sh](../analyze-video/scripts/extract-frames.sh) —
  frame and audio extraction, shared by both.
- [seedance-2.md](../prompt-library/seedance-2.md) — platform guide: fields, grid, craft,
  what the estimate flags. Read before composing any prompt.
- [seedance-2-ugc.md](../prompt-library/seedance-2-ugc.md) — 9-layer UGC formula, for
  talking-head sources.
- [seedance-2-premium-reveal.md](../prompt-library/seedance-2-premium-reveal.md) — for
  dark-void, product-only sources.
- [seedance-2-product-hero.md](../prompt-library/seedance-2-product-hero.md) — for
  elemental / effects-driven product-only sources.
- [seedance-2-studio-lookbook.md](../prompt-library/seedance-2-studio-lookbook.md) — for
  polished voiceover sources.
- [seedance-2-feature-walkthrough.md](../prompt-library/seedance-2-feature-walkthrough.md) —
  for fast-paced demo sources, and the reference for holding one person across a series.
- [../../SKILL.md](../../SKILL.md) — the router: decision tree, both gates, the full call
  sequence, polling and download.
- [../../reference.md](../../reference.md) — every endpoint, field, limit and error code.
