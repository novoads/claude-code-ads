# Claymation AI cartoon ad — prompting guide

**Aesthetic:** Aardman / Laika stop-motion claymation feature film look applied to short-form product ads (TikTok/Reels/Shorts).
**Default pipeline:** **`gpt-image-2`** for storyboard frames (or **`nano-banana-pro`** when clay texture detail matters more than identity continuity) → **`seedance-2.0`** + `startImageAssetId` for animation → stitch with ffmpeg.
**Format:** 9:16 vertical, **60–115s total**, 8–12 beats stitched from 6–12s Seedance clips, narrator voiceover, burned-in captions.

Use this guide when the user asks for a "claymation ad," "Aardman-style ad," or "stop-motion ad," or shows a reference video that matches the look.

Every HTTP detail — auth, upload, polling, error codes — comes from the `novoads-api` skill and its `reference.md`, which win whenever this file disagrees. This file owns the craft.

Sibling: [Pixar-style ad](../../pixar-style-ad/prompting/guide.md), same pipeline shape.

## What "claymation" means here (and what it doesn't)

This look anchors on **Aardman Animations** (Wallace & Gromit, Chicken Run) and **Laika** (Coraline, Kubo) lineage — hand-sculpted clay/plasticine, visible tool marks, slightly imperfect armatures, miniature physical sets. Not generic CGI cartoon.

Anchor every prompt on these traits:

- **Hand-sculpted clay/plasticine surfaces** — visible fingerprint impressions, sculpting-tool marks, slight asymmetry, subtle pinch lines around facial features
- **Matte clay material** — no Pixar wet-eye sheen, no glossy refraction; clay reads as opaque, slightly waxy, with soft micro-bumps
- **Exaggerated, character-driven faces** — oversized noses, deep wrinkles when called for, asymmetric eye placement, painted-on or sculpted eyebrows; characters can be quirky/grotesque rather than appealing
- **Real-looking knit/felt fabric** — chunky wool sweaters, knit cardigans, felt curtains — separately constructed and stitched, not painted-on
- **Wooden and ceramic props** — Aardman miniature-set vibe: real-wood tables, hand-thrown ceramic mugs, tin kettles, fabric tablecloths
- **Warm tungsten interior lighting** for domestic scenes; cool fluorescent for office/dystopian scenes
- **Shallow depth of field** with creamy bokeh; soft macro-photography feel that reinforces the miniature-set illusion
- **Subtle imperfection everywhere** — slightly uneven paint on labels, fabric weave irregular, clay surfaces never perfectly smooth

**Do NOT use these words** (they pull away from the claymation look):
`Pixar`, `3D rendered`, `digital`, `CGI`, `anime`, `cel-shaded`, `2D`, `painted illustration`, `realistic photo`, `live action`, `photorealistic`, `smooth render`, `subsurface scattering`, `ray-traced`.

Also drop the forbidden words — `cinematic`, `professional`, `stunning`, `8k`, `studio`, `perfect` — and substitute "stop-motion claymation film aesthetic", "polished hand-sculpted", "high fidelity", "evenly hand-painted". **Nothing on the API rejects them, and nothing reports them.** No endpoint reads a prompt for craft, so a prompt full of them is charged and rendered exactly as written. The reason to strip them is the render — and on this route especially, since every one of those words pulls toward the smooth digital finish the whole aesthetic is fighting.

## Smooth motion vs stop-motion judder — pick one

Real stop-motion has ~12–15 fps judder. AI video generators output smooth 24/30 fps. The reference ads in this genre are **all smooth** — the AI keeps the visual aesthetic but plays motion smoothly. That's the default.

If the user explicitly wants the **stop-motion judder feel**, add a post step: re-encode with `ffmpeg -filter:v "fps=12,fps=24"` (drops to 12 fps, then duplicates frames back to 24) — produces visible judder. Don't bake this into the Seedance prompt; Seedance can't reliably control framerate, and asking for "stop-motion judder" tends to break the aesthetic.

## The claymation story arc (8 beats — longer-form than Pixar)

Claymation ads in this genre are **narrative**: a quirky third-person narrator tells a story about a character. The protagonist drives the entire arc; there is no "anthropomorphized problem character" beat like in Pixar. Plan all 8 beats up front so character and miniature set stay consistent.

| Beat | Length | Purpose | What's on screen |
|------|--------|---------|------------------|
| **1. Setup** | 6–10s | Introduce the protagonist in their everyday world. | Wide or medium shot of the protagonist in their domestic miniature set (kitchen, bedroom, bathroom). Narrator says their name and a single defining trait. |
| **2. Inciting moment** | 6–8s | The protagonist notices the problem. | Close-up of the protagonist's face as they spot the issue (lines in a mirror, weight on a scale, a sound). Surprised or concerned expression. |
| **3. Social validation** | 6–10s | Someone else acknowledges the problem (often unintentionally). | Two-character scene: protagonist with a friend/spouse/coworker in a cafe / living room / office. A small exchange or remark. |
| **4. Quiet despair** | 5–8s | Solo reflection beat. | Protagonist alone at a window, mirror, or sink, looking at their reflection. No dialogue — narrator carries it. |
| **5. Clay infographic / "research"** | 6–10s | Explain the mechanism using a clay-rendered chart or diagram. | A hand-sculpted clay infographic on a wall or tablet (e.g. "Calcium in skin" chart with clay letters and a plasticine line graph). Static or with a small animated indicator. **Optional** — drop this beat if the product doesn't need explanation. |
| **6. Discovery** | 6–8s | The protagonist finds the product. | Close-up to medium shot of the product (rendered as a slightly imperfect clay-shaded prop) sitting on a wooden table, bathroom shelf, or windowsill. Protagonist reaches for it. |
| **7. Transformation** | 8–12s | Time passes, protagonist uses the product, change is visible. | Montage: applying / taking the product, then a "weeks later" reveal — clay protagonist with subtle visual improvement (smoother skin / brighter eyes / better posture). |
| **8. Resolution + CTA** | 6–8s | Confident protagonist with the product, captioned CTA. | Protagonist holds the product, smiling at camera or at another character. Lower third clean for burned-in CTA caption. |

**Total:** ~50–75s of clip duration; add 5–10s of breath/cuts in editing. If the user wants the shorter format, drop beats 3, 4, and 5 — the **5-beat short** (Setup → Inciting → Discovery → Transformation → CTA) lands around 35–45s.

**Variations by category:**

- **Health/supplement (refirm, ashwagandha, GLP-1)** — full 8-beat works well; the chart beat sells the mechanism.
- **Beauty/skincare** — emphasize beats 2 (mirror) and 4 (self-reflection); chart beat optional.
- **Office / B2B (Lion's Mane–style)** — protagonist is in a fluorescent-lit office (the canonical frame is a bald, exhausted office worker); cool-light palette for beats 1–4, warm only after the discovery/transformation.
- **Food / kitchen products** — beats 1, 6, 7 dominate; social beat (3) becomes a family dinner.

## Cast & continuity sheet (do this BEFORE generating anything)

Claymation ads usually feature **two or three named characters**. Lock all of them up front. Save the sheet to `references/<brand>-claymation-cast.md`.

```
PROTAGONIST
- Name (used by narrator): <e.g. Diane>
- Age range: <30s/40s/50s/60s — claymation favors middle-aged and older characters>
- Distinctive feature: <e.g. shoulder-length terracotta-brown wavy hair, deep laugh lines, hooded eyelids>
- Build: <average / petite / sturdy>
- Eye color: <e.g. warm brown, sculpted lower lids visible>
- Outfit: <e.g. cream chunky knit cardigan over rust-red blouse, dark wool trousers, brown leather slippers>
- Posture cue: <e.g. slight forward lean, soft rounded shoulders>

SUPPORTING CHARACTER (beat 3)
- Relationship: <best friend / spouse / coworker>
- Distinctive feature: <e.g. silver curly hair, round wire glasses, sage-green cable-knit sweater>
- Age range: <similar or older than protagonist>

NARRATOR (voiceover, not visible)
- Voice persona: <warm storytelling, slight British inflection, mid-pace> OR <wry midwestern, dry humor>
- Tone: <gentle observational / wry / matter-of-fact>

SETTING — primary location
- Domestic: <e.g. small sunlit kitchen with green-painted cabinets, red gingham tablecloth, wooden table, copper kettle on stove, potted herbs on windowsill>
- Reuse this setting for beats 1, 6, 8 to anchor continuity

SETTING — secondary location (beat 3)
- <e.g. neighborhood cafe with potted plants, wooden tables, hanging brass pendant lights>

PRODUCT
- Render as a clay-stylized prop: matte-painted label, slightly imperfect cylinder/jar shape, paint that looks hand-applied
- Copy exact label text from the brand reference
- Position: on the wooden table / bathroom shelf / kitchen counter

STYLE LOCK (paste verbatim into every image prompt)
"Aardman-style stop-motion claymation aesthetic. Hand-sculpted plasticine
characters with visible fingerprint impressions and sculpting-tool marks,
matte clay surfaces, slightly asymmetric features. Real knit-fabric clothing
with visible weave, wooden and ceramic miniature-set props. Warm tungsten
interior lighting, shallow macro depth of field, soft photographic bokeh.
Subtle imperfection in every surface. 9:16 vertical."
```

## Pipeline: `gpt-image-2` → `seedance-2.0` → stitch

### Why `gpt-image-2` (with a `nano-banana-pro` fallback)

1. **Identity continuity across 8 beats** — `gpt-image-2` holds the same sculpted character face when you re-feed prior frames as references. Critical for "Diane" appearing in beats 1, 2, 3, 4, 6, 7, 8.
2. **Strong stylized stop-motion output** — `gpt-image-2` renders clay textures cleanly when the STYLE LOCK is verbatim.
3. **Fallback to `nano-banana-pro`** — if the user reports that `gpt-image-2` is smoothing out the clay texture or losing fingerprint detail on close-ups, switch to Nano Banana Pro for those specific beats. Trade-off: Nano Banana Pro is slightly weaker on cross-beat identity, so use it only for product close-ups (beat 6) and infographic beats (beat 5) where character identity doesn't matter.

### Why Seedance 2.0 image-to-video

Same reasoning as Pixar — animates each approved still while preserving the rendered clay aesthetic. Seedance 2's 4–15s ceiling is per-clip; 8 beats × ~8s avg = ~64s of final ad after stitching.

### Step-by-step

1. **Lock the cast sheet** with the user. Confirm protagonist, supporting character, narrator voice, primary + secondary settings, product packaging.
2. **Write the 8-beat narrator script** as plain English. One narrator sentence per beat plus any spoken dialogue. Get user approval before any generation.
3. **Generate Beat 1 hero still** with `gpt-image-2` using [storyboard-gpt-image-2.md](storyboard-gpt-image-2.md). Show user, iterate.
4. **Generate Beats 2, 4, 6, 7, 8 (protagonist beats) sequentially**, passing the prior approved protagonist still as a reference. Approve each one.
5. **Generate Beat 3 (two-character scene)** with both the approved protagonist still and the supporting character description.
6. **Generate Beat 5 (clay infographic)** independently — no character continuity needed.
7. **Animate each still with `seedance-2.0`** using [animate-seedance-2.md](animate-seedance-2.md). Set `durationSeconds` explicitly per beat. Run beats concurrently, **at most 4 in flight** — the organization ceiling is 5 concurrent generations and the spare slot is what lets a QA retry start without queueing behind the batch.
8. **QA each clip** — claymation-specific: watch for clay texture flattening into 3D-rendered smoothness, fabric losing knit weave, label paint becoming digitally crisp. Up to 2 retries per beat; each retry is billed, so report the extra credits at the end.
9. **Stitch with ffmpeg.** Optional: re-encode with `fps=12,fps=24` filter chain for stop-motion judder if requested.
10. **Burn captions** — hand the stitched master to the `caption-video` skill. Use the same TikTok caption style as the Pixar guide, or the "orange highlight block" variant (white text on a solid orange rounded rectangle, slight tilt) that suits the clay palette.

### Aspect ratio defaults

- **Aspect ratio:** `9:16` for TikTok/Reels/Shorts, on both stills and clips. **Send it explicitly on every call** — Seedance defaults to `16:9` and `gpt-image-2` to `1:1`. Both models have `9:16` on their grid, which is what keeps the start frame from being letterboxed into the clip.
- **`seedance-2.0` does have a `resolution` field** — `480p`, `720p`, `1080p`, `4k`, default `720p` (verified live 2026-08-04; the older note here denying the field described a previous deployment). **But it is not a way to make drafts cheaper: `480p` costs exactly the same as `720p`.** Going the other way costs real money — `1080p` is ≈2.5x the base and `4k` ≈5x, which on an 8–12 beat ad is multiplied by every beat. Treat anything above `720p` as a spend decision, price it with `POST /v1/estimates`, and never quote a credit number from those ratios.
- **The cheap-draft lever is the model, not the resolution** — `seedance-2.0-mini` is half price on the same duration grid (and renders 720p only; never send it a `resolution` key). An 8–12 beat claymation ad is the longest pipeline in this repo, so blocking out beat timing on mini before committing is worth real money here.
- **`nano-banana-pro` has the wider ratio grid** (it adds `3:2 3:4 4:3 5:4` over `gpt-image-2`'s `1:1 4:5 2:3 9:16 16:9 21:9`). At 9:16 the choice between them is about texture versus identity continuity, not about ratios.

## Narration & dialogue

**Hard rule (confirmed 2026-05-19): Always generate the voiceover externally via ElevenLabs and overlay in post — never use Seedance's in-prompt `Narrator:` line for claymation ads.** The claymation visual is the storytelling vehicle; baking VO into Seedance forces character/lip-sync compromises, produces inconsistent voice quality across beats, and locks pacing to the video model's delivery. ElevenLabs gives one consistent voice across all 7–8 beats, predictable per-line durations, and a clean MP3 to run Whisper against for the caption track.

### Audio pipeline (do this, not in-prompt narrator)

1. **Seedance call — send `"audioEnabled": false`, and still omit the `Narrator:` line.** The field exists on `seedance-2.0` and `seedance-2.0-mini` (default `true`) and renders the clip silent. That is what this pipeline wants: step 4 muxes the ElevenLabs VO in and **replaces the clip's audio outright**, so any speech or SFX Seedance generates is paid for and then discarded. It costs the same either way — `audioEnabled` does not move the price, which is why `POST /v1/estimates` refuses the field — but a silent render cannot surprise you with an invented narrator, which is the failure the old `-an` advice was cleaning up after.

   **Keep the `Narrator:` line out anyway, and keep the ambient SFX language in.** Belt and suspenders: the flag mutes the render, while the absence of a narrator line stops the model *staging* a talking shot, and the SFX words still steer the action ("hose hiss" implies a hose actually running) even though they no longer produce a track. If a beat genuinely needs Seedance's own audio, set `audioEnabled: true` for that call and mix it yourself.

   **The trim step below is unaffected.** `-c:a copy` on a silent input is a no-op, not an error — verified, exit 0, video-only output.
2. **ElevenLabs TTS per beat** — one MP3 per beat using a single consistent `voice_id` across the whole ad. POST `https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`, header `xi-api-key: $ELEVENLABS_API_KEY`, body `{"text": "...", "model_id": "eleven_multilingual_v2", "voice_settings": {"stability": 0.45, "similarity_boost": 0.75, "style": 0.35, "use_speaker_boost": true}}`.
3. **Trim each clip to match its VO duration — no dead space.** See "No dead space" rule below. After ElevenLabs returns the MP3, `ffprobe` its duration and trim the matching clip to `lead (0.25s) + vo_dur + tail (0.25s)` before muxing. Don't let the clip ride silent after the VO ends.
4. **Pad each VO mp3** with the 0.25s lead-in and tiny trailing buffer so the audio aligns inside the trimmed clip, then mux (`-c:v copy` on the trimmed video, `-c:a copy` on the padded VO).
5. **Concat the trimmed voiced clips** into the master ad with ffmpeg `-f concat`.
6. **Whisper-transcribe the master VO** (model `medium.en` — required for music-mixed audio; see [caption-video guide](../../caption-video/prompting/guide.md)) and build the HyperFrames captions composition from word-level timestamps. **Always re-transcribe after trimming** — timestamps shift.

### ⚠️ No dead space — VO drives clip duration

**Hard rule:** the voiceover must fill the full duration of the clip it plays over. Dead space — clip footage continuing after the VO ends, or starting noticeably before the VO begins — kills retention on TikTok/Reels/Shorts. Viewers swipe on the first half-second of silence.

The Seedance default duration (~6–10s) is almost always longer than the ElevenLabs line that plays over it. **Measure both, then reconcile.**

```bash
VO_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 vo/beatN.mp3)
CLIP_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 clips/beatN.mp4)
TARGET=$(python3 -c "print(min($CLIP_DUR, $VO_DUR + 0.50))")  # lead 0.25 + tail 0.25

# Re-encode-trim the clip (not stream copy — re-encode for a clean cut at the exact target)
ffmpeg -y -i clips/beatN.mp4 -t $TARGET -c:v libx264 -preset slow -crf 18 \
  -pix_fmt yuv420p -c:a copy tight/beatN.mp4
```

**Allowed micro-buffer:** ~0.25s lead-in before VO starts (so the cut doesn't feel jammed) and ~0.25s tail after VO ends (so the cut breath sits before the next beat). Anything beyond that should be filled with more VO content or trimmed out.

**Per-beat: pick one of two options.**

| Option | When | How |
|--------|------|-----|
| **A. Trim the clip to fit the VO** (default) | VO is shorter than clip. Most beats. | Re-encode video to `vo_dur + 0.5s`. Saves runtime, tightens retention. |
| **B. Extend the VO to fill the clip** | Visual has motion that needs the full time to land (camera move, transformation montage, CTA hold). | Add 1–2 more words or a second short line. Re-render ElevenLabs MP3 and re-measure. |

**Never just let the clip ride in silence.** A 6s clip with a 3.5s VO has 2.5s of dead air — pick A or B.

**Hard subrules:**
- If the VO is *longer* than the clip, **never use `atempo` to speed up the VO** — sounds artificial. Instead either split the line across two beats, or re-generate the Seedance clip at a longer duration.
- Caption track must be rebuilt against the *final* trimmed master mp4. Whisper timestamps shift after trimming.
- Re-verify the lower-third caption Y position after trimming — if the trimmed clip ends on a different visual frame than the original, the caption may collide with a foreground element.

### Voice direction baseline

- Warm storytelling cadence, slight pause between sentences
- Mid-pace — never rushed
- Slight smile in the voice
- References to character by name when narrative ("Diane noticed…")
- For UGC feature-demo ads (vs narrative arc): wry midwestern UGC tone, energetic young american creator

**ElevenLabs voice picks that match these tones** (verify with `GET /v1/voices`):

| Use case | Voice | voice_id |
|----------|-------|----------|
| Warm narrative storytelling (Aardman tone) | George — Warm, Captivating Storyteller (british middle-aged male) | `JBFqnCBsd6RMkjVDRZzb` |
| UGC feature demo (TikTok energy, young female) | Hope — Upbeat and Clear | `tnSpp4vdxKPjI9w0GnoV` |
| Wry midwestern narration | Chris — Charming, Down-to-Earth | `iP95p4xoKVk53GoZ742B` |

Always pick **one** voice for the whole ad — don't mix narrator voices across beats.

### Character dialogue

- Sparse — one short line per character
- Casual, natural — no marketing copy
- Often the supporting character makes the observation: *"You look different — what is that?"*
- Generate character dialogue lines as **separate ElevenLabs renders** with their own `voice_id`, then composite at the right beat timestamp alongside the narrator track.

### Auto-select per-beat duration based on VO line length (~2.5 words/sec, plus 0.5s lead-in + 1.5–2.5s trail)

| Narrator words | ElevenLabs duration | Beat clip duration |
|----------------|---------------------|---------------------|
| 1–10 | ~2–3s | 6s |
| 11–17 | ~4–5s | 6s |
| 18–25 | ~6–7s | 8s |
| 26–32 | ~8–9s | 10s |
| 33+ | Split across beats | — |

Always measure actual ElevenLabs MP3 duration with `ffprobe` before muxing — TTS pace varies per voice and per `stability`/`style` setting.

## Cost & confirmation (mandatory)

**Never state a credit cost from memory.** There are no rate tables in this repo, and `logs/novoads-api.jsonl` is observability, not a price source. Every number shown to the user comes from a live `POST /v1/estimates` in the current session. That call is free.

This is the most expensive pipeline in the repo — an 8-beat ad is 16 billed generations before a single retry, and the worst case at the 2-retry cap is 24 image calls plus 24 video calls. **Price the whole run before firing the first call:**

- **8× stills.** Estimate with `kind: "image"` and `model: "gpt-image-2"` (or `nano-banana-pro` — the image schedules differ by more than 3×, so naming the wrong one understates the run badly). Generated sequentially, for identity continuity.
- **8× clips**, mostly 6–10s → ~64s of final video. Estimate with `kind: "video"`, the chosen model, and **each distinct `durationSeconds`** — duration is what drives the video price, so a 6s beat and a 12s beat are different quotes.
- **Retries.** Say out loud that the quoted total is the floor and the cap is 2 per beat.

The same response carries `balance`. **If the run total exceeds it, say so before asking for a yes**, and quote `shortBy` and `topUpUrl` when the estimate returns them. `sufficient` is a snapshot, not a reservation — another session or a renewal can move the balance between the quote and the call.

Show the per-call number, the count, the total, and the balance. Wait for an explicit yes. Then fire.

**Wall clock:** `seedance-2.0` renders in 3–8 minutes (median ~5), `seedance-2.0-mini` in 2–3. Eight beats at 4 concurrent is two render waves, so tell the user to expect roughly 10–20 minutes of video time on top of the storyboard loop.

## Negative prompt block (paste into every video prompt)

```
no live-action footage, no photorealistic faces, no Pixar style, no 3D rendered
look, no CGI, no anime, no 2D illustration, no smooth digital render, no ray-traced
materials, no subsurface scattering, no extra fingers, no melted features, no
morphing between frames, no warped product labels, no on-screen text unless
specified, no subtitles, no captions
```

For Seedance 2 specifically, also strip the model's forbidden words: no `cinematic`, `professional`, `stunning`, `8k`, `studio`, `perfect`. Substitute: "stop-motion claymation film aesthetic", "polished hand-sculpted", "high fidelity", "evenly hand-painted".

## Captioning

Two style options that work for this genre:

**A. TikTok white-with-stroke** (the default for this genre)
- White Proxima/Montserrat Bold, ~7% of video height
- 4–6 px solid black stroke
- Lower third, centered
- Per-phrase timing, not per-word

**B. Orange highlight block** (the handmade-feeling alternative)
- White Proxima/Montserrat Bold
- Solid orange-red rounded rectangle background (`#E94B23` ish), 8–12 px padding
- Slight 2–3° rotation for handmade feel
- Lower third, slightly off-center
- One word or short phrase per highlight block

Burn captions after stitching (`ffmpeg -vf "subtitles=caps.ass"`), not in the Seedance prompt. The negative block tells Seedance "no captions" — burn them on in post.

### Recommended pipeline: animated captions via the `caption-video` skill

For per-phrase emphasis (scale-pop on punchlines, brand-color callouts on the product reveal), hand the stitched MP4 to the **`caption-video`** skill rather than burning static `.ass` subtitles. It carries the full HyperFrames + Whisper + chroma-key recipe — Whisper model choice by audio type, the word-grouping helper, the composition, and the ffmpeg composite. Do not re-derive it here.

Two things to carry across the hand-off:

- **Claymation caption styling:** storytelling tone — white-with-stroke base, warm-cream punchlines, brand-color product reveal. Tag groups by emphasis (`normal` / `comedic` / `brand` / `product`). The orange highlight-block variant above is the claymation-native alternative.
- **Trim first, caption second.** Whisper timestamps taken from a master with dead space drift once you tighten it. Apply the [no-dead-space rule](#-no-dead-space--vo-drives-clip-duration) to every beat, re-concat, and only then transcribe.

The one trap worth repeating because it costs a whole render to discover: **never put the source `<video>` (or `<audio>`) element inside the HyperFrames composition.** The runtime wraps timed elements and injects its own positioning, which overrides your CSS and reserves a layout block that shows up as a black bar across the bottom of a portrait render. Captions render over a keyable background and the source video is composited underneath in ffmpeg — `caption-video` has the exact filter chain.

## Endpoint notes

One API, no chooser. The storyboard and animation files in this folder own the prompt content; the call mechanics are below, and the `novoads-api` skill's `reference.md` wins whenever the two disagree.

| Step | Call | Model | Images in |
|------|------|-------|-----------|
| Upload a still or product photo | `POST /v1/uploads` → PUT the bytes to `uploadUrl` | — | returns a durable `assetId` |
| Storyboard | `POST /v1/images` — **synchronous** | `gpt-image-2`, or `nano-banana-pro` when clay texture matters more than identity | `referenceAssetIds: [assetId, …]`, **max 4 on `gpt-image-2` / 14 on `nano-banana-pro`** (spec 2.7.0), images only, addressed as `@Image1`… |
| Animation | `POST /v1/videos` — **async, returns `jobId`** | `seedance-2.0` (or `seedance-2.0-mini` for drafts) | `startImageAssetId: assetId` — the approved still becomes the first frame |
| Polling | `GET /v1/generations/{jobId}` every 15s until **terminal** (`succeeded`/`failed`/`blocked`/`canceled`) | — | — |
| Download | `GET /v1/generations/{jobId}/watch` → 302 to the file | — | — |
| Auth | `Authorization: Bearer $NOVOADS_API_KEY` on every call | — | — |

**The reference cap is per model: 4 on `gpt-image-2`, 14 on `nano-banana-pro`** (spec 2.7.0 restored Nano Banana's 14-reference budget on this API). On the default `gpt-image-2` storyboard route, four is enough for the beats that chain identity — hero plus one or two prior stills — and when a beat wants more, keep a rolling window anchored on the hero (`[hero, N-1, N-2, N-3]`) and never feed a *drifted* still forward. The discipline holds even on `nano-banana-pro`'s bigger budget: too many style references dilute identity, and the documented fix for that failure is to cut back to two.

Poll at **15s**, not 5s: 5s across 5 concurrent jobs is 60 calls/min, exactly the per-key rate limit with zero headroom.

### Two inversions of the habits this pipeline used to carry

**1. The `assetId` is durable — re-uploading is the bug.**
A previous version of this guide told you to re-upload the source PNG once per downstream call, because that API's presigned paths were single-use. **That is backwards here.** The `assetId` is the storage key itself, nothing consumes it, and the same id works on call one and call one hundred. This skill chains the protagonist anchor across Beats 2, 3, 4, 6, 7 and 8 and then uses each beat-still again as a start frame — **all of that runs off one upload per image.**

Re-uploading is not merely wasted work. A fresh id is a fresh asset, and chaining continuity through a new id each time is how you lose the identity anchor an 8-beat storyboard exists to hold. The **900-second expiry belongs to the `uploadUrl`, not to the asset.**

**2. There is one polling path.**
Every video job, on every model, is `GET /v1/generations/{jobId}`. There is no per-model routing to infer from a `type` field, and no separate assets endpoint. Poll for a **terminal** status rather than for `succeeded` — `failed`, `blocked` and `canceled` are also final.

### Concurrency, retries, and the one error that matters here

- **5 concurrent generations per organization.** An 8-beat ad far exceeds that, so cap at 4 in flight and let the spare slot absorb a QA retry.
- A `429` has four causes, told apart by `error.details.reason`: `key_limit` (60/min), `organization_limit`, `client_limit`, and `concurrency_limit`. Only the first three are fixed by slowing down. **`concurrency_limit` is fixed by waiting** for a running job to finish.
- **Never blind-retry a 500 on a generation call.** There are no idempotency keys, so a retry can double-charge. Check `GET /v1/generations` for a matching job before resubmitting. At 24 potential calls per run, this is the pipeline where a retry loop does the most damage.
- A `400` means the body was malformed. A `422` is moderation, and it is now the only thing that refuses a prompt for what it says.

## Supporting files

- [storyboard-gpt-image-2.md](storyboard-gpt-image-2.md) — `gpt-image-2` prompt formulas for each of the 8 beats
- [animate-seedance-2.md](animate-seedance-2.md) — `seedance-2.0` image-to-video formulas, per-beat
- The `novoads-api` skill — auth, upload, estimates, polling, download, error codes
- The `caption-video` skill — the captions pass on the stitched master

## Trigger phrases (for skill activation)

- "make a claymation ad"
- "Aardman-style ad for {product}"
- "stop-motion ad like {reference}"
- "clay-style 3D ad"
- "Wallace and Gromit style ad"
- "claymation story ad with {character name}"
