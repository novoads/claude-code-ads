# Master context (project + agents)

**Purpose:** One place for humans and AI agents to capture **decisions**, **brand voice**, **API quirks**, and **what we learned** while using this repo.

## How agents should use this file

- **At the start of substantive work:** Read this file for project-specific context that is not in the skill.
- **After meaningful changes:** Append a new **dated entry** under [Changelog](#changelog) (Decision / What changed / Why).
- **If fields are empty:** Offer to populate them — ask the user once and write the values back.

## Brand (optional)

_Edit or replace with your real brand blocks. A starter template lives at `skills/novoads-api/prompting/brand-voice-starter.md`._

- **Tone:**
- **Audience:**
- **Words to use / avoid:**

## Reference images

Drop reference images into the `references/` folder at the repo root:
- `references/influencers/` — face/body photos to recreate as AI people
- `references/products/` — product photos for showcase workflows
- `references/aesthetics/` — mood boards, lighting references, style inspiration

The agent checks this folder when composing prompts. (If the API in this repo requires hosted URLs rather than local file uploads, also fill in your hosting strategy in the API-specific section below.)

## Universal prompting principles

These apply across all generative-image and generative-video APIs.

### UGC realism

- **Imperfection block (camera):** Every UGC image/video prompt must include camera imperfections: motion blur, overexposure, grain, lens distortion, off-center framing, soft focus. Without this, output looks too polished.
- **Skin realism block (mandatory):** Include 3–4 subtle skin cues inline with character description: "visible pores, slight unevenness in skin tone, minor undereye shadows, hint of shine from natural oils." Do NOT use: acne, pimples, breakouts, blemishes, redness. Goal is "real person, not retouched" — not "person with skin problems."
- **Reference image order:** character hero first (strongest identity signal), then product, then style refs.

### Influencer / character recreation

- Two-step flow: (1) generate a still image with the reference image as input, (2) show user for approval, (3) only then generate video using the approved still as the start frame / reference.
- Never skip the approval step — video is expensive, stills are cheap to iterate.

### Image QA

- Visually review still images after generation (hands, fingers, limbs, face, merged objects, artifacts).
- If defective, regenerate with refined prompt — up to **2 retries** (3 attempts total).
- QA retries skip a second credit confirmation but still bill credits.

### Video prompting

- **No subtitles, no captions, no text overlays** — append this clause to every prompt; many video models burn captions in by default.
- **Human motion cues are mandatory** for person-on-screen videos: 3–4 cues per prompt (breaking eye contact, head tilts, weight shifts, grip adjustments). Without these, subjects look like frozen mannequins.

## Meta ad deployment

Used by the **`meta-ad-builder`** shared skill (`shared/skills/meta-ad-builder/`) — publishes
finished creatives as Meta (Facebook/Instagram) ads. Fill in your account IDs once; the skill
reads them so you don't paste them every run. These are account identifiers, not secrets, but
the file is gitignored either way.

- **Default ad account** (`META_AD_ACCOUNT_ID`):
- **Facebook Page ID** (`META_PAGE_ID`):
- **Instagram user ID** (`META_IG_USER_ID`):
- **Meta Pixel ID** (`META_PIXEL_ID`):
- **Default destination URL / offer link:**
- **Default ad set(s) to deploy into** (name → ID):
- **Default CTA type** (e.g. `SIGN_UP`, `LEARN_MORE`):

The access token itself (`META_ACCESS_TOKEN`) lives in `.env`, never here. Every ad the skill
creates is **PAUSED** — review and un-pause in Meta Ads Manager.



## Project snapshot — Novoads

- **API base:** `https://api.novoads.ai/v1` (see `.env.example`). `NOVOADS_BASE_URL` overrides the host only — callers append `/v1/…`.
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`. The key is `novo_` plus 64 hex, created at <https://novoads.ai/dashboard/settings?tab=api>; no quoting needed in `.env`. Check it with `./scripts/check-novoads-env.sh`.
- **Skill:** `.claude/skills/novoads-api/` and `.cursor/skills/novoads-api/` (sync from `skills/novoads-api/` via `scripts/sync-skill.sh`).
- **Spec:** <https://api.novoads.ai/v1/openapi.json> is the authority whenever a file in this repo disagrees with it.

## My workspace

- **Default product ID:** _(auto-populated after first `GET /v1/products` call)_
- **Default product name:** _(auto-populated)_

## Credit costs

**This file holds no prices, deliberately.** Every credit number comes from a live
`POST /v1/estimates` call in the session that is about to spend, shown to you and approved
before anything is generated — that call is free and also validates the prompt. Do not add a
rate table here: a stored number goes stale silently and a quote that disagrees with the
invoice is worse than no quote. `GET /v1/models` carries the live schedules if you want to
compare models.

## API learnings — Novoads

**Empty on purpose. Your sessions fill it in.**

Endpoints, fields, limits, status codes, timings, and error branching are already documented in
the skill — `skills/novoads-api/SKILL.md` and its `reference.md`, with
<https://api.novoads.ai/v1/openapi.json> as the authority above both. Do not copy any of that
here: a second copy drifts, and then two files disagree about what the API does.

What belongs here is what the skill cannot know — things learned while generating *your* ads:
a prompt phrasing that keeps failing for your product category, a duration that reads better for
your audience than the table suggests, a reference image that consistently produces a good start
frame. Add them as dated bullets, and if a note contradicts the skill, say so explicitly and
verify against the live spec before trusting it.

Never record a price here. See "Credit costs" above.

## Changelog

Dated entries, newest last — Decision / What changed / Why.
