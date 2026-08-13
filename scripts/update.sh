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
#   `--help` is the one exit outside the wire: usage text, exit 0, no STATUS.
#
# USAGE
#   ./scripts/update.sh              install the newest commit older than 24h
#   ./scripts/update.sh --fresh      install the tip instead (see the warning)
#   ./scripts/update.sh --rollback   undo the update this script last applied
#
# ENVIRONMENT
#   PACK_NET_TIMEOUT   seconds per network call (default: 10). The ONLY knob.
#     Remote, branch and cooldown were overridable in the first draft and are
#     not any more: nothing needed them, and an env var that can quietly lower
#     the supply-chain bound is a hole with a config file's manners.
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

# The wire and the prose get their own file descriptors, dup'd from the real
# ones before anything else happens. This is not tidiness: a trap handler runs
# with the REDIRECTIONS OF THE COMMAND IT INTERRUPTED still in effect, so a
# `STATUS=interrupted` printed to plain stdout during, say, `git stash pop
# >/dev/null 2>&1` goes into that /dev/null and the caller sees no status line
# at all for a run that left the repo mid-flight. Measured, and the reason
# every emit below is `>&3`.
exec 3>&1
exec 4>&2

# ── Configuration ────────────────────────────────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The script lives at <root>/scripts/update.sh, so the repo root is one level up.
REPO_DIR="$(cd "$SELF_DIR/.." && pwd)"
REMOTE="origin"
BRANCH="main"
NET_TIMEOUT="${PACK_NET_TIMEOUT:-10}"
COOLDOWN="24 hours ago"

STATE_DIR="$REPO_DIR/.update-state"
LOCK_DIR="$STATE_DIR/lock"
RECORD="$STATE_DIR/last-update"
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
ENV_WAS_SYMLINK=0
ENV_LINK_TARGET=""
STASHED=no
DO_ROLLBACK=0
USE_FRESH=0
GIT_DIR_PATH=""

# ── Small helpers ────────────────────────────────────────────────────────────

# Everything a human reads goes to stderr, so stdout stays a wire.
say() { printf '%s\n' "$*" >&4; }

# The STATUS line, printed at most once, on the descriptor that is still the
# real stdout no matter what was being redirected when we got here.
emit() {
  [ "$STATUS_EMITTED" -eq 0 ] || return 0
  STATUS_EMITTED=1
  printf '%s\n' "$*" >&3
}

# A 12-character prefix of a sha. Always a genuine prefix of the full object
# name, which is what a consumer comparing FROM=/TO= against `git rev-parse`
# needs; `--short` would be too, but this costs no process.
short() { printf '%.12s' "$1"; }

# git, credential-hardened. Used for EVERY invocation, not only the network
# ones: uniformity is cheaper to audit than a rule about which calls count.
#
# `3>&- 4>&-` closes the wire and the prose to the child. Descriptors are
# INHERITED, so without this a repo-local hook — a post-merge hook is the easy
# one, and `git merge` runs whatever the clone carries — can `echo >&3` and put
# a line on stdout AHEAD of the STATUS line, which is the whole contract. One
# chokepoint, because a rule about which git calls can reach a hook is a rule
# somebody gets wrong later.
g() { git -c credential.helper= "$@" 3>&- 4>&-; }

# Bounded execution. `timeout(1)` is NOT on stock macOS, and git's own
# GIT_HTTP_LOW_SPEED_* knobs do not bound the CONNECT phase — a blackhole
# address takes 75 seconds to fail naturally. So: coreutils when present, an
# explicit watchdog when not. Returns 124 on the timeout, like timeout(1).
# `3>&- 4>&-` here for the same reason as in g(): this runs git directly rather
# than through the wrapper, because `timeout` cannot invoke a shell function.
run_bounded() {
  secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@" 3>&- 4>&-; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@" 3>&- 4>&-; return $?; fi
  "$@" 3>&- 4>&- &
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

ensure_state_dir() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  # Self-ignoring, so this directory can never read as the customer's diff and
  # can never be swept into a stash — even in a clone whose .gitignore predates
  # the `.update-state/` line, or one where the customer edited it.
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null || true
  return 0
}

# ── The .env guard ───────────────────────────────────────────────────────────
# Non-negotiable, and the reason this script exists. The backup is a plain copy
# taken out of git's reach; the restore runs on every exit path including a
# signal, because a Ctrl-C between the merge and the restore would otherwise
# leave the customer's key replaced by upstream's template.
#
# NO BACKUP, NO MUTATION. A failed backup used to warn and carry on, which is
# the worst of both worlds: the guard reports itself as present, the merge runs
# anyway, and a key can be destroyed under a `STATUS=updated exit 0`. Every
# caller now refuses instead. The copy is verified with cmp rather than trusted
# from a redirect's exit code, because a truncated backup and a real one look
# identical to everything downstream.

backup_env() {
  ENV_BACKUP=""
  ENV_WAS_SYMLINK=0
  ENV_LINK_TARGET=""
  [ -e "$REPO_DIR/.env" ] || return 0        # nothing to protect: not a failure

  # A .env that is a symlink into a password store or a shared secrets dir is a
  # deliberate arrangement, and a merge or reset replaces the LINK with a plain
  # file. Remember the shape, not only the bytes.
  if [ -L "$REPO_DIR/.env" ]; then
    ENV_WAS_SYMLINK=1
    ENV_LINK_TARGET="$(readlink "$REPO_DIR/.env" 2>/dev/null || true)"
  fi
  [ -f "$REPO_DIR/.env" ] || return 0        # a dangling link has no bytes to copy

  local candidate=""
  if ensure_state_dir; then
    candidate="$STATE_DIR/env.bak"
  else
    candidate="$(mktemp "${TMPDIR:-/tmp}/pack-env.XXXXXX" 2>/dev/null || true)"
  fi
  [ -n "$candidate" ] || return 1

  # Truncate first: this is the step that fails when the path is a directory, or
  # a leftover with no write bit, and it must fail BEFORE anything is mutated.
  ( umask 077; : > "$candidate" ) 2>/dev/null || return 1
  cat "$REPO_DIR/.env" > "$candidate" 2>/dev/null || return 1
  cmp -s "$REPO_DIR/.env" "$candidate" 2>/dev/null || return 1
  chmod 600 "$candidate" 2>/dev/null || true

  ENV_BACKUP="$candidate"
  return 0
}

# Refuse, loudly and without touching anything, when the guard cannot be armed.
refuse_no_env_backup() {
  emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=env_backup_failed"
  say "HINT=Could not take a verified copy of .env, so nothing was changed."
  say "HINT=This script will not move the tree without one: git treats an ignored"
  say "HINT=.env as expendable the moment upstream tracks that path."
  say "HINT=Check $STATE_DIR is writable and that env.bak is not a directory."
}

restore_env() {
  [ -n "$ENV_BACKUP" ] || return 0
  local bak="$ENV_BACKUP"
  ENV_BACKUP=""                              # idempotent: one restore per backup
  [ -f "$bak" ] || return 0

  local relinked=0
  if [ "$ENV_WAS_SYMLINK" -eq 1 ] && [ -n "$ENV_LINK_TARGET" ] && [ ! -L "$REPO_DIR/.env" ]; then
    rm -f "$REPO_DIR/.env" 2>/dev/null
    if ln -s "$ENV_LINK_TARGET" "$REPO_DIR/.env" 2>/dev/null; then
      relinked=1
    else
      say "NOTE=.env was a symlink to $ENV_LINK_TARGET; the link could not be recreated, so your values are being written back as a regular file."
    fi
  fi

  # Say nothing when nothing happened. The first draft announced a rescue on
  # every run that took a backup, including the overwhelming majority where the
  # file was never touched — a guard that cries every time is a guard nobody
  # reads on the day it matters.
  if [ "$relinked" -eq 0 ] && [ -e "$REPO_DIR/.env" ] && cmp -s "$REPO_DIR/.env" "$bak" 2>/dev/null; then
    rm -f "$bak" 2>/dev/null || true
    return 0
  fi

  if cat "$bak" > "$REPO_DIR/.env" 2>/dev/null; then
    if [ "$relinked" -eq 1 ]; then
      say "NOTE=.env: the symlink to $ENV_LINK_TARGET was recreated and your values written back through it."
    else
      say "NOTE=.env changed during this run and was rewritten from the copy taken before it; the values on disk are yours."
    fi
    rm -f "$bak" 2>/dev/null || true
    return 0
  fi

  say "WARNING=.env could NOT be restored. Your values are kept at: $bak"
  say "WARNING=Copy them back by hand before running anything that needs the key."
  return 1
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

# ── The update record ────────────────────────────────────────────────────────
# `--rollback` used to mean `git reset --hard HEAD@{1}`, which is not "undo the
# update" but "undo the last thing that moved HEAD" — two different sentences
# that diverge the moment anything else moves it. Measured consequences: a
# second --rollback re-INSTALLED the update while reporting rolled_back, and a
# --rollback after an unrelated checkout put the branch on a stranger's commit.
# So the update names itself, and the rollback refuses anything it did not do.

write_update_record() {
  ensure_state_dir || return 0
  printf 'FROM=%s\nTO=%s\nAT=%s\n' "$1" "$2" "$(date +%s 2>/dev/null || echo 0)" \
    > "$RECORD" 2>/dev/null || true
}

record_field() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([0-9a-fA-F]\{1,\}\).*\$/\1/p" \
    "$RECORD" 2>/dev/null | tail -1
}

# ── Traps ────────────────────────────────────────────────────────────────────
# The EXIT trap deliberately never calls `exit`, so the script's own status is
# preserved. The signal trap has to: it is the only place that can report an
# interrupt, and it must leave the repo in a state somebody can read.

# A conflicted `git stash pop` leaves unmerged index entries and `<<<<<<<`
# markers in the tree and does NOT write MERGE_HEAD, so a MERGE_HEAD-only check
# walks straight past the one state that must never survive: conflict markers
# inside a SKILL.md, which an agent does not recognise as a merge — it reads
# them as content and follows them. Recover to exactly what the non-interrupt
# conflict path guarantees: a clean tree, the work in the stash.
recover_unmerged() {
  g ls-files -u 2>/dev/null | grep -q . || return 0
  if [ "$STASHED" = yes ] && g rev-parse --verify --quiet refs/stash >/dev/null 2>&1; then
    g checkout -- . >/dev/null 2>&1 || true
    g reset --hard --quiet HEAD >/dev/null 2>&1 || true
    say "NOTE=interrupted while replaying your local edits; the tree was returned to a clean state."
  else
    # Discarding here would destroy the only copy, so it does not.
    say "WARNING=interrupted with a conflicted index and no stash to fall back on; the tree was left exactly as found."
    say "WARNING=Inspect with: git status   then resolve, or discard with: git reset --hard HEAD"
  fi
}

on_exit() {
  restore_env
  release_lock
}

on_signal() {
  trap - INT TERM HUP
  if [ -n "$GIT_DIR_PATH" ] && [ -e "$GIT_DIR_PATH/MERGE_HEAD" ]; then
    g merge --abort >/dev/null 2>&1 || true
  fi
  recover_unmerged
  # Said on EVERY interrupted run that stashed, not only the one that got as far
  # as a conflict. An interrupt in the merge window leaves the customer's edits
  # sitting in a stash they never asked for and were never told about, and a
  # working tree that silently lost the change you were making is the report we
  # would get instead.
  if [ "$STASHED" = yes ] && g rev-parse --verify --quiet refs/stash >/dev/null 2>&1; then
    say "HINT=Your local edits were set aside before this run touched the tree and are still there:"
    say "HINT=  git stash list   then   git stash pop"
  fi
  restore_env
  emit "STATUS=interrupted"
  say "HINT=Interrupted. Your .env is intact and nothing is half-applied."
  release_lock
  exit 130
}

# ── After a successful update ────────────────────────────────────────────────
# Both are non-fatal by contract: the update itself already landed, and reporting
# it as a failure because a follow-up step complained would be a lie about the
# repo's state. Their output goes to stderr so the wire stays clean.

# Both are handed the prose descriptor and then have BOTH of ours closed, so
# they can talk to the user without being able to reach the wire. The order is
# load-bearing: the dups happen first, so fd1/fd2 survive the close.
run_sync_skill() {
  [ -f "$REPO_DIR/shared/scripts/sync-skill.sh" ] || return 0
  if ! bash "$REPO_DIR/shared/scripts/sync-skill.sh" >&4 2>&4 3>&- 4>&-; then
    say "NOTE=sync-skill.sh reported a failure; the update itself stands. Re-run it by hand."
  fi
}

run_migrations() {
  [ -f "$REPO_DIR/migrations/run.sh" ] || return 0
  if ! bash "$REPO_DIR/migrations/run.sh" >&4 2>&4 3>&- 4>&-; then
    say "NOTE=the migration runner reported a failure; the update itself stands."
  fi
}

# The dirty check both mutating paths share. `.env` is excluded on purpose:
# once upstream tracks that path, the customer's own key reads as an
# uncommitted modification FOREVER, which would make rollback permanently
# unavailable to exactly the people the .env guard exists for. It is safe to
# exclude because every reset here is bracketed by the backup/restore above.
working_tree_dirt() {
  g status --porcelain 2>/dev/null | grep -v '^.. \.env$' || true
}

# ── The rollback path ────────────────────────────────────────────────────────

rollback_path() {
  local from to head dirty

  if [ ! -f "$RECORD" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=no_recorded_update"
    say "HINT=There is no update by this script to undo — nothing was changed."
    say "HINT=(A rollback is cleared once it runs, so this is also what a second one says.)"
    return 1
  fi

  from="$(record_field FROM)"
  to="$(record_field TO)"
  if [ -z "$from" ] || [ -z "$to" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=unreadable_update_record"
    say "HINT=$RECORD does not name a FROM and a TO. Nothing was changed."
    return 1
  fi

  head="$(g rev-parse HEAD 2>/dev/null || true)"
  if [ "$head" != "$to" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=head_moved_since_update"
    say "HINT=HEAD is at $(short "$head"), but the update this would undo ended at $(short "$to")."
    say "HINT=Rolling back now would move you onto an unrelated commit, so it refuses."
    say "HINT=Nothing was changed. To go somewhere deliberately: git reset --hard <commit>"
    return 1
  fi

  if ! g rev-parse --verify --quiet "$from^{commit}" >/dev/null 2>&1; then
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=unknown_rollback_target"
    say "HINT=The recorded pre-update commit $(short "$from") is not in this repository."
    return 1
  fi

  dirty="$(working_tree_dirt)"
  if [ -n "$dirty" ]; then
    emit "STATUS=blocked REASON=dirty_unresolvable"
    say "HINT=Uncommitted work would be destroyed by a hard reset. Nothing was changed."
    say "HINT=Commit or stash it, then re-run: ./scripts/update.sh --rollback"
    return 1
  fi

  if ! backup_env; then refuse_no_env_backup; return 1; fi

  if ! g reset --hard --quiet "$from" >/dev/null 2>&1; then
    restore_env
    emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=reset_failed"
    say "HINT=git could not reset to $(short "$from"). Nothing was changed."
    return 1
  fi
  restore_env
  rm -f "$RECORD" 2>/dev/null || true

  emit "STATUS=rolled_back TO=$(short "$from")"
  say "HINT=Back at $(short "$from"). Run ./scripts/update.sh when you want the update again."
  run_sync_skill
  return 0
}

# ── The update path ──────────────────────────────────────────────────────────

update_path() {
  local cur_branch known local_sha remote_sha base ahead target new_sha
  local pre_stash post_stash merge_log conflict stash_ref

  # A renamed remote is a MISCONFIGURATION, and calling it `offline` would make
  # updates stop forever while looking like weather.
  if ! g config --get "remote.${REMOTE}.url" >/dev/null 2>&1; then
    known="$(g remote 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
    emit "STATUS=blocked REASON=no_such_remote REMOTE=$REMOTE"
    say "HINT=No remote named '$REMOTE'. Known remotes: ${known:-none}."
    say "HINT=Restore it with: git remote add $REMOTE <url>"
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
    say "HINT=The fetch succeeded but $REMOTE/$BRANCH does not resolve."
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

  # From here on the tree can move — so the .env copy is taken first, and a
  # failure to take it stops the run rather than annotating it.
  if ! backup_env; then refuse_no_env_backup; return 1; fi

  # The stash decision reads `status --porcelain`, NOT `git diff`. A diff does
  # not see untracked files, so a customer-authored file colliding with a NEW
  # upstream file slips past a diff-only check and then aborts the merge.
  pre_stash="$(g rev-parse --verify --quiet refs/stash 2>/dev/null || true)"
  if [ -n "$(g status --porcelain 2>/dev/null)" ]; then
    g stash push --quiet --include-untracked -m "pack-update-$(date +%s)" >/dev/null 2>&1 || true
    post_stash="$(g rev-parse --verify --quiet refs/stash 2>/dev/null || true)"
    # "No local changes to save" exits 0 and creates nothing; popping on that
    # assumption would restore somebody else's older stash on top of the update.
    if [ -n "$post_stash" ] && [ "$post_stash" != "$pre_stash" ]; then STASHED=yes; fi
  fi

  # NOT wrapped in a command substitution, deliberately: a subshell here would
  # sit between git and this script in the process tree, and a signal delivered
  # mid-merge would land on the subshell instead of on the trap that restores
  # .env. The merge's output is captured through a file for the same reason.
  # The record is written BEFORE the merge, naming the commit about to be
  # installed. Written after, there is a window — the whole merge, hooks and
  # all — where an interrupt leaves HEAD on the new commit with nothing that
  # knows how to undo it: the update landed and `--rollback` answers
  # no_recorded_update. A record that briefly describes an update still in
  # flight is the cheaper error, because the only thing that reads it refuses
  # unless HEAD is exactly the TO it names.
  prev_record=""
  [ -f "$RECORD" ] && prev_record="$(cat "$RECORD" 2>/dev/null || true)"
  write_update_record "$local_sha" "$target"

  merge_log="$STATE_DIR/merge.log"
  ensure_state_dir || merge_log="/dev/null"
  if ! g merge --ff-only --quiet "$target" >"$merge_log" 2>&1; then
    [ "$STASHED" = yes ] && g stash pop --quiet >/dev/null 2>&1
    restore_env
    rm -f "$merge_log" 2>/dev/null || true
    # Put back whatever was there. Simply deleting would strip an EARLIER
    # update's record because a LATER one failed to start, and take a legitimate
    # rollback with it.
    if [ -n "$prev_record" ]; then
      printf '%s\n' "$prev_record" > "$RECORD" 2>/dev/null || true
    else
      rm -f "$RECORD" 2>/dev/null || true
    fi
    emit "STATUS=blocked REASON=dirty_unresolvable"
    say "HINT=Local files block the fast-forward and could not be set aside safely."
    say "HINT=Nothing was changed. Move or commit them, then re-run ./scripts/update.sh"
    return 1
  fi
  rm -f "$merge_log" 2>/dev/null || true

  new_sha="$(g rev-parse HEAD 2>/dev/null || true)"
  # --ff-only cannot land anywhere but the target, and the record still has to
  # describe what is actually there rather than what was intended.
  [ "$new_sha" = "$target" ] || write_update_record "$local_sha" "$new_sha"

  # A stash-pop conflict must NEVER be left in the tree. Conflict markers inside
  # a SKILL.md are not a merge state an agent recognises — they are content it
  # reads and follows. So: hard-return to the clean post-merge tree and leave the
  # customer's work in the stash, named on the wire.
  conflict=no
  stash_ref='stash@{0}'
  if [ "$STASHED" = yes ]; then
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
  say "  --rollback   undo the update this script last applied"
}

main() {
  for arg in ${1+"$@"}; do
    case "$arg" in
      --rollback) DO_ROLLBACK=1 ;;
      --fresh)    USE_FRESH=1 ;;
      -h|--help)  usage; exit 0 ;;
      # An unknown flag used to be noted and ignored, which meant `--rollbcak`
      # ran a normal update: a typo for "undo it" performing the thing being
      # undone. A flag this script does not understand is a request it cannot
      # honor, so it refuses without touching anything.
      *)
        usage
        emit "STATUS=blocked REASON=dirty_unresolvable DETAIL=bad_usage"
        say "HINT=Unrecognized argument: $arg — nothing was changed."
        exit 1
        ;;
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
