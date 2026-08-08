---
name: novoads-claymation-storyboard-ad
description: >-
  Build a 40 to 70 second hand-sculpted stop-motion CLAY ad as a STORYBOARD —
  five to eight separate beats, each rendered from its own key frame, with a
  storyteller narration laid into the gaps, a music bed under it and captions
  burned on, assembled locally with ffmpeg. Carries the genre's narrative arc:
  a named protagonist, an inciting moment, a social beat, quiet despair, a
  sculpted clay infographic, discovery, transformation and a resolution card.
  Also recreates a found clay ad: hand it a reference video and it reads the
  video's own beats with analyze_ad before writing the board. Produces a cast
  sheet, a beat board, a per-beat still, a per-beat clip, a per-gap voice-over
  line, and the exact generation calls in order. Trigger on "claymation ad",
  "stop-motion ad", "clay ad", "plasticine characters", "make an ad like this
  clay one", or a reference video with sculpted clay characters in it. Do NOT
  use for the smooth 3D animated look (use novoads-pixar-storyboard-ad, or
  novoads-pixar-ad for a single 15-second shot), for talking-head UGC (the
  default Novoads flow), or for a static image ad (use a static image-ad
  skill).
---

# Novoads Claymation Storyboard Ad

One product in. A 40 to 70 second hand-sculpted clay ad out, cut from five to
eight separately rendered beats, with narration, music and captions.

This is the **sibling** of `novoads-pixar-storyboard-ad` and it runs the same
pipeline: the same gates, the same calls, the same still gate, the same local
assembly. Read that skill for the pipeline. **This file owns two things it does
not: the clay look, and a narrative arc that is longer and quieter than the
Pixar one.**

The two are not interchangeable, and the difference is not decoration:

| | Pixar storyboard | Claymation storyboard |
|---|---|---|
| Hook | an anthropomorphized problem with eyes, speaking | a named person in their kitchen, and a narrator |
| Arc | 4 to 6 beats, a want and a turn | 5 to 8 beats, a small life story |
| Voice | in-scene SYNC plus narration | a storyteller carrying almost all of it |
| Surface | smooth, wet-eyed, subsurface scattering | matte clay, thumbprints, tool marks |
| Runs on | want, then relief | affection for a character |

Picking the wrong one is not a style mistake, it is a story mistake. If the
product's pain is a moment, that is the Pixar skill. If it is a season of
someone's life, it is this one.

## Before anything: this runs on a Novoads account

1. A Novoads account with credits. https://novoads.ai
2. The connector at `https://novoads.ai/api/mcp`, added to **the surface you are
   actually using**:
   - **Claude Code** — `claude mcp add --transport http novoads https://novoads.ai/api/mcp`,
     then `/mcp` to authenticate, then **restart Claude Code**.
   - **claude.ai** — add it as a connector in settings.
3. **ffmpeg on your machine.** The assembly happens here, not on the server.
   `ffmpeg -version` before you start.

## What one run costs

Two shapes, and the choice is the operator's:

| Step | 5-beat short | 8-beat full |
|---|---|---|
| Cast sheet | 3 cc | 3 cc |
| Beat stills | 5 × 3 = 15 | 8 × 3 = 24 |
| Beat clips | 5 × 6s = 170 | 8 × 7s = 304 |
| Voice-over | 5 lines = 10 | 8 lines = 16 |
| Music bed | 5 | 5 |
| Captions | 4 | 4 |
| **Total** | **207 cc ≈ 20.7 credits** | **356 cc ≈ 35.6 credits** |

**The clips are 82% of the bill either way**, and a still costs a eleventh of the
clip it produces. That is the whole economic argument for the board gate.

Check it rather than trust it. `estimate_cost` prices every one of these kinds
and spends nothing.

**Say the shape out loud before pricing it.** An 8-beat clay ad is the most
expensive thing in this family, and the honest question at Gate 0 is whether
beats 3, 4 and 5 are earning their 100+ credits. They often are; the arc is what
this genre is for. But the operator decides that, not you.

## Hard constraints

Everything in `novoads-pixar-storyboard-ad`'s Hard constraints section applies
unchanged: one call per beat, 4 to 15 seconds, 9:16, `audioEnabled: true`, a
narrator line in the prompt OR the VO track and never both, one continuous
voice, no `styleFamily` field. Read them there.

Three are different here:

- **Five to eight beats**, not four to six. The arc is a story and a story needs
  its middle. Below five beats it is a Pixar-shaped ad in clay, and the Pixar
  skill will render it better and cheaper.
- **The narrator carries the ad.** This genre is third-person storytelling, and
  the narration is not filler between spoken lines the way it is in the Pixar
  skill. Most beats are VO beats and that is correct here.
- **At least one beat is still SYNC.** Usually beat 3, the social beat, where a
  second character says the thing the protagonist has been avoiding. A whole ad
  of narration over silent faces is the failure this rule exists to prevent.

## Two ways in

### A. From a product

Run `novoads-pixar-storyboard-ad`'s Gate 0 and Gate 1 unchanged: is the pain
emotional, visible on a face, in a relationship, impulse-priced; then the product
read. One extra question at this length: **does this product have a before and an
after that a viewer would recognise a month apart?** The transformation beat is
the spine of the clay arc, and a product with no visible change does not have one.

### B. From a found video

The other entry, and the one this genre is usually asked for: someone shows you a
clay ad and wants theirs. Do not guess at its structure from the thumbnail.

```
upload_asset  contentType: "video/mp4", sizeBytes: <n>
              → { uploadUrl, assetId, headers } — PUT the bytes with `headers`
                VERBATIM. Content-Type and Content-Length are signed into the
                URL, so an omitted Content-Type is a 403, not an upload.
      │
      ▼
analyze_ad    assetId: <the reference>, question: "the beats and the narration"
              → summary, hook boundary with the observable signal behind it,
                beats, on-screen text, casting, layout zones
```

**`analyze_ad` reads the first 20 seconds of a video.** A 60-second clay ad is
therefore read down to its opening third, which is enough for the hook, the
casting and the palette, and is NOT enough for the arc. Watch the rest yourself
and write the remaining beats by hand. A board that claims eight beats from a
20-second read is a board with five invented beats in it.

Then map what it returns onto the arc below, and **write our own story**. Recreate
the FORMAT, never the script: their protagonist, their brand and their claims are
theirs. What transfers is the shape, the palette, the pacing and the narrator
persona.

## The clay look

### Style lock — one paragraph, pasted verbatim into every prompt

<!-- eval:style-lock:start -->
```
Hand-sculpted stop-motion clay look. Plasticine characters with visible
fingerprint impressions and sculpting-tool marks, matte clay surfaces with
subtle micro-bumps, slightly asymmetric features, painted-on or sculpted
eyebrows. Real knit-fabric clothing with visible wool weave and stitch lines,
wooden and ceramic miniature-set props with hand-painted finishes. Warm tungsten
interior lighting, shallow macro depth of field, soft photographic bokeh.
Subtle imperfection in every surface. Vertical 9:16 composition.
```
<!-- eval:style-lock:end -->

**Never name a studio or a franchise.** The lineage this look comes from belongs
to two specific studios, and naming either is both an IP problem and a
worse prompt: the model reaches for their characters instead of your sculpt.
"Hand-sculpted stop-motion clay" is what the words above are doing.

### The negative block

<!-- eval:negative-block:start -->
```
no live-action footage, no photorealistic humans, no uncanny faces, no dead eyes,
no smooth 3D digital render, no glossy surfaces, no ray-traced reflections,
no subsurface scattering, no wet-eye highlights, no anime style,
no 2D illustration, no named or copyrighted animated film characters,
no extra fingers, no melted features, no morphing between frames,
no warped product labels, no on-screen text, no subtitles, no captions
```
<!-- eval:negative-block:end -->

Half of this block is doing a job the Pixar one does not: **holding the render
away from its own default.** The video models smooth clay into 3D plastic over
the length of a clip, so `no smooth 3D digital render`, `no glossy surfaces` and
`no subsurface scattering` are load-bearing, not boilerplate.

### Material detail — paste the lines that apply to what is in frame

<!-- eval:material-detail:start -->
```
Skin: matte plasticine, visible thumbprint impressions on cheeks and forehead,
small sculpting-knife creases at the corners of the eyes, slight asymmetry
between the left and right side of the face.
Hair: sculpted in distinct ribbon-strands of plasticine, individual strand
grooves carved with a tool, slightly stiff and not flowing.
Eyes: small matte clay orbs set into sculpted sockets, a single soft highlight,
no wet shine.
Knitwear: real chunky wool yarn, individual stitches visible, slight wear at the
cuffs and hems.
Wood props: hand-painted matte finish, visible grain, small dents and scratches
that suggest age.
Ceramic: hand-thrown irregular form, glaze pooling at the bottom edges, slightly
off-round.
Product packaging: a clay-shaded prop with a hand-painted label, the paint
slightly uneven and matte.
```
<!-- eval:material-detail:end -->

This block is the difference between clay and a cartoon of clay. Paste the
relevant lines into every still prompt. Drop the ones for materials that are not
in the frame; a knitwear line on a product close-up buys nothing.

### Faces here may be quirky. That is a licence, not a defect

The Pixar sibling chases APPEAL: symmetrical, soft, a moment before a smile. This
genre does the opposite and it is the single easiest thing to lose when the two
skills sit side by side. **Clay characters are allowed to be odd.** Oversized
noses, deep wrinkles where the sculptor pressed, eyes set slightly unevenly,
a jaw that is not quite level. Quirky beats appealing here, and a clay
protagonist rendered pretty reads as a 3D render wearing a clay texture.

Say it in the prompt, per character, or the model will smooth it out: "an
oversized nose, deep sculpted wrinkles at the eyes, slightly uneven eye
placement."

### Smooth motion or stop-motion judder

Real stop-motion carries a 12 to 15 fps judder. Our renders come out smooth at 24
or 30, and **smooth is the default** because it is what the genre's own reference
ads do.

If the operator wants the judder, it is a post step and never a prompt:

```bash
ffmpeg -i master.mp4 -filter:v "fps=12,fps=24" -c:a copy master-judder.mp4
```

Asking the render for "stop-motion judder" does not control frame rate and does
break the look. Do not put it in a prompt.

## The arc

Eight beats, and the operator picks how many of them get made. The beat formulas,
the variable tables and the worked prompts are in
[`references/formulas.md`](references/formulas.md).

| # | Beat | Seconds | Track | Drop for the short? |
|---|---|---|---|---|
| 1 | Setup — the protagonist in their own world | 7 | VO | keep |
| 2 | Inciting moment — they notice the problem | 6 | VO | keep |
| 3 | Social validation — someone else says it out loud | 8 | **SYNC** | drop |
| 4 | Quiet despair — alone, at a mirror or a window | 6 | VO | drop |
| 5 | Clay infographic — the mechanism, sculpted | 7 | VO | drop |
| 6 | Discovery — they find the product | 6 | VO | keep |
| 7 | Transformation — weeks pass, the change is visible | 9 | VO | keep |
| 8 | Resolution — confident, then the end card | 6 | VO closes | keep |

**The 5-beat short is 1, 2, 6, 7, 8** and lands around 34 seconds. It is the
right call for a first run with a brand, and it is what the dry run below uses.

**Beat 3 is where the SYNC line goes** when the short is not being made. When it
is, promote the SYNC line to beat 6: the protagonist says one short thing to
themselves when they find the product. Do not ship an ad where no mouth ever
moves.

**Beat 5 is optional even in the full arc.** A sculpted clay chart sells a
mechanism; it wastes 7 seconds on a product that has none.

### Which beats earn their place, by category

| Category | Arc | What changes |
|---|---|---|
| Supplement, stress, sleep | the full 8 | Beat 5 is the one that sells it. Keep the chart |
| Beauty and skincare | 8, chart optional | Beats 2 and 4 carry it: the mirror, then the reflection alone |
| Office or B2B | the full 8 | **Beats 1 to 4 in cool fluorescent light**, warm only from the discovery on. The palette is the story |
| Food and kitchen | the 5-beat short | Beats 1, 6 and 7 dominate; if you keep beat 3, make it a family table rather than a cafe |

The office row is the one worth reading twice. Everywhere else this genre is
warm tungsten throughout; a fluorescent first half and a tungsten second half
tells the arc in light before a word is spoken.

Everything else about the board — one action per beat, its own setup, the word
budget, VO and SYNC never overlapping in the same beat, no em dashes, never
"free" — is the Pixar skill's board section, unchanged.

## The cast sheet

Same call, same 3 credits, different contents. Clay ads usually carry **two named
characters**, and the narrator is a third presence who is never on screen.

Write the sheet text first from the template in
[`references/formulas.md`](references/formulas.md), then render it. The template's
slots that matter most here:

- **A name.** The narrator says it out loud, and a named protagonist is most of
  why this genre works. "Diane" is a person. "A woman in her 50s" is a stock
  photo.
- **Middle-aged or older.** The look flatters sculpted laugh lines and hooded
  eyelids, and the arc needs a life already in progress.
- **The terse tag**, 11 to 30 characters, anchored on wardrobe. Our renders
  re-cast on every cut, so this is what carries one face across eight beats.
- **A narrator persona**, chosen once from `list_voices` and reused for every
  line. Warm storyteller and wry observer are the two that fit; pick one and say
  which.

## The gates

Gates 2 through 8 are `novoads-pixar-storyboard-ad`'s, unchanged, including:

- **Gate 2** — price every kind once, multiply, announce in one line, proceed.
- **Gate 3** — every still before any clip, each chained on the cast sheet and
  the previous still, then **STOP at the board gate**. At eight beats the stills
  are 27 credits and the clips are 304. This gate is worth more here than
  anywhere else in the family.
- **Gate 4** — clips in waves of at most five. **Eight beats is two waves**, five
  then three, because a sixth concurrent generation is refused with
  `concurrency_limit` and that is a real refusal, not a queue.
- **Gate 5** — one voice, chosen once. **Gate 6** — the music bed.
- **Gate 7** — trim each clip to its narration plus 0.5 seconds, concat, mix,
  composite the end card from the real photograph, transcribe and read it back.
  **Read the levels out of the Pixar skill rather than from here** — the mix is
  per beat, not one recipe, and this line used to restate it as a flat
  `VO 100% / clip 28% / music 10%`. That recipe was written when every beat was
  a VO beat. This genre has a SYNC beat (beat 3), where the clip's own audio IS
  the dialogue, and 28% buries it under a caption spelling out words the viewer
  cannot hear. One number cannot serve both cases, so this file states none.
- **Gate 8** — captions, and the **BLOCKING** caption gate.
  **A garbled brand name is a failed run, not a note in the report.**

Gate 7 in particular carries three rules this genre needs verbatim and does not
restate here: trim to the VO or extend the VO to fill the shot, **never
`atempo`** a long line to fit, and re-check the caption's vertical position
after trimming because the frame at the new cut is not the frame that was there.

**Do the assembly in `outputs/<ad-name>/`, not in the directory you started in.** The
downloaded beats, `beats.txt`, the trimmed clips, the placed VO lines and the master are one
run's working set — a dozen of them loose in a repo root is a diff somebody else has to
explain. That includes the judder pass above: `master.mp4` and `master-judder.mp4` live
there too.

Two caption looks fit this genre, and the preset guidance in the Pixar skill's
Gate 8 is how you choose between them. The default is the heavy white sans with
a thick dark outline. The alternative, and the one the genre's own reference ads
use, is **a solid warm-orange rounded block behind white text, sitting slightly
tilted** in the lower third. No preset renders that block, so it is the one case
where the local burn is the right call rather than the fallback.

Two clay-specific additions:

**The clay QA is its own check and it is not the Pixar one.** Both checklists are
in `references/formulas.md`. The one that matters: **the render smooths clay into
plastic over the length of a clip.** Watch the last second, not the first frame.
A still that passed and a clip that ends in glossy 3D is the single most common
failure in this genre.

**Beat 7's improvement must be localised.** "Weeks later" on a whole face
produces a different person, which reads as a lie and breaks continuity in one
shot. Name the one thing that changed and say that everything else is unchanged.

## Output format

Deliver in this order, no preamble:

1. **PRODUCT READ** — or, on entry B, the `analyze_ad` breakdown of the reference
   with a line saying how much of it was actually read.
2. **FIT** — one line confirming Gate 0, or a plain refusal naming a better
   format. If the pain is a moment rather than a season, hand off to
   `novoads-pixar-storyboard-ad` and say so.
3. **ARC LENGTH** — 5-beat short or 8-beat full, and why, with both prices.
4. **CAST + STYLE LOCK** — the cast sheet text including the name and the terse
   tag, and the paragraph pasted into every prompt.
5. **BEAT BOARD** — the table. At least one SYNC beat.
6. **COST** — the `estimate_cost` figures, announced in one line.
7. Then generate: cast sheet, all stills, **stop at the board gate**, clips, VO,
   music, assemble, composite the end card, verify, caption, **read the captions
   against the script before calling it finished**.

## The calls

Identical to `novoads-pixar-storyboard-ad`'s call list, plus one:

```
analyze_ad        assetId, question?
                  → { summary, hook, beats, onScreenText, casting, layoutZones }
                    READS THE FIRST 20 SECONDS OF A VIDEO. Free of render cost,
                    not free of tokens. Entry B only.
```

### Worked beat prompt

A finished **beat 3** (social validation) `generate_video` prompt: the SYNC beat,
one action, style lock and material detail included, negatives at the end.
`lib/generation/__tests__/claymation-storyboard-skill-prompts.test.ts` reads this
exact block and runs it through the same rule engine `estimate_cost` lints with.

<!-- eval:beat-prompt:start -->
```
Hand-sculpted stop-motion clay look, vertical 9:16, animating the two characters
in the reference image. A sunlit miniature clay kitchen, green-painted wooden
cabinets, a red gingham tablecloth, warm tungsten light from a window on
camera-left.

Diane, a woman in her late 50s in a cream chunky knit cardigan, matte plasticine
skin with visible thumbprint impressions and deep sculpted laugh lines, sits
across the table from her friend in a sage-green cable-knit sweater.

From zero to three seconds Diane lowers her cup and her sculpted brow furrows.
From three to eight seconds her friend leans in and says: "You have not been
sleeping, have you." Diane holds still and her eyes drop to the table.

Camera: locked medium two-shot at table height, gentle handheld breathing motion,
no dolly, no zoom. Shallow macro depth of field with the window softly out of
focus.

Skin: matte plasticine, visible thumbprint impressions on cheeks and forehead,
small sculpting-knife creases at the corners of the eyes. Knitwear: real chunky
wool yarn, individual stitches visible, slight wear at the cuffs. Ceramic:
hand-thrown irregular cups, glaze pooling at the bottom edges.

Audio: two warm, unhurried voices at a kitchen table, close and intimate, with
faint kettle and street ambience behind them.

Both characters stay visually unchanged from the reference image: same face
proportions, same hair, same wool weave, same clay texture held to the last
frame. no live-action footage, no photorealistic humans, no uncanny faces, no
dead eyes, no smooth 3D digital render, no glossy surfaces, no ray-traced
reflections, no subsurface scattering, no wet-eye highlights, no anime style, no
named or copyrighted animated film characters, no extra fingers, no melted
features, no on-screen text, no subtitles, no captions
```
<!-- eval:beat-prompt:end -->

## Failure modes

Everything in `novoads-pixar-storyboard-ad`'s Failure modes list applies. Four
are this skill's own:

- **The clay turned into plastic by the end of the clip.** The most common
  failure here. The material detail block was thin or the negative block was
  missing its anti-smoothing lines. Re-render with both, and add "clay texture
  held to the last frame" to the constraints.
- **The eyes went wet.** A Pixar-style multi-catchlight eye leaked in. `no
  wet-eye highlights` in the negative block and `a single soft highlight, no wet
  shine` in the material block. Both, not either.
- **The transformation beat produced a different person.** The improvement was
  described on the whole face. Name the one thing and pin the rest.
- **Eight beats and no mouth ever moved.** Every beat went to the narrator. Beat
  3 is a SYNC beat; if you dropped it for the short, beat 6 is.

## Hard rules

- One product per run.
- Stop at the board gate. The operator approves the board before the clips fire.
- Never name a studio or a franchise, in a prompt or in ad copy.
- Never invent reviews, ratings, prices, or performance claims.
- Use the real brand and the real packaging from the photo.
- On-screen text is short words and numbers only, never sentences.
- No em dashes in ad copy. Never say "free" — the entry offer is the $1 trial.
- On entry B, recreate the format and never the script.
- The end card is composited from the real photograph. Never rendered.
- Transcribe the master before you call it finished, and read the burned captions
  against the script. A garbled brand name blocks the ship.
