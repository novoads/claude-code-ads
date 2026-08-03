# Pixar-style AI cartoon ad — prompting guide

**Aesthetic:** Disney-Pixar 3D animated feature film look applied to short-form product ads (TikTok/Reels/Shorts).
**Default pipeline:** **`gpt-image-2`** for storyboard frames → **`seedance-2.0`** + `startImageAssetId` for animation → stitch with ffmpeg.
**Format:** 9:16 vertical, 60–90s total, 4–6 beats stitched from 4–15s Seedance clips, burned-in captions.

Use this guide when the user asks for a "Pixar-style ad," "Pixar cartoon ad," "3D animated ad," or shows a reference video that matches the look.

Every HTTP detail — auth, upload, polling, error codes — comes from the `novoads-api` skill and its `reference.md`, which win whenever this file disagrees. This file owns the craft.

> Sibling guide: [claymation](../../claymation-ad/prompting/guide.md), same pipeline shape.

## What "Pixar style" means here (and what it doesn't)

The look is the **Disney-Pixar feature film aesthetic** specifically — not generic CGI, not Studio Ghibli (that's 2D), not anime, not Dreamworks-stretchy. Anchor every prompt on these traits:

- **3D rendered**, full volumetric lighting, ray-traced reflections
- **Oversized expressive eyes** with multiple specular highlights (the Pixar "wet eye")
- **Stylized but believable proportions** — slightly larger heads, soft features, simplified hands, smooth flowing forms
- **Rich material rendering** — subsurface scattering on skin, detailed fabric weave (waffle robes, knitwear), realistic hair strands, glass/liquid refraction
- **Soft warm golden-hour interior lighting** — sunlight through curtains, window light, lamp glow; almost never harsh top-down or fluorescent
- **Shallow depth of field** with creamy bokeh; subject always sharply rendered
- **"Appeal"** — characters look like they're about to smile, mid-emotion, never blank-staring
- **Anthropomorphism welcome** — objects with faces/limbs/eyes are core to the genre

**Do NOT use these words** (they pull away from the Pixar look):
`anime`, `Ghibli`, `2D`, `cel-shaded`, `cartoon` (yes — say "Pixar-style 3D animated" instead), `Dreamworks`, `realistic photo`, `live action`, `photorealistic`.

Also drop the forbidden words — `cinematic`, `professional`, `stunning`, `8k`, `studio`, `perfect` — and substitute: "3D animated film aesthetic" for cinematic, "polished" for stunning, "high fidelity" for 8k, "ivory white matte material" for perfect. **Nothing on the API rejects them, and nothing reports them.** No endpoint reads a prompt for craft, so a prompt full of them is charged and rendered exactly as written. The reason to strip them is the render, and this checklist is the only place it will be raised.

## The 4-beat Pixar ad arc (what makes these ads work)

Every successful Pixar-style product ad in this genre follows roughly the same structure. The hook is **anthropomorphism + a tiny story**, not the product. Plan all 4 beats upfront so character/setting are consistent across stills.

| Beat | Length | Purpose | What's on screen |
|------|--------|---------|------------------|
| **1. Hook — anthropomorphized problem** | 3–6s | Give the user's pain point a sentient face and voice. The pain point itself is the character. | Close-up macro shot of the problem object given Pixar eyes/mouth (e.g. a clump of hair in a drain, a cracked fingernail, a tired pillow, a moody pile of laundry). It speaks the user's complaint in first person. |
| **2. Reveal — protagonist meets product** | 4–8s | Cut to a Pixar-style human in a sunlit cozy interior, introducing the product. | Big-eyed protagonist (robe, knitwear, soft hair) holding the product, soft window light, plants in background. Surprised/delighted expression. |
| **3. Mechanism-of-action — mascot scene** | 6–10s | Visualize *how* the product works using cute mascot characters inside the body / inside a structure. | Stylized interior (skin layers, hair follicle, joint, gut) with chibi mascot characters actively doing the mechanism — repairing collagen fibers, stitching keratin, plumping cells. Glowing energy lines connect them. |
| **4. CTA — protagonist + packaging** | 4–6s | Resolve the hook by showing the protagonist with the product packaging, captioned CTA. | Protagonist now smiling/confident, holding one or two product packs facing camera. Burned-in caption: "Try {Brand} {Product} now." |

Variations:
- **Cold-open intercut**: alternate Beat 1 (problem character) with quick cuts of the human protagonist looking distressed before settling into Beat 2. Adds urgency.
- **Multi-pain montage**: 3–4 anthropomorphized problem characters in sequence ("I clog your drain", "I weigh down your hair", "I make you self-conscious") before Beat 2.
- **Testimonial overlay**: Beat 2 protagonist speaks the value prop in first person ("I tried this for 30 days and...") instead of a third-person narrator.

## Cast & continuity sheet (do this BEFORE generating anything)

Pixar ads live or die on **character continuity across beats**. Build a one-page sheet you reuse in every `gpt-image-2` prompt:

```
PROTAGONIST (human hero)
- Age range: 20s / 30s / 40s
- Build: petite / average / curvy
- Hair: color, length, style (e.g. "ash-brown low bun with face-framing strands")
- Eyes: color, large Pixar irises, multiple catchlights
- Skin: warm undertone with light freckles across nose bridge
- Outfit: cream waffle-knit robe over fitted tank, gold thin necklace
- Personality cue: gentle smile, slightly tilted head

ANTHROPOMORPHIC PROBLEM CHARACTER (beat 1)
- What object: <e.g. clump of dark hair in shower drain>
- Face placement: <e.g. two big sad eyes and small downturned mouth embedded in the hair>
- Voice/personality: <e.g. defeated, weary, mumbling>

MASCOT CHARACTERS (beat 3)
- Form: chibi blob, 2–3 inches "tall", smooth matte rubbery material
- Color: ivory white with soft pink cheeks
- Eyes: tiny black dot pupils, single highlight, oversized
- Behavior: cooperative team, gently working on the mechanism

SETTING
- Beat 2 & 4: sunlit bedroom or kitchen, sheer curtains, plant in clay pot, soft warm color grade
- Beat 3: stylized cross-section interior of <skin / hair follicle / joint / etc.>

PRODUCT
- Packaging colors / shape / label text (paste from the brand or take from product photo)
- Held at chest height with one or both hands, facing camera

STYLE LOCK (paste verbatim into every image prompt)
"Disney-Pixar 3D animated feature film aesthetic, soft volumetric golden-hour lighting,
subsurface scattering on skin, large expressive eyes with multiple catchlights, stylized
but believable proportions, rich material rendering, shallow depth of field, warm cozy
color palette, painterly background."
```

Save this sheet in `references/<brand>-pixar-cast.md` so the next ad in the same campaign reuses it.

## Pipeline: `gpt-image-2` → `seedance-2.0` → stitch

### Why this order

1. **`gpt-image-2` for storyboard stills** — it produces the most consistent stylized 3D-animated stills of the three image models here, especially when you re-feed prior outputs as `referenceAssetIds` for the next frame in the storyboard. It holds character identity across beats far better than text-only text-to-video. `POST /v1/images` is **synchronous** — the stills come back on the response, there is nothing to poll.
2. **`seedance-2.0` image-to-video** — animates each still while preserving the rendered character. Pass the approved still's `assetId` as **`startImageAssetId`** and it becomes the clip's first frame; a text prompt drives 4–15s of motion from there. `POST /v1/videos` is **async** — it returns a `jobId` you poll.
3. **ffmpeg concat** — stitch the per-beat clips into one continuous 60–90s vertical video and (optionally) burn in TikTok-style captions.

**`startImageAssetId` and `referenceAssetIds` are two different modes and sending both is a 400**, not a merge. This pipeline uses `startImageAssetId` on the video calls (one still → one clip) and `referenceAssetIds` on the *image* calls (prior stills → continuity). See the `novoads-api` skill's `reference.md` for the full modes table.

### One-shot text-to-video is the wrong choice

Don't try to one-prompt the whole ad in Seedance 2.0. You'll get character drift between beats, and Seedance's 15s ceiling caps you below the typical 60–90s ad length anyway. The image-first pipeline is mandatory for this style.

### Step-by-step

1. **Lock the cast sheet** with the user (above). Confirm protagonist appearance, packaging, brand voice.
2. **Write the 4–6 beat script** as plain English narration with timestamps. One sentence per beat. Get user approval before any generation.
3. **Generate Beat 1 hero still** with `gpt-image-2` using the storyboard formula in [storyboard-gpt-image-2.md](storyboard-gpt-image-2.md). Show user. Iterate until approved.
4. **Generate Beats 2–N hero stills** one at a time, passing the prior approved still(s) as `referenceAssetIds` to lock continuity — **up to 4 per call**, images only. Approve each before moving on.
5. **Animate each still with `seedance-2.0`** using the formula in [animate-seedance-2.md](animate-seedance-2.md). Set `durationSeconds` explicitly to match the beat target (4–15s) — Seedance defaults to 5. Run beats concurrently, but **at most 4 in flight**: the API allows 5 concurrent generations per organization and leaving a slot free keeps a QA retry from queueing behind the batch.
6. **QA each clip** — watch for character morphing, hand artifacts, product-label drift, eye misalignment. Regenerate up to 2 retries per beat; each retry is billed, so report the extra credits at the end. After the cap, stop and show the best attempt.
7. **Stitch with ffmpeg** — `ffmpeg -f concat -safe 0 -i list.txt -c copy ad.mp4` (re-encode with `-c:v libx264 -c:a aac` if codecs differ).
8. **Burn captions** (optional) — TikTok-style: white sans-serif (Montserrat/Proxima Bold), thick black stroke, mid-low third placement. Use `ffmpeg drawtext` or pre-export an `.ass` subtitle file and burn with `-vf subtitles=`.

### Aspect ratio defaults

- **Aspect ratio:** `9:16` (vertical) for TikTok / Reels / Shorts, on both the stills and the clips. Use `1:1` only if the user explicitly wants a feed post. Avoid `16:9` for this genre — the framing assumptions in the prompts (close-up macros, head-and-shoulders human shots) don't translate. **Set it explicitly on every video call: Seedance defaults to `16:9`,** which is a wasted render for this format. `gpt-image-2` defaults to `1:1` and also needs it stated.
- **`9:16` is on both grids** — `gpt-image-2` accepts `1:1 4:5 2:3 9:16 16:9 21:9`, Seedance accepts `16:9 9:16 1:1 4:3 3:4 21:9`. The still and the clip can therefore share a ratio, which is what keeps the start frame from being letterboxed.
- **There is no `resolution` field**, and no 480p draft tier to trade quality for cost — the spec publishes no output size at all, and Seedance measured 720x1280 at `9:16` (2026-08-02). The cheap-draft lever is the **model**: `seedance-2.0-mini` is half the price of `seedance-2.0` on the same grid. Prototype the beat timing on mini, finalize on `seedance-2.0`.
- Upload the still with `POST /v1/uploads`, PUT the bytes, then pass the returned `assetId`. The upload URL expires in 900s; **the `assetId` does not expire and is reusable without limit.**

## Audio pipeline — ElevenLabs VO, no in-prompt narrator

**Hard rule (cross-skill):** generate voiceover externally via ElevenLabs and overlay in post — never use Seedance's in-prompt `Narrator:` line. See [claymation guide § Audio pipeline](../../claymation-ad/prompting/guide.md#audio-pipeline-do-this-not-in-prompt-narrator) — the same flow applies to Pixar ads. Same ElevenLabs voice across all beats, same Whisper→HyperFrames caption pipeline.

**Render the beats silent: send `"audioEnabled": false`.** The field is live on `seedance-2.0` and `seedance-2.0-mini` and defaults to `true`, so a call that omits it generates speech and sound effects that final assembly then replaces with the ElevenLabs track — paid for, discarded. `scripts/generate-seedance.sh` already sends `false` and only for the Seedance variants (the other video models are strict and would `400`); override with `AUDIO_ENABLED=true` for a beat that genuinely wants Seedance's own audio. It does not change the price, which is why `POST /v1/estimates` refuses the field. Keep the no-`Narrator:` discipline in the prompt regardless — the flag mutes the render, the prompt is what stops the model staging a talking shot.

### ⚠️ No dead space — VO drives clip duration

**The voiceover must fill the full duration of the clip it plays over.** Dead space — clip footage continuing after the VO ends, or starting noticeably before the VO begins — kills retention on TikTok/Reels/Shorts. Viewers swipe on the first half-second of silence.

Seedance default beats (4–10s) almost always exceed the ElevenLabs line that plays over them. **Measure both, then reconcile per beat:**

| Option | When | How |
|--------|------|-----|
| **A. Trim the clip to fit the VO** (default) | VO is shorter than clip. Most beats. | Re-encode video to `vo_dur + 0.5s` (0.25s lead + 0.25s tail). |
| **B. Extend the VO to fill the clip** | Visual has a long camera move, mascot mechanism, or CTA hold that needs the full time to land. | Add 1–2 more words or a second short line. Re-render ElevenLabs MP3 and re-measure. |

```bash
VO_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 vo/beatN.mp3)
CLIP_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 clips/beatN.mp4)
TARGET=$(python3 -c "print(min($CLIP_DUR, $VO_DUR + 0.50))")
ffmpeg -y -i clips/beatN.mp4 -t $TARGET -c:v libx264 -preset slow -crf 18 \
  -pix_fmt yuv420p -c:a copy tight/beatN.mp4
```

**Hard subrules:**
- Allowed micro-buffer: ~0.25s lead, ~0.25s tail. Anything beyond that is dead air — pick A or B.
- If VO is *longer* than the clip, never use `atempo` to speed it up. Split the line across two beats, or regenerate Seedance at a longer duration.
- **Always re-transcribe + rebuild captions against the trimmed master mp4** — Whisper timestamps shift after trimming.
- Verify caption Y position after trimming — the final frame at the cut may have different foreground content than the original last frame.

This rule applies cross-skill — claymation, Pixar, UGC, any video-ad pipeline that pairs generated video with TTS VO.

## Cost & confirmation (mandatory)

**Never state a credit cost from memory.** There are no rate tables in this repo, and the logs are observability, not a price source. Every number shown to the user comes from a live `POST /v1/estimates` in the current session. The call is free.

A Pixar ad is the most expensive shape this repo produces — a 5-beat ad is 10+ billed generations before retries — so price the **whole run** before firing the first call, not beat by beat:

- **5× stills.** One estimate with `kind: "image"`, `model: "gpt-image-2"`, and the assembled Beat-1 prompt. The estimate takes `numImages`, so if you are generating variations of a beat, price them in that one call.
- **5× clips.** One estimate per distinct `durationSeconds`, with `kind: "video"` and the model the user picked. Duration drives the video price, so an 8s beat and a 15s beat are different quotes — do not extrapolate one from the other.
- **Retries.** The QA cap is 2 per beat and each retry is billed. Say so when you present the total: the quoted number is the floor, not the ceiling.

Pass `model` explicitly on every estimate. It defaults to `seedance-2.0` for video and `gpt-image-2` for images, the video schedules differ 2× across the set and the image schedules by more than 3×, and the estimate enforces the *named* model's prompt ceiling. Pricing the wrong model is a quote that disagrees with the invoice.

The same response carries `balance`. **If the run total exceeds it, say so before asking for a yes** and quote `shortBy` and `topUpUrl` when the estimate returns them. `sufficient` is a snapshot, not a reservation.

Show the per-call number, the count, the total, and the balance. Get an explicit yes. Then fire.

**Wall-clock, so the user knows what they are waiting for:** `seedance-2.0` renders in 3–8 minutes (median ~5), `seedance-2.0-mini` in 2–3. A 5-beat ad run at 4 concurrent is roughly two render waves. Images are synchronous and return in well under a minute.

## Negative prompt block (paste into every video prompt)

```
no live-action footage, no photorealistic faces, no anime style, no 2D cel-shaded
look, no Studio Ghibli style, no flat illustration, no harsh fluorescent lighting,
no extra fingers, no melted features, no morphing between frames, no warped product
labels, no on-screen text unless specified, no subtitles, no captions
```

Strip the forbidden words as described above. Nothing rejects them and nothing reports them — the substitutions are there because they render better, and this file is the only place you will be reminded.

## Captioning (the TikTok burned-in look)

If the user wants the white-text-with-black-outline TikTok caption style:

- **Font:** Proxima Nova Bold, Montserrat Bold, or system Inter Bold (use a license you own). Avoid Arial — looks dated.
- **Size:** ~7% of video height
- **Position:** lower third, centered horizontally, ~25% from the bottom (above the TikTok UI overlay)
- **Style:** white fill, 4–6 px solid black stroke, no drop shadow
- **Timing:** caption changes per spoken phrase, not per word. Display for the duration of the phrase + 0.3s buffer.
- **Burn pipeline:** write the captions to an `.ass` (Advanced SubStation) file with timing, then `ffmpeg -i clip.mp4 -vf "subtitles=caps.ass" out.mp4`. This is more reliable than `drawtext` for multi-line timing.

**Important — let Seedance render the scene WITHOUT captions.** Tell Seedance "no on-screen text, no captions, no subtitles" in every prompt. Burn captions on after stitching, with control. Seedance occasionally invents captions when you don't ask for them — the negative prompt fights this.

### Recommended pipeline: animated captions via the `caption-video` skill

For per-phrase emphasis (scale-pop on punchlines, brand-color callouts on the product reveal), hand the stitched MP4 to the **`caption-video`** skill rather than burning static `.ass` subtitles. It carries the full HyperFrames + Whisper + chroma-key recipe: Whisper model choice by audio type, the word-grouping helper, the composition, and the ffmpeg composite. Do not re-derive it here.

Two things to carry across the hand-off:

- **Pixar caption styling:** bold scale-pop on punchlines, bright cream/pink palette, social/hype tone. Tag groups by emphasis (`normal` / `comedic` / `brand` / `product`).
- **Trim first, caption second.** Whisper timestamps taken from a master with dead space drift once you tighten it. Apply the [no-dead-space rule](#-no-dead-space--vo-drives-clip-duration) below to every beat, re-concat, and only then transcribe.

The one trap worth repeating because it costs a whole render to discover: **never put the source `<video>` (or `<audio>`) element inside the HyperFrames composition.** The runtime wraps timed elements and injects its own positioning, which overrides your CSS and reserves a layout block that shows up as a black bar across the bottom of a portrait render. Captions render over a keyable background and the source video is composited underneath in ffmpeg — `caption-video` has the exact filter chain.

## Endpoint notes

One API, no chooser. The storyboard and animation files in this folder are the source of truth for prompt content; the call mechanics are below, and the `novoads-api` skill's `reference.md` is the authority whenever the two disagree.

| Step | Call | Model | Images in |
|------|------|-------|-----------|
| Upload a still or product photo | `POST /v1/uploads` → PUT the bytes to `uploadUrl` | — | returns a durable `assetId` |
| Storyboard | `POST /v1/images` — **synchronous** | `gpt-image-2` | `referenceAssetIds: [assetId, …]`, **max 4**, images only, addressed in the prompt as `@Image1`…`@Image4` |
| Animation | `POST /v1/videos` — **async, returns `jobId`** | `seedance-2.0` (or `seedance-2.0-mini` for drafts) | `startImageAssetId: assetId` — the approved still becomes the first frame |
| Polling | `GET /v1/generations/{jobId}` every 15s until **terminal** (`succeeded`/`failed`/`blocked`/`canceled`) | — | — |
| Download | `GET /v1/generations/{jobId}/watch` → 302 to the file | — | — |
| Auth | `Authorization: Bearer $NOVOADS_API_KEY` on every call | — | — |

Poll at **15s**, not 5s: 5s across 5 concurrent jobs is 60 calls/min, exactly the per-key rate limit with zero headroom.

### Two inversions of the habits this pipeline used to carry

**1. The `assetId` is durable — re-uploading is the bug.**
A previous version of this guide said the uploaded reference was one-time-use and had to be re-uploaded for every call that referenced it. **That is backwards here.** The `assetId` is the storage key itself; nothing consumes it, and the same id works on call one and call one hundred, from `startImageAssetId`, from `referenceAssetIds`, and from the MCP tools. Upload the hero still **once** and pass the same id into Beats 2, 3 and 4.

Re-uploading is not merely wasted work — it is actively worse. A fresh id is a fresh asset, and chaining continuity through a new id each time is how you lose the identity anchor the storyboard exists to hold. The **900-second expiry belongs to the `uploadUrl`, not to the asset.**

**2. There is one polling path.**
Every video job, on every model, is `GET /v1/generations/{jobId}`. There is no per-model routing to work out from a `type` field on the create response, and no separate assets endpoint. Poll for a **terminal** status rather than for `succeeded` — `failed`, `blocked` and `canceled` are also final, and waiting for `succeeded` on a blocked job polls forever.

### Concurrency, retries, and the one error that matters here

- **5 concurrent generations per organization.** A 5-beat ad exceeds that if you fire everything at once, so cap at 4 in flight and let the 5th slot absorb a QA retry.
- A `429` has four causes and they are told apart by `error.details.reason`: `key_limit` (60/min), `organization_limit`, `client_limit`, and `concurrency_limit`. Only the first three are fixed by slowing down. **`concurrency_limit` is fixed by waiting** for a running job to finish — backing off the request rate does nothing for it. Honor `Retry-After` when present.
- **Never blind-retry a 500 on a generation call.** There are no idempotency keys, so a retry can double-charge. Check `GET /v1/generations` for a job matching what you just submitted before resubmitting.
- A `400` means the body was malformed. A `422` is moderation, and it is now the only thing that refuses a prompt for what it says — prompt-quality rules do not block anything.

## Supporting files

- [storyboard-gpt-image-2.md](storyboard-gpt-image-2.md) — `gpt-image-2` prompt formulas for each of the 4 beats
- [animate-seedance-2.md](animate-seedance-2.md) — `seedance-2.0` image-to-video formulas, per-beat
- [../scripts/README.md](../scripts/README.md) — end-to-end shell + Python pipeline (storyboard → Seedance → VO → music → captions → final mix); reusable across campaigns
- The `novoads-api` skill — auth, upload, estimates, polling, download, error codes
- The `caption-video` skill — the captions pass on the stitched master

## Trigger phrases (for skill activation)

- "make a Pixar-style ad"
- "Pixar cartoon ad for {product}"
- "3D animated ad like {reference}"
- "animated ad with the [object] character"
- "Pixar-style storyboard for an ad"
