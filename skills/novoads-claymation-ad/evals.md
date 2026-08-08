# novoads-claymation-ad evals

This skill runs `novoads-pixar-ad`'s pipeline, so
[that skill's evals](../novoads-pixar-ad/evals.md) apply here unchanged —
E1 through E13, the board gate, the character hold, the seams, the mix, the
transcript and the timeout recovery. Run them against a clay run too; the
failure modes do not care which style lock is in the prompt.

What follows is what is NOT covered there: the port's own check, and the four
failures that belong to clay and to nothing else.

The machine-checkable half runs in CI as
`lib/generation/__tests__/claymation-storyboard-skill-prompts.test.ts`, which
reads the worked beat prompt out of `SKILL.md` and runs it through the same rule
engine `POST /v1/estimates` lints with. Everything below is human, against a real
run, before publishing a new version.

---

### C0 — it runs on `.env` and `curl`, with no MCP connector configured

**Why:** this skill was MCP-native until the REST port, and entry B was the part
most tied to the connector — it called `analyze_ad`, which does not exist on
this API at all. A reader with a key and no connector must still be able to
recreate a found clay ad, or entry B is a documented path to a dead end.

**Check:** human, in a fresh clone with `NOVOADS_API_KEY` in `.env` and **no**
Novoads MCP server registered. Run **both entries**: from a product, and from a
reference video. Confirm each reaches the board gate on `curl`, `ffmpeg` and
Whisper alone. Then grep the skill and its `references/` for the old tool names
(`analyze_ad`, `estimate_cost`, `generate_image`, `generate_video`,
`upload_asset`, `list_voices`, `generate_voiceover`, `generate_music`,
`generate_captions`, `get_generation`, `list_generations`, `transcribe_video`):
zero hits outside a sentence that is explicitly about the MCP surface.

---

### C1 — the clay is still clay in the last frame

**Why:** the most common failure in this genre and the one a still gate cannot
catch. The video models smooth plasticine into 3D plastic over the length of a
clip, so a beat that passed as an image can end glossy. That is what the
anti-smoothing negatives and the material-detail block are for.

**Check:** human, per beat. Pull the LAST frame of every clip, not the first.
Matte surface, visible thumbprints, tool marks, no ray-traced highlights. A beat
that ends in plastic is re-rendered with the material block thickened and "clay
texture held to the last frame" added, not re-rolled unchanged.

---

### C2 — the eyes never went wet

**Why:** a Pixar-style multi-catchlight eye is the single tell that leaks between
these two sibling skills, and it converts a sculpt into a 3D render wearing a
clay texture. It needs the negative and the material line, both, not either.

**Check:** human. Crop a face at full size on two beats. One soft highlight per
eye, matte orb, no wet shine.

---

### C3 — the transformation beat is the same person

**Why:** "weeks later" described on a whole face produces a different character,
which reads as a lie and breaks continuity in one shot — in the exact beat the
arc is built on.

**Check:** human. Put beat 1 and beat 7 side by side at full size. One named
thing has changed; the face, the hair, the wardrobe and the sculpt are otherwise
identical.

---

### C4 — a mouth moves at least once

**Why:** this genre is narrator-led, so the doubling rule is easy to over-obey
into an ad of narration over silent faces. Beat 3 is the SYNC beat; on the 5-beat
short it is beat 6.

**Check:** human. Watch the cut and confirm at least one character speaks on
screen, in the clip's own audio, at full level rather than at the ambience level.
