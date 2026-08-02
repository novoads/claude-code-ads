@shared/CLAUDE.md

# Novoads-specific session rules

- **API:** Novoads REST API — `https://api.novoads.ai/v1`. `NOVOADS_BASE_URL` overrides the **host only**; callers append `/v1/…`.
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY` (`novo_` + 64 hex, created at <https://novoads.ai/dashboard/settings?tab=api>). Setup check: `./scripts/check-novoads-env.sh`. A 401 is a bad key; a 403 with `details.reason: plan_required` is a good key on an account without API access — different problems, say which.
- **Skill:** `.claude/skills/novoads-api/SKILL.md` for the call sequence, prompts, polling, and download; its `reference.md` for every endpoint, field, limit, and error code.
- **YouTube thumbnails:** `.claude/skills/generate-youtube-thumbnail/SKILL.md` — batch thumbnail workflow on top of the Novoads image endpoint.
- **Image-ad ecosystem (Meta image creatives):** read `shared/skills/image-ad-prompting/OVERVIEW.md` FIRST. Three skills (`chatgpt-image-ad`, `nano-banana-image-ad`, `image-ad-clone`) + a shared 37-template prompt library. The `image-ad-clone` skill asks which backend to validate against at Phase 1, so generic "clone this ad" prompts route correctly. Output is image files; Meta upload is the separate `meta-ad-builder` skill.
- **Cost policy:** **never state a credit cost from memory.** Every price comes from a live `POST /v1/estimates` in the current session, shown to the user and explicitly approved before anything is generated. There are no rate tables anywhere in this repo — not in `MASTER_CONTEXT.md`, not in the logs. The estimate call is free and also validates the prompt, so it costs nothing to run every time.
- **Dialogue policy:** for any video where the model speaks, the spoken line is approved on its own, before the cost gate. Concept approval is not sentence approval, and sentence approval is not spend approval.
- **Logging:** log every generation call to `logs/novoads-api.jsonl` — timestamps, config, `jobId`, and `creditsCharged` after the fact. **Observability only, never a pricing source** (see `logs/README.md`).
- **First-time setup:** if `.env` is missing, run `./scripts/setup.sh`. If `MASTER_CONTEXT.md` is missing, copy `MASTER_CONTEXT.template.md` to `MASTER_CONTEXT.md`.
