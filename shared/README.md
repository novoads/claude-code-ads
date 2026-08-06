# `shared/` — cross-API skills and scripts

Everything here is hand-edited in this repo. The upstream skill pack this repo was forked from generated this
directory from a `gen-ai-core` source via a `propagate.sh` sync script; this fork does not run
that script, so these files are the canonical source — edit them directly.

Contents:

- `shared/CLAUDE.md` — base Claude Code session rules, included by the root `CLAUDE.md`.
- `shared/references/` — `craft.md`, the cross-skill craft doctrine (transcribe-verify, the
  per-beat mix, no dead space), plus `README.md` documenting the repo-root `references/`
  image folders. Two different senses of "reference" in one directory; the file names say
  which is which.
- `shared/skills/` — skills that aren't tied to a single generative API (image-ad prompting
  library, caption-video, meta-ad-builder, gemini-omni-flash).
- `shared/scripts/` — `sync-skill.sh` (copies skills into `.claude/` and `.cursor/`) and
  `check-context.sh` (the SessionStart orientation banner).
