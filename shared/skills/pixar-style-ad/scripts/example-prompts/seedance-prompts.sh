#!/bin/bash
# Example Seedance 2.0 prompts for each of the 7 beats. SFX-only audio, NO spoken dialogue
# Placeholder brand: swap "YOUR COMMUNITY" for the real campaign.
# (ElevenLabs VO will be layered in post). Style words avoid Seedance forbidden
# list: no "cinematic", "professional", "stunning", "8k", "studio", "perfect".

STYLE_TAIL='Disney-Pixar 3D animated feature film aesthetic, soft volumetric warm lighting, subsurface scattering, painterly soft-focus background, shallow depth of field, warm cozy color palette. No live-action footage, no photorealistic faces, no anime style, no 2D cel-shaded look, no extra fingers, no morphing limbs, no warped product labels, no on-screen text, no subtitles, no captions, no spoken dialogue, no voiceover speech, no human speech.'

# ---------- BEAT 1: 4 pain characters (silent, 4s each, SFX-only) ----------

PROMPT_PAIN_CPM="3D animated film aesthetic, image-to-video animation of the character in the start frame.

Subject: A chunky cream-and-gold 3D-rendered dollar amount with embedded oversized Pixar eyes, smug arched eyebrow, and a small smirk, floating just above a soft glowing ads-dashboard tablet.

Action (0-1.5s): The dollar amount blinks slowly with a self-satisfied half-lid, eyebrows arching higher. (1.5-3s): It tilts back another inch with a smug little wobble, leaning into the camera in a relaxed lounging pose. (3-4s): It opens its mouth into a wider smirk, gives a tiny celebratory shimmy as if growing slightly larger, and a faint dollar-sign sparkle glints off its surface.

Camera: Locked extreme close-up macro, very subtle handheld micro-drift, no zoom or pan.

Style: $STYLE_TAIL

Audio: A short metallic cha-ching coin sound at 1.5s, faint smug chuckle-grunt at 3s (wordless), soft ambient electronic dashboard hum throughout.

Constraints: The character must remain visually unchanged from the start frame — same digit shape, same eye placement, same surface texture. No new text, no labels appearing on screen."

PROMPT_PAIN_DEAD="3D animated film aesthetic, image-to-video animation of the character in the start frame.

Subject: A coral-pink phone-shaped video thumbnail lying flat on a dark stone slab with X-cross eyes, a downturned mouth, a tear droplet rolling off the corner, and a crack along one edge, set in a graveyard of glowing tombstone-shaped thumbnails.

Action (0-1.5s): The thumbnail twitches once weakly, the crack along its edge widens a tiny bit, and one X-cross eye droops slightly lower than the other. (1.5-3s): The tear droplet finishes rolling off its lower corner with a soft glint. (3-4s): The thumbnail slumps another fraction lower against the slab, the play button at its center fades a shade dimmer, faint glowing dust drifts past from background.

Camera: Locked extreme close-up macro, very subtle handheld micro-drift, no zoom or pan.

Style: $STYLE_TAIL

Audio: A single soft tear-drop ping at 1.5s, faint mournful low ambient drone, distant echoey wind in the background.

Constraints: The character must remain visually unchanged from the start frame — same shape, same X-eye placement, same crack, same coral color. No live-action, no morphing into a different object."

PROMPT_PAIN_SLACK="3D animated film aesthetic, image-to-video animation of the character in the start frame.

Subject: A coral-pink rounded chat-message notification bubble with embedded oversized worried Pixar eyes, pinched eyebrows, and a small frowning mouth, with soft sparkles floating around it.

Action (0-1.5s): The bubble pulses gently outward and back, sparkles drifting slowly around it. (1.5-3s): The bubble's eyebrows pinch tighter together, the small frown deepens, and the bubble itself stretches slightly upward as if pleading. (3-4s): The bubble vibrates with a short three-pulse impatient buzz, the sparkles brighten, and it tilts very slightly forward toward camera.

Camera: Locked extreme close-up macro, very subtle handheld micro-drift, no zoom or pan.

Style: $STYLE_TAIL

Audio: A soft Slack-style ping at 0.5s, a second ping at 2.0s, a third more insistent ping at 3.5s, faint soft laptop-fan room tone in the background.

Constraints: The character must remain visually unchanged from the start frame — same coral color, same eye placement, same bubble shape. No new text, no message previews appearing."

PROMPT_PAIN_CAPCUT="3D animated film aesthetic, image-to-video animation of the character in the start frame.

Subject: A long horizontal video-editor timeline ribbon with embedded oversized exhausted Pixar eyes (half-lidded, with dark under-circles), a slightly-open panting mouth, sweat droplets on top, and small wiggly arms hanging limp, sagging in the middle on a dim home-office desk at 2am.

Action (0-1.5s): The timeline ribbon's eyes blink slowly and heavily, its small mouth pants in shallow rhythm. (1.5-3s): The middle of the ribbon sags another inch lower with a small whimpering motion, one of its limp little arms gives a feeble wiggle as if trying to lift itself, a sweat droplet beads up and slides down one side. (3-4s): The eyes droop further, threatening to close, the ribbon's overall pose collapses a touch more into a defeated slump.

Camera: Locked extreme close-up macro, very subtle handheld micro-drift, no zoom or pan.

Style: $STYLE_TAIL

Audio: A soft exhausted sigh-exhale at 1.5s (wordless), a faint sweat-droplet plip at 2.5s, ambient distant late-night room tone with a soft mechanical keyboard click in the deep background.

Constraints: The character must remain visually unchanged from the start frame — same ribbon colors, same eye placement, same arm positions, same desk setting. No new on-screen edits, no caption text appearing."

# ---------- BEAT 2: Brent reveal (8s, SFX-only) ----------

PROMPT_BRENT_REVEAL="3D animated film aesthetic, image-to-video animation of the protagonist in the start frame.

Subject: Brent, a mid-30s man with messy brown hair, three-day stubble, heavy dark circles under his eyes, gray hoodie over a faded blue tee, one white earbud in his left ear, sitting at his cluttered home-office desk holding a slim silver laptop angled toward camera. The laptop screen shows a stylized yellow Pixar-rendered community page reading 'MAKE ADS WITH AI' for 'YOUR COMMUNITY' with a green JOIN pill and several community tiles, exactly as in the start frame.

Action (0-2s): Brent's eyes widen further as a fresh warm golden glow from his desk lamp brightens across his face, his eyebrows raise higher, his lips remain parted in a small 'oh' of surprise. (2-5s): He blinks once slowly in disbelief, tilts his head a small fraction to the right while studying the laptop screen, and his eyes flick once down toward the screen and back up to camera. (5-8s): A small dawning smile begins at the corner of his mouth, he lets out a tiny chuckle-breath of recognition, and gives one small slow head-shake of incredulous delight.

Camera: Locked medium head-and-shoulders 9:16, very subtle handheld breathing motion. No dolly, no pan.

Style: $STYLE_TAIL

Audio: A soft warm desk-lamp click-on at 0.5s, faint laptop-fan hum, a small wordless chuckle-breath exhale at 6s (no speech, no words), distant pre-dawn ambient room tone with a faint single bird call outside.

Constraints: The protagonist must remain visually unchanged from the start frame — same face, same stubble pattern, same hoodie, same earbud, same five-finger hands on either side of the laptop. The laptop screen content must remain visually unchanged. No new text appearing on screen, no morphing of the UI."

# ---------- BEAT 3: Community mechanism (12s, SFX-only) ----------

PROMPT_COMMUNITY="3D animated film aesthetic, image-to-video animation of the scene in the start frame.

Subject: A warm Pixar-rendered cross-section of the 'YOUR COMMUNITY' clubhouse interior with a yellow 'YOUR COMMUNITY' banner across the top. Brent (mid-30s, gray hoodie, messy brown hair, three-day stubble, warm brown Pixar eyes) stands grinning in the center foreground. Four small ivory-white chibi mascot characters around him are mid-action: one at a chalkboard labeled 'Hooks' with a quill, one painting a tiny Pixar ad frame on an easel, one stitching film clips on an edit bench labeled 'EDIT', one loading a tiny rocket on a 'LAUNCH PAD'. Glowing golden energy lines connect them.

Action (0-3s): Each mascot performs one small primary motion in coordinated rhythm — the quill-mascot scribbles a fresh word on the chalkboard, the easel-mascot adds a small brush stroke, the edit-mascot snips and joins two clips together with a small flick, the launch-mascot pats the rocket on its nose with a tiny cheer-pose. Brent watches with delight, his grin widening. (3-7s): The glowing golden energy lines pulse brighter and travel between the mascots in a soft wave from left to right, lighting up the room and reflecting in Brent's wide eyes. The mascots glance up at Brent and at each other, briefly waving. (7-12s): The mascots resume their tasks, this time slightly faster and more confident; Brent gives a small thumbs-up gesture toward one of them with his right hand; the camera pushes in very slowly toward the center of the action while soft golden particles drift through the air.

Camera: Slow gentle dolly-in toward Brent in the center of the action, 9:16 vertical framing, maintaining focus on the scene throughout.

Style: $STYLE_TAIL

Audio: Soft magical sparkle sounds matching each mascot motion (quill scratch at 0.5s, easel brush at 1.5s, edit-bench clip-snip at 2.5s, rocket-pat soft squeak at 3.5s), gentle warm ambient hum, a low energy-line whoosh swelling between 4s and 6s, soft cozy room tone throughout. No human voices, no spoken words.

Constraints: Brent must remain visually unchanged from the start frame — same face, same hoodie, same hands with five fingers each. The mascots must remain visually consistent (same ivory color, same proportions, same eye style). No morphing, no extra mascot limbs, no horror anatomy, no new written text appearing."

# ---------- BEAT 4: Brent CTA (8s, SFX-only) ----------

PROMPT_BRENT_CTA="3D animated film aesthetic, image-to-video animation of the protagonist in the start frame.

Subject: Brent (same character as before — mid-30s, messy brown hair, three-day stubble groomed cleaner, gray hoodie over faded blue tee, warm brown Pixar eyes) standing in a sunlit home office with morning daylight, holding a slim silver phone at chest height with two five-finger hands. The phone screen shows a bright green upward 'ROAS 4.37x' line graph rendered in soft Pixar UI style.

Action (0-2s): Brent gives a small warm confident smile, eyes brightening, a small happy head tilt to the left. (2-5s): He rotates the phone a touch more cleanly toward camera, the green ROAS line on the screen subtly animates one small additional notch upward, his smile widens slightly. (5-8s): He gives a small relaxed nod of satisfaction, a final tiny chuckle-breath, and his eyes crinkle warmly at the corners.

Camera: Locked medium shot 9:16, gentle handheld breathing motion. No dolly or zoom.

Style: $STYLE_TAIL

Audio: A soft phone notification chime at 3s, a faint cash-register kerr-chunk at 5s, gentle morning room tone with faint birdsong outside. No human voices, no spoken words.

Constraints: Brent must remain visually identical to the start frame — same hair, same stubble, same hoodie, same five-finger hands. The phone screen must remain visually clean and unchanged in geometry. Lower third of frame must remain clean for post-production caption overlay. No new on-screen text, no morphing labels."

export PROMPT_PAIN_CPM PROMPT_PAIN_DEAD PROMPT_PAIN_SLACK PROMPT_PAIN_CAPCUT
export PROMPT_BRENT_REVEAL PROMPT_COMMUNITY PROMPT_BRENT_CTA
