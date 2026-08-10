# Craft doctrine — the rules that belong to no single skill

Three rules keep getting restated in whichever skill needs them next, and a
restatement is where they go wrong.

Measured 2026-08-06: `novoads-claymation-ad` was found carrying the
mix recipe **exactly as it read before it was fixed** in the skill it was ported
from — the fix and the copy were merged the same day, and the regression guard
was scoped to the file being fixed, so it could not see the copy. Nothing failed.
Everything was green.

So this file exists, and it holds one position per rule. **Read it before writing
a QA step, a mix, or a trim into any skill.** If your skill needs one of these,
point at it; do not restate it.

---

## 1. Transcribe-verify — check the burn, not the transcript API

**A reference asset pins the LABEL. Nothing pins the AUDIO. They fail
independently, so a perfect wordmark is not evidence about the voice, and
`succeeded` is not evidence the ad says what was approved.**

Measured across three clones of one source, product pinned as a reference image:

| Script | A | B | C |
|---|---|---|---|
| `Magnesi-Om` | "Magnesium" | "Magnesium" | "Magneum" |
| `L-theanine` | — | **"L-Thiamine"** | — |

Every glyph of the on-screen label was correct in all three. The brand name was
never once spoken as written, and B substituted **a different compound** into a
script that had already passed the dialogue gate. Digits survived ("310
milligrams" was correct). All three returned `succeeded` and charged.

**A coined or hyphenated brand name is the high-risk case** — the model resolves
it to the nearest ordinary word. Spell it phonetically inside the quoted line and
re-check. A clone that says the wrong brand name is a failed render, not a note
in the report.

### And the captions are a second, separate check

Captions are **transcribed from the audio, not taken from your script**, so they
inherit every mishearing — and brand names are what they mishear. Measured:
"Owala FreeSip" captioned as **"Olaf. Free sip water"**; a run whose transcript
read `NoseFrida 1499` shipped captions reading **"Nos Frida 1499."**

**The check is the burned frames, not the transcript you already have.**
`POST /v1/captions` returns a new MP4 and nothing else — no caption text, no SRT,
and `GET /generations/{jobId}` on a caption job carries neither. So there is no
API answer to read: you look at the video. A clean transcript of the *audio* is
not evidence the *burn* is clean, because the burn ran its own transcription.

A garbled brand name in even one frame blocks the ship.

**Full procedure:** each skill's own QA step — the call differs by path
(`POST /v1/transcripts` hosted, Whisper locally). The rule above is what does
not differ.

---

## 2. The per-beat mix — a SYNC beat's audio is dialogue, not ambience

**The clip track is two different things and one level cannot serve both.**

- On a **VO beat** the clip's own audio is ambience. About **28%**.
- On a **SYNC beat** the clip's own audio **IS the dialogue**. **100%**, alongside
  the narrator, because attenuating it attenuates the only line in the shot.

A run mixed at a flat 28% buried its SYNC beat so far down that an independent
judge measured the line at **-36 dB**, under a caption spelling out words the
viewer could not hear. An ad with a caption for a line nobody can hear is worse
than an ad with no line.

Two corollaries that travel with it:

- **The music bed is set by MEASUREMENT, not by a multiplier.** `volume=0.10` is
  -20 dB applied to a source whose own level you never checked; measured on a real
  run that landed at -33 to -40 dB — a bed that was paid for and never heard.
  Normalize it to a known loudness first, then place it a fixed distance under the
  voice.
- **Master to -16 LUFS and verify it.** Vertical social sits near -16; a mix
  delivered at -22 plays quiet against everything around it and the viewer reads
  that as cheap.

If the narration is fighting something, lower the AMBIENCE track before raising
the voice. **Never lower a SYNC beat's own track to make room.**

**Canonical home:** `skills/novoads-pixar-ad/SKILL.md`, Gate 7 — the
filter graphs, the split-before-you-mix recipe and the `loudnorm`/`ebur128`
commands. It is stated there rather than here on purpose; see *Why two of these
point* below.

---

## 3. No dead space — trim every beat to its narration

Dead air at the end of a beat is **the single most common tell** that an ad was
assembled from clips rather than shot. A generated clip is as long as the model
made it; the line inside it is as long as the line. The difference is silence,
and it lands at the seam where the viewer is already deciding whether to keep
watching.

**Trim each clip to its narration plus about 0.5 seconds** before concatenating.
Or extend the VO to fill the shot. Never **`atempo`** a long line to fit — that
warps the voice audibly, and it is the repair that looks equivalent and is not.

Two consequences worth knowing before you hit them:

- **Trim before captioning.** Timestamps taken from a dead-space master drift the
  moment the source is tightened. Re-encode each beat, re-concat, then transcribe.
- **Re-check any caption's vertical position after trimming.** The frame at the
  new cut is not the frame that was there.

This is an EDITING rule about assembled beats. It is not the same as the
model-level dead-air budget in `skills/novoads-api/SKILL.md` — that one is about
Seedance spending part of a single render on silence, which is a draw you reserve
against, not something you trim.

**Canonical home:** `skills/novoads-pixar-ad/SKILL.md`, § Trim to the
narration — the ffmpeg recipe.

---

## Why two of these point instead of restating

Rules 2 and 3 are stated in full inside `novoads-pixar-ad` rather than
here, and that is deliberate rather than lazy.

That skill is **published into two repos**. It is canonical in `novoads.ai` under
`.claude/skills/`, mirrored here, and a CI job blob-SHA-compares every file. This
`shared/` directory does not exist on the canonical side, so a manifest-mapped
skill cannot link to this file without pointing at something half its readers do
not have. Moving those rules here would make them *less* reachable, not more.

What actually stops them drifting is not a pointer, it is a check:
`lib/generation/__tests__/skill-craft-doctrine.test.ts` in `novoads.ai` is scoped
to the **doctrine**, not to a skill. It discovers every skill file that takes a
position on a rule and holds all of them to it, so a new skill restating the flat
mix recipe fails on the commit that adds it. That test is the reason rule 2 has
one home; this file is the reason you can find it.

Rule 1 is stated in full here because its consumers are spread across skills that
live only in this repo, and no single one of them owns it.

---

## Using this file

Skills that point here today:

| Skill | Rule |
|---|---|
| `skills/clone-video-ad` | 1 — transcribe-verify (step 12.3) |
| `skills/novoads-api` | 1 — transcribe-verify (the QA step) |
| `shared/skills/caption-video` | 3 — trim before captioning |
| `skills/novoads-pixar-ad` | 2, 3 — canonical home for both |
| `skills/novoads-claymation-ad` | 2, 3 — points at its Pixar sibling |

When you add a skill that needs one of these, add a one-line pointer to this file
and a row above. Do not paste the rule in. The copy is the failure mode.
