# Image-ad ecosystem — overview for AI coding agents

**One-line summary:** three skills + one shared prompt library let you generate standalone Meta image-ad creatives on any of the Novoads image models — ChatGPT Image 2, Nano Banana Pro, Reve 2.1 — and reverse-engineer existing ads into reusable templates. Output is image files. Meta-side uploading is handled by a *separate* `meta-ad-builder` skill, not by these.

**Read this whole file** at the start of any session where the user mentions: making an ad, image creative, ad library, gpt-image-2, ChatGPT Image 2, Nano Banana, Nano Banana Pro, Reve, cloning an ad, reverse-engineering an ad, or anything in the `T1–T39` template namespace.

---

## What's in the family

```
┌─────────────────────────────────────────────────────────────────┐
│ SHARED BRAIN (no SKILL.md — referenced by all 3 skills below)   │
│ shared/skills/image-ad-prompting/                               │
│   ├ prompting/prompt-library.md   37 validated templates        │
│   ├ prompting/template-format.md  entry-format skeleton         │
│   ├ prompting/safety-suffixes.md  3 always-on prompt guards     │
│   └ OVERVIEW.md                   this file                     │
├─────────────────────────────────────────────────────────────────┤
│ GENERATOR SKILLS (produce image files)                          │
│ skills/chatgpt-image-ad/         → gpt-image-2                  │
│ skills/nano-banana-image-ad/     → nano-banana-pro              │
├─────────────────────────────────────────────────────────────────┤
│ TEMPLATE-CREATION SKILL (reverse-engineer an ad → library)      │
│ skills/image-ad-clone/   asks which model to validate against,  │
│                          routes to the matching generator, and  │
│                          can cross-check on a third (reve-2.1). │
└─────────────────────────────────────────────────────────────────┘
```

`reve-2.1` has no generator skill of its own. It is reachable from `image-ad-clone`'s
Phase-1 chooser and by naming it directly on a call — it exists as a second opinion when a
template renders wrong on both of the other two, not as a default route.

---

## One endpoint, three models

Every image in this ecosystem comes from the same call: **`POST /v1/images`**, which is
**synchronous** — the response already carries the finished images. There is no job to poll
and no asset to wait on. `Authorization: Bearer $NOVOADS_API_KEY`. The full contract lives in
the `novoads-api` skill's `reference.md`; this table is only what differs *between the models*.

| | `gpt-image-2` | `nano-banana-pro` | `reve-2.1` |
|---|---|---|---|
| **Default?** | yes — omit `model` and this renders | no | no |
| **Prompt cap** | model cap | model cap | model cap |
| **Reference images** | up to 4 `referenceAssetIds` | up to 4 | up to 4 |
| **Aspect ratios** | `1:1` `4:5` `2:3` `9:16` `16:9` `21:9` | those plus `3:2` `3:4` `4:3` `5:4` | same 10 as Nano Banana Pro |
| **Images per call** | `numImages` 1–4 | 1–4 | 1–4 |

Notes that bite:

- **`aspectRatio` defaults to `1:1`** on every model. For a Stories/Reels creative you must
  say `9:16` — the default is not the ad you wanted.
- **The three ratios the template library actually uses (`1:1`, `2:3`, `9:16`) are supported
  on all three models**, so no template needs a fallback-and-crop. Only bespoke prompts can
  hit the gap: `3:2`, `3:4`, `4:3` and `5:4` exist on Nano Banana Pro and Reve but **not** on
  gpt-image-2.
- **`numImages` is one call, not N calls.** Ask for 4 variants by sending `numImages: 4` and
  the response comes back with four images in `images[]`. Do not fan out four parallel
  requests — that burns four of your five concurrency slots for no benefit.
- **Every image is charged**, so `numImages` multiplies the price. It is the single biggest
  lever on what a run costs.
- **Reference images are uploaded once and reused.** `POST /v1/uploads` returns a durable
  `assetId`; pass those in `referenceAssetIds`. The id keeps working across later calls — you
  do not re-upload per variant.

**There is no image-editing path on this API.** No `source`, no mask, no inpainting, no
img2img — not on any of the three models. A request to "change the background of this image"
or "fix the text in this one" cannot be served by editing; it is a fresh generation with the
original passed as a reference. Say that plainly rather than pretending to edit.

---

## Decision tree — which skill to use

The user's first sentence usually tells you which way to branch.

**Step 1: Are they generating from scratch, or cloning an existing ad image?**

- **Generating** → one of the two generator skills.
- **Cloning** (they shared an ad image and want it as a reusable prompt) → the single
  `image-ad-clone` skill (it asks which model to validate against at Phase 1).

**Step 2: Pick the model.**

Skim what the user wants and match it to model strengths:

| The user wants... | Pick |
|---|---|
| Apple Notes lists, fake search results, chat threads, ChatGPT-style conversations, iOS dialogs, Slack snapshots, comparison tables, Hinge cards, iMessage, calendar UI, weather forecast UI, magazine cover, anything **typography-heavy or UI-mimicry** | **`chatgpt-image-ad`** |
| Handheld whiteboard signs, napkin handwritten testimonials, sticky-note + product flatlays, letter-board signs, lifestyle scenes, OOH/transit photography, scratch-off tickets, **photoreal / material-rich / multi-reference** ads | **`nano-banana-image-ad`** |
| A second opinion after both of the above rendered the same template wrong, or a deliberately different look on a concept that already works | **`reve-2.1`**, via `image-ad-clone`'s chooser or by naming the model on the call |
| Ambiguous? | Look up the matching template in `prompting/prompt-library.md` and read its `Model notes:` block — every entry recommends one. |

**Step 3: For cloning, the `image-ad-clone` skill handles all three models.** At Phase 1 it
asks the user (or auto-detects from the reference's typography-vs-photo balance) which model
to validate against. It then routes through the matching generator's
`scripts/generate_image.py`. Phase 8 optionally cross-validates on a second model so the
resulting library entry has `Model notes:` for more than one.

---

## The shared prompt library

`prompting/prompt-library.md` ships with **37 validated full prompts** (tags T1 through T39,
with intentional gaps at T16/T22 from the source Uni1 lineage). Every entry has:

- **When to use** — positioning fit
- **Aspect ratio** — recommended canvas
- **Reference image** — what to upload and pass in `referenceAssetIds`
- **Variables** — the placeholder schema
- **Template prompt** — the full validated prompt in a fenced code block (drop-in usable; swap brand-specifics per the Variables block)
- **Model notes** — per-model behavior on this template (which model is preferred, where each struggles)

The library is **the first place to look** when the user describes an ad concept. Match their
brief to a template, fill the variables, and ship — that's the fast path. The bespoke-prompt
path (writing from scratch) is the fallback when nothing matches.

---

## Always-on safety suffixes

Every generator script auto-appends three guards to the prompt:

1. **`NO_CHROME_SUFFIX`** — strips iOS chrome, Sponsored badges, engagement rows, link-card footers, story chrome, tab bars. The output is the *standalone* image creative, not a screenshot of how it displays in-feed. Override with `--allow-chrome` only when the ad concept genuinely needs simulated platform chrome (rare).
2. **`SAFE_ZONE_SUFFIX`** — keeps text + focal subjects inside the central 84% of the canvas. Eliminates clipped headlines.
3. **`GLYPH_SAFETY_SUFFIX`** — forbids emoji and unicode glyphs inside body-text blocks (chat bubbles, comment threads, ChatGPT responses); enforces the exact count of conversation elements.

Full text in `prompting/safety-suffixes.md`. **Do not silently disable these** — they fix
recurring rendering failures across every modern image model. If you need to disable one for a
specific run, use `--allow-chrome` or `--no-safe-zone` flags and document why.

The suffixes count against the model's 4,000-character prompt cap, and together they run to
roughly 1,500. A template prompt that is already near the cap can push the final prompt over
it — the failure is a `400` naming the limit, before anything is charged.

---

## Standard workflow — generate an ad from a brief

This is the workflow inside any chat session where the user wants to make an ad:

1. **Match to a library template.** Read `prompting/prompt-library.md`. If their brief maps
   onto an existing template, use it. If not, plan a fresh prompt.

2. **Pick the model.** Read the template's `Model notes:`. If more than one works, default to
   `chatgpt-image-ad` for typography-heavy templates and `nano-banana-image-ad` for
   photoreal/lifestyle templates.

3. **Fill placeholders.** Swap `{brand.name}`, `{brand.color_primary}`, `{ad.headline}`, etc.
   with the user's brand. Show the rewritten prompt and ask for approval.

4. **Price it with a live estimate, and show the user.** `POST /v1/estimates` with
   `{"kind":"image","model":"<model>","prompt":"<final prompt>","numImages":<N>}`. It is free,
   it returns `credits`, `balance` and `sufficient`, and **it is the only place a price may
   come from** — never quote a credit cost from memory, from a log file, or from
   `MASTER_CONTEXT.md`. Wait for explicit confirmation before generating. If `sufficient` is
   false, say so and stop; the response carries `shortBy` and `topUpUrl`.

   The same call **lints the prompt for free** and returns anything it finds in `warnings`.
   Post-2.0.0 those are advice, not blockers — nothing there stops the generation. Read them
   anyway: each one names the problem and ships the fix inline (they are the reason a prompt
   says "sunlit kitchen, soft window light from camera-left" instead of "cinematic kitchen").
   A clean estimate omits the `warnings` key entirely.

   Two things the estimate will not catch: it prices `numImages` but never sees
   `aspectRatio` or `referenceAssetIds` (sending either is a `400 Unrecognized key`), and it
   does not run moderation — so a prompt the estimate blessed can still come back `422`.

5. **Generate.** Run the matching `scripts/generate_image.py` with `--prompt`,
   `--aspect-ratio`, `--n`, and reference images. The response is synchronous: finished images,
   with `creditsCharged` telling you what it actually cost.

6. **Visual QA.** Read each output image. Check for: garbled small text (most common
   gpt-image-2 failure), extra fingers / wrong limb count (Nano Banana failure), wordmark
   drift, wrong text count, UI proportion drift. Regenerate with a revised prompt if defective
   (cap 2 retries). **Each retry is a fresh charge** — there is no free re-roll — so report the
   extra credits at the end of the run.

7. **Hand off the image paths** to the user's separate `meta-ad-builder` skill — that's the
   skill that uploads to Meta, writes ad copy, clones page/ad-set/CTA, etc. The image-ad skills
   produce *images*, not *ads*.

---

## Standard workflow — clone an existing ad into a reusable template

Use the `image-ad-clone` skill (single model-agnostic skill — Phase 1 asks which generator to
validate against, Phase 8 optionally cross-validates on another).

The 10-phase workflow lives in `shared/skills/image-ad-clone/prompting/guide.md`. Key checkpoints:

- **Phase 2 (visual analysis)** — describe the reference structurally, separating brand-specific content from format/structure.
- **Phase 4-5 (generate + iterate)** — round-trip the prompt through the matching generator until structure is faithful. Cap at 4 iterations.
- **Phase 6 (generalize)** — replace `[BRAND]`-marked elements with `{placeholder}` variables.
- **Phase 7 (test with different brand)** — fill placeholders for a different brand and regenerate. If structure breaks, refine the placeholder set.
- **Phase 8 (cross-model validation, optional)** — round-trip the same template through another model and document deltas in the `Model notes:` block.
- **Phase 9-10 (document + save)** — append a new T<n> entry to `prompting/prompt-library.md` with the required structure.

A clone run is many generations — the iteration cap alone allows four, plus the
different-brand test and any cross-model check. **Estimate the whole run up front, not each
call**, so the user approves a total rather than being asked six times.

The library is append-only. New templates start at T40 (next available number after the
seeded T1-T39).

---

## What this ecosystem does NOT do

Surface these limits clearly when the user asks for anything outside scope:

- **Meta upload.** Different skill — `meta-ad-builder` (in `shared/skills/meta-ad-builder/`). The image-ad skills produce image files; the ad-builder skill handles cloning page/ad-set/CTA, writing copy, and uploading as paused ads.
- **Ad copy writing.** Different skill (the user's `meta-ad-builder` or equivalent handles body/headline).
- **Video, carousel, DCO ads.** Image only. For video, the `novoads-api` skill owns the video models.
- **Editing or retouching an existing image.** No model on this API has an edit or inpainting path. The nearest honest answer is a fresh generation with the original uploaded as a reference — say that, don't imply an edit.
- **Cross-model in one run.** If the user wants gpt-image-2 AND nano-banana-pro variants of the same prompt, run the generators sequentially. Each generator skill is locked to one model.

---

## Files this ecosystem owns

```
skills/
  chatgpt-image-ad/
    SKILL.md
    scripts/generate_image.py
  nano-banana-image-ad/
    SKILL.md
    scripts/generate_image.py
  image-ad-clone/
    SKILL.md

shared/skills/
  image-ad-prompting/      ← shared brain (this folder)
    OVERVIEW.md            ← this file
    prompting/
      prompt-library.md
      template-format.md
      safety-suffixes.md
  chatgpt-image-ad/
    prompting/guide.md
  nano-banana-image-ad/
    prompting/guide.md
  image-ad-clone/
    prompting/guide.md
```

---

## For human onboarding

If you're a human reading this for the first time:
- See [prompt-library.md](prompting/prompt-library.md) for the 37 validated ad templates.
- See [chatgpt-image-ad/SKILL.md](../../../skills/chatgpt-image-ad/SKILL.md) and [nano-banana-image-ad/SKILL.md](../../../skills/nano-banana-image-ad/SKILL.md) for hands-on usage.
- The `image-ad-clone` skill is for *making new templates*, not generating ads — only invoke it when you want to add to the library.
