# Storyboard frames — `gpt-image-2`

**Use this guide to generate the still-image storyboard before animating with `seedance-2.0`.**

Read [guide.md](guide.md) first for the 4-beat arc, cast sheet, and aesthetic anchors.

## Why `gpt-image-2` for the storyboard

Two traits make it the right choice of the three image models for Pixar-style storyboards:

1. **Strong stylized 3D rendering** — Pixar lookalike without leaking photoreal artifacts.
2. **Reference fidelity** — passing prior approved stills as `referenceAssetIds` holds protagonist identity across beats.

**There is no image-edit path on this API.** A previous version of this guide listed "editable — iterate on a frame by passing the same image back with a refinement instruction" as the third trait. That is not available: `POST /v1/images` has no `source`, no mask, no img2img, on any of the three image models. The honest substitute is a **fresh generation with the previous still passed as a reference** — it is a new image that resembles the old one, not an edit of it, and it is billed as a new image. Say that plainly to the user rather than implying a cheap touch-up.

`nano-banana-pro` is the fallback when a beat needs a ratio outside `gpt-image-2`'s grid (`1:1 4:5 2:3 9:16 16:9 21:9`); it and `reve-2.1` also accept `3:2 3:4 4:3 5:4`. For a 9:16 storyboard the question never comes up.

The call is `POST /v1/images` and it is **synchronous** — the image comes back on the response, there is nothing to poll.

## Universal prompt structure

Every beat prompt has the same five-block structure. Paste them in this order:

```
[STYLE LOCK]      ← identical across all beats
[ASPECT + FRAMING]
[CHARACTER]       ← protagonist OR anthropomorphic problem OR mascot
[SCENE / ACTION]
[NEGATIVE]
```

### STYLE LOCK (paste verbatim into every beat)

```
Disney-Pixar 3D animated feature film aesthetic, rendered in a stylized 3D animation
style. Soft volumetric golden-hour lighting from a large window, warm cozy color
palette of cream, butter yellow, dusty pink, and soft sage. Subsurface scattering
on skin, painterly background, shallow depth of field with creamy bokeh. Characters
have large expressive eyes with multiple specular catchlights, stylized but
believable proportions, smooth simplified hands, soft hair strands with subsurface
glow. Rich material detail: waffle-knit fabric weave, ceramic glaze, glass
refraction. Slightly desaturated film color grade. Vertical 9:16 composition.
```

### NEGATIVE (paste into every beat — `gpt-image-2` accepts these as inline constraints)

```
Not photorealistic, not live-action, not anime, not 2D, not cel-shaded, not Studio
Ghibli, not flat illustration. No extra fingers, no merged features, no warped
product labels, no on-screen text unless explicitly requested.
```

## Beat 1 — anthropomorphized problem character

**Goal:** A close-up macro of the user's pain point, given Pixar eyes and a small mouth. Speaking the user's complaint in first person.

**Formula:**

```
{STYLE LOCK}

Aspect ratio 9:16, extreme close-up macro shot of {{PAIN_POINT_OBJECT}} resting on
{{SURFACE/LOCATION}}. Embedded in the {{OBJECT}} are two oversized Pixar-style eyes
with thick lower lashes and {{EYE_EXPRESSION}} expression — pupils oversized,
{{2-3 specular highlights}} catchlights, slight tears welling at the corners. A small
downturned mouth sits below the eyes. The {{OBJECT}} has a slight slump or {{POSTURE}}
posture that reinforces its sadness. Background is soft-focus {{SETTING}} with warm
ambient bokeh. The character looks directly at camera.

{NEGATIVE}
```

**Variable examples:**

| Pain point object | Surface/Location | Eye expression | Posture |
|-------------------|------------------|----------------|---------|
| clump of dark tangled hair | stainless steel shower drain with soap bubbles | exhausted, half-lidded | drooping over the drain edge |
| cracked, flaking fingernail | a pale fingertip with subtle skin texture | tearful, brows pinched inward | slightly bent and chipped |
| a worn, dingy pillow | rumpled white linen sheets with morning light | grumpy, brows furrowed | sagging in the middle |
| a tired plant leaf | terracotta pot on a kitchen counter | weary, eyes half-closed | wilted, drooping downward |
| a heap of laundry | wicker basket overflowing | overwhelmed, eyes wide and frazzled | precariously stacked |

**Worked example (drain hair):**

```
[STYLE LOCK]

Aspect ratio 9:16, extreme close-up macro shot of a dark tangled clump of long brown
hair resting in a stainless steel shower drain with small soap bubbles around it.
Embedded in the hair clump are two oversized Pixar-style eyes with thick lower
lashes, pupils oversized, three specular catchlights, slight tears welling at the
corners — an exhausted, half-lidded expression. A small downturned mouth sits below
the eyes. The hair clump droops over the drain edge, slumped and defeated. Background
is soft-focus white shower tile with warm ambient bokeh. The character looks directly
at camera.

[NEGATIVE]
```

## Beat 2 — protagonist reveal

**Goal:** Cut to the Pixar-style human hero in a sunlit interior, holding the product, with a delighted/curious expression.

**Formula:**

```
{STYLE LOCK}

Aspect ratio 9:16, medium head-and-shoulders shot of {{PROTAGONIST}} standing in
{{INTERIOR_SETTING}}. Soft window light from camera-left wraps across her face,
backlight rim through {{LIGHT_SOURCE}}. She holds {{PRODUCT}} at chest height with
{{HAND_POSITION}}, looking down at it with {{EXPRESSION}}, lips slightly parted. Her
hair is {{HAIR_DESCRIPTION}}, eyes are {{EYE_COLOR}} with oversized Pixar irises and
multiple highlights. She wears {{OUTFIT}}. Background includes {{BACKGROUND_PROPS}}
in soft focus.

{NEGATIVE}
```

**Variable examples:**

| Slot | Examples |
|------|----------|
| `PROTAGONIST` | "a young woman in her late 20s, warm undertone skin with light freckles across nose bridge" |
| `INTERIOR_SETTING` | "a sunlit bedroom with sheer linen curtains and exposed beam ceiling" / "a bright kitchen with pale oak cabinets" |
| `LIGHT_SOURCE` | "sheer curtains" / "a south-facing window" / "morning kitchen window" |
| `PRODUCT` | full description of the user's product packaging — color, shape, label text |
| `HAND_POSITION` | "both hands cradling it gently" / "one hand around the pouch, the other thumb on the label" |
| `EXPRESSION` | "delighted curiosity, eyes wide" / "gentle surprise, eyebrows raised" |
| `HAIR_DESCRIPTION` | "ash-brown low bun with face-framing strands" / "honey blonde messy bun" |
| `OUTFIT` | "a cream waffle-knit robe over a fitted tank, gold thin necklace" |
| `BACKGROUND_PROPS` | "a leafy potted monstera, an unmade linen bed, soft morning light" |

**Reference input:** When generating Beat 2, pass the **approved cast-sheet hero portrait** (if you generated one earlier) in `referenceAssetIds`. This locks identity. Upload it once with `POST /v1/uploads` and reuse the returned `assetId` on every later beat — it is durable and never needs re-uploading.

## Beat 3 — mascot mechanism-of-action

**Goal:** Stylized cross-section of the relevant body interior with chibi blob mascots actively doing the mechanism the product claims.

**Formula:**

```
{STYLE LOCK}

Aspect ratio 9:16, stylized cross-section view of {{INTERIOR_STRUCTURE}}, rendered as
a soft painterly landscape of {{TEXTURES}}. Three to five small chibi mascot
characters populate the scene — each is a 2-3 inch tall ivory-white matte blob with
a smooth rounded body, tiny black-dot eyes with one highlight each, soft pink cheeks,
and small simple limbs. They are {{MASCOT_ACTION}}. Glowing golden energy lines /
{{ENERGY_VISUAL}} connect the mascots and trace through the structure, indicating
the active mechanism. Soft warm interior lighting with golden ambient glow.

{NEGATIVE}
```

**Variable examples (by mechanism):**

| Product claim | Interior structure | Mascot action | Energy visual |
|---------------|--------------------|----------------|---------------|
| Builds collagen | cross-section of skin layers — epidermis, dermis, with hair follicles and collagen fibers | mascots pulling and weaving glowing golden collagen strands taut | golden energy lines linking strand nodes |
| Strengthens nails | inside a nail bed with keratin layers, capillaries below | mascots stacking and stitching keratin scales into a smooth shield | sparkling crystalline keratin layers forming |
| Supports gut | cross-section of intestinal villi with friendly microbiome | mascots high-fiving and tending tiny gardens between villi | soft pink-green energy waves rolling through |
| Soothes joints | inside a knee joint with cartilage and synovial fluid | mascots gently smoothing cartilage with tiny tools, applying a glowing gel | swirling teal cushioning halo around the joint |
| Hydrates hair | cross-section of a single hair shaft with cuticle scales | mascots smoothing down lifted cuticle scales like roof shingles | iridescent moisture droplets soaking in |

**Worked example (collagen):**

```
[STYLE LOCK]

Aspect ratio 9:16, stylized cross-section view of human skin layers — pale peachy
epidermis on top, dermis below filled with woven golden collagen fibers, a hair
follicle descending on the right. Rendered as a soft painterly landscape of warm
ivory and gold tones. Four small chibi mascot characters populate the scene — each
is a 2-3 inch tall ivory-white matte blob with a smooth rounded body, tiny black-dot
eyes with one highlight each, soft pink cheeks, and small simple limbs. They are
pulling glowing golden collagen strands taut and weaving them into a tight lattice,
one mascot on each anchor point. Glowing golden energy lines connect the mascots
along the collagen network, pulsing softly. Soft warm interior lighting with golden
ambient glow.

[NEGATIVE]
```

## Beat 4 — CTA frame

**Goal:** Protagonist (same identity as Beat 2) now holds one or two product packages facing camera, confident smile, ready for caption overlay.

**Formula:**

```
{STYLE LOCK}

Aspect ratio 9:16, medium shot of {{PROTAGONIST}} (same character as previous frames)
standing in {{SAME_INTERIOR_SETTING}}, now facing camera directly with a warm
confident smile, eyes bright. She holds {{ONE OR TWO product packages}} at chest
height, one in each hand, labels turned cleanly toward camera. Soft window light
from camera-left, gentle backlight rim. Background includes {{BACKGROUND_PROPS}} in
soft focus. Lower third of frame has empty negative space {{for caption overlay}}.

{NEGATIVE}
```

The "empty negative space in the lower third" hint helps `gpt-image-2` leave room for the burned-in caption you'll add in post.

## Cross-beat continuity rules

1. **Always pass the prior approved frame in `referenceAssetIds`** when generating the next beat featuring the same character. `gpt-image-2` honors references strongly for style and identity. **The cap is 4 references per call**, images only, order preserved and addressable in the prompt as `@Image1`…`@Image4`. Four is plenty here — a beat needs the hero portrait and at most one or two prior stills. If you ever do run up against the cap, keep a rolling window anchored on the hero (`[hero, N-1, N-2, N-3]`) and never feed a *drifted* frame forward: one bad still in the window teaches every later beat the drift.
2. **Keep the STYLE LOCK block byte-identical** across all beats. Don't paraphrase — it's a style anchor.
3. **Reuse exact phrasing** for hair, outfit, eye color, freckles, skin tone in every beat that includes the protagonist. Don't say "ash-brown low bun" in beat 2 and "brown hair tied back" in beat 4 — those produce different characters.
4. **Lock product packaging description** once in the cast sheet; copy-paste the same description into beats 2 and 4.
5. **Generate beats sequentially**, not in parallel. You need to approve each one before passing it as the reference to the next.

## Image QA checklist (per beat)

Before sending a still to Seedance for animation, verify:

- [ ] Character has the **right number of fingers** on each visible hand (5 each, including thumb)
- [ ] **Eyes are aligned** (both pupils centered, no lazy-eye drift)
- [ ] **Product label** reads correctly and matches the brand reference
- [ ] **Same protagonist** across beats — same hair, eye color, freckles, outfit
- [ ] **No burned-in text** unless requested
- [ ] **Aspect ratio is 9:16** — send `aspectRatio: "9:16"` explicitly; `gpt-image-2` defaults to `1:1`
- [ ] **Lower third has clean negative space** if this frame will get a caption overlay

Apply the 2-retry cap per beat: after an approved batch, regenerate a defective still with a corrected prompt without re-confirming, at most twice. **Each retry is billed** — report the extra credits at the end. If the third attempt still fails, stop, show the best attempt, and ask the user.

## When the user has a brand character sheet already

If they provide an existing Pixar-style hero image, skip the protagonist-generation step. **Check `references/` at the repo root first** — that is where product shots, actor stills and style boards live, and it is gitignored, so the files are the user's own. Upload the hero once, then pass its `assetId` in `referenceAssetIds` on Beat 2 and Beat 4. Beat 1 and Beat 3 don't need the hero reference (different subjects).
