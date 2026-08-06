#!/usr/bin/env bash
# Claude Code SessionStart context banner.
#
# Runs after sync-skill.sh. Detects which generative APIs this repo serves
# (based on .env.example / installed skills), checks setup files, and prints
# a one-screen orientation banner that surfaces:
#   - what skills are installed
#   - whether the user's .env / MASTER_CONTEXT.md are populated
#   - where the image-ad ecosystem master doc lives
#
# The banner goes to STDOUT on purpose: a SessionStart hook's stdout is what
# Claude Code injects into session context, and the user sees it too. It was
# written to stderr until 2026-08-03, which meant the hook reported "success"
# every session while delivering the agent nothing — the one reader the banner
# exists for never saw a byte of it. Do not "tidy" this back to >&2.
# Non-blocking: prints warnings but never refuses.

set -u  # don't fail on unset vars beyond -u — this script is informational

# Resolve project root regardless of CWD when the hook fires.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
  parent="$(dirname "$SCRIPT_DIR")"
  if [[ "$(basename "$parent")" == "shared" ]]; then
    ROOT="$(dirname "$parent")"
  else
    ROOT="$parent"
  fi
else
  ROOT="$SCRIPT_DIR"
fi

REPO_NAME="$(basename "$ROOT")"

# ── Upstream-updates check ───────────────────────────────────────────────────
# If this is a git clone with an `origin` remote, quietly check whether any
# commits are pending upstream. Notify only — never auto-pull. The actual pull
# requires the user to run `git pull` themselves (so their local edits and
# in-flight work stay safe).
upstream_behind=0
upstream_ref=""
upstream_log=""
upstream_dirty=0
if [[ -d "$ROOT/.git" ]] && git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  # Quiet fetch with a 10s ceiling so offline sessions don't hang.
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 git -C "$ROOT" fetch origin --quiet 2>/dev/null || true
  else
    # macOS without coreutils — fall back to plain fetch, accept the small risk.
    git -C "$ROOT" fetch origin --quiet 2>/dev/null || true
  fi
  # Resolve upstream: prefer the user's tracked branch; fall back to origin/main.
  upstream_ref="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  [[ -z "$upstream_ref" ]] && upstream_ref="origin/main"
  if git -C "$ROOT" rev-parse --verify "$upstream_ref" >/dev/null 2>&1; then
    upstream_behind="$(git -C "$ROOT" rev-list --count "HEAD..$upstream_ref" 2>/dev/null || echo 0)"
    if (( upstream_behind > 0 )); then
      upstream_log="$(git -C "$ROOT" log "HEAD..$upstream_ref" --oneline 2>/dev/null | head -5)"
      [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]] && upstream_dirty=1
    fi
  fi
fi

# Detect which generative APIs this repo is wired for.
apis=()
[[ -f "$ROOT/.env.example" ]] && grep -q "NOVOADS_API_KEY" "$ROOT/.env.example" 2>/dev/null && apis+=("Novoads")
[[ -f "$ROOT/.env.example" ]] && grep -q "META_ACCESS_TOKEN" "$ROOT/.env.example" 2>/dev/null && apis+=("Meta Ads (optional)")

# Check setup files. Each ✗ carries its own remediation inline — a status line
# that reports a problem without the command that fixes it just moves the
# question elsewhere. The placeholder case is separate from the missing case
# because they need different next steps.
# The filename lives INSIDE the status string, not appended by the printf —
# a remediation long enough to be useful otherwise trails a stray " .env".
env_status="✓ .env"
if [[ ! -f "$ROOT/.env" ]]; then
  env_status="✗ .env MISSING — run ./scripts/setup.sh"
elif grep -q "novo_your_key_here" "$ROOT/.env" 2>/dev/null; then
  env_status="✗ .env has no key yet — run ./scripts/setup.sh"
  env_status="$env_status (create a key at https://novoads.ai/dashboard/settings?tab=api)"
fi

mctx_status="✓ MASTER_CONTEXT.md"
[[ -f "$ROOT/MASTER_CONTEXT.md" ]] \
  || mctx_status="✗ MASTER_CONTEXT.md MISSING — copy MASTER_CONTEXT.template.md to MASTER_CONTEXT.md"

# Inventory registered skills.
skills_dir="$ROOT/.claude/skills"
skills_count=0
image_ad_skills=()
other_skills=()
if [[ -d "$skills_dir" ]]; then
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    skills_count=$((skills_count + 1))
    case "$name" in
      chatgpt-image-ad|nano-banana-image-ad|image-ad-clone)
        image_ad_skills+=("$name")
        ;;
      *)
        other_skills+=("$name")
        ;;
    esac
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# Resolve the OVERVIEW path — prefer the one closest to the user's session.
overview_path=""
for candidate in \
  "$ROOT/shared/skills/image-ad-prompting/OVERVIEW.md" \
  "$ROOT/content/skills/image-ad-prompting/OVERVIEW.md" \
  "$ROOT/.claude/skills/image-ad-prompting/OVERVIEW.md"
do
  if [[ -f "$candidate" ]]; then
    overview_path="${candidate#$ROOT/}"
    break
  fi
done

library_path=""
for candidate in \
  "$ROOT/shared/skills/image-ad-prompting/prompting/prompt-library.md" \
  "$ROOT/content/skills/image-ad-prompting/prompting/prompt-library.md" \
  "$ROOT/.claude/skills/image-ad-prompting/prompting/prompt-library.md"
do
  if [[ -f "$candidate" ]]; then
    library_path="${candidate#$ROOT/}"
    break
  fi
done

# Banner output.
{
  printf '\n'
  printf '─────────────────────────────────────────────────────────────────────\n'
  printf '🎬 %s — Novoads AI video + image ads\n' "$REPO_NAME"
  if [[ ${#apis[@]} -gt 0 ]]; then
    printf '   APIs wired: %s\n' "$(printf '%s, ' "${apis[@]}" | sed 's/, $//')"
  fi
  printf '─────────────────────────────────────────────────────────────────────\n'

  printf '\nSetup:\n'
  printf '  %s\n' "$env_status"
  printf '  %s\n' "$mctx_status"
  # Zero synced skills is not a pass. `.claude/skills/` is gitignored and empty on a
  # fresh clone until the SessionStart hook first runs sync-skill.sh, so a checkmark on
  # a zero count tells a first-time user everything is fine at the one moment it isn't.
  # It self-heals on the next session; the remediation is here for the session in hand.
  if (( skills_count > 0 )); then
    printf '  ✓ skills synced (%d in .claude/skills/)\n' "$skills_count"
  else
    printf '  ✗ no skills synced yet — run ./scripts/sync-skill.sh\n'
  fi

  if [[ ${#image_ad_skills[@]} -gt 0 ]]; then
    printf '\nImage-ad ecosystem (live-validated 2026-05-25):\n'
    for s in "${image_ad_skills[@]}"; do
      case "$s" in
        chatgpt-image-ad)
          printf '  • %-30s — gpt-image-2 / typography / UI mimicry\n' "$s"
          ;;
        nano-banana-image-ad)
          printf '  • %-30s — Nano Banana / photoreal / lifestyle\n' "$s"
          ;;
        image-ad-clone)
          printf '  • %-30s — clone ad → reusable library entry (asks which backend)\n' "$s"
          ;;
      esac
    done
    if [[ -n "$overview_path" ]]; then
      printf '\n📖 Read first: %s\n' "$overview_path"
    fi
    if [[ -n "$library_path" ]]; then
      printf '📚 Library:    %s (40 validated templates)\n' "$library_path"
    fi
    printf '   Aspect-ratio compatibility matrix is at the top of the library.\n'
    printf '   Output is image files; Meta upload is the separate meta-ad-builder skill.\n'
  fi

  if [[ ${#other_skills[@]} -gt 0 ]]; then
    printf '\nOther skills installed: %s\n' "$(printf '%s, ' "${other_skills[@]}" | sed 's/, $//')"
  fi

  # Stated on every session start because a stale credit number in a repo is
  # invisible until it has already misquoted someone. There is one price source.
  printf '\nCost: every price comes from POST /v1/estimates, which also returns\n'
  printf '      your balance. This repo ships no credit tables.\n'

  if (( upstream_behind > 0 )); then
    printf '\n⚠️  %d update(s) available from %s:\n' "$upstream_behind" "$upstream_ref"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '   %s\n' "$line"
    done <<< "$upstream_log"
    if (( upstream_behind > 5 )); then
      printf '   (... and %d more)\n' "$((upstream_behind - 5))"
    fi
    if (( upstream_dirty == 1 )); then
      printf '\n   ⚠️  You have uncommitted local changes. Stash or commit first:\n'
      printf '       git stash && git pull && git stash pop\n'
    else
      printf '\n   To update: git pull   (then re-run ./scripts/sync-skill.sh if skills changed)\n'
    fi
  fi

  printf '─────────────────────────────────────────────────────────────────────\n\n'
}
