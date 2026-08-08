# Agent instructions

This repository is set up for AI coding agents (Cursor, Claude Code, Copilot-style tools, etc.) to generate AI video and image assets via the API documented in this repo.

## First-time setup

If `.env` or `MASTER_CONTEXT.md` do not exist, tell the user to run `./scripts/setup.sh`.

When the session IS the setup ("help me set this up"), setup is the whole job and the
final report is SHORT — the few sentences a non-developer wants, not an engineering log.
`./scripts/setup.sh` run without a TTY prints this same close between
`FINAL MESSAGE START` / `END` markers; relay that block verbatim. The script and the
template below are mirrors — change them together. One or two status lines, then:

> Setup's done — your key works.
> *(or, when the key is missing:)* One step left, the only one I can't do: create an API
> key at <https://novoads.ai/dashboard/settings?tab=api>, paste it into `.env`, and tell
> me — I'll verify it. *(No account yet? The [$1 trial](https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack).)*
>
> **What you can ask for now:**
> - "Make a UGC video ad for my product" — Seedance 2.0/2.5, Veo 3.1, Sora 2
> - "Make a static image ad from this photo" — 40-template library
> - "Clone this ad" plus an image of one you like
> - Pixar or claymation story ads, YouTube thumbnails, burned-in captions, generated music
>
> Drop product photos into `references/products/` and describe the ad you want. Every
> generation is priced by a live estimate and shown to you before anything is spent.

Everything else the run surfaced — git mechanics, pulls, sync counts, files that already
existed, MCP/connector notes, untracked directories — is stated ONLY if it blocks one of
those asks. Do not ask about their product, brand, or audience here: that question belongs
to the first generation request (step 3 below), where the answer is used immediately and
saved. The only setup input a human owes is the API key.

## Every session

1. Read **[MASTER_CONTEXT.md](MASTER_CONTEXT.md)** for brand voice, default product, and accumulated learnings. It carries **no prices** — that is deliberate, see "Cost policy" below.
2. Follow the skill at `.cursor/skills/` or `.claude/skills/` (synced from `skills/` via `scripts/sync-skill.sh`).
3. The first time the user asks to generate something and `MASTER_CONTEXT.md` is missing a field that request needs (default product, brand voice), ask for it then — once — and write the answer back so no future session asks again. Ask only for what the request in hand needs; a setup-only session asks for nothing. Never write a credit number into it.
4. After material changes, add a dated entry to **MASTER_CONTEXT.md** Changelog.
5. Before changing any stated API limit — or whenever a preflight prints `WARN(image-caps)` — run `./scripts/verify-image-caps.sh`: the standing audit that checks the repo's per-model reference caps against the live spec, exercises the scripts' refusal gates (no key, no spend), and greps for resurrected universal-cap claims.
6. **Everything a session writes that is not repo content goes in a gitignored home, and the session leaves `git status` as clean as it found it.** The homes already exist:
   - `generated/` — image renders
   - `outputs/<job>/` — video downloads and the workfiles an edit needs (beat lists, stitch lists, trimmed clips)
   - `prompts/` — prompt files you compose so a 3,000-character prompt never goes through a shell argument
   - `iterations/` — clone rounds (`iterations/clone-<date>/<tag>/`)
   - `logs/` — the generation log

   **Never invent a new top-level directory.** A directory that is not on that list is not ignored, and the diff lands on the user: on 2026-08-08 a session composing ten image-ad prompts created `prompts/` unprompted — the right instinct, and why it is sanctioned above rather than forbidden — but nothing ignored it yet, so the next thing the user saw was a "+162 / Create PR" badge over files they never asked for. Writing into one of these five is always in scope and never needs permission. If a run genuinely needs a home that is not here, add it to `.gitignore` in the same breath as the first file you write into it.

## Cost policy

Every credit number shown to a user must come from a live `POST /v1/estimates` call made in the current session, and the user approves it before anything is generated. There are no rate tables in this repo — not in `MASTER_CONTEXT.md`, not in `logs/`. The estimate is free and runs the same structural validation the paid call runs, so there is no reason to skip it. It also returns an advisory `warnings` array of craft notes on a video prompt (verified live 2026-08-04) — the generation endpoints do not. Those warnings never refuse a call or change the price, and they false-positive on substring matches, so read them, judge each one against the prompt, and say so when you override one.

For any video where the model speaks, the spoken line gets its own approval before the cost gate. The two gates are separate and neither implies the other.

## Craft doctrine

Three rules span every skill that produces video with speech: **transcribe-verify** (a
reference pins the label, nothing pins the audio), **the per-beat mix** (a SYNC beat's own
audio is dialogue, not ambience), and **no dead space** (trim every beat to its narration).
They are stated once in [shared/references/craft.md](shared/references/craft.md). Read it
before writing a QA step, a mix or a trim into any skill, and point at it rather than
restating it — a restatement is how the clay skill shipped a mix recipe that had already
been fixed in the skill it was ported from.

## Image-ad skill ecosystem (cross-API)

This repo ships a 3-skill ecosystem for generating standalone Meta image-ad creatives. **Read [shared/skills/image-ad-prompting/OVERVIEW.md](shared/skills/image-ad-prompting/OVERVIEW.md) before invoking any of these skills** — it explains the decision tree (gpt-image-2 vs Nano Banana), the shared 40-template library, the hand-off to the separate `meta-ad-builder` skill, and what's out of scope.

Quick map:
- **Generate from a brief** → `chatgpt-image-ad` (typography / UI mimicry) or `nano-banana-image-ad` (photoreal / lifestyle / multi-ref).
- **Clone an existing ad into a reusable template** → `image-ad-clone` (single backend-agnostic skill; asks you which generator to validate against at Phase 1, optionally cross-validates against the other backend at Phase 8).
- **Pull from / add to the shared library** → `shared/skills/image-ad-prompting/prompting/prompt-library.md` (40 ready-to-use validated prompts).
- **Hand off finished images to Meta** → separate `meta-ad-builder` skill; the image-ad skills produce images only.


## This repo specifically

- **API:** Novoads REST API (`https://api.novoads.ai/v1`). Public spec: <https://api.novoads.ai/v1/openapi.json> — the authority whenever a file in this repo disagrees with it.
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`. The key is `novo_` plus 64 hex characters, created at <https://novoads.ai/dashboard/settings?tab=api>. No quoting needed in `.env`. Optional `NOVOADS_BASE_URL` overrides the **host only** — callers append `/v1/…`.
- **Shape of the API:** videos are asynchronous (`POST /v1/videos` → `202` + `jobId` → poll `GET /v1/generations/{jobId}` to a **terminal** status → `…/watch` for the file). Images are **synchronous** — `POST /v1/images` returns the finished images in the response body, so there is nothing to poll.
- **Skills:**
  - `novoads-api` — the spine: endpoints, auth, the two gates, uploads, polling, error branching, and the prompt libraries.
  - `generate-youtube-thumbnail` — YouTube thumbnail batch workflow on top of the image endpoint.
  - **Image-ad ecosystem** (3 skills + shared 40-template library) — see [shared/skills/image-ad-prompting/OVERVIEW.md](shared/skills/image-ad-prompting/OVERVIEW.md):
    - `chatgpt-image-ad` — generate via `gpt-image-2` (typography / UI-mimicry creatives)
    - `nano-banana-image-ad` — generate via `nano-banana-pro` (photoreal / lifestyle creatives)
    - `image-ad-clone` — single backend-agnostic skill that reverse-engineers existing ads into reusable templates (asks which backend to validate against at Phase 1; optionally cross-validates at Phase 8)
- **Setup check:** `./scripts/check-novoads-env.sh`.
- **Logging:** every generation call is appended to `logs/novoads-api.jsonl`. Observability only — never a pricing input. Schema in [logs/README.md](logs/README.md).
