#!/usr/bin/env bash
# Ratchet: no skill in this pack may take a name the HOST already uses.
#
# Why this can happen at all: a skill's directory name is its slash command. The
# docs are explicit that `.claude/commands/deploy.md` and
# `.claude/skills/deploy/SKILL.md` both create `/deploy` and work the same way —
# so installing this pack adds sixteen names to a namespace we do not own and
# cannot see. If one of them is already a built-in, the user types a command they
# have used for months and gets our skill, or types ours and gets the built-in.
# Which one wins is the host's business, not ours, and it can change between
# releases without anything in this repo moving.
#
# That failure is silent in the worst way. Nothing errors. The user gets the
# wrong behaviour from a command they typed correctly, and the only clue is that
# it started the day they installed an ad pack.
#
# So this is a SENTINEL rather than a linter: it holds a hard-coded list of the
# host's names and refuses ours if they land on one. It is green today and its
# whole job is to still be green in six months, when someone names a skill
# `/review` because that is what it does.
#
# Usage: ./scripts/check-skill-collisions.sh   (exit 0 clean, 1 on any collision)
set -uo pipefail
cd "$(dirname "$0")/.."

# ── The host's names ─────────────────────────────────────────────────────────
# Built-in commands and bundled skills, transcribed from the commands reference
# at code.claude.com/docs/en/commands on 2026-08-13.
#
# MAINTAINERS: this list is a snapshot and WILL go stale — the host ships new
# commands on its own schedule, and nothing here can notice. Re-read that page
# when adding a skill whose name is a plain English verb (`/verify`, `/review`,
# `/export` are all taken already), and add whatever is new below. A name missing
# from this list is not proof it is free; it is proof nobody has checked lately.
#
# Kept as one name per line, sorted, so a diff that adds a host command is one
# readable line rather than a re-wrapped paragraph.
HOST_BUILTINS=(
  add-dir
  advisor
  agents
  autocompact
  autofix-pr
  background
  batch
  branch
  btw
  bug
  cd
  chrome
  claude-api
  clear
  code-review
  color
  compact
  config
  context
  copy
  cost
  dataviz
  debug
  deep-research
  design-login
  design-sync
  desktop
  diff
  doctor
  effort
  exit
  export
  fast
  feedback
  fewer-permission-prompts
  focus
  fork
  goal
  heapdump
  help
  hooks
  ide
  import
  init
  insights
  install-github-app
  install-slack-app
  keybindings
  list-agents
  login
  logout
  loop
  mcp
  memory
  mobile
  model
  passes
  permissions
  plan
  plugin
  powerup
  pr-comments
  privacy-settings
  radio
  recap
  release-notes
  reload-plugins
  reload-skills
  remote-control
  rename-session
  rewind
  review
  security-review
  settings
  share
  simplify
  skills
  status
  subtask
  tasks
  teleport
  theme
  upgrade
  usage
  verify
  web
  webui
)

# ── Tolerated collisions ─────────────────────────────────────────────────────
# Format: one "name::justification" per entry. A name listed here collides on
# purpose and the justification says why shadowing is acceptable — which in
# practice means the host command is one no user of an ad pack would reach for,
# AND the skill's name is load-bearing enough that renaming it costs more than
# the shadow does.
#
# EMPTY, and that is the finding rather than an omission: all sixteen routable
# names in this pack are clear of all 88 host names as of 2026-08-13. The array
# exists so the next person has somewhere to record a decision instead of
# deleting the check, and so "we tolerated this deliberately" is distinguishable
# from "nobody noticed".
#
# The bar for adding one: renaming is almost always cheaper. A skill's name is
# changed by moving a directory; a shadowed built-in is a bug report from someone
# who will never guess the cause. Prefer the rename.
#
#   Example of the shape, if it were ever needed:
#     'debug::this pack has no debugger; the ad-debug skill is what users mean'
KNOWN_TOLERATED=()

# ── Scan ─────────────────────────────────────────────────────────────────────
# Routable = a directory carrying a SKILL.md. shared/skills/ entries that hold
# only a prompting/ guide are libraries other skills read, never commands, so
# they cannot collide and are not checked.
violations=0
tolerated=0
checked=0

for dir in skills/*/ shared/skills/*/; do
  [ -f "${dir}SKILL.md" ] || continue
  name="$(basename "$dir")"
  checked=$((checked + 1))

  hit=0
  for builtin in "${HOST_BUILTINS[@]}"; do
    [ "$name" = "$builtin" ] && { hit=1; break; }
  done
  [ "$hit" -eq 1 ] || continue

  why=""
  for entry in ${KNOWN_TOLERATED[@]+"${KNOWN_TOLERATED[@]}"}; do
    [ "${entry%%::*}" = "$name" ] && why="${entry#*::}"
  done

  if [ -n "$why" ]; then
    echo "tolerated  $name shadows the built-in /$name — $why"
    tolerated=$((tolerated + 1))
  else
    if [ "$violations" -eq 0 ]; then
      echo "FAIL: a skill name collides with a host built-in." >&2
      echo "" >&2
      echo "A skill directory name IS its slash command, so this one shadows a" >&2
      echo "command the user already had. Whoever wins is the host's decision and" >&2
      echo "it can change between releases; the user just sees the wrong thing" >&2
      echo "happen to a command they typed correctly." >&2
      echo "" >&2
      echo "Rename the skill directory. That is a git mv plus its links; the" >&2
      echo "alternative is a bug nobody can trace back to installing this pack." >&2
      echo "" >&2
    fi
    echo "  ${dir}SKILL.md: /$name is a host built-in" >&2
    violations=$((violations + 1))
  fi
done

# A tolerated name that no longer exists is a dead exemption, and a dead
# exemption is a live hole waiting for the next person who trusts it — the same
# reasoning the MCP guard carries for its own allowlist.
for entry in ${KNOWN_TOLERATED[@]+"${KNOWN_TOLERATED[@]}"}; do
  n="${entry%%::*}"
  [ -f "skills/$n/SKILL.md" ] || [ -f "shared/skills/$n/SKILL.md" ] || {
    echo "warn  KNOWN_TOLERATED lists '$n', which is not a skill here. Delete the entry."
  }
done

if [ "$violations" -gt 0 ]; then
  echo "" >&2
  echo "$violations collision(s); $tolerated tolerated." >&2
  exit 1
fi

echo "OK: $checked routable skill names, none collide with the ${#HOST_BUILTINS[@]} known host built-ins ($tolerated tolerated)."
