# Claude Code — project instructions

> **Paths in this file are relative to the REPO ROOT, not to `shared/`.** This file is `@`-included
> into the root `CLAUDE.md`, which is the context it is read in. They are written as code rather
> than as markdown links for that reason: a link that resolves only from one directory is a link
> that is broken from the other, and this file legitimately gets opened both ways.

## First-time setup

If `.env` does not exist, tell the user to run `./scripts/setup.sh` or walk them through:
1. Copy `.env.example` to `.env`.
2. Paste their API key into `.env` (line: `*_API_KEY=`).
3. Run `./scripts/check-*-env.sh` to verify.

If `MASTER_CONTEXT.md` does not exist, copy `MASTER_CONTEXT.template.md` to `MASTER_CONTEXT.md`.

## Every session

1. Read **`MASTER_CONTEXT.md`** (repo root) for brand voice, defaults, and accumulated learnings.
2. Use the API skill in `.claude/skills/` for API calls, prompts, and polling.
3. If `MASTER_CONTEXT.md` has empty fields (default product, brand voice, defaults), offer to populate them — ask the user and **write the values back into `MASTER_CONTEXT.md`** so future sessions have them. Prices are not among them: quote costs from a live estimate call, never from a stored number.

## After significant changes

Append a short dated note to **MASTER_CONTEXT.md** under Changelog (Decision / What changed / Why).

## Skill edits

Edit the canonical source under `skills/`. Run `./scripts/sync-skill.sh` to copy changes to `.claude/skills/` and `.cursor/skills/`.

## Image-ad skill ecosystem (cross-API)

This repo ships a 3-skill ecosystem for generating standalone Meta image-ad creatives. **Read `shared/skills/image-ad-prompting/OVERVIEW.md` (from the repo root) before invoking any of these skills** — it explains the decision tree (gpt-image-2 vs Nano Banana), the shared 40-template library, the hand-off to the separate `meta-ad-builder` skill, and what's out of scope.

Quick map:
- **Generate from a brief** → `chatgpt-image-ad` (typography / UI mimicry) or `nano-banana-image-ad` (photoreal / lifestyle / multi-ref).
- **Clone an existing ad into a reusable template** → `image-ad-clone` (single backend-agnostic skill; asks you which generator to validate against at Phase 1, optionally cross-validates against the other backend at Phase 8).
- **Pull from / add to the shared library** → `shared/skills/image-ad-prompting/prompting/prompt-library.md` (40 ready-to-use validated prompts).
- **Hand off finished images to Meta** → separate `meta-ad-builder` skill; the image-ad skills produce images only.
