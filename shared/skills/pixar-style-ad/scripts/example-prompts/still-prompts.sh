#!/usr/bin/env bash
# Example Pixar ad — storyboard prompts (gpt-image-2, 9:16)
# Placeholder brand: swap "yourbrand.com" / "YOUR COMMUNITY" for the real campaign.
# STYLE LOCK and NEGATIVE blocks pasted verbatim from
# content/skills/pixar-style-ad/prompting/storyboard-gpt-image-2.md

STYLE_LOCK='Disney-Pixar 3D animated feature film aesthetic, rendered in a stylized 3D animation style. Soft volumetric golden-hour lighting from a large window, warm cozy color palette of cream, butter yellow, dusty pink, and soft sage. Subsurface scattering on skin, painterly background, shallow depth of field with creamy bokeh. Characters have large expressive eyes with multiple specular catchlights, stylized but believable proportions, smooth simplified hands, soft hair strands with subsurface glow. Rich material detail: waffle-knit fabric weave, ceramic glaze, glass refraction. Slightly desaturated film color grade. Vertical 9:16 composition.'

NEGATIVE='Not photorealistic, not live-action, not anime, not 2D, not cel-shaded, not Studio Ghibli, not flat illustration. No extra fingers, no merged features, no warped product labels, no on-screen text unless explicitly requested.'

# --- BATCH A: 4 pain characters + Brent reveal (no character references) ---

PROMPT_PAIN_CPM="$STYLE_LOCK

Aspect ratio 9:16, extreme close-up macro shot of a chunky 3D rendered dollar amount \"\$47.83\" floating just above a softly glowing tablet-style screen showing rows of a fake ads-manager dashboard. The dollar amount is rendered as a thick stylized 3D object with rounded edges and smooth cream-and-gold surfaces. Embedded in the digits are two oversized Pixar-style eyes with thick lower lashes, pupils oversized, three specular catchlights, one eyebrow raised in a smug arch. A small smug smirk sits below the eyes. The number is slightly tilted back as if lounging victoriously, casting a faint warm glow on the dashboard below. Background is soft-focus rows of out-of-focus fake campaign cards in warm ambient bokeh. The character looks directly at camera with a smirk.

$NEGATIVE"

PROMPT_PAIN_DEAD="$STYLE_LOCK

Aspect ratio 9:16, extreme close-up macro shot of a small 3D-rendered phone-shaped video thumbnail lying flat on a soft dark surface like a tombstone slab. The thumbnail has a blank pale play-button icon at its center. Embedded in the thumbnail's surface are two oversized Pixar-style eyes — both pupils replaced with two cartoon \"X\" marks, thick lower lashes, faint specular catchlights. A small downturned defeated mouth sits below the eyes. A single tear droplet rolls off the lower corner with a soft glint. The thumbnail is slightly cracked along one edge and slumped flat, looking exhausted and beaten. Background is soft-focus warm bokeh suggesting a digital graveyard with faint glowing dust particles drifting. The character looks plaintively at camera.

$NEGATIVE"

PROMPT_PAIN_SLACK="$STYLE_LOCK

Aspect ratio 9:16, extreme close-up macro shot of a single bright red 3D-rendered chat-message notification bubble — the classic rounded-square chat-bubble shape with a small tail. The bubble is pulsing aggressively, slightly stretched as if vibrating with anger. Embedded in the bubble are two oversized Pixar-style angry eyes with thick lower lashes, pupils oversized and constricted, three specular catchlights, brows furrowed downward into a sharp V. A small wide-open mouth sits below the eyes, mid-shout. Faint shockwave ripples emanate softly from the bubble. Background is soft-focus warm bokeh suggesting an out-of-focus laptop screen at night with a single small ambient glow. The character glares directly at camera.

$NEGATIVE"

PROMPT_PAIN_CAPCUT="$STYLE_LOCK

Aspect ratio 9:16, extreme close-up macro shot of a long horizontal video-editor timeline ribbon — a soft 3D-rendered strip made of multiple stacked colored clip blocks in muted red, blue, and green with a small playhead crosshair across it. Embedded near the front of the timeline ribbon are two oversized Pixar-style exhausted eyes with thick lower lashes, half-lidded, pupils oversized, two specular catchlights, dark under-circles visible. A small slightly-open mouth sits below the eyes, panting tired. The timeline ribbon droops in the middle like a sagging rope, two small sweat droplets rendered on top, small simplified wiggly arms hanging limp at its sides. Background is soft-focus warm bokeh of a dim home-office desk at 2am, lit only by a monitor's soft blue glow. The character looks pleadingly at camera.

$NEGATIVE"

PROMPT_BRENT_REVEAL="$STYLE_LOCK

Aspect ratio 9:16, medium head-and-shoulders shot of Brent, a man in his mid-30s with a slight dad-bod, warm undertone skin, three-day stubble, and visible dark circles under his eyes. He sits at a home-office desk in a dim cluttered room, his face suddenly lit by a fresh warm golden glow from a small desk lamp that just clicked on, rim-lighting his hair from camera-right. One white earbud rests in his left ear. He wears a slightly wrinkled gray hoodie over a faded blue tee. He holds a slim silver open laptop angled up toward camera, the screen showing a clean browser tab with the URL \"yourbrand.com\" and a bright community page preview. Both his hands rest on either side of the laptop, five clearly defined fingers each, no extra fingers. His expression is wide-eyed surprised curiosity — eyebrows raised high, lips parted in a small \"oh\", oversized Pixar irises in warm brown with three specular catchlights each, hair messy and slightly disheveled. Background includes a second monitor in soft focus showing a half-paused dashboard, an empty cold-brew cup, scattered sticky notes, and a small potted plant on the windowsill catching pre-dawn light.

$NEGATIVE"

# --- BATCH B: Brent in the community + Brent CTA (use Beat 2 still as reference) ---

PROMPT_COMMUNITY="$STYLE_LOCK

Aspect ratio 9:16, stylized cross-section view of the \"YOUR COMMUNITY\" clubhouse rendered as a warm cozy classroom-clubhouse hybrid — a multi-room interior with hand-painted pale wood floors, sunlit windows with sheer curtains, plants in clay pots, soft warm pendant lamps overhead. Brent (the same mid-30s man with three-day stubble, gray hoodie, messy hair, warm brown oversized Pixar irises with three catchlights each, slight dad-bod from the previous frame) stands grinning in the center foreground, hands relaxed at his sides with five clearly defined fingers each, watching the scene unfold around him. Four small chibi mascot characters populate the rooms around him — each is a 2-3 inch tall ivory-white matte blob with a smooth rounded body, tiny black-dot eyes with one highlight each, soft pink cheeks, and small simple limbs. One mascot writes \"hooks\" on a tiny chalkboard with a quill. One mascot stands at a miniature easel painting a tiny Pixar-style ad frame of Brent's face. One mascot stitches two short film clips together on a tiny editing bench. One mascot loads a tiny rocket-shaped object into a miniature launchpad. Glowing soft golden energy lines connect the mascots in a friendly network, pulsing gently with warmth. Soft warm interior lighting with golden ambient glow.

$NEGATIVE"

PROMPT_BRENT_CTA="$STYLE_LOCK

Aspect ratio 9:16, medium shot of Brent (same character as previous frames — mid-30s man, slight dad-bod, warm undertone skin, three-day stubble groomed cleaner now, messy hair tidied slightly, oversized warm brown Pixar irises with three catchlights each, gray hoodie over faded blue tee). The dark circles under his eyes are gone. He stands in a sunlit home office in clear morning daylight with a warm confident smile, eyes bright and crinkled at the corners. He holds a slim silver phone at chest height with two clearly defined hands, five fingers each, the phone screen turned cleanly toward camera and showing a bright green upward ROAS line graph plus the text \"yourbrand.com\" beneath. Soft window light from camera-left wraps across his face with a gentle backlight rim. Background includes a clean desk with a closed laptop, a small plant in a clay pot, a coffee mug with steam, and a monitor in soft focus showing a small green \"campaign live\" badge. Lower third of frame has empty negative space for caption overlay.

$NEGATIVE"

export STYLE_LOCK NEGATIVE
export PROMPT_PAIN_CPM PROMPT_PAIN_DEAD PROMPT_PAIN_SLACK PROMPT_PAIN_CAPCUT
export PROMPT_BRENT_REVEAL PROMPT_COMMUNITY PROMPT_BRENT_CTA
