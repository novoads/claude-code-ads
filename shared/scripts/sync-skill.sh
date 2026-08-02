#!/usr/bin/env bash
# Copies canonical skills to Claude Code and Cursor paths.
# Called automatically by scripts/setup.sh and by the SessionStart hook in .claude/settings.json.
# Run manually after editing any file under skills/ (or shared/skills/).
#
# Sources, in order:
#   skills/         — API-specific skills authored in this repo
#   shared/skills/  — skills propagated from gen-ai-core/content/ (only those
#                     carrying a SKILL.md are registered; prompting-only shared
#                     content folders are skipped)
#
# Resolves project root robustly so it works whether invoked as `scripts/sync-skill.sh`
# (the legacy location) or `shared/scripts/sync-skill.sh` (the propagated copy).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# If we landed inside shared/, the actual project root is one level up.
if [[ "$(basename "$ROOT")" == "shared" ]]; then
  ROOT="$(dirname "$ROOT")"
fi

# Register every top-level directory under $1 that contains a SKILL.md.
sync_skills_from() {
  local src_dir="$1"
  [[ -d "$src_dir" ]] || return 0
  for skill_path in "$src_dir"/*/; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_path")
    if [[ ! -f "$skill_path/SKILL.md" ]]; then
      continue
    fi
    for dest in "$ROOT/.claude/skills/$skill_name" "$ROOT/.cursor/skills/$skill_name"; do
      rm -rf "$dest"
      mkdir -p "$(dirname "$dest")"
      cp -R "$skill_path" "$dest"
    done
    echo "Synced $skill_name skill to .claude/skills and .cursor/skills"
  done
}

if [[ ! -d "$ROOT/skills" ]]; then
  echo "Expected $ROOT/skills — aborting." >&2
  exit 1
fi

sync_skills_from "$ROOT/skills"
sync_skills_from "$ROOT/shared/skills"
