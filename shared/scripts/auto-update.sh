#!/usr/bin/env bash
# auto-update.sh — the opt-in auto-apply SessionStart hook.
#
# Notify-only is this pack's default. This script is the READER of a consent
# flag, and it does nothing at all until someone has turned that flag on. It is
# registered for EVERY install regardless, and that ordering is the whole point:
#
#   The upstream pack this design learned from shipped an "Always keep me up to
#   date" dialog that wrote a config flag whose only reader was a hook installed
#   under a separate, rarely-used setup mode. Config said on. The dialog said on.
#   Nothing ever updated, for four months, on a real install. A writer without a
#   reader is a dead gate — the flag is not the feature, the reader is.
#
#   So the reader ships pre-registered for everyone and the flag only ENABLES it.
#   A dead gate is structurally impossible here: consent cannot outrun its reader
#   because the reader was already there.
#
# CONTRACT (spec §4)
#   - Silent fast path. If auto-apply is not on, or the kill switch is active,
#     or the throttle/snooze says skip, this exits 0 having written NOTHING to
#     stdout. A SessionStart hook's stdout is injected into the session, so an
#     unrequested byte here is a tax on every session the pack is installed in.
#   - Total self-imposed budget: 15s. Session start is never delayed past it,
#     and every outcome is exit 0. A pack that cannot update is a nuisance; a
#     pack that cannot start a session is a broken tool.
#   - When it acts, it runs scripts/update.sh and NEVER passes --fresh: the
#     24h cooldown is the supply-chain buffer, and the one path that applies
#     changes with nobody watching is the last place to skip it.
#   - On STATUS=updated it prints EXACTLY ONE line: the JSON control message.
#     Any other STATUS is silent — check-context.sh's banner still informs.
#
# The JSON shape is verified against the Claude Code hooks reference,
# "SessionStart decision control": hookSpecificOutput takes hookEventName,
# additionalContext and reloadSkills (boolean, re-scans the skill and command
# directories after SessionStart hooks finish, so skills this update rewrote are
# live in THIS session rather than the next one). The same reference requires
# that "your hook's stdout must contain only the JSON object" — mixed prose and
# JSON is not a supported shape, which is why the prose lives in additionalContext
# and everything else this script has to say goes to the log file.
#
# Diagnostics go to .update-state/auto-update.log, never to stdout or stderr.
# Silence toward the session, a paper trail on disk: a hook that cannot explain
# itself and a hook that shouts are both failures, and the log is the seam.

set -u
umask 022

# ── Locations ────────────────────────────────────────────────────────────────
# Resolve the project root from this script's own path, not the caller's cwd —
# a SessionStart hook fires from wherever the session opened. Tolerates both the
# canonical shared/scripts/ home and a plain scripts/ copy.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  PARENT="$(dirname "$SCRIPT_DIR")"
  if [ "$(basename "$PARENT")" = "shared" ]; then ROOT="$(dirname "$PARENT")"; else ROOT="$PARENT"; fi
else
  ROOT="$SCRIPT_DIR"
fi

STATE_DIR="$ROOT/.update-state"
CONFIG="$STATE_DIR/config"
STAMP="$STATE_DIR/last-auto-update"
SNOOZE="$STATE_DIR/update-snoozed"
LOG="$STATE_DIR/auto-update.log"
UPDATE_SH="$ROOT/scripts/update.sh"

THROTTLE_SECONDS=3600   # spec §4: at most one ATTEMPT per hour
BUDGET_SECONDS=14       # under the 15s ceiling, with room for the trailing work

# ── Logging (never stdout, never stderr) ─────────────────────────────────────
log() {
  [ -d "$STATE_DIR" ] || return 0
  printf '%s auto-update: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')" "$*" >> "$LOG" 2>/dev/null
  # Keep the file bounded; a session-start log that grows forever is its own bug.
  if [ -f "$LOG" ]; then
    local n
    n="$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"
    case "$n" in
      ''|*[!0-9]*) : ;;
      *) if [ "$n" -gt 500 ]; then
           tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
         fi ;;
    esac
  fi
  return 0
}

# ── Kill switch, env half (spec §5) ──────────────────────────────────────────
# The env override wins over the config file and is checked FIRST, before any
# file is read and long before any git call. Off means off: zero network.
case "${NOVOADS_PACK_NO_UPDATE_CHECK:-}" in
  ''|0|false|FALSE|no|NO|off|OFF) : ;;
  *) exit 0 ;;
esac

# ── Config (spec §5) ─────────────────────────────────────────────────────────
# key=value lines. Unreadable or absent = defaults, which are the safe ones:
# checking on, applying off. A malformed config must never be read as consent.
cfg_get() {
  local key="$1" default="$2" val=""
  if [ -f "$CONFIG" ] && [ -r "$CONFIG" ]; then
    val="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*\$/\1/p" \
      "$CONFIG" 2>/dev/null | tr -d '\r' | tail -1)"
  fi
  [ -n "$val" ] || val="$default"
  printf '%s' "$val"
}

is_on() {
  case "$1" in on|ON|On|true|TRUE|True|yes|YES|1) return 0 ;; *) return 1 ;; esac
}

UPDATE_CHECK="$(cfg_get update_check on)"
AUTO_APPLY="$(cfg_get auto_apply off)"

is_on "$UPDATE_CHECK" || exit 0        # kill switch, config half — silence, no network
is_on "$AUTO_APPLY"   || exit 0        # notify-only is the default; consent has not been given

# ── Preconditions ────────────────────────────────────────────────────────────
# scripts/update.sh may legitimately not be here: an older clone, a partial
# checkout, a vendored copy. Missing apply path = nothing to do, quietly.
[ -f "$UPDATE_SH" ] || exit 0
[ -d "$ROOT/.git" ] || git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

now="$(date +%s 2>/dev/null)" || exit 0
case "$now" in ''|*[!0-9]*) exit 0 ;; esac

# ── Throttle (spec §4) ───────────────────────────────────────────────────────
# One ATTEMPT per hour, not one success — an update.sh that fails fast would
# otherwise be re-run on every session in a rapid open/close cycle.
if [ -f "$STAMP" ]; then
  last="$(tr -cd '0-9' < "$STAMP" 2>/dev/null | head -c 20)"
  if [ -n "$last" ] && [ "$last" -gt 0 ] 2>/dev/null; then
    age=$(( now - last ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$THROTTLE_SECONDS" ]; then
      exit 0
    fi
  fi
  # A stamp that will not parse is treated as absent: fail toward updating a
  # consenting user rather than stranding them behind an unreadable byte.
fi

# ── Snooze ───────────────────────────────────────────────────────────────────
# Written by the novoads-update skill's "Not now". Format, key=value:
#   level=<1|2|3+>   the ladder position (1=24h, 2=48h, 3+=7d)
#   until=<epoch>    when the snooze lapses
#   version=<sha>    the upstream commit that was snoozed on
#
# A snooze is honored here because "not now" is an answer about unattended
# change, and applying one while that request stands would be reading consent
# out of a refusal. It never touches the MANUAL path: ./scripts/update.sh
# ignores this file entirely, which is spec §5's rule that a switch stranding
# the manual path is not a switch.
#
# Three ways it lapses, and all three resolve toward acting rather than staying
# quiet: the clock runs out, a NEW upstream commit arrives (the answer was about
# the version in hand, not about updates forever), or the file does not parse.
# `git rev-parse` reads an already-fetched ref — no network call happens here.
if [ -f "$SNOOZE" ]; then
  snooze_until="$(sed -n 's/^[[:space:]]*until[[:space:]]*=[[:space:]]*\([0-9]*\).*$/\1/p' "$SNOOZE" 2>/dev/null | tail -1)"
  snooze_ver="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*\([0-9a-fA-F]*\).*$/\1/p' "$SNOOZE" 2>/dev/null | tail -1)"
  if [ -n "$snooze_until" ] && [ "$snooze_until" -gt "$now" ] 2>/dev/null; then
    upstream_sha="$(git -C "$ROOT" rev-parse origin/main 2>/dev/null || true)"
    if [ -z "$snooze_ver" ] || [ -z "$upstream_sha" ] || [ "$snooze_ver" = "$upstream_sha" ]; then
      log "snoozed until $snooze_until; skipping"
      exit 0
    fi
    log "snooze reset: upstream moved to $upstream_sha"
  fi
fi

# ── The attempt ──────────────────────────────────────────────────────────────
# Stamp BEFORE running. If update.sh dies in a way that takes this process with
# it, the next session must still be throttled rather than retrying in a loop.
printf '%s\n' "$now" > "$STAMP" 2>/dev/null

# Capture update.sh's output OUTSIDE the repository, and not merely for tidiness:
# update.sh stashes the working tree (`git stash -u`) as part of doing its job.
# A capture file living under the repo root is untracked, so the stash absorbs
# it MID-RUN — the redirect keeps writing to an unlinked inode and the pop
# restores the empty version it stashed. Measured here: update.sh applied the
# update, exited 0, and this script read back an empty buffer, saw no STATUS
# line, and stayed silent about an update that had actually landed. The buffer
# cannot live in the tree it is watching get rewritten.
TMPBASE="${TMPDIR:-/tmp}"
CAPTURE="$(mktemp -d "$TMPBASE/novoads-auto-update.XXXXXX" 2>/dev/null)" || exit 0
OUT_F="$CAPTURE/out"
ERR_F="$CAPTURE/err"
: > "$OUT_F" 2>/dev/null || exit 0
: > "$ERR_F" 2>/dev/null || true

cleanup() {
  case "$CAPTURE" in
    */novoads-auto-update.*) rm -rf "$CAPTURE" 2>/dev/null ;;
  esac
}
trap cleanup EXIT INT TERM HUP

# Bound the child ourselves. `timeout(1)` is not on stock macOS, so the fallback
# is the one that has to be right. TERM first, so update.sh's own trap runs and
# restores .env and drops its lock; KILL only if it ignores that.
(
  cd "$ROOT" 2>/dev/null || exit 97
  bash "$UPDATE_SH" >"$OUT_F" 2>"$ERR_F"
) &
child=$!

waited=0
limit=$(( BUDGET_SECONDS * 5 ))
while kill -0 "$child" 2>/dev/null && [ "$waited" -lt "$limit" ]; do
  sleep 0.2
  waited=$(( waited + 1 ))
done

if kill -0 "$child" 2>/dev/null; then
  kill -TERM "$child" 2>/dev/null
  grace=0
  while kill -0 "$child" 2>/dev/null && [ "$grace" -lt 10 ]; do sleep 0.1; grace=$(( grace + 1 )); done
  kill -KILL "$child" 2>/dev/null
  wait "$child" 2>/dev/null
  log "update.sh exceeded the ${BUDGET_SECONDS}s budget; signalled and stood down"
  exit 0
fi
wait "$child" 2>/dev/null
rc=$?

# ── Read the wire contract (spec §2) ─────────────────────────────────────────
# The STATUS line is the API. Human prose in update.sh's output is ignored on
# purpose: branching on it is how a status parser starts lying the first time
# someone reflows a sentence.
status_line="$(grep '^STATUS=' "$OUT_F" 2>/dev/null | tail -1)"
status_tok="$(printf '%s' "$status_line" | sed -n 's/^STATUS=\([^ ]*\).*$/\1/p')"

log "update.sh rc=$rc status='${status_line:-<none>}'"
if [ -s "$ERR_F" ]; then
  sed 's/^/    | /' "$ERR_F" >> "$LOG" 2>/dev/null
fi

# Anything other than a clean update stays silent. `updated_with_conflict` is
# deliberately in the silent set: work is parked in a stash and that needs a
# human reading a banner, not one line of injected context at session start.
[ "$status_tok" = "updated" ] || exit 0

# Read one KEY=value field off the STATUS line, then harden it. Values are SHAs;
# constraining them to hex is what lets this script emit JSON with no encoder
# available — nothing that survives the filter can escape a JSON string.
field() {
  local k="$1" tok
  for tok in $status_line; do
    case "$tok" in "$k"=*) printf '%s' "${tok#$k=}" | tr -cd '0-9a-fA-F' | head -c 40; return 0 ;; esac
  done
  return 1
}

from_sha="$(field FROM)"
to_sha="$(field TO)"
[ -n "$from_sha" ] || from_sha="unknown"
[ -n "$to_sha" ] || to_sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null | tr -cd '0-9a-fA-F')"
[ -n "$to_sha" ] || to_sha="unknown"

# EXACTLY ONE line on stdout, and it is the whole of stdout.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true,"additionalContext":"novoads pack auto-updated %s->%s; changelog summary follows in banner"}}\n' \
  "$from_sha" "$to_sha"

exit 0
