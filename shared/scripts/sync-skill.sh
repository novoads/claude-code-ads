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
      # Provenance, so prune_orphans below can tell this copy from a skill the
      # user hand-placed in the same directory.
      : > "$dest/.synced-from-pack"
    done
    echo "Synced $skill_name skill to .claude/skills and .cursor/skills"
  done
}

# Delete synced skills whose source is gone. Copy-only sync means a rename leaves
# BOTH names installed, and the stale one keeps whatever the source said before
# the change: after #49 renamed the two storyboard skills, every machine that had
# synced before still had `novoads-pixar-storyboard-ad` in `.claude/skills/`,
# carrying prose the repo had already corrected. The mirrors are gitignored, so
# no diff and no grep over tracked files can see it, and `.claude/skills/` is what
# the editor actually loads.
#
# Only directories THIS script wrote are removed, identified by the marker file
# it drops on every sync. A skill someone hand-placed in .claude/skills/ has no
# marker and is left alone. RETIRED covers the gap the marker cannot: names that
# went stale before the marker existed, so an install that predates this change
# still gets cleaned. Entries can be dropped once nobody is syncing from a
# pre-marker checkout.
MARKER=".synced-from-pack"
RETIRED=(novoads-pixar-storyboard-ad novoads-claymation-storyboard-ad)

prune_orphans() {
  local dest_root="$1"
  [[ -d "$dest_root" ]] || return 0
  for installed in "$dest_root"/*/; do
    [[ -d "$installed" ]] || continue
    local name reason=""
    name=$(basename "$installed")
    # Still a live source? Keep it.
    [[ -f "$ROOT/skills/$name/SKILL.md" || -f "$ROOT/shared/skills/$name/SKILL.md" ]] && continue

    if [[ -f "$installed/$MARKER" ]]; then
      reason="no longer in skills/ or shared/skills/"
    else
      for retired in "${RETIRED[@]}"; do
        [[ "$name" == "$retired" ]] && reason="retired from this pack" && break
      done
    fi

    if [[ -n "$reason" ]]; then
      rm -rf "$installed"
      echo "Removed $name — $reason"
    fi
  done
}

if [[ ! -d "$ROOT/skills" ]]; then
  echo "Expected $ROOT/skills — aborting." >&2
  exit 1
fi

sync_skills_from "$ROOT/skills"
sync_skills_from "$ROOT/shared/skills"
prune_orphans "$ROOT/.claude/skills"
prune_orphans "$ROOT/.cursor/skills"
