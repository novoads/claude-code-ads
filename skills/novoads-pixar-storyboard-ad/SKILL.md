---
name: novoads-pixar-storyboard-ad
description: >-
  Build a 30 to 60 second stylized 3D animated ad as a STORYBOARD — four to six
  separate beats, each rendered from its own key frame, with narration laid into
  the gaps, a music bed under it and captions burned on, assembled locally with
  ffmpeg. Carries the genre's beat formulas: an anthropomorphized problem
  character that speaks the pain in first person, a protagonist reveal, a mascot
  mechanism-of-action scene, and a composited end card. Produces a cast sheet, a
  beat board, a per-beat still, a per-beat clip, a per-gap voice-over line, and
  the exact generation calls in order. Trigger when the user wants a MULTI-SHOT
  animated spot: "a 30 second animated ad", "a storyboard ad", "several scenes",
  "a longer Pixar-style ad", "an animated ad with a voice-over", "an animated ad
  with the [object] character", "show how it works with little mascots", or
  hands you a product and asks for something with an arc rather than a single
  shot. Do NOT use for a single 15-second animated shot
  (use novoads-pixar-ad, which is one call and cheaper), for talking-head UGC
  (the default Novoads flow), for cloning a competitor's video (use an
  ad-clone workflow), or for a static image ad (use a static image-ad skill).
---

# Novoads Pixar Storyboard Ad

One product in. A 30 to 60 second stylized 3D animated ad out, cut from four to
six separately rendered beats, with narration, music and captions.

This is the **sibling** of `novoads-pixar-ad`, not a replacement for it. That
skill renders one 15-second shot in ONE call, and its single-call doctrine is
deliberate — everything that can go wrong in a stitch cannot go wrong there.
This one buys an arc and pays for it in seams. If the story fits in fifteen
seconds, use that skill instead and say so.

Everything that skill says about STORY — the gates, the doctrines, the word
budget per beat, the IP rules — still applies. Read it. This file covers only
what changes when there are five shots instead of one.

**The beat formulas live in [`references/formulas.md`](references/formulas.md).**
That file is the craft: the four genre roles, the variable tables, and a worked
still prompt and a worked clip prompt for each. This file is the pipeline. Read
the formulas before you write the board, because the board is where the roles
are assigned and it is the last cheap place to get them wrong.

## Before anything: this runs on a Novoads account

1. A Novoads account with credits. https://novoads.ai
2. The connector at `https://novoads.ai/api/mcp`, added to **the surface you are
   actually using**:
   - **Claude Code** — `claude mcp add --transport http novoads https://novoads.ai/api/mcp`,
     then `/mcp` to authenticate, then **restart Claude Code**.
   - **claude.ai** — add it as a connector in settings.
3. **ffmpeg on your machine.** This is the one hard local dependency, and it is
   what separates this skill from its sibling: the assembly happens here, not on
   the server. `ffmpeg -version` before you start.

If the tools are missing, it is almost always step 2 on the wrong surface, or a
session that has not been restarted.

## What one run costs

A five-beat, 25-second ad, at the defaults this file recommends:

| Step | Calls | Centi-credits |
|---|---|---|
| Cast sheet | 1 image | 3 |
| Beat stills | 5 images | 15 |
| Beat clips | 5 × 5s Seedance | 150 |
| Voice-over | 5 lines | 10 |
| Music bed | 1 | 5 |
| Captions | 1 pass | 4 |
| **Total** | | **187 cc ≈ 18.7 credits** |

Check it rather than trust it. `estimate_cost` prices every one of these kinds
and spends nothing; Gate 2 below fires it before anything else.

Two numbers worth holding: **the clips are 80% of the bill**, and a still costs
a fiftieth of the clip it produces. That is the whole economic argument for the
still gate — and for never re-rendering a beat you have not first tried to fix
in its still.

## Hard constraints

- **Four to six beats.** Fewer is `novoads-pixar-ad`'s job. More than six and
  the seams outnumber the story.
- **Each beat is its own `generate_video` call from its own start frame.** Never
  ask one call for multiple scenes.
- **4 to 15 seconds per beat**, and in practice 4 to 6. A beat is one action.
- **9:16** unless the operator says otherwise.
- **`audioEnabled: true` on every beat.** The clip's own audio is the SFX bed
  and the in-scene voices; there is no SFX endpoint and none is needed.
- **A narrator line goes in the PROMPT or in the VO track. Never both.** This is
  the rule that separates this skill from its sibling, and getting it wrong is
  silent: Seedance renders any `NARRATOR: "…"` line in the prompt into the clip's
  own audio, so laying a `generate_voiceover` take of the same words on top plays
  every line twice. Measured — a raw beat clip transcribed on its own came back
  saying the narrator's line, and the finished mix said it twice. Decide per beat:
  - **Narration from the VO track** (the default here, because it is the only way
    to get ONE voice across five separate renders): the prompt carries in-scene
    dialogue only, or states that the shot has no speech. Keep `audioEnabled:
    true` for ambience.
  - **Narration native to the clip**: put `NARRATOR: "…"` in the prompt and
    generate NO voice-over for that beat. Its voice will not match the others.
- **At least one beat must be SYNC.** The rule above is a warning against
  doubling a line, and it is easy to over-obey: make every beat a VO beat and the
  ad becomes a slideshow with a voice talking over it. Measured — T12 shipped
  three beats, all VO, no character ever spoke, and it lost to the reference ad
  on exactly that. The genre's opening move is a problem character saying its own
  complaint out loud, and it only lands when the voice comes out of the face.
- **The product appears in its own beats and on the end card. Nowhere else.** A
  product held in every shot reads as a catalogue. Roles B and D show it; the
  hook and the mechanism scene do not. See `references/formulas.md`.
- **One continuous voice.** Pick the narrator voice ONCE, from `list_voices`,
  and use that same `voiceId` for every line. A voice that changes between beats
  reads as a different ad — which is also why native per-beat narration does not
  work across a storyboard: each render casts its own.
- **There is no `styleFamily` field.** It was deleted from the whole API. Nothing
  on the generation path refuses a prompt on style grounds any more; the only
  prompt refusal left is content moderation.

## The gates run in order. Do not skip to the render.

### Gate 0, 1 — fit and product read

Unchanged from `novoads-pixar-ad`. Run its Gate 0 filter (emotional pain, visible
on a face or a mechanism, a relationship, impulse-priced) and its Gate 1 product
read (verified facts, buyer language, who actually buys, what you will not claim,
anything unbuyable). A longer format does not lower that bar; it raises the cost
of getting it wrong.

One addition at this length: **an arc needs a turn that is worth 25 seconds.** If
the product read produces one feeling and one feature, the honest answer is a
15-second single-shot ad. Say so.

### Gate 2 — price the whole board, then announce it

Price each KIND once and multiply. `estimate_cost` takes one call at a time, so
four calls describe the whole run:

```
estimate_cost  kind: "image",     prompt: <a beat still prompt>
estimate_cost  kind: "video",     prompt: <a beat prompt>, durationSeconds: 5
estimate_cost  kind: "voiceover", script: <the longest VO line>
estimate_cost  kind: "music"                    (skip if the tool is absent)
```

Then announce in one line and proceed:

> Cast sheet + 5 stills + 5 clips + 5 VO lines + music + captions ≈ 18.7 credits
> (balance: 340). Starting.

This is an announcement, not a question. Two cases change it:

- **`sufficient: false` on any kind** — stop. Name what is short and give the
  `topUpUrl`. That is a blocker.
- **The balance covers the run and no retry.** Say so in one clause before
  firing: "this covers one pass, not a re-render." At this length a re-render is
  a beat, not the whole ad — which is worth saying too, because it is the good
  news: a bad beat costs 3 credits to redo, not 18.

**The `warnings` array is advice.** `estimate_cost` is the only call that lints a
prompt, and it lints against the UGC talking-head rules — nothing here refuses
anything. A prompt written the way this file says comes back clean; a warning
usually means you drifted, not that the lint is confused.

Two clauses are what make it come back clean, and both are in the style lock and
the worked prompt for this reason. Measured on a beat prompt without them: the
VOICE STYLE casting line answers `missing_actor_descriptor` (the rule looks for
an age or gender token anywhere in the prompt), and the labelHold clause answers
`label_without_hold`, which fires on the word "bottle" alone. Drop either and the
same beat comes back with a warning that is telling you the truth.

**The one warning to ignore: `missing_actor_descriptor` on a beat with no human
in it.** The lint reads prompts as talking-head UGC, where a shot without an age
or gender token gets a randomly cast person. A role-A beat is a hair clump with
eyes, or a blob of congestion, and it has no age and no gender to state. The rule
is answering a question the beat does not ask. This is the only lint output this
skill tells you to overrule, and only on a beat whose subject is genuinely not a
person — a beat that merely FORGOT to describe its human is the case the rule
exists for, and it looks identical from here. Check which one you wrote.

## The board

Before a single call, write the board. It is the artifact the operator approves,
and it is cheaper to argue with than any render.

### Cast sheet — one image, referenced by every still

`generate_image`, `1:1`, product photo as reference. On one canvas: the lead in
three emotional states readable in the eyes, any secondary character, the product
in 2 to 3 views, and a scale line-up at true relative size.

This single image is what makes five separately-rendered beats look like one
film. Every beat still references it. Skipping it is the most expensive shortcut
available here — five beats with five differently-imagined characters is not an
ad, and no amount of prompt discipline recovers it afterwards.

Write the cast sheet TEXT first, from the template in
[`references/formulas.md`](references/formulas.md), and render the image from it.
The template has the slots that matter — including the **terse tag**, the 11 to
30 character wardrobe-anchored phrase repeated verbatim in every later beat. Our
renders re-cast on every cut, so "the same woman" names nobody; one measured run
came back with three visibly different women across five beats.

If the ad has a mascot scene, the cast sheet carries the mascots too: one canvas
with the lead, the problem character and the mascot trio settles all three
designs for the price of one image.

### Style lock — one paragraph, pasted verbatim into every prompt

Write it once. Location palette, one named practical light source, lens and
camera height, the finish of the world. Paste it into every still prompt and
every beat prompt, unchanged, character for character. Rewording it between
beats is how the grade drifts.

Never name a studio or a franchise. Write "stylized 3D animated feature film
look." The trademark risk is higher for this aesthetic than for any other,
because it belongs to specific studios and the models will hand you near-copies
of their characters if invited.

This is the genre default. Change the palette and the light source to the
product's world; keep the structure and the render vocabulary.

<!-- eval:style-lock:start -->
```
Stylized 3D animated feature film look. Soft volumetric golden-hour lighting from
a large window, warm cosy palette of cream, butter yellow, dusty pink and soft
sage. Subsurface scattering on skin, painterly background, shallow depth of field
with creamy bokeh. Characters have large expressive eyes with multiple specular
catchlights, stylized but believable proportions, smooth simplified hands, soft
hair strands with subsurface glow. Rich material detail: waffle-knit fabric
weave, ceramic glaze, glass refraction. Slightly desaturated colour grade.
Every character reads mid-emotion, caught a moment before a smile or a sigh,
never blank-staring. Vertical 9:16 composition.
```
<!-- eval:style-lock:end -->

**The mid-emotion line is the genre's oldest craft rule and the easiest to
lose.** A character rendered at rest reads as a mannequin however good the
lighting is; the whole look depends on faces caught between expressions. It sits
in the style lock rather than in prose because that is the block that actually
reaches every prompt.

And the negative block, pasted at the end of every prompt, still and clip alike:

<!-- eval:negative-block:start -->
```
no live-action footage, no photorealistic humans, no uncanny faces, no dead eyes,
no anime style, no 2D cel-shaded look, no flat illustration,
no named or copyrighted animated film characters, no harsh fluorescent lighting,
no extra fingers, no melted features, no morphing between frames,
no warped product labels, no on-screen text, no subtitles, no captions
```
<!-- eval:negative-block:end -->

`no named or copyrighted animated film characters` is the IP line and it is not
optional. `no on-screen text, no subtitles, no captions` is what stops the render
inventing its own captions, which it does unprompted and which then collide with
the ones burned on in Gate 8.

### Beat board — the table you get approved

Two things are decided here: what happens (the skeleton) and how the genre says
to shoot it (the role). The roles are in
[`references/formulas.md`](references/formulas.md); this is where they are
assigned.

| # | Beat | Genre role | Seconds | Track | Visual |
|---|---|---|---|---|---|
| 1 | Hook — the want, stated out loud | A. anthropomorphized problem | 5 | SYNC | … |
| 2 | Problem — the attempt fails | A. second problem character, or the human low | 5 | VO | … |
| 3 | Low point — the private defeat | B. protagonist reveal | 4 | SYNC | … |
| 4 | Turn — the product arrives and is used | C. mascot mechanism | 6 | VO | … |
| 5 | Payoff — warmth, then the hero card | D. CTA and end card | 5 | VO closes | … |

That mapping is the default, not the only one. Role A can hold two beats as a
montage; role B can take the SYNC beat as a first-person testimonial. What does
not move: **role A opens** and **role D closes**, and at least one of them is
SYNC.

Rules for the board:

1. **One action per beat.** Two actions in one prompt is the single most reliable
   way to get glitched physics. Splitting them is what a storyboard is FOR.
2. **Give each beat its own setup.** Five beats in one location at one shot size
   reads as boring no matter how clean the arc is. Change location at least once;
   vary shot size (medium → close → wide). Measured against the reference ad this
   skill was rebuilt to match: its beats each had their own world — a macro
   problem shot, a lit interior, a stylized interior cross-section, a card — and
   T12's three all shared one. That is the difference a viewer names first.
3. **The low point is the shortest beat and the most important one.** Everything
   rides on that face.
4. **Word budget is per beat, not per ad.** Two spoken lines per 5-second beat is
   the ceiling. Across five beats that is a 45 to 60 word script, which is
   correct for 25 seconds — and much easier to write than the 30-to-33 the
   single-call skill squeezes into fifteen.
5. **VO and SYNC never overlap in the same beat.** Write the SYNC lines first;
   fit the narration into beats that have none. And keep the narrator's words out
   of the prompt for any beat you are giving a VO line — see the hard constraint
   above. The board's Track column is what records that decision per beat.
6. No em dashes in ad copy. Never say "free" — the entry offer is the $1 trial.

## Gate 3 — stills first, all of them, then STOP

Render every beat still BEFORE any clip. Sequentially, each referencing the cast
sheet and the previous still:

```
upload_asset(product photo) → PUT the bytes with the returned `headers` VERBATIM
      │
      ▼
generate_image  cast sheet   1:1   ref [product]                        3 cc
      │  ← returns images[].assetId. Pass it straight to the next call.
      ▼
generate_image  beat 1       9:16  ref [castSheet, product]             3 cc
generate_image  beat 2       9:16  ref [castSheet, beat1]               3 cc
generate_image  beat 3       9:16  ref [castSheet, beat2]               3 cc      ← sequential,
generate_image  beat 4       9:16  ref [castSheet, beat3]               3 cc        each on the
generate_image  beat 5       9:16  ref [castSheet, beat4]               3 cc        one before
      │  ← each one's assetId feeds the next, no upload in between
      ▼
╔═══════════════════════════════════════════════════════════════════════╗
║  BOARD GATE — show all six images in order. Wait for the operator.    ║
║  18 cc spent. The clips are 150. A wrong character, a wrong palette   ║
║  or a wrong location caught here costs an eighth of what it costs     ║
║  after the renders.                                                   ║
╚═══════════════════════════════════════════════════════════════════════╝
```

**A generated image IS an assetId — chain it directly.** `generate_image`
returns `images[].assetId` alongside `images[].url`, and that id is what
`referenceAssetIds`, `startImageAssetId` and `sourceAssetId` take. No download,
no re-upload, nothing in between:

```
generate_image → images[0].assetId  ← pass this to the next call, as-is
```

**Chain from `assetId`, not from `url`.** The URL is a one-hour presign for
fetching the bytes; the assetId does not expire that way. Still download each
still as it lands if you want the files locally — a slow board review will
outlive the URLs.

<details>
<summary>Fallback for a deployment older than API spec 2.11.0</summary>

Before 2.11.0, `generate_image` returned a URL and no asset id, and every still
needed a round trip before the next call could reference it. If `images[]` has
no `assetId`, you are on such a deployment — do this instead, per still:

```
generate_image → images[0].url
      │  download the bytes
      ▼
upload_asset  contentType: "image/png", sizeBytes: <n>
      │  PUT with `headers` VERBATIM
      ▼
assetId  ← what referenceAssetIds and startImageAssetId take
```

It costs nothing (uploads are free) and applies to the cast sheet and every beat
still. Skipping it there gets the reference rejected as a foreign id, which reads
as a permissions problem rather than a format one. On those deployments the
one-hour URL expiry is load-bearing: download each still as it lands rather than
at the end of the board, or a slow review turns into re-rendering images you
already paid for.

</details>

**Chain each still on the previous one, not just on the cast sheet.** That is
what carries the location, the light and the wardrobe forward. `gpt-image-2`
takes up to 4 reference images, so cast sheet plus previous still plus the
product leaves room for one more; use it for the product when the product is in
frame.

**This gate is one stop, not five.** Do not ask after each still. A board is
approved as a board — the operator is judging whether beat 3 follows beat 2,
which they cannot do one image at a time.

## Gate 4 — the clips, in waves of five

```
generate_video  beat N  seedance-2.0  9:16  startImageAssetId=<beat N still>
                        durationSeconds=<from the board>  audioEnabled=true
```

**Submit in waves of at most five.** The API allows five generations in flight
per organization; a sixth is refused with `concurrency_limit`, which is a real
refusal and not a queue. Five beats is exactly one wave. Six beats is one wave of
five, then one.

**Write every jobId down the moment it comes back**, before you start waiting —
id, which beat, the credits it cost. A job whose id you recorded is a lookup when
something goes wrong. A job whose id you did not is an investigation.

**Poll every 3 seconds. Give up at 10 minutes.** Poll `get_generation` per job
until `succeeded`. Renders take minutes and the poll is what drives completion —
keep the session open.

**If a call times out, do NOT generate again.** The work usually completed and
was charged; what timed out was the response carrying its id. Call
`list_generations`, find the job by timestamp and prompt preview, take its
`outputUrl`.

### Per-clip QA, before you spend a voice-over on it

Check each clip as it lands. A beat that fails here is 3 credits to redo; a beat
that fails after the mix has cost the mix too.

1. The character is the same character as the cast sheet.
2. The action in the prompt is the action on screen, and it is ONE action.
3. Nothing grew eyes, limbs or a mouth that the design does not have.
4. The product's identifying details survived, and any printed label is legible.
5. The clip's own audio is usable — ambience and in-scene voices, not a music bed
   competing with the narration you are about to lay over it.

**The repair depends on the failure, and the two repairs are opposites.** A beat
that did two things, smeared its action or glitched its physics gets a SHORTER
prompt: fewer clauses, one action, the actor named in it. A beat that grew a
sixth finger, melted a feature or drifted a label gets ONE added negative naming
that artefact exactly. Getting it backwards is why a beat gets re-rolled three
times. The table in `references/formulas.md` has both cases.

## Gate 5 — the voice-over

One line per beat that needs narration. Pick the voice once:

```
list_voices                    → pick ONE voiceId, note it, reuse it
generate_voiceover  script: <beat 2 VO line>, voiceId: <the one>
                    → { url, assetId, characters, creditsCharged }
```

**This call returns the finished mp3, not a job.** There is nothing to poll —
download the `url` immediately, because it is time-limited and minted per
response. If a call times out, do NOT retry it: the audio was probably rendered
and charged, and `list_generations` will show it with its cost.

**Write the lines to the gaps, not to the beats.** A beat with a SYNC line has no
room for narration. Read each line aloud against the beat's length before
generating it: about 15 characters per second of speech, so a 5-second beat holds
roughly 70 characters of narration and no more.

**The script is read VERBATIM**, including anything in square brackets — the
model interprets those as performance tags rather than skipping them. Keep stage
directions out.

**Language**, if the ad is not in English: pass `language` and pick a voice whose
`languages` include it. A mismatch is refused before anything is charged, which
is the good outcome; picking a voice that does not speak the language and getting
a charged take in the wrong accent is the bad one.

## Gate 6 — the music bed

```
generate_music  prompt: <what it sits under>, instrumental: true   5 cc
                → { jobId } — poll get_generation, read audio[]
```

One request returns TWO takes for one charge. Listen to both and use the one that
sits better under the voice; they differ in length and arrangement, not price.
Expect one to two minutes of audio whatever you ask for — you will trim it.

**If `generate_music` is not in your tool list, skip this step.** It is behind a
flag and some deployments do not offer it. Say one sentence — "no music bed on
this account, mixing without one" — and carry on. The ad works without it; clip
audio plus narration is a complete mix.

## Gate 7 — local assembly

This is where the seams either disappear or announce themselves.

### Trim to the narration, not to the clip

For each beat: the clip is as long as you asked for, and the line inside it is
whatever length it is. **Trim the clip to the voice-over plus 0.5 seconds**, not
the other way round. Dead air at the end of a beat is the single most common tell
that an ad was assembled rather than shot.

```bash
# VO duration, to two decimals
ffprobe -v error -show_entries format=duration -of csv=p=0 beat2-vo.mp3
# trim the clip to it, +0.5s of air
ffmpeg -i beat2.mp4 -t <vo+0.5> -c:v libx264 -c:a aac beat2-trimmed.mp4
```

A beat with no narration keeps its own length.

**Trimming is the default, not the only option.** Measure both and pick per beat:

| Option | When | How |
|---|---|---|
| **A. Trim the clip to the VO** (default) | The VO is shorter than the clip. Most beats. | Re-encode to `vo + 0.5s`: 0.25s lead, 0.25s tail. |
| **B. Extend the VO to fill the clip** | The visual needs its full length to land: a long camera move, the mascot mechanism, a CTA hold. | Add one or two words, or a second short line. Re-render the take and re-measure. |

The allowed micro-buffer is about 0.25s of lead and 0.25s of tail. Anything past
that is dead air, and dead air at the end of a beat is the single most common
tell that an ad was assembled rather than shot.

**If the VO is LONGER than the clip, never speed it up.** No `atempo`. Split the
line across two beats, or re-render the beat at a longer duration. A voice at
1.1x is audible as a voice at 1.1x, and it costs the ad its calm.

**Re-check the caption's vertical position after trimming.** The frame at the new
cut is not the frame that was there before, so a caption band that sat over clean
floor can land on a face or a label. This is why captions are burned AFTER the
trim and the mix, never before: the timings and the safe area both move.

### Concatenate, then mix

```bash
# 1. concat the trimmed beats
printf "file '%s'\n" beat*-trimmed.mp4 > beats.txt
ffmpeg -f concat -safe 0 -i beats.txt -c copy stitched.mp4

# 2. one VO track: the lines, each delayed to its beat's start
#    (adelay is in MILLISECONDS, per channel)
ffmpeg -i beat2-vo.mp3 -af "adelay=5000|5000" vo2-placed.mp3
# …then amix the placed lines into one vo.mp3

# 3. the mix
ffmpeg -i stitched.mp4 -i vo.mp3 -i music.mp3 -filter_complex \
  "[0:a]volume=0.28[clip];[1:a]volume=1.0[vo];[2:a]volume=0.10[bed];\
   [clip][vo][bed]amix=inputs=3:duration=first:dropout_transition=0[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac master.mp4
```

**The clip track is TWO different things and one level cannot serve both.** On a
VO beat the clip audio is ambience and belongs at about 28%. **On a SYNC beat the
clip audio IS the dialogue and belongs at 100%**, alongside the narrator, because
attenuating it is attenuating the only line in the shot.

Measured, and the reason this is stated as a rule: a run mixed at a flat 28%
buried its SYNC beat so far down that an independent judge measured the line at
-36 dB under a caption that said the words the viewer could not hear. The ad had
a caption for a line nobody could hear. That is worse than no line.

So split the clip track before you mix:

```bash
# SYNC beats keep their own audio at full; VO beats drop to ambience level
ffmpeg -i beat1-sync.mp4 -vn -c:a aac sync1.m4a
ffmpeg -i beat2-vo.mp4   -vn -af "volume=0.28" -c:a aac amb2.m4a
# …then place each on the timeline with adelay, exactly as the VO lines are placed
```

**The music bed is set by MEASUREMENT, not by a multiplier.** `volume=0.10` is
-20 dB applied to a source whose own level you did not check, and on a quiet
generated bed that lands somewhere inaudible: measured on a real run at -33 to
-40 dB, which is a bed that was paid for and never heard. Normalize it to a known
level first, then place it a fixed distance under the voice:

```bash
# bring the bed to a known loudness, THEN sit it ~18 dB under the narration
ffmpeg -i music.mp3 -af "loudnorm=I=-30:TP=-2:LRA=7" -c:a aac bed.m4a
```

**Master the finished mix to -16 LUFS and verify it.** Vertical social placements
sit near -16; a mix delivered at -22 plays quiet against everything around it and
the viewer reads that as cheap. Measure, do not assume:

```bash
ffmpeg -i master.mp4 -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:v copy master-loud.mp4
ffmpeg -i master-loud.mp4 -af ebur128=framelog=quiet -f null -    # read Integrated
```

If the narration is fighting something, lower the AMBIENCE track before you raise
the voice. Never lower a SYNC beat's own track to make room.

**If you hear a line twice, the mix is not the problem.** That beat's prompt
carried the narrator's words and Seedance rendered them, and no level will fix
it — re-render the beat with the narration removed from the prompt. The
transcribe-verify step below is what catches this, and it is why that step is not
optional.

### The end card is composited, never rendered

The last beat ends on the real product photograph, dropped over the render. Do
not ask the model to draw the card: asking it to draw a card is asking it to
regenerate a wordmark from scratch, and it will get it wrong. Measured on this
family of runs — `Novoads.ai` came back as `Novads.ai` in every frame with the
label-hold clause present and the key frame spelled correctly, and `Owala` came
back as `ovola`. The model carries a MARK, which is a shape, and destroys TYPE.

```bash
# 1. find the cut to the card (expect a dissolve, not the hard cut you asked for)
ffmpeg -i beat5-trimmed.mp4 -vf "select='gt(scene,0.3)',showinfo" -f null - 2>&1 | grep pts_time
# 2. measure the product's bounding box in BOTH the rendered card and the real
#    photo, then scale and position the real one to match. Matching by eye jumps.
# 3. fade the real card in on the render's own dissolve curve, at full opacity
#    BEFORE the wordmark becomes legible, or the misspelling ghosts through
ffmpeg -i beat5-trimmed.mp4 -loop 1 -i endcard.png -filter_complex \
  "[1:v]scale=<w>:-1,format=rgba,fade=t=in:st=<t0>:d=0.4:alpha=1[card];\
   [0:v][card]overlay=<x>:<y>:enable='gte(t,<t0>)'" \
  -c:a copy beat5-carded.mp4
```

**Match the card's background to the render before you composite it.** A retail
photo shot on near-white dropped onto a warm cream field leaves a visible
rectangle seam, and the seam is the first thing a viewer sees on the last frame.
Sample the render's own background colour and pad the card to it, or key the
photo's white out entirely.

**Do not let the card be a frozen frame in silence.** Hold the beat's own room
tone under it and let the music resolve rather than cut. A warm animated film
that ends on a still, silent packshot ends on the worst-made object in the ad.

**Then read the wordmark at full crop.** Pull the frame, crop the label, look at
it at full size. A contact sheet at thumbnail size is too small to catch a single
missing letter, which is exactly how the first one shipped.

**And review the CLIPS at full size, not on the contact sheet.** Measured on a
run that used this file: a payoff beat rendered TWO cots and TWO babies, and it
survived a contact-sheet review because at thumbnail width the second cot reads
as furniture. The contact sheet is for judging whether beat 3 follows beat 2. It
is not for judging whether beat 3 is correct.

### Verify what it actually says, before it ships

The render can gain or lose a word, and a script that survived in your head is
not evidence. Transcribe the master and read it back against the script:

- If `transcribe_video` is in your tool list, `upload_asset` the master and call
  it. That is the cheap path and it returns timings.
- Otherwise transcribe locally.

Read the transcript against the board. A dropped word in the offer line is worth
a re-render of that beat.

## Gate 8 — captions

Captions are burned SERVER-side, and the source has to be an asset the API can
reach. A local file is not a caption source until it is uploaded.

```
upload_asset  contentType: "video/mp4", sizeBytes: <n>
              → { uploadUrl, assetId, headers } — then HTTP PUT the bytes to
                uploadUrl, sending `headers` VERBATIM. Content-Type and
                Content-Length are signed into the URL, so an omitted or
                library-inferred Content-Type is a 403, not an upload.
      │
      ▼
generate_captions  assetId: <the master>, preset: <a style>
                   → { jobId } — poll get_generation
```

`list_caption_presets` shows the styles and their prices; the basic tier is 0.4
credits per billed minute and the dynamic tier is 0.8. A 25-second ad bills one
minute — the minimum — either way. **Read the list rather than trusting the names
below**; presets are added and the tiers are the product surface, not this file.

### Which preset, and why it is not a free choice

The genre's caption look is a specific thing: heavy sans-serif, white fill, a
thick dark outline, roughly 7% of frame height, sitting in the lower third but
clear of the platform UI, changing per phrase rather than per word. That is what
a hand-burned caption track was built to produce, and it is what to match when
picking from the list.

| You want | Reach for | Note |
|---|---|---|
| The default heavy-outline social look | a basic-tier preset such as `hustle`, `slay` or `flex` | 0.4 cr/min. Fixed styling, which is the point: it will not surprise you |
| Per-phrase emphasis, a punchline that pops | a dynamic-tier preset such as `glide` or `fusion` | 0.8 cr/min. Context-aware animation, worth it on a hook beat |
| A quiet, typographic register | `simple`, `plain` or `lowkey` | Basic tier. Right when the ad is doing the work and the captions should not |

Two things the preset cannot do for you, and both are yours:

- **Placement against the frame.** The preset picks a band; your role D still is
  what leaves the lower third clean for it. Ask for the negative space in the
  still prompt, not in the caption call.
- **The words.** Presets style a transcript; they do not correct one. See the
  gate above.

**Burning locally is the fallback, not the default.** Take it when the transcript
keeps mangling a name you cannot move to the card, or when a brand's caption
styling is contractual. You then own the timing, the font licence and the safe
area. At this length that is five phrases of timing to get right by hand, which
is why it is the fallback.

```
╔═══════════════════════════════════════════════════════════════════════╗
║  CAPTION GATE — BLOCKING. Read every caption against the script.      ║
║  A garbled brand name is a FAILED RUN, not a note in the report.      ║
╚═══════════════════════════════════════════════════════════════════════╝
```

**Captions are TRANSCRIBED, not taken from your script**, so they inherit every
mishearing the transcript does — and brand names are what they mishear. Measured
on real runs: a voice-over saying "Owala FreeSip" was captioned **"Olaf. Free sip
water"**; "bottles" came back "bootles"; and a run whose own transcript read
`NoseFrida 1499` shipped captions reading **"Nos Frida 1499."** — the brand split
in half and the price read as a number nobody says out loud.

**That class of defect blocks the ship.** Do not deliver a master with it and
mention it in the notes; that is what happened to T12 and the caption was the
first thing a viewer read. Compare the burned captions word by word against the
board's script. If a brand name, a product name or a number is wrong in even one
frame, the run is not finished.

Three fixes, in order of preference:

1. **Keep the brand name out of the NARRATION entirely** and put it on screen as
   the composited end card, which is where a wordmark belongs anyway. This is the
   only fix that removes the failure mode rather than catching it.
2. **Keep numbers out of the narration too.** A price spoken aloud is a price the
   transcript writes as digits. Put it on the card.
3. **Burn the captions locally from your own script**, where you own every
   character. The server pass is the cheap default, not the safe one.

Burning captions locally is the fallback, not the default. The server pass reads
the audio you just mixed and places words on it; a local burn means you own the
timing, and at this length the timing is five separate lines.

## Output format

Deliver in this order, no preamble:

1. **PRODUCT READ** — verified facts, buyer language, who actually buys, what you
   will not claim, anything unbuyable.
2. **FIT** — one line confirming Gate 0, or a plain refusal naming a better
   format. If the story fits in 15 seconds, say so and hand off to
   `novoads-pixar-ad`.
3. **ANGLE** — the enemy this ad attacks.
4. **DOCTRINE** — C or D (see `novoads-pixar-ad`), and why.
5. **CAST + STYLE LOCK** — the cast sheet text, including the terse tag, and the
   paragraph that will be pasted into every prompt.
6. **BEAT BOARD** — the table, with the genre role assigned per beat. Word count
   per beat against the two-line ceiling. At least one SYNC beat.
7. **COST** — the `estimate_cost` figures, announced in one line.
8. Then generate: cast sheet, all stills, **stop at the board gate**, clips, VO,
   music, assemble, composite the end card, verify, caption, **read the captions
   against the script before calling it finished**.

## The calls

```
upload_asset      contentType: "image/jpeg" | "video/mp4", sizeBytes: <n>
                  → { uploadUrl, assetId, headers } — PUT the bytes with
                    `headers` VERBATIM

estimate_cost     kind: "image" | "video" | "voiceover" | "music" | "caption"
                  → { credits, balance, sufficient, shortBy?, topUpUrl?,
                      warnings? }   `warnings` is advice; it refuses nothing

generate_image    prompt, aspectRatio: "1:1" | "9:16",
                  referenceAssetIds: [castSheet, previousStill, product?]
                  → { jobId, images: [{ url, expiresInSeconds, assetId }] } —
                    SYNCHRONOUS, the finished image is in the response.
                    `assetId` chains straight into the next call's
                    referenceAssetIds / startImageAssetId — no re-upload.
                    (Absent on deployments older than spec 2.11.0; see Gate 3
                    for that fallback.) Blocks ~45-75s.

generate_video    prompt, durationSeconds: 4-15, aspectRatio: "9:16",
                  startImageAssetId: <this beat's still>, audioEnabled: true
                  → { jobId } — not ready yet

list_voices       → [{ id, name, source, languages?, category? }]
                    Read once. Pick one. Reuse it for every line.
                    Unpaginated and LARGE — measured at 12,566 voices / 6.6 MB.
                    Filter it in your own code; do not print it.

generate_voiceover script, voiceId, language?
                  → { url, assetId, characters, creditsCharged }
                    ALREADY DONE — no jobId to poll. Download `url` now.

generate_music    prompt, instrumental: true
                  → { jobId } — poll, then read audio[] (two takes, one charge)

generate_captions assetId | jobId, preset
                  → { jobId } — poll get_generation

get_generation    jobId → { status, kind, outputUrl?, audio? }

list_generations  limit, kind  → the recovery path when a call times out and you
                    never received the jobId. Reads only, spends nothing.
```

### Worked beat prompt

A finished **beat 4** (the turn) `generate_video` prompt — one action, style lock
included, negatives at the end.
`lib/generation/__tests__/pixar-storyboard-skill-prompts.test.ts` reads this exact
block and runs it through the same rule engine `estimate_cost` lints with, so the
worked example cannot drift into one the lint has real complaints about.

<!-- eval:beat-prompt:start -->
```
Stylized 3D animated feature film look, 9:16. A warm kitchen in late afternoon,
one window low and to the left as the only light source, honey and clay palette,
35mm at chest height, shallow focus band on the counter.

The grandmother sits at the table with the copper kettle in front of her. She
lifts the lid in a single frame and the steam catches the window light across her
face. She says, half to herself: "There you are."

No other speech in this shot. This beat's narration is laid in afterwards from
generate_voiceover, so nobody here speaks it.

The kettle is exactly as shown in the reference: same shape, same colour, same
proportions, same finish. Do not redesign or restyle it. Hold the printed markings
on the base sharp and legible. The woman is a warm, unhurried grandmother in her
seventies in a grey cardigan.

no named or copyrighted animated film characters, no photorealistic humans, no
uncanny faces, no dead eyes
```
<!-- eval:beat-prompt:end -->

## Failure modes

- **The prompt is rejected.** Only content moderation can refuse a render, and it
  answers `content_policy`. There is no rule-id rejection any more, so a refusal
  is not a wording problem to lint your way out of — read what it says.
- **`concurrency_limit` on the sixth clip.** Not an error in your request: five
  generations are already in flight. Wait for one, then submit. This is why the
  waves are five.
- **`voiceover_concurrency_limit`.** A different queue from the renders, and the
  wait is seconds rather than minutes. Your clips are unaffected.
- **The character changed between beats.** The cast sheet was not referenced, or
  a still was chained on the cast sheet alone rather than on the previous still.
  Re-render the stills, not the clips.
- **The grade drifted across beats.** The style lock was reworded. Paste it
  verbatim and re-render the affected stills.
- **Two props in one clause glitch physics.** "Swallows capsules with water"
  rendered capsules on the counter and an empty palm. Split into sequential
  single-action sentences, name the actor in each, and add explicit negatives.
- **A stray reference became a shot.** Every reference passed to a render is a
  shot the model may spend time on; an unneeded product still produced a 0.13s
  flash insert. Pass only what the beat needs.
- **The render gained or lost a word.** Measured: "And wake up, we're rested" for
  a scripted "And wake up rested". Transcribe before shipping; never assume the
  script survived.
- **The wordmark on the rendered product is garbled.** Expected, and the
  labelHold clause does not fully fix it — measured on a run carrying the
  canonical clause verbatim that still rendered "Owala" as "ovola". The model
  carries a MARK (a shape) and destroys TYPE. Do not re-roll hoping for a clean
  one: keep the label small and out of focus in the beats, and composite the real
  product photo over the final beat, which is what the sibling skill's Doctrine C
  does and why.
- **The captions renamed the product.** They are transcribed from the audio, not
  from your script. Blocking, not a note. See Gate 8.
- **Every beat is a VO beat and the ad feels flat.** The doubling rule was
  over-obeyed. At least one beat must be SYNC, and role A is the one that wants
  it: a problem character speaking its own complaint is the genre's opening move.
- **The beats all look like the same shot.** No role was assigned, so every beat
  became a setup shot. Each beat gets its own world and its own shot size, and
  the roles in `references/formulas.md` are what produce that variety for free.
- **The product is in every frame.** It belongs in roles B and D and on the end
  card. In the hook and the mechanism scene it is a distraction from the only
  thing carrying the ad, which is a face.
- **Dead air between beats.** The clips were not trimmed to their narration. Go
  back to Gate 7.
- **A caption for a line nobody can hear.** The SYNC beat's own audio was mixed
  at the ambience level. Its track goes at 100%, not 28%. See Gate 7.
- **The music bed cannot be heard at all.** It was set with a multiplier instead
  of a measurement. Normalize the bed to a known loudness first.
- **The whole ad plays quiet.** It was never mastered. -16 LUFS, verified with
  `ebur128`, not assumed.
- **The render duplicated a prop or a character.** Measured: one cot and one baby
  came back as two. Name the count in the prompt ("exactly one cot, exactly one
  baby") and negate the clone, and review the clip at full size.
- **`insufficient_credits`.** The error carries `required` and `available`.
  Report both and the top-up path. Do not retry.

## Hard rules

- One product per run.
- Stop at the board gate. The operator approves the board before 150 credits of
  clips fire.
- Never invent reviews, ratings, prices, or performance claims.
- Never claim what the reviews contradict.
- Use the real brand and the real packaging from the photo. Never invent a brand
  and never blank-label the product.
- On-screen text is short words and numbers only, never sentences.
- No em dashes in ad copy. Never say "free" — the entry offer is the $1 trial.
- The end card is composited from the real photograph. Never rendered.
- If a fact cannot be verified from the source given, leave it out and say so.
- Transcribe the master before you call it finished.
- Read the burned captions against the script. A garbled brand name blocks the
  ship.
