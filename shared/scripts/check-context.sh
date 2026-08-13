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

# ── Update-check kill switch ─────────────────────────────────────────────────
# `.update-state/config`, key=value lines, `update_check=on|off` (default on).
# The env override `NOVOADS_PACK_NO_UPDATE_CHECK=1` wins over the file.
#
# Off means OFF: no fetch, no banner, no network call of any kind from this
# hook. The nag meta-pattern is well documented — a check gets added, an opt-out
# gets added under pressure, and the opt-out ships broken — so this is one
# function, read at one place, and the harness mutation-tests it in both
# directions. It deliberately does NOT reach ./scripts/update.sh: a kill switch
# that strands the manual path is not a kill switch.
#
# The file is read with grep, never sourced. A config file that can execute is a
# config file that can be a payload.
update_check_enabled() {
  [[ "${NOVOADS_PACK_NO_UPDATE_CHECK:-}" == "1" ]] && return 1
  local cfg="$ROOT/.update-state/config" line val
  [[ -f "$cfg" ]] || return 0
  line="$(grep -E '^[[:space:]]*update_check[[:space:]]*=' "$cfg" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 0
  val="$(printf '%s' "${line#*=}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$val" in
    off|0|false|no) return 1 ;;
    *) return 0 ;;
  esac
}

# ── Snooze reader (spec §4) ──────────────────────────────────────────────────
# `.update-state/update-snoozed` is written by the novoads-update skill's "Not
# now". Format, key=value, and the shape shared/scripts/auto-update.sh writes:
#   level=<1|2|3+>   ladder position (1=24h, 2=48h, 3+=7d)
#   until=<epoch>    when the snooze lapses
#   version=<sha>    the upstream commit the answer was about
#
# "Not now" is an answer about the version in hand, so it silences the NAG and
# nothing else. It does NOT silence the fetch above — that fetch is how we learn
# a NEWER commit arrived, which is one of the three ways the answer expires —
# and it does not reach ./scripts/update.sh or the skill, which stay available
# the whole time. The kill switch silences the channel; a snooze silences one
# sentence.
#
# All three lapse conditions resolve toward SPEAKING: the clock runs out, a new
# upstream commit lands beyond the snoozed one, or the file does not parse. That
# last bias is the opposite of auto-update.sh's, and deliberately so: for a hook
# that APPLIES changes unattended the safe failure is to do nothing, and for a
# banner that only informs the safe failure is to inform.
banner_snoozed() {
  local f="$ROOT/.update-state/update-snoozed" ref="$1" until_s ver now up
  [[ -f "$f" ]] || return 1
  until_s="$(sed -n 's/^[[:space:]]*until[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*$/\1/p' "$f" 2>/dev/null | tail -1)"
  ver="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*\([0-9a-fA-F]\{1,\}\).*$/\1/p' "$f" 2>/dev/null | tail -1)"
  [[ -n "$until_s" ]] || return 1                    # no readable clock → notify
  [[ -n "$ver" ]] || return 1                        # no readable version → notify
  now="$(date +%s 2>/dev/null || echo 0)"
  (( until_s > now )) || return 1                    # lapsed → notify
  # The longest rung of the ladder is 7 days. A parseable `until` far past that
  # is not a snooze, it is a permanent mute wearing a snooze's clothes — from a
  # clock skew, a milliseconds-for-seconds bug, or an edit. Treat it as corrupt,
  # which here means notify. "Never ask again" is a real answer with its own
  # switch (`update_check=off`); it is not something a stray digit gets to say.
  (( until_s <= now + 3456000 )) || return 1         # > 40 days → corrupt → notify
  up="$(git -C "$ROOT" rev-parse "$ref" 2>/dev/null || true)"
  [[ -n "$up" ]] || return 1                         # cannot compare → notify
  # Abbreviated or full, either way: same commit → the answer still stands.
  case "$up" in "$ver"*) return 0 ;; esac
  case "$ver" in "$up"*) return 0 ;; esac
  return 1                                           # upstream moved → notify
}

# ── Upstream-updates check ───────────────────────────────────────────────────
# If this is a git clone with an `origin` remote, quietly check whether any
# commits are pending upstream. Notify only — never auto-apply. Applying is a
# separate, explicit step the user takes with ./scripts/update.sh, which stashes
# their in-flight work, copies `.env` out of git's reach across the merge, and
# puts both back afterwards.
upstream_behind=0
upstream_ref=""
upstream_log=""
upstream_dirty=0
if update_check_enabled && [[ -d "$ROOT/.git" ]] && git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
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

# Asked and answered: "Not now" holds until it lapses. Evaluated here rather
# than inside the output block so the banner stays a wall of printf.
upstream_snoozed=0
if (( upstream_behind > 0 )) && banner_snoozed "$upstream_ref"; then
  upstream_snoozed=1
fi

# ── Untracked working-tree check ─────────────────────────────────────────────
# A session's work-product has gitignored homes (generated/, outputs/, prompts/,
# iterations/, logs/). Anything ELSE it writes shows up in `git status` and reaches
# the user as a diff they did not make: on 2026-08-08 a run that composed image-ad
# prompts into a then-unignored `prompts/` surfaced in their desktop app as a
# "+162 / Create PR" badge over ten files they never asked to commit. Those five
# homes are ignored now — this line is for the NEXT invented directory, which no
# .gitignore can know about in advance.
#
# Top-level entries only: one name however deep the tree under it, because the
# remediation ("move it into a home or ignore it") is the same for all of them.
# `git status --porcelain` already collapses an untracked directory to `dir/`.
stray_paths=()
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && stray_paths+=("$p")
  done < <(git -C "$ROOT" status --porcelain 2>/dev/null \
    | sed -n 's/^?? //p' | sed 's|/.*|/|' | sort -u)
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
needs_key=0
if [[ ! -f "$ROOT/.env" ]]; then
  env_status="✗ .env MISSING — run ./scripts/setup.sh"
  needs_key=1
elif grep -q "novo_your_key_here" "$ROOT/.env" 2>/dev/null; then
  env_status="✗ .env has no key yet — run ./scripts/setup.sh"
  env_status="$env_status (create a key at https://novoads.ai/dashboard/settings?tab=api)"
  needs_key=1
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
      chatgpt-image-ad|nano-banana-image-ad|clone-image-ad)
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
  # Addressed to the agent, and printed at the one moment it can still be acted
  # on: BEFORE the first request, while the key is missing. On 2026-08-08 a setup
  # session in exactly this state decided the connected connector "has its own
  # auth" and generated over it — the user got a demo, prices in the wrong units,
  # and still no key. The rule needs to reach a session that never opens
  # AGENTS.md, and a SessionStart hook's stdout is the channel that always does.
  if (( needs_key == 1 )); then
    printf '  → AGENT: a connected Novoads MCP connector is NOT a substitute for this key.\n'
    printf '    Never call mcp__novoads__* tools from this repo. Ask for the key and stop.\n'
  fi
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
        clone-image-ad)
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

  if (( upstream_behind > 0 && upstream_snoozed == 0 )); then
    printf '\n⚠️  %d update(s) available from %s:\n' "$upstream_behind" "$upstream_ref"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '   %s\n' "$line"
    done <<< "$upstream_log"
    if (( upstream_behind > 5 )); then
      printf '   (... and %d more)\n' "$((upstream_behind - 5))"
    fi
    # The remediation is ./scripts/update.sh in BOTH branches, because the one
    # thing that separated them — "you have local changes, deal with them
    # yourself first" — is precisely what that script does for you. A raw pull
    # is not offered at all: it destroys a gitignored .env, silently and with
    # exit 0, the moment upstream starts tracking that path.
    if (( upstream_dirty == 1 )); then
      printf '\n   You have uncommitted local changes — that is fine, the updater expects it:\n'
      printf '       ./scripts/update.sh   (stashes your work, fast-forwards, puts it back)\n'
    else
      printf '\n   To update: ./scripts/update.sh   (re-syncs skills for you; --rollback undoes it)\n'
    fi
  fi

  # Informational, never a refusal — the user may have put those files there on
  # purpose, and a session that stops over an untracked folder is worse than a
  # stray folder.
  if (( ${#stray_paths[@]} > 0 )); then
    printf '\n📂 Untracked, so it will read as YOUR diff: %s\n' \
      "$(printf '%s, ' "${stray_paths[@]}" | sed 's/, $//')"
    printf '   Session work-product has homes: generated/, outputs/<job>/, prompts/,\n'
    printf '   iterations/, logs/ — all gitignored. Move it into one, or add it to\n'
    printf '   .gitignore. Nothing is blocked either way.\n'
  fi

  printf '─────────────────────────────────────────────────────────────────────\n\n'
}
