#!/usr/bin/env bash
# scripts/update.sh — upgrade this cloned skill pack without eating your .env.
#
# WHY THIS EXISTS, in one measured sentence: `git pull` silently destroys a
# gitignored `.env` — exit 0, no warning — the moment upstream begins tracking
# that path. Git refuses to clobber an untracked file, but treats an IGNORED one
# as expendable, and `git stash -u` does not rescue it either. The only safe
# answer is an explicit out-of-band copy of the file around the merge, which is
# what this script does and why the banner no longer recommends a raw pull.
#
# THE CONTRACT (the API is the STATUS line, not the prose):
#   Exactly ONE `STATUS=` line is printed to stdout. Everything a human reads
#   goes to stderr. Callers branch on the STATUS token and on the exit code.
#
#     STATUS=updated FROM=<sha> TO=<sha>
#     STATUS=current
#     STATUS=updated_with_conflict FROM=<sha> TO=<sha> STASH=<ref>
#     STATUS=offline
#     STATUS=blocked REASON=diverged|detached_head|no_such_remote|dirty_unresolvable|lock_held
#     STATUS=interrupted
#     STATUS=rolled_back TO=<sha>
#
#   exit 0 — the repo is in a usable state (updated / current / offline /
#            updated_with_conflict / rolled_back).
#   exit 1 — a decision is required and the repo was left EXACTLY as found.
#   An interrupt exits nonzero, with `.env` restored and no partial merge.
#
# USAGE
#   ./scripts/update.sh              install the newest commit older than 24h
#   ./scripts/update.sh --fresh      install the tip instead (see the warning)
#   ./scripts/update.sh --rollback   undo the last update (git reset HEAD@{1})
#
# ENVIRONMENT
#   PACK_REMOTE            remote name           (default: origin)
#   PACK_BRANCH            branch                (default: main)
#   PACK_NET_TIMEOUT       seconds per network call (default: 10)
#   PACK_UPDATE_COOLDOWN   git date expression   (default: "24 hours ago")
#   PACK_REPO_DIR          repo root override    (default: this script's parent)
#
# WHY THE COOLDOWN. `--ff-only` buys integrity of HISTORY, not of CONTENT: an
# appended malicious commit is a perfectly clean fast-forward with exit 0 and no
# marker of any kind. The dangerous update is the one that SUCCEEDS. Package
# managers converged on the same cheap defense in 2025-26 (npm min-release-age,
# pnpm minimumReleaseAge, VS Code's extension delay) because malicious-version
# takedown latency is measured in hours: install the newest commit that has been
# public long enough for someone else to have noticed, not the tip.
#
# NOTE ON SHAPE: the whole program lives inside main(). This script can REPLACE
# ITSELF mid-run — that is literally its job — and bash reads a script
# incrementally from a byte offset, so a file that changes underneath a running
# shell resumes at the wrong place. Parsing the entire body as one function
# before any merge runs deletes that class of failure.

set -u

# ── Configuration ────────────────────────────────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The script lives at <root>/scripts/update.sh, so the repo root is one level up.
REPO_DIR="${PACK_REPO_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
REMOTE="${PACK_REMOTE:-origin}"
BRANCH="${PACK_BRANCH:-main}"
NET_TIMEOUT="${PACK_NET_TIMEOUT:-10}"
COOLDOWN="${PACK_UPDATE_COOLDOWN:-24 hours ago}"

STATE_DIR="$REPO_DIR/.update-state"
LOCK_DIR="$STATE_DIR/lock"
LOCK_STALE_MIN=60          # a lock older than an hour belonged to a dead run

# Credential hardening. Without these a headless run hangs forever on a
# credential prompt; Apple's git ships a SECOND system gitconfig inside Xcode.app
# with credential.helper=osxkeychain, so a dev Mac silently authenticates and
# fails to reproduce the hang. Every network call also carries
# `-c credential.helper=` on the command line, which is the only form that beats
# both system configs.
export GIT_TERMINAL_PROMPT=0
export GIT_OPTIONAL_LOCKS=0
if [ -x /usr/bin/true ]; then
  export GIT_ASKPASS=/usr/bin/true
elif [ -x /bin/true ]; then
  export GIT_ASKPASS=/bin/true
fi

# ── Run state ────────────────────────────────────────────────────────────────
STATUS_EMITTED=0
LOCK_OWNED=0
ENV_BACKUP=""
DO_ROLLBACK=0
USE_FRESH=0

# ── Small helpers ────────────────────────────────────────────────────────────

# Everything a human reads goes to stderr, so stdout stays a wire.
say() { printf '%s\n' "$*" >&2; }

# The STATUS line, printed at most once. A second one would make the wire
# ambiguous, and an interrupt arriving after a decision must not overwrite it.
emit() {
  [ "$STATUS_EMITTED" -eq 0 ] || return 0
  STATUS_EMITTED=1
  printf '%s\n' "$*"
}

# A 12-character prefix of a sha. Always a genuine prefix of the full object
# name, which is what a consumer comparing FROM=/TO= against `git rev-parse`
# needs; `--short` would be too, but this costs no process.
short() { printf '%.12s' "$1"; }

# git, credential-hardened. Used for EVERY invocation, not only the network
# ones: uniformity is cheaper to audit than a rule about which calls count.
g() { git -c credential.helper= "$@"; }

# Bounded execution. `timeout(1)` is NOT on stock macOS, and git's own
# GIT_HTTP_LOW_SPEED_* knobs do not bound the CONNECT phase — a blackhole
# address takes 75 seconds to fail naturally. So: coreutils when present, an
# explicit watchdog when not. Returns 124 on the timeout, like timeout(1).
run_bounded() {
  secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  "$@" &
  _rb_pid=$!
  _rb_n=0
  while kill -0 "$_rb_pid" 2>/dev/null && [ "$_rb_n" -lt "$secs" ]; do
    sleep 1
    _rb_n=$((_rb_n + 1))
  done
  if kill -0 "$_rb_pid" 2>/dev/null; then
    kill -9 "$_rb_pid" 2>/dev/null
    wait "$_rb_pid" 2>/dev/null
    return 124
  fi
  wait "$_rb_pid"
  return $?
}

# ── The .env guard ───────────────────────────────────────────────────────────
# Non-negotiable, and the reason this script exists. The backup is a plain copy
# taken out of git's reach; the restore runs on every exit path including a
# signal, because a Ctrl-C between the merge and the restore would otherwise
# leave the customer's key replaced by upstream's template.

ensure_state_dir() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  # Self-ignoring, so this directory can never read as the customer's diff and
  # can never be swept into a stash — even in a clone whose .gitignore predates
  # the `.update-state/` line, or one where the customer edited it.
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null || true
  return 0
}

backup_env() {
  [ -f "$REPO_DIR/.env" ] || return 0
  if ensure_state_dir; then
    ENV_BACKUP="$STATE_DIR/env.bak"
  else
    ENV_BACKUP="$(mktemp "${TMPDIR:-/tmp}/pack-env.XXXXXX" 2>/dev/null || true)"
    [ -n "$ENV_BACKUP" ] || return 0
  fi
  if ! cat "$REPO_DIR/.env" > "$ENV_BACKUP" 2>/dev/null; then
    ENV_BACKUP=""
    say "NOTE=could not back up .env; refusing to risk it is not possible here, proceeding read-only."
    return 1
  fi
  chmod 600 "$ENV_BACKUP" 2>/dev/null || true
  return 0
}

restore_env() {
  [ -n "$ENV_BACKUP" ] || return 0
  if [ ! -f "$ENV_BACKUP" ]; then ENV_BACKUP=""; return 0; fi
  if [ ! -f "$REPO_DIR/.env" ] || ! cmp -s "$REPO_DIR/.env" "$ENV_BACKUP"; then
    cat "$ENV_BACKUP" > "$REPO_DIR/.env" 2>/dev/null || true
    say "NOTE=.env was restored — upstream's copy of that path would have replaced your key."
  fi
  rm -f "$ENV_BACKUP" 2>/dev/null || true
  ENV_BACKUP=""
}

# ── The lock ─────────────────────────────────────────────────────────────────
# `mkdir` is the atomic primitive (the same one oh-my-zsh uses). A lock older
# than an hour belonged to a run that died; honoring it forever would strand
# updates on a machine that crashed once.

acquire_lock() {
  ensure_state_dir || return 0        # unwritable state dir: proceed unlocked
  if mkdir "$LOCK_DIR" 2>/dev/null; then LOCK_OWNED=1; return 0; fi
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +"$LOCK_STALE_MIN" 2>/dev/null)" ]; then
    rm -rf "$LOCK_DIR" 2>/dev/null
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      LOCK_OWNED=1
      say "NOTE=reclaimed an update lock older than ${LOCK_STALE_MIN}m; its owner is gone."
      return 0
    fi
  fi
  return 1
}

release_lock() {
  [ "$LOCK_OWNED" -eq 1 ] || return 0     # never remove a lock we do not own
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  LOCK_OWNED=0
}

# ── Traps ────────────────────────────────────────────────────────────────────
# The EXIT trap deliberately never calls `exit`, so the script's own status is
# preserved. The signal trap has to: it is the only place that can report an
# interrupt, and it must leave no partial merge behind it.

on_exit() {
  restore_env
  release_lock
}

on_signal() {
  trap - INT TERM HUP
  if [ -n "${GIT_DIR_PATH:-}" ] && [ -e "$GIT_DIR_PATH/MERGE_HEAD" ]; then
    g merge --abort >/dev/null 2>&1 || true
  fi
  restore_env
  emit "STATUS=interrupted"
  say "HINT=Interrupted. Nothing is half-applied and your .env is intact."
  release_lock
  exit 130
}

# ── The rollback path ────────────────────────────────────────────────────────
# `git reset --hard HEAD@{1}`, guarded. `.env` is excluded from the dirty check
# on purpose: once upstream tracks that path, the customer's own key reads as an
# uncommitted modification forever, which would make rollback permanently
# unavailable to exactly the people the .env guard exists for. It is safe to
# exclude because the reset is bracketed by the same backup/restore as a merge.

rollback_path() {
  dirty="$(g status --porcelain 2>/dev/null | grep -v '^.. \.env$' || true)"
  if [ -n "$dirty" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable"
    say "HINT=Uncommitted work would be destroyed by a hard reset. Nothing was changed."
    say "HINT=Commit or stash it, then re-run: ./scripts/update.sh --rollback"
    return 1
  fi

  prev="$(g rev-parse --verify --quiet 'HEAD@{1}' 2>/dev/null || true)"
  if [ -z "$prev" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=no_reflog_entry"
    say "HINT=There is no previous HEAD in the reflog to roll back to. Nothing was changed."
    return 1
  fi

  backup_env
  if ! g reset --hard --quiet "$prev" >/dev/null 2>&1; then
    restore_env
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=reset_failed"
    say "HINT=git could not reset to $(short "$prev"). Nothing was changed."
    return 1
  fi
  restore_env

  emit "STATUS=rolled_back TO=$(short "$prev")"
  say "HINT=Back at $(short "$prev"). Run ./scripts/update.sh when you want the update again."
  run_sync_skill
  return 0
}

# ── After a successful update ────────────────────────────────────────────────
# Both are non-fatal by contract: the update itself already landed, and reporting
# it as a failure because a follow-up step complained would be a lie about the
# repo's state. Their output goes to stderr so the wire stays clean.

run_sync_skill() {
  [ -f "$REPO_DIR/shared/scripts/sync-skill.sh" ] || return 0
  if ! bash "$REPO_DIR/shared/scripts/sync-skill.sh" >&2; then
    say "NOTE=sync-skill.sh reported a failure; the update itself stands. Re-run it by hand."
  fi
}

run_migrations() {
  [ -f "$REPO_DIR/migrations/run.sh" ] || return 0
  if ! bash "$REPO_DIR/migrations/run.sh" >&2; then
    say "NOTE=the migration runner reported a failure; the update itself stands."
  fi
}

# ── The update path ──────────────────────────────────────────────────────────

update_path() {
  # A renamed remote is a MISCONFIGURATION, and calling it `offline` would make
  # updates stop forever while looking like weather.
  if ! g config --get "remote.${REMOTE}.url" >/dev/null 2>&1; then
    known="$(g remote 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
    emit "STATUS=blocked REASON=no_such_remote REMOTE=$REMOTE"
    say "HINT=No remote named '$REMOTE'. Known remotes: ${known:-none}."
    say "HINT=Re-run with PACK_REMOTE=<name>, or: git remote add $REMOTE <url>"
    return 1
  fi

  # A detached HEAD is a deliberately pinned checkout. Never move one silently.
  cur_branch="$(g symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -z "$cur_branch" ]; then
    emit "STATUS=blocked REASON=detached_head HEAD=$(short "$(g rev-parse HEAD 2>/dev/null || echo unknown)")"
    say "HINT=This clone is pinned to a commit. To follow the branch again:"
    say "HINT=  git checkout $BRANCH && ./scripts/update.sh"
    return 1
  fi

  # Offline must FAIL OPEN: the pack still works without the update, and a
  # session that refuses to start because a laptop is on a plane is worse than a
  # stale skill.
  if ! run_bounded "$NET_TIMEOUT" git -c credential.helper= fetch --quiet "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
    emit "STATUS=offline"
    say "HINT=Could not reach $REMOTE within ${NET_TIMEOUT}s. Nothing was changed."
    return 0
  fi

  local_sha="$(g rev-parse HEAD 2>/dev/null || true)"
  remote_sha="$(g rev-parse --verify --quiet "$REMOTE/$BRANCH" 2>/dev/null || true)"
  if [ -z "$remote_sha" ]; then
    emit "STATUS=blocked REASON=no_such_remote REMOTE=$REMOTE/$BRANCH"
    say "HINT=The fetch succeeded but $REMOTE/$BRANCH does not resolve. Check PACK_BRANCH."
    return 1
  fi

  # Divergence, including an upstream force-push. Refuse rather than guess —
  # this check runs BEFORE anything is stashed, so a blocked run leaves the
  # repo byte-identical to how it was found.
  base="$(g merge-base HEAD "$REMOTE/$BRANCH" 2>/dev/null || true)"
  if [ "$base" != "$local_sha" ]; then
    ahead="$(g rev-list --count "$REMOTE/$BRANCH..HEAD" 2>/dev/null || echo '?')"
    emit "STATUS=blocked REASON=diverged LOCAL_COMMITS=$ahead"
    say "HINT=Local history differs from upstream (your own commits, or upstream rewrote history)."
    say "HINT=Nothing was changed. To discard local commits and take upstream:"
    say "HINT=  git reset --hard $REMOTE/$BRANCH"
    return 1
  fi

  if [ "$local_sha" = "$remote_sha" ]; then
    emit "STATUS=current AT=$(short "$local_sha")"
    return 0
  fi

  # The cooldown target: the newest commit that has been public long enough for
  # someone other than its author to have looked at it.
  if [ "$USE_FRESH" -eq 1 ]; then
    target="$remote_sha"
  else
    target="$(g rev-list -1 --before="$COOLDOWN" "$REMOTE/$BRANCH" 2>/dev/null || true)"
  fi

  if [ -z "$target" ] || [ "$target" = "$local_sha" ]; then
    emit "STATUS=current AT=$(short "$local_sha")"
    say "NOTE=upstream has newer commits, all of them inside the '$COOLDOWN' cooldown window."
    say "NOTE=They install on their own once they age out. To take them now: ./scripts/update.sh --fresh"
    return 0
  fi

  # The cooldown walks commit dates, so on a non-linear history it can name a
  # commit that is not a descendant of HEAD. Installing that would be a rewind.
  if ! g merge-base --is-ancestor "$local_sha" "$target" 2>/dev/null; then
    emit "STATUS=current AT=$(short "$local_sha")"
    say "NOTE=the cooldown target is not a descendant of HEAD; nothing was safely installable."
    return 0
  fi

  # From here on the tree can move, so the .env copy is taken first.
  backup_env

  # The stash decision reads `status --porcelain`, NOT `git diff`. A diff does
  # not see untracked files, so a customer-authored file colliding with a NEW
  # upstream file slips past a diff-only check and then aborts the merge.
  stashed=no
  pre_stash="$(g rev-parse --verify --quiet refs/stash 2>/dev/null || true)"
  if [ -n "$(g status --porcelain 2>/dev/null)" ]; then
    g stash push --quiet --include-untracked -m "pack-update-$(date +%s)" >/dev/null 2>&1 || true
    post_stash="$(g rev-parse --verify --quiet refs/stash 2>/dev/null || true)"
    # "No local changes to save" exits 0 and creates nothing; popping on that
    # assumption would restore somebody else's older stash on top of the update.
    if [ -n "$post_stash" ] && [ "$post_stash" != "$pre_stash" ]; then stashed=yes; fi
  fi

  # NOT wrapped in a command substitution, deliberately: a subshell here would
  # sit between git and this script in the process tree, and a signal delivered
  # mid-merge would land on the subshell instead of on the trap that restores
  # .env. The merge's output is captured through a file for the same reason.
  merge_log="$STATE_DIR/merge.log"
  ensure_state_dir || merge_log="/dev/null"
  if ! g merge --ff-only --quiet "$target" >"$merge_log" 2>&1; then
    [ "$stashed" = yes ] && g stash pop --quiet >/dev/null 2>&1
    restore_env
    rm -f "$merge_log" 2>/dev/null || true
    emit "STATUS=blocked REASON=dirty_unresolvable"
    say "HINT=Local files block the fast-forward and could not be set aside safely."
    say "HINT=Nothing was changed. Move or commit them, then re-run ./scripts/update.sh"
    return 1
  fi
  rm -f "$merge_log" 2>/dev/null || true

  new_sha="$(g rev-parse HEAD 2>/dev/null || true)"

  # A stash-pop conflict must NEVER be left in the tree. Conflict markers inside
  # a SKILL.md are not a merge state an agent recognises — they are content it
  # reads and follows. So: hard-return to the clean post-merge tree and leave the
  # customer's work in the stash, named on the wire.
  conflict=no
  stash_ref='stash@{0}'
  if [ "$stashed" = yes ]; then
    if ! g stash pop --quiet >/dev/null 2>&1; then
      conflict=yes
      g checkout -- . >/dev/null 2>&1 || true
      g reset --hard --quiet HEAD >/dev/null 2>&1 || true
      # Name the ref only if it really resolves — a STASH= field pointing at
      # nothing is worse than none, because it reads as "your work is over there".
      g rev-parse --verify --quiet 'stash@{0}' >/dev/null 2>&1 || stash_ref='none'
    fi
  fi

  restore_env

  if [ "$conflict" = yes ]; then
    emit "STATUS=updated_with_conflict FROM=$(short "$local_sha") TO=$(short "$new_sha") STASH=$stash_ref"
    say "HINT=The update landed. Your local edits conflicted with it and were SET ASIDE, not lost."
    say "HINT=Recover them with:  git stash list   then   git stash pop"
  else
    emit "STATUS=updated FROM=$(short "$local_sha") TO=$(short "$new_sha")"
    say "HINT=Updated $(short "$local_sha") -> $(short "$new_sha")."
  fi

  run_sync_skill
  run_migrations
  return 0
}

# ── main ─────────────────────────────────────────────────────────────────────

usage() {
  say "Usage: ./scripts/update.sh [--fresh | --rollback]"
  say "  (no flag)    install the newest upstream commit older than 24h"
  say "  --fresh      install the tip instead, skipping the cooldown"
  say "  --rollback   undo the last update (git reset --hard HEAD@{1})"
}

main() {
  for arg in ${1+"$@"}; do
    case "$arg" in
      --rollback) DO_ROLLBACK=1 ;;
      --fresh)    USE_FRESH=1 ;;
      -h|--help)  usage; exit 0 ;;
      *)          say "NOTE=ignoring unrecognized argument: $arg" ;;
    esac
  done

  if [ "$USE_FRESH" -eq 1 ]; then
    say "WARNING=--fresh takes the upstream tip, skipping the 24h cooldown that exists because a malicious appended commit is an ordinary clean fast-forward."
  fi

  if ! cd "$REPO_DIR" 2>/dev/null; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=bad_repo_dir"
    say "HINT=Could not enter $REPO_DIR."
    exit 1
  fi

  GIT_DIR_PATH="$(g rev-parse --git-dir 2>/dev/null || true)"
  if [ -z "$GIT_DIR_PATH" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=not_a_git_repo"
    say "HINT=$REPO_DIR is not a git clone, so there is no update channel to follow."
    say "HINT=Re-clone the pack, or update it the way you installed it."
    exit 1
  fi

  trap on_exit EXIT
  trap on_signal INT TERM HUP

  if ! acquire_lock; then
    emit "STATUS=blocked REASON=lock_held"
    say "HINT=Another update is already running (.update-state/lock). Nothing was changed."
    say "HINT=If nothing is running, remove it: rm -rf .update-state/lock"
    exit 1
  fi

  if [ "$DO_ROLLBACK" -eq 1 ]; then
    rollback_path
    exit $?
  fi

  update_path
  exit $?
}

main ${1+"$@"}; exit $?
