#!/usr/bin/env bash
# Thin wrapper — delegates to the canonical shared/scripts/sync-skill.sh
# which is propagated from gen-ai-core and handles both skills/ and
# shared/skills/ in a single pass.
#
# Kept here so the documented path (`./scripts/sync-skill.sh`) keeps
# working after first-time setup; the implementation lives in shared/.
#
# It then points `.agents/skills` at the tree that delegate just wrote, which is
# the only place OpenAI Codex looks — see link_agents_skills below.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/shared/scripts/sync-skill.sh" "$@"

# Codex reads skills ONLY from `.agents/skills` (repo scope: $CWD/.agents/skills
# up to the repo root; user scope: ~/.agents/skills). It never looks in
# `.claude/skills/` or `.cursor/skills/`, so without this the pack installs
# fully and is offered by nothing: every skill present, none of them reachable.
#
# A SYMLINK to the tree the delegate already wrote, not a third copy, and the
# reason is the SessionStart hook in `.claude/settings.json` — it calls
# `shared/scripts/sync-skill.sh` DIRECTLY, bypassing this wrapper. A copy made
# here would go stale the moment that hook refreshed `.claude/skills` behind it,
# and a stale skill copy is a bill this repo has already paid: after #49 renamed
# two skills, every machine that had synced earlier kept the dead name installed,
# still carrying prose the repo had corrected. A link holds no stale state —
# there is one tree, and it is the one every entry point writes. So this runs
# once at setup and stays correct without ever running again.
#
# Verified 2026-08-13 against a real `codex debug prompt-input`: a symlinked
# scan root registers exactly like a real directory, which is the documented
# behavior ("Codex supports symlinked skill folders and follows the symlink
# target when scanning these locations").
#
# Relative, so moving or renaming the clone does not break it. Pointed at
# `.claude/` rather than `.cursor/` only because that is the copy the
# SessionStart hook keeps warmest; the two are byte-identical.
#
# This lives in the wrapper and not in the delegate because the delegate is
# propagated from gen-ai-core: pack-local policy written there is policy the
# next propagation quietly reverts.
link_agents_skills() {
  local link="$ROOT/.agents/skills"
  local target="../.claude/skills"

  # `-L` as well as `-e`, because a dangling symlink fails `-e` and would then
  # be overwritten as if nothing were there.
  if [[ -e "$link" || -L "$link" ]]; then
    if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
      echo "Codex discovery: .agents/skills -> $target (already linked)"
      return 0
    fi
    # Anything else at that path is the user's own — a real directory of their
    # Codex skills, or a link they aimed somewhere deliberate. Replacing it with
    # ours would delete skills this pack never installed.
    echo "Codex discovery: .agents/skills exists and is not ours — left untouched."
    echo "  To let Codex see this pack too, link the skills you want into it:"
    echo "  ln -s ../../.claude/skills/<skill> .agents/skills/<skill>"
    return 0
  fi

  mkdir -p "$ROOT/.agents"
  ln -s "$target" "$link"
  echo "Codex discovery: linked .agents/skills -> $target"
}

link_agents_skills

# The two storyboard skills' SKILL.md files are BUILD ARTIFACTS of their own
# sections/*.md.in (scripts/build-skill-md.py), and the delegate copies a skill
# directory wholesale with `cp -R`. So every install carried the sections too,
# and that is wrong in three separate ways:
#
#   1. It is a full second copy of the skill. The sections concatenate INTO
#      SKILL.md, so a 1,123-line skill shipped as roughly twice that in one
#      directory, the same prose either side of a build step. This pack competes
#      for context with everything else a user has installed; paying twice for
#      one document is the cheapest thing here to stop doing.
#   2. It is an edit trap. An agent that opens the installed skill, finds
#      sections/, and correctly infers "this is the source, edit it here" makes a
#      change that reaches nothing — the mirror is rewritten from the repo on the
#      next sync, and the builder only ever reads the repo's sections. The
#      failure is silent and looks exactly like a change that worked.
#   3. `.md.in` exists so the guards that glob `*.md` cannot see build inputs
#      whose relative links are written for a different directory depth. Shipping
#      them past that boundary hands the installed tree files whose links do not
#      resolve from where they sit.
#
# Only directories the delegate WROTE are touched, identified by the marker file
# it drops on every sync — the same test its own prune_orphans uses, for the same
# reason: a skill someone hand-placed in .claude/skills/ is theirs, and if it has
# a sections/ of its own that is theirs too.
#
# Pack-local, like link_agents_skills above and for the identical reason: the
# delegate is propagated from gen-ai-core, so policy written there is policy the
# next propagation quietly reverts.
prune_installed_sections() {
  local removed=0
  for root in "$ROOT/.claude/skills" "$ROOT/.cursor/skills"; do
    [[ -d "$root" ]] || continue
    for installed in "$root"/*/; do
      [[ -d "$installed" ]] || continue
      [[ -f "$installed/.synced-from-pack" ]] || continue
      [[ -d "$installed/sections" ]] || continue
      rm -rf "$installed/sections"
      removed=$((removed + 1))
    done
  done
  [[ "$removed" -gt 0 ]] && echo "Build inputs: removed sections/ from $removed installed skill(s)"
  return 0
}

prune_installed_sections
