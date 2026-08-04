# Novoads — AI Video & Image Ad Skill Pack

Make AI video ads and static image ads from **Claude Code** or **Cursor**, against your own
[Novoads](https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack)
account. The agent does the mechanical part — upload, price, generate, poll, download — and the
skills carry the part that decides whether the render is any good: the prompt.

Eight models are live on the API. Five make video (**Seedance 2.0**, **Seedance 2.0 Mini**,
**Omni Flash**, **Veo 3.1**, **Sora 2**) and three make stills (**GPT Image 2**, **Nano Banana
Pro**, **Reve 2.1**). On top of them this repo ships five Seedance prompt formulas, a 37-template
static-ad library, Pixar and claymation pipelines, YouTube thumbnails, caption burn-in, and a Meta
publishing step.

Two rules run through the whole pack, and they are the reason it is safe to point an agent at a
billing API:

- **No price is ever quoted from memory.** Every credit number comes from a live
  `POST /v1/estimates` call in the session that is about to spend, shown to you and approved first.
  That call is free, and there is no rate table anywhere in this repo to fall back on.
- **The spoken line is approved on its own**, before the cost gate. Seedance renders the dialogue
  and the lip-sync in the same call, so the sentence in the prompt is the sentence in the finished
  ad. Approving a concept is not approving a sentence, and approving a sentence is not approving
  a spend.

Need an account? The entry offer is a **$1 trial** — not a free tier, and it can generate through
the API like any other live plan:
**[novoads.ai](https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack)**

## Prerequisites

The core workflow — upload a photo, price it, generate a video or an image, poll, download — is
plain HTTP. **`curl` and `jq` are enough**, and both are already on most machines. Everything else
is per-workflow:

| Tool | Needed for | Install (macOS) |
|---|---|---|
| **`curl` + `jq`** | Everything on the API: uploads, estimates, generation, polling, download | preinstalled / `brew install jq` |
| **Python 3.10+** | The image-ad callers (`chatgpt-image-ad`, `nano-banana-image-ad`, `image-ad-clone`) — **stdlib only, nothing to `pip install`** | preinstalled or `brew install python@3.12` |
| **`ffmpeg`** | Pixar and claymation stitching, caption overlay, frame extraction in `analyze-video` | `brew install ffmpeg` |
| **`whisper`** | Transcription for `caption-video` and `analyze-video` | `pip install openai-whisper` |
| **Node.js** | Caption burn-in (`npx hyperframes`, run on demand) | `brew install node` |
| **`meta-ad-builder` deps** | Publishing to the Meta Marketing API | `pip install -r shared/skills/meta-ad-builder/scripts/requirements.txt` |

Linux: `apt install curl jq ffmpeg nodejs python3`. Windows: WSL2 — the shell scripts assume bash.

## Get started (5 minutes)

### 1. Clone

```bash
git clone https://github.com/novohq-ai/novoads-claude-code-v2.git
cd novoads-claude-code-v2
```

### 2. Run setup

```bash
./scripts/setup.sh
```

It creates `.env` (chmod 600), asks for your API key, and **validates the key against
`GET /v1/models` before writing it to disk** — a key that has never been probed is the most
expensive thing to debug later. It then copies `MASTER_CONTEXT.template.md` to your personal
`MASTER_CONTEXT.md`, syncs the skills, and runs the connectivity check.

Your key looks like `novo_` followed by 64 hex characters. Create one at
**[novoads.ai/dashboard/settings?tab=api](https://novoads.ai/dashboard/settings?tab=api)** — it is
shown once, at creation, and cannot be retrieved afterwards.

Setup never hangs an agent: with no TTY (or with `--non-interactive`) it prompts for nothing,
prepares the workspace, prints the one step left for a human, and exits 0.

Re-check connectivity any time with `./scripts/check-novoads-env.sh`. It tells you *which* failure
you have: a `401` is a bad or revoked key, a `403` with `plan_required` is a good key on an account
without API access. Different problems, different fixes.

### 3. Open in your editor

**Claude Code:** open the folder. A `SessionStart` hook syncs the skills and prints a banner —
which skills are installed, whether `.env` and `MASTER_CONTEXT.md` are set up, and the reminder
that prices come from `/v1/estimates`.

**Cursor:** open the folder. The same skills are exposed at `.cursor/skills/`.

### 4. Ask for something

Drop a product photo into `references/products/` and say what you want. The agent picks the route,
reads the matching prompt formula, prices it, confirms the dialogue, and generates.

## What you can make

### 🎬 Seedance 2.0 video — the flagship

Any integer duration from **4 to 15 seconds**, six aspect ratios, native audio and lip-sync
rendered in the same call. Start from one photo (`startImageAssetId` animates it as the first
frame) or composite up to **nine** reference images (`referenceAssetIds`, addressed in the prompt
as `@Image1`…`@ImageN`). Those are two separate modes — a request carrying both is rejected.

Five prompt formulas ship, each with a worked example that has been priced live:

| Formula | For | File |
|---|---|---|
| **UGC selfie review** | A person talking to camera about the product | [seedance-2-ugc.md](skills/novoads-api/prompting/prompt-library/seedance-2-ugc.md) |
| **Premium reveal** | Dark void, text narrative, no person | [seedance-2-premium-reveal.md](skills/novoads-api/prompting/prompt-library/seedance-2-premium-reveal.md) |
| **Product hero** | Splash, mist, light rays, slow rotation | [seedance-2-product-hero.md](skills/novoads-api/prompting/prompt-library/seedance-2-product-hero.md) |
| **Studio lookbook** | Polished multi-look editorial with voiceover | [seedance-2-studio-lookbook.md](skills/novoads-api/prompting/prompt-library/seedance-2-studio-lookbook.md) |
| **Feature walkthrough** | Fast-paced demo cuts, one person held across clips | [seedance-2-feature-walkthrough.md](skills/novoads-api/prompting/prompt-library/seedance-2-feature-walkthrough.md) |

> "Make a 12-second Seedance UGC video — woman in a kitchen holding the product, says she stopped
> buying the drugstore version"

The platform guide — grids, the two reference modes, prompt length by shot count, the mini-draft
tier — is [seedance-2.md](skills/novoads-api/prompting/prompt-library/seedance-2.md).

**Draft on Mini first.** `seedance-2.0-mini` takes the same grid and the same formulas at half the
price and comes back in 2–3 minutes. Upload once, draft on Mini, re-price naming the final tier,
render once. The agent asks which tier you want before the first Seedance call of a workflow.

### 🎬 Omni Flash — fast vertical clips

> "Give me a fast 8-second vertical clip of the product on a kitchen counter, no dialogue"

`omni-flash` is the only model here with a **20,000-character** prompt ceiling, which is what makes
long structured briefs possible. Its grids are narrower than Seedance's — durations `4/6/8/10`,
aspect ratios `9:16` or `16:9` only — and it takes **no** reference images. Prompt craft in
[shared/skills/gemini-omni-flash/prompting/guide.md](shared/skills/gemini-omni-flash/prompting/guide.md),
which is Google DeepMind's own guide with the parts this API cannot reach marked as such.

### 🖼️ Stills — people, products, characters

`POST /v1/images` is **synchronous**: the finished images come back in the response body, so there
is nothing to poll. Up to 4 images per call, up to 4 reference images each.

- **`gpt-image-2`** — heavy typography and mimicked UI.
- **`nano-banana-pro`** — photoreal people and products in a scene; holds a character's identity
  tightest across a reference batch.
- **`reve-2.1`** — a different look on the same still, or a second opinion.

> "Create a new AI influencer — 22-year-old with freckles, golden-hour kitchen lighting"
> · "UGC selfie of Sofia holding the product in her bedroom"
> · "Recreate this influencer's look from this photo"

Character sheets, influencer recreation, UGC product selfies and product-showcase stills live in
[skills/novoads-api/prompting/prompt-library/](skills/novoads-api/prompting/prompt-library/). The
standard flow is still-first: generate the still, get it approved, then animate the approved frame
on Seedance. Stills are cheap to iterate; video is not.

Every returned image gets a **QA look** — hands, fingers, faces, merged objects, garbled text. A
defect is regenerated with a corrected prompt, capped at 2 retries, and the extra credits are
reported at the end.

### 📸 Static Meta image ads (37-template library)

> "Make me an Apple Notes-style ad for my product" · "Generate a Forbes editorial ad" ·
> "Clone this comparison-table ad as a template"

A three-skill family over a shared library of **37 validated prompt templates** — Apple Notes
lists, editorial hero, fake Google search, comparison tables, sticky-note flatlays, Slack threads,
ChatGPT-conversation ads, iMessage screenshots, magazine covers, billboards, museum exhibits,
weather UI, scratch-off tickets, founder letters, dating-app cards, and more.

- **[`chatgpt-image-ad`](skills/chatgpt-image-ad/SKILL.md)** — typography / UI mimicry, on `gpt-image-2`
- **[`nano-banana-image-ad`](skills/nano-banana-image-ad/SKILL.md)** — photoreal / lifestyle / multi-reference, on `nano-banana-pro`
- **[`image-ad-clone`](skills/image-ad-clone/SKILL.md)** — reverse-engineer an existing ad into a new library entry; asks which backend to validate against at Phase 1 (`gpt-image-2`, `nano-banana-pro` or `reve-2.1`) and can cross-validate against another at Phase 8

**Read [shared/skills/image-ad-prompting/OVERVIEW.md](shared/skills/image-ad-prompting/OVERVIEW.md)
first** — it holds the decision tree, the per-backend aspect-ratio matrix, and the standard
generate / clone workflows. Output is image files; publishing is the separate `meta-ad-builder`
skill.

### 🎞️ Multi-step animated pipelines

| Pipeline | Shape | Guide |
|---|---|---|
| **Pixar-style 3D ad** | Lock a cast sheet → `gpt-image-2` storyboard stills (each beat references the previous for identity lock) → `seedance-2.0` + `startImageAssetId` per beat → ffmpeg stitch | [pixar-style-ad](shared/skills/pixar-style-ad/prompting/guide.md) · runnable scripts in [scripts/](shared/skills/pixar-style-ad/scripts/) |
| **Claymation / Aardman ad** | Same backbone over an 8-beat narrator arc, clay textures, optional `fps=12,fps=24` stop-motion judder | [claymation-ad](shared/skills/claymation-ad/prompting/guide.md) |
| **YouTube thumbnails** | 5 CTR formulas (peace-sign branding, real-vs-AI, terminal flow, reaction shock, before/after split) on `nano-banana-pro`, likeness locked with face references | [generate-youtube-thumbnail](skills/generate-youtube-thumbnail/SKILL.md) |
| **Burn captions onto an MP4** | Whisper transcript → reading phrases → captions-only HTML over magenta → ffmpeg chroma-key overlay. **Out of band — no API call, no credits** | [caption-video](shared/skills/caption-video/prompting/guide.md) |
| **Overlay b-roll cutaways on a finished MP4** | Whisper transcript → EDL of overlay windows (`file`, `start`, `end`, `covers`) → validate → ffmpeg overlay → verify duration, audio and every window. Base audio runs untouched, duration never changes. **Local ffmpeg, no credits** (the cutaway clips themselves are generated first, and those are charged) | [broll-overlay](shared/skills/broll-overlay/SKILL.md) |

### 🔄 Reverse-engineer existing creative

> "Reverse-engineer this video into a reusable Seedance template" ·
> "Clone this video ad for our product"

- **[analyze-video](skills/novoads-api/prompting/analyze-video/SKILL.md)** — pulls frames with
  ffmpeg and the transcript with Whisper *locally*, reads out the beat structure, and writes a new
  parameterized formula into the prompt library. Nothing is charged until an optional test render.
- **[clone-ad](skills/novoads-api/prompting/clone-ad/SKILL.md)** — the same local analysis, but the
  output is a rendered clip, so both gates apply. There is no video-to-video on this API: a source
  longer than 15s becomes a series of clips held together by passing the same reference images to
  each one.

### 📤 Publish as a paused Meta ad

> "Publish this approved creative as a paused Meta ad"

[`meta-ad-builder`](shared/skills/meta-ad-builder/SKILL.md) takes a finished file and uploads it
through the Meta Marketing API. **Every ad is created PAUSED** — you launch it yourself in Ads
Manager. It can also pull your top-spending ads and competitor ads to inform copy. Auth via the
`META_*` rows in `.env`.

## What it costs

There is **no price list in this repo**, on purpose. A stored rate goes stale silently, and a quote
that disagrees with the invoice is worse than no quote at all.

Instead, before anything is generated, the agent calls `POST /v1/estimates` and shows you what came
back: the credits for that exact configuration, your balance, and — when the batch would exceed the
balance — how short you are and where to top up. You approve the number, then it generates.

The estimate is free, and what it does *not* do is worth stating:

- **Nothing on this API reads your prompt for quality.** Not the estimate, not `POST /v1/videos`,
  not `POST /v1/images`. A weak prompt is priced, charged and rendered exactly like a strong one.
  The prompt libraries in this repo are the entire quality gate — which is why the skills treat
  them as mandatory reading rather than reference material.
- **It refuses malformed requests for free**, including a prompt over the named model's character
  ceiling.
- **Its quote cannot disagree with the invoice**, with one caveat worth knowing: the estimate skips
  moderation, which the paid call runs, so a prompt priced clean can still be refused as
  `content_policy`. Nothing is charged when it is.

`GET /v1/models` carries each model's live grid and its price for a representative output if you
want to compare models yourself.

## Supported models

All eight are live on `api.novoads.ai/v1`. Grids below come from `GET /v1/models` — that endpoint
is the current answer, this table is a map.

| Model | Kind | Duration | Aspect ratios | Prompt cap | Notes |
|---|---|---|---|---|---|
| **`seedance-2.0`** | Video | 4–15s, any integer | `16:9` `9:16` `1:1` `4:3` `3:4` `21:9` | 4,000 chars | The flagship. Native audio + lip-sync, mutable with `audioEnabled: false`. `startImageAssetId` **or** up to 9 `referenceAssetIds`, never both. Fleet range 3–8 min; one render here came back in ~171s. |
| **`seedance-2.0-mini`** | Video | 4–15s, any integer | same as above | 4,000 chars | Same grid, same formulas, half the price, back in 2–3 min. The drafting tier. |
| **`omni-flash`** | Video | `4` `6` `8` `10` | `9:16` `16:9` | **20,000 chars** | No reference images. Defaults to `9:16` and 8s. Best for long structured briefs and silent b-roll. |
| **`veo-3.1`** | Video | `4` `6` `8` | `9:16` `16:9` | 4,000 chars | Start frame only, no reference images. Defaults to 8s — the one model that defaults to its own ceiling. Shot-evolution prompting. Unmeasured here: no render time on record. |
| **`sora-2`** | Video | `4` `8` `12` | `9:16` `16:9` | 4,000 chars | Start frame only, no reference images. Measured with **no leading silence** where Seedance front-loads 3–5s, and ~123s to render. Coarse grid: no 6s, no 10s. |
| **`gpt-image-2`** | Image | — | `1:1` `4:5` `2:3` `9:16` `16:9` `21:9` | 4,000 chars | Typography and UI mimicry. Synchronous. |
| **`nano-banana-pro`** | Image | — | 10 ratios incl. `3:2` `4:3` `5:4` | 4,000 chars | Photoreal people and products; strongest identity lock across references. |
| **`reve-2.1`** | Image | — | same 10 ratios | 4,000 chars | Third look / second opinion on a still. |

Image calls take `numImages` 1–4. The `referenceAssetIds` cap is **per model** — 8 on `reve-2.1`,
4 on `gpt-image-2` and `nano-banana-pro` — and images have no start-frame concept. Videos are
asynchronous (`202` + `jobId`, poll to a terminal status); images come back in the response body.

`audioEnabled` is a Seedance-only boolean (default `true`); send `false` for a clip meant to run
silent. The other three video models are strict and `400` on it, as does `POST /v1/estimates` for
every model — it does not move the price.

**Kling 3 is not on this API and is not queued for it.** Its prompt library sits in
`skills/novoads-api/prompting/prompt-library/` as craft only; the agent will say so plainly rather
than routing you somewhere else. There is likewise no b-roll or scene endpoint — a silent
`omni-flash` or Seedance clip is the b-roll path.

## What's in the box

| Path | What it does |
|---|---|
| [`skills/novoads-api/`](skills/novoads-api/) | **The spine.** [`SKILL.md`](skills/novoads-api/SKILL.md) is the router: decision tree, the two gates, the full call sequence, error branching. [`reference.md`](skills/novoads-api/reference.md) is every endpoint, field, limit and status code, plus the dated discrepancy list. Carries the Seedance formulas, the image/character libraries, and the `analyze-video` + `clone-ad` sub-workflows. |
| [`skills/chatgpt-image-ad/`](skills/chatgpt-image-ad/) | Static Meta image-ad creatives on `gpt-image-2` (typography / UI mimicry). |
| [`skills/nano-banana-image-ad/`](skills/nano-banana-image-ad/) | Static Meta image-ad creatives on `nano-banana-pro` (photoreal / lifestyle). |
| [`skills/image-ad-clone/`](skills/image-ad-clone/) | Turn an existing ad image into a reusable library entry. Backend chosen at Phase 1. |
| [`skills/generate-youtube-thumbnail/`](skills/generate-youtube-thumbnail/) | 5 CTR-tested thumbnail formulas with bounded batch generation. |
| [`shared/skills/image-ad-prompting/`](shared/skills/image-ad-prompting/) | Shared brain for the image-ad family: [`OVERVIEW.md`](shared/skills/image-ad-prompting/OVERVIEW.md), the [37-template library](shared/skills/image-ad-prompting/prompting/prompt-library.md), safety suffixes, entry format. |
| [`shared/skills/pixar-style-ad/`](shared/skills/pixar-style-ad/) | 8-beat mascot ad: `gpt-image-2` storyboard → `seedance-2.0` i2v → ffmpeg. Includes runnable scripts. |
| [`shared/skills/claymation-ad/`](shared/skills/claymation-ad/) | Aardman-style clay narrative on the same backbone. |
| [`shared/skills/gemini-omni-flash/`](shared/skills/gemini-omni-flash/) | Prompting guide for `omni-flash`, scoped to what this API actually exposes. |
| [`shared/skills/caption-video/`](shared/skills/caption-video/) | Out-of-band caption burn-in for any finished MP4. |
| [`shared/skills/broll-overlay/`](shared/skills/broll-overlay/) | Overlay b-roll cutaways on a finished MP4 — local ffmpeg, no credits. Validates the EDL, renders atomically, and verifies duration, audio and every window. |
| [`shared/skills/meta-ad-builder/`](shared/skills/meta-ad-builder/) | Publish finished creatives as paused Meta ads. |
| [`scripts/setup.sh`](scripts/setup.sh) | One-time setup. Validates the key before writing it. |
| [`scripts/check-novoads-env.sh`](scripts/check-novoads-env.sh) | Connectivity check that names the failure. |
| [`scripts/sync-skill.sh`](scripts/sync-skill.sh) | Copies skill edits into `.claude/skills/` and `.cursor/skills/`. |
| [`shared/scripts/check-context.sh`](shared/scripts/check-context.sh) | The `SessionStart` banner. |
| [`MASTER_CONTEXT.template.md`](MASTER_CONTEXT.template.md) | Template for your workspace memory. Setup copies it to `MASTER_CONTEXT.md` (gitignored). |
| `references/` | Your reference images — gitignored, local only. |
| [`logs/`](logs/README.md) | Per-call audit log. Latency, config, `creditsCharged` after the fact. **Observability, never a pricing source.** |
| [`AGENTS.md`](AGENTS.md) | Entry point for non-Claude assistants. |

## Reference images

Drop images into `references/` and the agent finds them before asking you for anything:

- **`references/influencers/`** — faces and bodies to recreate, plus saved character sheets
- **`references/products/`** — product photos for showcase and UGC workflows
- **`references/aesthetics/`** — mood boards, lighting and style references

The folder is gitignored, so the files stay on your machine. Uploads are minted through
`POST /v1/uploads` and the resulting `assetId` is **durable and reusable forever** — upload the
product shot once and reuse it across every iteration and every model, which is what makes drafting
on Mini cheap. (The presigned *upload URL* expires in 900 seconds; the `assetId` does not.)

## Project memory

`MASTER_CONTEXT.md` is your workspace's living memory — created by setup, gitignored, read at the
start of every session and written back to. It holds:

- **Default product** — auto-populated on first use, so you are never asked "which product?" twice
- **Brand voice** — tone, audience, words to use and avoid
- **API learnings** — empty on purpose, filled by your own sessions with what the skill cannot know
- **Meta ad defaults** — account, page, pixel IDs for `meta-ad-builder`
- **Changelog** — dated entries as decisions accumulate

It holds **no prices**, deliberately. See [what it costs](#what-it-costs).

## Editing skills

Canonical sources live under `skills/` and `shared/skills/`. After editing any file there:

```bash
./scripts/sync-skill.sh
```

That copies changes into `.claude/skills/` and `.cursor/skills/`, which are generated and
gitignored. The `SessionStart` hook runs it automatically when Claude Code opens the folder.

## Staying current

- **At session start**, the banner hook runs `git fetch origin` (10s timeout, never blocks). If your
  clone is behind, it lists the pending commits and tells you to pull. No surprise pulls.
- **To update:** `git pull origin main`. With local edits to tracked files, `git stash && git pull
  && git stash pop`.
- **Your data survives updates:** `.env`, `MASTER_CONTEXT.md`, `references/` and `outputs/` are all
  gitignored. `logs/` is *not* — latency and failure history across sessions is worth keeping, which
  is exactly why the log never records keys, presigned URLs, or prompt text.
- **Customizing a shipped skill file** invites merge conflicts on pull. Keep heavily customized
  versions under a non-tracked path if you would rather not deal with them.

## Security

- `.env` is gitignored and written `chmod 600`. Never commit it.
- `MASTER_CONTEXT.md` is gitignored — it holds your product IDs and workspace data.
- The agent never prints your key back to you, and never writes it into `MASTER_CONTEXT.md`. If you
  paste a key into a chat, rotate it — transcripts get shared.
- Keys are shown once at creation and are scoped to the organization that created them. Another
  organization's object returns `404`, not `403`: "not found" and "not yours" are deliberately
  indistinguishable.
- Every Meta ad created by `meta-ad-builder` is **PAUSED**. Nothing goes live without you.

## API docs

- **[docs.novoads.ai](https://docs.novoads.ai)** — the full API reference (Scalar).
- **[`GET /v1/openapi.json`](https://api.novoads.ai/v1/openapi.json)** — the machine-readable spec.
  Public, no key needed, and **the authority** whenever a file in this repo disagrees with it.
- **[novoads.ai/mcp](https://novoads.ai/mcp)** — the MCP connector, for tools that speak MCP rather
  than HTTP. Ad analysis (`analyze_ad`) lives there and is not on the REST API.

## Vendor prompting guides

| Model | Guide |
|---|---|
| Seedance 2.0 | ByteDance's published Seedance prompting platform, summarized in [seedance-2.md](skills/novoads-api/prompting/prompt-library/seedance-2.md) |
| Omni Flash | [Google DeepMind — Gemini Omni prompt guide](https://deepmind.google/models/gemini-omni/prompt-guide/), scoped for this API in [gemini-omni-flash](shared/skills/gemini-omni-flash/prompting/guide.md) |
| Nano Banana | [Google Cloud — Nano Banana](https://cloud.google.com/blog/products/ai-machine-learning/ultimate-prompting-guide-for-nano-banana) |
| ChatGPT Image 2 | OpenAI image guidance, summarized with model-specific limits in [chatgpt-image-ad](shared/skills/chatgpt-image-ad/prompting/guide.md) |

## Other AI assistants (Manus, Copilot, etc.)

Point your assistant at [AGENTS.md](AGENTS.md) — it carries the auth shape, the async-video /
sync-image distinction, the cost policy, and the skill map.
