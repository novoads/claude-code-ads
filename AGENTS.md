# Agent instructions

This repository is set up for AI coding agents (Cursor, Claude Code, Copilot-style tools, etc.) to generate AI video and image assets via the API documented in this repo.

## First-time setup

If `.env` or `MASTER_CONTEXT.md` do not exist, tell the user to run `./scripts/setup.sh`.

## Every session

1. Read **[MASTER_CONTEXT.md](MASTER_CONTEXT.md)** for brand voice, default product, and accumulated learnings. It carries **no prices** — that is deliberate, see "Cost policy" below.
2. Follow the skill at `.cursor/skills/` or `.claude/skills/` (synced from `skills/` via `scripts/sync-skill.sh`).
3. If `MASTER_CONTEXT.md` has empty fields (default product, brand voice, defaults), offer to populate them — ask the user and write the values back so future sessions have them. Never write a credit number into it.
4. After material changes, add a dated entry to **MASTER_CONTEXT.md** Changelog.

## Cost policy

Every credit number shown to a user must come from a live `POST /v1/estimates` call made in the current session, and the user approves it before anything is generated. There are no rate tables in this repo — not in `MASTER_CONTEXT.md`, not in `logs/`. The estimate is free and runs the same structural validation the paid call runs, so there is no reason to skip it. It also returns an advisory `warnings` array of craft notes on a video prompt (verified live 2026-08-04) — the generation endpoints do not. Those warnings never refuse a call or change the price, and they false-positive on substring matches, so read them, judge each one against the prompt, and say so when you override one.

For any video where the model speaks, the spoken line gets its own approval before the cost gate. The two gates are separate and neither implies the other.

## Image-ad skill ecosystem (cross-API)

This repo ships a 3-skill ecosystem for generating standalone Meta image-ad creatives. **Read [shared/skills/image-ad-prompting/OVERVIEW.md](shared/skills/image-ad-prompting/OVERVIEW.md) before invoking any of these skills** — it explains the decision tree (gpt-image-2 vs Nano Banana), the shared 37-template library, the hand-off to the separate `meta-ad-builder` skill, and what's out of scope.

Quick map:
- **Generate from a brief** → `chatgpt-image-ad` (typography / UI mimicry) or `nano-banana-image-ad` (photoreal / lifestyle / multi-ref).
- **Clone an existing ad into a reusable template** → `image-ad-clone` (single backend-agnostic skill; asks you which generator to validate against at Phase 1, optionally cross-validates against the other backend at Phase 8).
- **Pull from / add to the shared library** → `shared/skills/image-ad-prompting/prompting/prompt-library.md` (37 ready-to-use validated prompts).
- **Hand off finished images to Meta** → separate `meta-ad-builder` skill; the image-ad skills produce images only.


## This repo specifically

- **API:** Novoads REST API (`https://api.novoads.ai/v1`). Public spec: <https://api.novoads.ai/v1/openapi.json> — the authority whenever a file in this repo disagrees with it.
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`. The key is `novo_` plus 64 hex characters, created at <https://novoads.ai/dashboard/settings?tab=api>. No quoting needed in `.env`. Optional `NOVOADS_BASE_URL` overrides the **host only** — callers append `/v1/…`.
- **Shape of the API:** videos are asynchronous (`POST /v1/videos` → `202` + `jobId` → poll `GET /v1/generations/{jobId}` to a **terminal** status → `…/watch` for the file). Images are **synchronous** — `POST /v1/images` returns the finished images in the response body, so there is nothing to poll.
- **Skills:**
  - `novoads-api` — the spine: endpoints, auth, the two gates, uploads, polling, error branching, and the prompt libraries.
  - `generate-youtube-thumbnail` — YouTube thumbnail batch workflow on top of the image endpoint.
  - **Image-ad ecosystem** (3 skills + shared 37-template library) — see [shared/skills/image-ad-prompting/OVERVIEW.md](shared/skills/image-ad-prompting/OVERVIEW.md):
    - `chatgpt-image-ad` — generate via `gpt-image-2` (typography / UI-mimicry creatives)
    - `nano-banana-image-ad` — generate via `nano-banana-pro` (photoreal / lifestyle creatives)
    - `image-ad-clone` — single backend-agnostic skill that reverse-engineers existing ads into reusable templates (asks which backend to validate against at Phase 1; optionally cross-validates at Phase 8)
- **Setup check:** `./scripts/check-novoads-env.sh`.
- **Logging:** every generation call is appended to `logs/novoads-api.jsonl`. Observability only — never a pricing input. Schema in [logs/README.md](logs/README.md).
