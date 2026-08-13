#!/usr/bin/env bash
# tests/upgrade-harness.sh — the executable gate for the pack upgrade system.
#
# This file lands BEFORE the features it gates. Every case for a feature that is
# not built yet fails with the reason `not_implemented`, which is the expected
# initial state: the red table is the specification, in executable form.
#
# WHAT IT TESTS (the subjects, all optional at any moment in the build):
#   scripts/update.sh              the apply path        spec §2, §3
#   shared/scripts/auto-update.sh  the consent hook      spec §4
#   shared/scripts/check-context.sh the banner + switch  spec §3 tail, §5
#   migrations/run.sh              the migration runner  spec §6
#   .gitignore / .claude/settings.json / skills/novoads-update  structural pins
#
# HOW IT STAYS HONEST
#   - Nothing here touches the real repository's remote, working tree or refs.
#     Every case runs against fixtures built in a mktemp sandbox with its own
#     HOME and its own git config: a bare "origin", an author clone that pushes
#     to it, and a customer clone that is the repo under test.
#   - No case makes a real network call. "Offline" is simulated with an
#     unroutable address (10.255.255.1, RFC 5737 style blackhole) and bounded.
#   - Stock macOS bash 3.2 is the floor: no associative arrays, no mapfile, no
#     `${var,,}`. Stock macOS also has no coreutils `timeout(1)`; the harness
#     detects it, notes it, and has a case that MASKS it to prove the subject's
#     own fallback works.
#   - A capability probe (a grep of the subject) may only ever soften a FAIL's
#     reason to `not_implemented`. A PASS always requires observed behavior.
#     A grep can never turn a case green.
#   - Every subject invocation is bounded by a watchdog, so a hung script is a
#     FAIL with `subject_timed_out`, never a hung harness.
#
# USAGE
#   ./tests/upgrade-harness.sh                 run every case
#   ./tests/upgrade-harness.sh clean_update    run a subset (any number of names)
#   ./tests/upgrade-harness.sh --list          print the manifest
#   PACK_HARNESS_KEEP=1 ...                    keep the sandbox for inspection
#   PACK_UPDATE_SH=/path/to/update.sh ...      test an update.sh from elsewhere
#   PACK_REPO_ROOT=/path/to/pack ...           test a checkout from elsewhere
#
# Exit 0 only when every selected case passes.

set -u
umask 022

# ── Locations ────────────────────────────────────────────────────────────────
HARNESS_SRC="${BASH_SOURCE[0]}"
TESTS_DIR="$(cd "$(dirname "$HARNESS_SRC")" && pwd)"
REPO_ROOT="${PACK_REPO_ROOT:-$(dirname "$TESTS_DIR")}"

UPDATE_SH="${PACK_UPDATE_SH:-$REPO_ROOT/scripts/update.sh}"
AUTO_UPDATE_SH="${PACK_AUTO_UPDATE_SH:-$REPO_ROOT/shared/scripts/auto-update.sh}"
CHECK_CONTEXT_SH="$REPO_ROOT/shared/scripts/check-context.sh"
MIGRATION_RUNNER="$REPO_ROOT/migrations/run.sh"
CONSENT_SKILL="$REPO_ROOT/skills/novoads-update/SKILL.md"
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"
REPO_GITIGNORE="$REPO_ROOT/.gitignore"

REAL_GIT="$(command -v git 2>/dev/null || true)"
[ -n "$REAL_GIT" ] || { echo "harness: git not found on PATH" >&2; exit 2; }
PYTHON="$(command -v python3 2>/dev/null || true)"

HAVE_TIMEOUT=no
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then HAVE_TIMEOUT=yes; fi

# The canary. Every case that touches the tree checks this survived byte for byte.
ENV_CANARY='NOVOADS_API_KEY=novo_live_CANARY_must_survive_every_update'

# Ages, in seconds. The cooldown (spec §3.1) installs the newest commit OLDER
# than 24h, so every "an update is available" fixture commits at 48h old — a
# tip-dated commit would legitimately read as `current` once the cooldown lands.
AGE_OLD=2592000     # 30 days — the base commit
AGE_AGED=172800     # 48h — installable under the cooldown
AGE_FRESH=3600      # 1h — held back by the cooldown

SUBJECT_BUDGET=60   # per-invocation watchdog, seconds

# ── Sandbox ──────────────────────────────────────────────────────────────────
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/pack-upgrade-harness.XXXXXX")" || exit 2
export HOME="$SANDBOX/home"
export XDG_CONFIG_HOME="$SANDBOX/home/.config"
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE 2>/dev/null || true
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

"$REAL_GIT" config -f "$GIT_CONFIG_GLOBAL" user.email harness@example.invalid
"$REAL_GIT" config -f "$GIT_CONFIG_GLOBAL" user.name  "Upgrade Harness"
"$REAL_GIT" config -f "$GIT_CONFIG_GLOBAL" init.defaultBranch main
"$REAL_GIT" config -f "$GIT_CONFIG_GLOBAL" commit.gpgsign false
"$REAL_GIT" config -f "$GIT_CONFIG_GLOBAL" advice.detachedHead false
"$REAL_GIT" config -f "$GIT_CONFIG_GLOBAL" protocol.file.allow always

LAB="$SANDBOX/lab"
UP="$LAB/up.git"; DEV="$LAB/dev"; CUST="$LAB/cust"
SHIM_DIR="$LAB/shim"; SHIM_LOG="$LAB/git-shim.log"
OUT_F="$LAB/stdout"; ERR_F="$LAB/stderr"
NOBIN=""            # built lazily by mask_timeout_path

cleanup() {
  cd / 2>/dev/null || true
  if [ "${PACK_HARNESS_KEEP:-0}" = "1" ]; then
    printf 'harness: sandbox kept at %s\n' "$SANDBOX" >&2
    return 0
  fi
  case "$SANDBOX" in
    */pack-upgrade-harness.*) rm -rf "$SANDBOX" ;;
    *) printf 'harness: refusing to remove unexpected sandbox path %s\n' "$SANDBOX" >&2 ;;
  esac
}
trap cleanup EXIT

# ── Reporting ────────────────────────────────────────────────────────────────
PASS_N=0; FAIL_N=0
RESULT_SET=0; CASE_NAME=""; CASE_ERR=""
FAILED_NAMES=""
NOTES=""

note() { NOTES="${NOTES}${NOTES:+
}$*"; }

bad() { CASE_ERR="${CASE_ERR:+$CASE_ERR; }$*"; }

pass() {
  RESULT_SET=1; PASS_N=$((PASS_N + 1))
  printf 'PASS  %s\n' "$CASE_NAME"
}

fail() {
  RESULT_SET=1; FAIL_N=$((FAIL_N + 1))
  FAILED_NAMES="${FAILED_NAMES}${FAILED_NAMES:+ }$CASE_NAME"
  printf 'FAIL  %s  %s\n' "$CASE_NAME" "$*"
}

# Close a case: any accumulated complaint fails it, silence passes it.
finish() {
  if [ -n "$CASE_ERR" ]; then fail "$CASE_ERR"; else pass; fi
}

# not_implemented — the expected red for a feature nobody has built yet.
ni() { fail "not_implemented${1:+: $1}"; }

# ── Subject capability probes (may only soften a FAIL, never create a PASS) ───
have_update()      { [ -f "$UPDATE_SH" ]; }
have_auto()        { [ -f "$AUTO_UPDATE_SH" ]; }
have_checkctx()    { [ -f "$CHECK_CONTEXT_SH" ]; }
have_migrations()  { [ -f "$MIGRATION_RUNNER" ]; }

# Flag probes take the flag itself; `grep --` keeps the leading dashes literal.
# An earlier version of this file passed `--` twice, so every probe matched the
# `--` inside `git checkout -- .` and reported features that were not there —
# which turned one case GREEN against a script that ignored the flag entirely.
# That is the exact hazard the probe rule exists to prevent, so: probes are
# narrow, and they may only ever soften a FAIL to not_implemented.
update_has_flag()     { grep -q -- "$1" "$UPDATE_SH" 2>/dev/null; }
update_has_lock()     { grep -q 'lock_held' "$UPDATE_SH" 2>/dev/null; }
update_has_cooldown() { grep -qE -- '--before|cooldown' "$UPDATE_SH" 2>/dev/null; }

# ── Portable helpers ─────────────────────────────────────────────────────────
now_epoch() { date +%s; }

# `touch -t` stamp for "N seconds ago", BSD and GNU date alike.
stamp_ago() {
  if date -v-1S +%Y >/dev/null 2>&1; then
    date -v-"$1"S +%Y%m%d%H%M.%S
  else
    date -d "@$(( $(date +%s) - $1 ))" +%Y%m%d%H%M.%S
  fi
}

# ── Fixture construction ─────────────────────────────────────────────────────
make_shim() {
  # A `git` that records every invocation and then becomes the real git. Used to
  # prove what the hooks do and do not do on the network (spec §5) and that the
  # network calls are credential-hardened (spec §3.4).
  mkdir -p "$SHIM_DIR"
  : > "$SHIM_LOG"
  cat > "$SHIM_DIR/git" <<SHIM
#!/bin/sh
printf 'TERMPROMPT=%s ASKPASS=%s ARGS=%s\n' "\${GIT_TERMINAL_PROMPT-unset}" "\${GIT_ASKPASS-unset}" "\$*" >> "$SHIM_LOG"
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$SHIM_DIR/git"
}

shim_reset() { : > "$SHIM_LOG"; }

shim_net_calls() {
  grep -E 'ARGS=([^ ]* )*(fetch|ls-remote|pull|clone|push)( |$)' "$SHIM_LOG" 2>/dev/null | wc -l | tr -d ' '
}

# Mirror any PATH directory that carries timeout/gtimeout, minus those two, so a
# case can prove the subject's own watchdog works where coreutils is absent.
mask_timeout_path() {
  local d n f newpath=""
  NOBIN="$LAB/nobin"; mkdir -p "$NOBIN"
  local oldifs="$IFS"; IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/timeout" ] || [ -x "$d/gtimeout" ]; then
      for f in "$d"/*; do
        [ -e "$f" ] || continue
        n="${f##*/}"
        case "$n" in timeout|gtimeout) continue ;; esac
        [ -e "$NOBIN/$n" ] || ln -s "$f" "$NOBIN/$n" 2>/dev/null
      done
      newpath="${newpath}${newpath:+:}$NOBIN"
    else
      newpath="${newpath}${newpath:+:}$d"
    fi
  done
  IFS="$oldifs"
  printf '%s' "$SHIM_DIR:$newpath"
}

# Copy whichever subjects exist into the fixture. A missing subject is normal —
# its cases report not_implemented rather than exploding.
install_subjects() {
  local profile="$1"
  mkdir -p "$DEV/scripts" "$DEV/shared/scripts" "$DEV/skills/demo" "$DEV/.claude"

  if [ -f "$UPDATE_SH" ]; then
    cp "$UPDATE_SH" "$DEV/scripts/update.sh"; chmod +x "$DEV/scripts/update.sh"
  fi
  if [ -f "$CHECK_CONTEXT_SH" ]; then
    cp "$CHECK_CONTEXT_SH" "$DEV/shared/scripts/check-context.sh"; chmod +x "$DEV/shared/scripts/check-context.sh"
  fi
  if [ -f "$AUTO_UPDATE_SH" ]; then
    cp "$AUTO_UPDATE_SH" "$DEV/shared/scripts/auto-update.sh"; chmod +x "$DEV/shared/scripts/auto-update.sh"
  fi
  if [ -f "$SETTINGS_JSON" ]; then
    cp "$SETTINGS_JSON" "$DEV/.claude/settings.json"
  fi

  # sync-skill is a STUB here on purpose: the subject under test is update.sh,
  # and the question this fixture answers is "did update.sh call it" (spec §3.7).
  # The marker lands in .claude/skills/, which is the real script's output home
  # AND is already gitignored. An earlier version wrote it to the repo root,
  # where it read as customer dirt: it broke the post-update cleanliness check
  # and made --rollback refuse on a tree the customer had not touched.
  cat > "$DEV/shared/scripts/sync-skill.sh" <<'STUB'
#!/usr/bin/env bash
# harness stub — records that it was called.
root="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$root/.claude/skills"
printf 'sync-skill ran\n' >> "$root/.claude/skills/.sync-skill-ran"
exit 0
STUB
  chmod +x "$DEV/shared/scripts/sync-skill.sh"

  # The .gitignore ships verbatim from the repo: whether `.update-state/` is
  # ignored is B1's line to add, and several behaviors depend on it.
  if [ -f "$REPO_GITIGNORE" ]; then cp "$REPO_GITIGNORE" "$DEV/.gitignore"; else : > "$DEV/.gitignore"; fi
  grep -q '^\.env$' "$DEV/.gitignore" 2>/dev/null || printf '.env\n' >> "$DEV/.gitignore"
  grep -q '^\.claude/skills/$' "$DEV/.gitignore" 2>/dev/null || printf '.claude/skills/\n' >> "$DEV/.gitignore"

  printf 'skill v1\n' > "$DEV/skills/demo/SKILL.md"
  printf 'doc v1\n' > "$DEV/README.md"

  if [ "$profile" = "migrations" ]; then
    mkdir -p "$DEV/migrations"
    [ -f "$MIGRATION_RUNNER" ] && { cp "$MIGRATION_RUNNER" "$DEV/migrations/run.sh"; chmod +x "$DEV/migrations/run.sh"; }
    fake_migration "$DEV/migrations/v0.9.0.sh"  0
    fake_migration "$DEV/migrations/v1.0.1.sh"  0
    fake_migration "$DEV/migrations/v1.2.0.sh"  0
    fake_migration "$DEV/migrations/v1.10.0.sh" 0
    printf '1.10.0\n' > "$DEV/VERSION"
  elif [ -f "$REPO_ROOT/VERSION" ]; then
    cp "$REPO_ROOT/VERSION" "$DEV/VERSION"
  else
    printf '1.1.0\n' > "$DEV/VERSION"
  fi
}

# A migration that records its own name, and optionally fails afterwards. Paths
# are derived from its own location, so it does not care where it is invoked from.
fake_migration() {
  local path="$1" fails="$2" name
  name="$(basename "$path" .sh)"
  cat > "$path" <<MIG
#!/usr/bin/env bash
root="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
printf '%s\n' "$name" >> "\$root/migration-log.txt"
exit $fails
MIG
  chmod +x "$path"
}

# Rebuild upstream + a customer clone. Profile "migrations" also ships the fake
# migration set and a VERSION the runner can reason about.
fresh() {
  local profile="${1:-base}"
  cd / || exit 2
  rm -rf "$LAB"; mkdir -p "$LAB"
  make_shim
  "$REAL_GIT" init -q --bare "$UP"
  "$REAL_GIT" init -q "$DEV"
  ( cd "$DEV" && "$REAL_GIT" remote add origin "$UP" ) >/dev/null 2>&1
  install_subjects "$profile"
  local ts=$(( $(now_epoch) - AGE_OLD ))
  (
    cd "$DEV" &&
    "$REAL_GIT" add -A . >/dev/null 2>&1
    "$REAL_GIT" add -f scripts shared migrations .claude VERSION >/dev/null 2>&1
    GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
      "$REAL_GIT" commit -q -m "pack base" >/dev/null 2>&1
    "$REAL_GIT" push -q -u origin main >/dev/null 2>&1
  )
  "$REAL_GIT" clone -q "$UP" "$CUST" >/dev/null 2>&1
  printf '%s\n' "$ENV_CANARY" > "$CUST/.env"
  BASE_SHA="$(cd "$CUST" && "$REAL_GIT" rev-parse HEAD)"
  shim_reset
}

# Land a commit upstream. Third argument is its AGE in seconds (default: aged
# past the cooldown, because most cases want an installable update).
upstream_commit() {
  local p="$1" c="$2" age="${3:-$AGE_AGED}"
  local ts=$(( $(now_epoch) - age ))
  mkdir -p "$DEV/$(dirname "$p")"
  printf '%s\n' "$c" > "$DEV/$p"
  (
    cd "$DEV" &&
    "$REAL_GIT" add -A . >/dev/null 2>&1 &&
    GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
      "$REAL_GIT" commit -q -m "up: $p" >/dev/null 2>&1 &&
    "$REAL_GIT" push -q origin main >/dev/null 2>&1
  )
}

remote_tip() { ( cd "$DEV" && "$REAL_GIT" rev-parse HEAD ); }
cust_head()  { ( cd "$CUST" && "$REAL_GIT" rev-parse HEAD 2>/dev/null ); }
# The fake migrations' log is harness instrumentation, not customer state.
cust_status(){ ( cd "$CUST" && "$REAL_GIT" status --porcelain 2>/dev/null | grep -v 'migration-log\.txt$' ); }
cust_stashes(){ ( cd "$CUST" && "$REAL_GIT" stash list 2>/dev/null | wc -l | tr -d ' ' ); }

env_intact() {
  [ -f "$CUST/.env" ] || return 1
  [ "$(cat "$CUST/.env" 2>/dev/null)" = "$ENV_CANARY" ]
}

no_conflict_markers() {
  ! grep -r -l '^<<<<<<< ' "$CUST" --exclude-dir=.git >/dev/null 2>&1
}

partial_merge_state() {
  [ -e "$CUST/.git/MERGE_HEAD" ] || [ -d "$CUST/.git/rebase-merge" ] || [ -d "$CUST/.git/rebase-apply" ]
}

write_config() { mkdir -p "$CUST/.update-state"; printf '%s\n' "$@" > "$CUST/.update-state/config"; }

# ── Bounded subject invocation ───────────────────────────────────────────────
# RC, OUT, ERR, ELAPSED are set for the case to assert on. RC=124 means the
# subject blew the watchdog, which is a failure of the subject, not the harness.
run_subject() {
  local path_override="$1"; shift
  local started ended p n limit
  : > "$OUT_F"; : > "$ERR_F"
  started="$(now_epoch)"
  (
    cd "$CUST" 2>/dev/null || exit 97
    PATH="$path_override" CLAUDE_PROJECT_DIR="$CUST" "$@" >"$OUT_F" 2>"$ERR_F"
  ) &
  p=$!
  n=0; limit=$(( SUBJECT_BUDGET * 5 ))
  while kill -0 "$p" 2>/dev/null && [ "$n" -lt "$limit" ]; do sleep 0.2; n=$((n + 1)); done
  if kill -0 "$p" 2>/dev/null; then
    kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; RC=124
  else
    wait "$p"; RC=$?
  fi
  ended="$(now_epoch)"
  ELAPSED=$(( ended - started ))
  OUT="$(cat "$OUT_F" 2>/dev/null)"
  ERR="$(cat "$ERR_F" 2>/dev/null)"
  parse_status
}

run_update()      { run_subject "$SHIM_DIR:$PATH" bash scripts/update.sh "$@"; }
run_auto()        { run_subject "$SHIM_DIR:$PATH" bash shared/scripts/auto-update.sh "$@"; }
run_checkctx()    { run_subject "$SHIM_DIR:$PATH" bash shared/scripts/check-context.sh "$@"; }

parse_status() {
  STATUS_COUNT="$(printf '%s\n' "$OUT" | grep -c '^STATUS=' 2>/dev/null || true)"
  STATUS_COUNT="$(printf '%s' "$STATUS_COUNT" | tr -d ' ')"
  [ -n "$STATUS_COUNT" ] || STATUS_COUNT=0
  STATUS_LINE="$(printf '%s\n' "$OUT" | grep '^STATUS=' | tail -1)"
  STATUS_TOK="$(printf '%s' "$STATUS_LINE" | sed -n 's/^STATUS=\([^ ]*\).*$/\1/p')"
}

# Read one KEY=value field off the final STATUS line.
field() {
  local k="$1" tok
  for tok in $STATUS_LINE; do
    case "$tok" in "$k"=*) printf '%s' "${tok#$k=}"; return 0 ;; esac
  done
  return 1
}

# A reported sha is acceptable short or long, as long as it prefixes the real one.
sha_matches() {
  local reported="$1" actual="$2"
  [ -n "$reported" ] || return 1
  case "$actual" in "$reported"*) return 0 ;; esac
  return 1
}

expect_status() {
  [ "$STATUS_TOK" = "$1" ] || bad "want STATUS=$1, got '${STATUS_LINE:-<no STATUS line>}'"
}
expect_rc() {
  [ "$RC" = "$1" ] || bad "want exit $1, got $RC$( [ "$RC" = 124 ] && printf ' (subject_timed_out)' )"
}
expect_env() { env_intact || bad ".env clobbered -> [$(cat "$CUST/.env" 2>/dev/null)]"; }

# ══════════════════════════════════════════════════════════════════════════════
# CASES
# Each function is named case_<manifest entry> and must reach exactly one of
# pass/fail (finish, ni, or fail directly). The runner flags any that does not.
# ══════════════════════════════════════════════════════════════════════════════

# ── §3 the script ships runnable ─────────────────────────────────────────────
case_update_script_is_executable() {
  have_update || { ni "scripts/update.sh missing"; return; }
  [ -x "$UPDATE_SH" ] || bad "scripts/update.sh is not executable (customers run ./scripts/update.sh)"
  head -1 "$UPDATE_SH" | grep -q '^#!' || bad "no shebang"
  finish
}

# ── §2/§3 the nine proto-validated behaviors ─────────────────────────────────
case_clean_update() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  local want; want="$(remote_tip)"
  run_update
  expect_status updated
  expect_rc 0
  expect_env
  [ "$(cust_head)" = "$want" ] || bad "HEAD did not advance to upstream"
  [ "$(cat "$CUST/skills/demo/SKILL.md" 2>/dev/null)" = "skill v2" ] || bad "file content not updated"
  finish
}

case_already_current() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  local after; after="$(cust_head)"
  run_update
  expect_status current
  expect_rc 0
  expect_env
  [ "$(cust_head)" = "$after" ] || bad "HEAD moved on a no-op run"
  finish
}

case_local_edit_preserved() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  printf 'my notes\n' > "$CUST/README.md"
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  expect_status updated
  expect_rc 0
  expect_env
  [ "$(cat "$CUST/README.md" 2>/dev/null)" = "my notes" ] || bad "local edit to an untouched file was lost"
  [ "$(cat "$CUST/skills/demo/SKILL.md" 2>/dev/null)" = "skill v2" ] || bad "update did not land"
  finish
}

case_untracked_collision_no_data_loss() {
  # spec §3.8 — the stash decision reads `status --porcelain`, which sees
  # untracked files; a `git diff` check misses them and the merge aborts.
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  printf 'mine\n' > "$CUST/NOTES.md"
  upstream_commit NOTES.md "theirs"
  run_update
  case "$STATUS_TOK" in
    updated|updated_with_conflict) : ;;
    *) bad "want updated or updated_with_conflict, got '${STATUS_LINE:-<none>}'" ;;
  esac
  expect_rc 0
  expect_env
  no_conflict_markers || bad "conflict markers left in the worktree"
  # The customer's bytes must be recoverable: in the tree, or in the stash.
  # An untracked file stashed with -u lands in the stash's THIRD parent, which
  # plain `stash show -p` does not print. Look in every place it can be.
  local found=no
  grep -q '^mine$' "$CUST/NOTES.md" 2>/dev/null && found=yes
  if [ "$found" = no ]; then
    (
      cd "$CUST" && {
        "$REAL_GIT" stash show -p --include-untracked 2>/dev/null
        "$REAL_GIT" show 'stash@{0}^3' 2>/dev/null
        "$REAL_GIT" stash show -p 2>/dev/null
      } | grep -q '^+mine$'
    ) && found=yes
  fi
  [ "$found" = yes ] || bad "customer's untracked content is neither in the tree nor in a stash"
  finish
}

case_conflict_to_stash() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  printf 'MY CUSTOM SKILL\n' > "$CUST/skills/demo/SKILL.md"
  upstream_commit skills/demo/SKILL.md "skill v2"
  local want; want="$(remote_tip)"
  run_update
  expect_status updated_with_conflict
  expect_rc 0
  expect_env
  no_conflict_markers || bad "conflict markers left in a file an agent will read"
  [ "$(cust_stashes)" -ge 1 ] 2>/dev/null || bad "the customer's work is not in a stash"
  [ "$(cust_head)" = "$want" ] || bad "the update itself did not land"
  [ -z "$(cust_status)" ] || bad "worktree not returned to a clean tree after the failed pop"
  finish
}

case_env_survives_upstream_tracking() {
  # The headline measured failure: git treats an IGNORED file as expendable the
  # moment upstream starts tracking that path. Exit 0, no warning (spec §3.5).
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  local ts=$(( $(now_epoch) - AGE_AGED ))
  (
    cd "$DEV" &&
    printf 'NOVOADS_API_KEY=novo_REPLACE_ME\n' > .env &&
    "$REAL_GIT" add -f .env >/dev/null 2>&1 &&
    GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
      "$REAL_GIT" commit -q -m "add .env template" >/dev/null 2>&1 &&
    "$REAL_GIT" push -q origin main >/dev/null 2>&1
  )
  run_update
  expect_rc 0
  expect_env
  finish
}

case_env_survives_sigint_mid_merge() {
  # spec §3.5 — "also on signal (trap)". A post-merge hook fires the interrupt
  # at the exact window that matters: after HEAD moved, before the restore.
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  local ts=$(( $(now_epoch) - AGE_AGED ))
  (
    cd "$DEV" &&
    printf 'NOVOADS_API_KEY=novo_REPLACE_ME\n' > .env &&
    "$REAL_GIT" add -f .env >/dev/null 2>&1 &&
    GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
      "$REAL_GIT" commit -q -m "add .env template" >/dev/null 2>&1 &&
    "$REAL_GIT" push -q origin main >/dev/null 2>&1
  )
  local marker="$LAB/hook-fired"
  mkdir -p "$CUST/.git/hooks"
  cat > "$CUST/.git/hooks/post-merge" <<HOOK
#!/bin/sh
printf 'fired\n' >> "$marker"
pid=\$PPID
i=0
while [ "\$i" -lt 6 ]; do
  cmd=\$(ps -o command= -p "\$pid" 2>/dev/null || ps -o args= -p "\$pid" 2>/dev/null)
  case "\$cmd" in *update.sh*) kill -INT "\$pid" 2>/dev/null; break ;; esac
  pid=\$(ps -o ppid= -p "\$pid" 2>/dev/null | tr -d ' ')
  [ -n "\$pid" ] || break
  i=\$((i + 1))
done
sleep 1
exit 0
HOOK
  chmod +x "$CUST/.git/hooks/post-merge"
  run_update
  [ -s "$marker" ] || bad "harness could not reach the merge window (post-merge hook never fired)"
  expect_env
  partial_merge_state && bad "a partial merge was left behind"
  no_conflict_markers || bad "conflict markers left in the worktree"
  finish
}

case_diverged_blocked() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  ( cd "$CUST" && printf 'local\n' > skills/demo/SKILL.md && "$REAL_GIT" commit -qam "customer commit" ) >/dev/null 2>&1
  upstream_commit skills/demo/SKILL.md "skill v2"
  local before; before="$(cust_head)"
  run_update
  expect_status blocked
  expect_rc 1
  expect_env
  [ "$(field REASON)" = "diverged" ] || bad "want REASON=diverged, got '$(field REASON 2>/dev/null)'"
  [ "$(cust_head)" = "$before" ] || bad "a blocked run moved HEAD"
  finish
}

case_force_push_blocked() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  local ts=$(( $(now_epoch) - AGE_AGED ))
  (
    cd "$DEV" && printf 'rewritten\n' > skills/demo/SKILL.md &&
    GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
      "$REAL_GIT" commit -q --amend -m "rewritten" >/dev/null 2>&1 &&
    "$REAL_GIT" push -qf origin main >/dev/null 2>&1
  )
  local before; before="$(cust_head)"
  run_update
  expect_status blocked
  expect_rc 1
  expect_env
  [ "$(field REASON)" = "diverged" ] || bad "want REASON=diverged (§2 has no separate force-push reason), got '$(field REASON 2>/dev/null)'"
  [ "$(cust_head)" = "$before" ] || bad "a blocked run moved HEAD"
  finish
}

case_detached_head_blocked() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" checkout -q "$(cd "$CUST" && "$REAL_GIT" rev-parse HEAD)" ) >/dev/null 2>&1
  upstream_commit skills/demo/SKILL.md "skill v2"
  local before; before="$(cust_head)"
  run_update
  expect_status blocked
  expect_rc 1
  expect_env
  [ "$(field REASON)" = "detached_head" ] || bad "want REASON=detached_head, got '$(field REASON 2>/dev/null)'"
  [ "$(cust_head)" = "$before" ] || bad "a blocked run moved a pinned checkout"
  finish
}

case_offline_fail_open() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" remote set-url origin https://10.255.255.1/pack.git ) >/dev/null 2>&1
  PACK_NET_TIMEOUT=5 PACK_CHECK_TIMEOUT=5 run_update
  expect_status offline
  expect_rc 0
  expect_env
  [ "$ELAPSED" -le 25 ] || bad "offline path took ${ELAPSED}s (must be bounded, not a 75s natural failure)"
  finish
}

case_offline_without_timeout_binary() {
  # Stock macOS has no timeout(1). The subject's own watchdog must carry it.
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" remote set-url origin https://10.255.255.1/pack.git ) >/dev/null 2>&1
  local masked; masked="$(mask_timeout_path)"
  if PATH="$masked" command -v timeout >/dev/null 2>&1 || PATH="$masked" command -v gtimeout >/dev/null 2>&1; then
    fail "harness_limitation: could not mask timeout(1) out of PATH"
    return
  fi
  PACK_NET_TIMEOUT=5 run_subject "$masked" bash scripts/update.sh
  expect_status offline
  expect_rc 0
  expect_env
  [ "$ELAPSED" -le 30 ] || bad "unbounded without timeout(1): took ${ELAPSED}s"
  finish
}

case_no_such_remote_is_not_offline() {
  # A renamed remote is a misconfiguration, and reporting it as `offline` makes
  # updates stop forever while looking like weather (spec §2).
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" remote rename origin upstream ) >/dev/null 2>&1
  run_update
  expect_status blocked
  expect_rc 1
  [ "$(field REASON)" = "no_such_remote" ] || bad "want REASON=no_such_remote, got '$(field REASON 2>/dev/null)'"
  finish
}

case_blocked_leaves_repo_untouched() {
  # spec §2 — exit 1 means "repo left EXACTLY as found". Including no stray stash.
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  printf 'dirty\n' > "$CUST/README.md"
  ( cd "$CUST" && printf 'local\n' > skills/demo/SKILL.md && "$REAL_GIT" commit -qam "customer commit" ) >/dev/null 2>&1
  upstream_commit skills/demo/SKILL.md "skill v2"
  local h0 s0 st0
  h0="$(cust_head)"; s0="$(cust_status)"; st0="$(cust_stashes)"
  run_update
  expect_rc 1
  expect_status blocked
  [ "$(cust_head)" = "$h0" ] || bad "HEAD moved"
  [ "$(cust_status)" = "$s0" ] || bad "working tree changed"
  [ "$(cust_stashes)" = "$st0" ] || bad "a stash was left behind by a blocked run"
  expect_env
  finish
}

# ── §2 the wire contract, asserted field by field ────────────────────────────
case_wire_single_status_line() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  [ "$STATUS_COUNT" = "1" ] || bad "want exactly one STATUS= line on stdout, got $STATUS_COUNT"
  printf '%s\n' "$ERR" | grep -q '^STATUS=' && bad "a STATUS= line went to stderr; the contract is stdout"
  [ -n "$STATUS_LINE" ] && [ "$STATUS_LINE" = "$(printf '%s\n' "$OUT" | grep '^STATUS=' | head -1)" ] || bad "could not identify a single final STATUS line"
  finish
}

case_wire_updated_from_to() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  local from want
  from="$(cust_head)"; want="$(remote_tip)"
  run_update
  expect_status updated
  local f t
  f="$(field FROM || true)"; t="$(field TO || true)"
  [ -n "$f" ] || bad "no FROM= field (spec §2: STATUS=updated FROM=<sha> TO=<sha>)"
  [ -n "$t" ] || bad "no TO= field"
  [ -n "$f" ] && { sha_matches "$f" "$from" || bad "FROM=$f is not the pre-update sha"; }
  [ -n "$t" ] && { sha_matches "$t" "$want" || bad "TO=$t is not the installed sha"; }
  finish
}

case_wire_conflict_stash_ref() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  printf 'MY CUSTOM SKILL\n' > "$CUST/skills/demo/SKILL.md"
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  expect_status updated_with_conflict
  local s; s="$(field STASH || true)"
  if [ -z "$s" ]; then
    bad "no STASH= field (spec §2: updated_with_conflict FROM=<sha> TO=<sha> STASH=<ref>)"
  else
    ( cd "$CUST" && "$REAL_GIT" rev-parse --verify --quiet "$s" >/dev/null 2>&1 ) || bad "STASH=$s does not resolve in the customer repo"
  fi
  [ -n "$(field FROM || true)" ] || bad "no FROM= field"
  [ -n "$(field TO || true)" ]   || bad "no TO= field"
  finish
}

case_wire_blocked_reason_enum() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" checkout -q "$(cd "$CUST" && "$REAL_GIT" rev-parse HEAD)" ) >/dev/null 2>&1
  run_update
  expect_status blocked
  local r; r="$(field REASON || true)"
  case "$r" in
    diverged|detached_head|no_such_remote|dirty_unresolvable|lock_held) : ;;
    "") bad "no REASON= field (spec §2 names it in caps)" ;;
    *)  bad "REASON=$r is outside the §2 enum" ;;
  esac
  finish
}

# ── §3.1 cooldown ────────────────────────────────────────────────────────────
case_cooldown_holds_fresh_commit() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2" "$AGE_FRESH"
  local before; before="$(cust_head)"
  run_update
  if [ "$STATUS_TOK" = "updated" ]; then
    update_has_cooldown || { ni "no cooldown: a 1h-old upstream commit was installed"; return; }
    bad "a 1h-old upstream commit was installed despite a cooldown being present"
    finish; return
  fi
  expect_status current
  expect_rc 0
  [ "$(cust_head)" = "$before" ] || bad "HEAD moved to a commit inside the cooldown window"
  finish
}

case_cooldown_installs_aged_commit() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2" "$AGE_AGED"
  local want; want="$(remote_tip)"
  run_update
  expect_status updated
  expect_rc 0
  [ "$(cust_head)" = "$want" ] || bad "a 48h-old commit is outside the cooldown and must install"
  finish
}

case_cooldown_stops_at_aged_commit() {
  # Two commits: one installable, one still inside the window. The update must
  # land on the aged one, not the tip (spec §3.1 — rev-list -1 --before).
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2" "$AGE_AGED"
  local aged; aged="$(remote_tip)"
  upstream_commit skills/demo/SKILL.md "skill v3" "$AGE_FRESH"
  local tip; tip="$(remote_tip)"
  run_update
  local head; head="$(cust_head)"
  if [ "$head" = "$tip" ]; then
    update_has_cooldown || { ni "no cooldown: the update landed on the tip"; return; }
    bad "landed on the tip; the cooldown target is the newest commit older than 24h"
    finish; return
  fi
  [ "$head" = "$aged" ] || bad "want HEAD at the aged commit, got $head"
  expect_status updated
  expect_rc 0
  finish
}

case_fresh_flag_installs_tip() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_flag '--fresh' || { ni "scripts/update.sh does not accept --fresh"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2" "$AGE_FRESH"
  local tip; tip="$(remote_tip)"
  run_update --fresh
  expect_status updated
  expect_rc 0
  [ "$(cust_head)" = "$tip" ] || bad "--fresh must override the cooldown and install the tip"
  finish
}

case_fresh_flag_warns_on_stderr() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_flag '--fresh' || { ni "scripts/update.sh does not accept --fresh"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2" "$AGE_FRESH"
  run_update --fresh
  [ -n "$ERR" ] || bad "--fresh must print a one-line supply-chain warning to stderr (§3.1); stderr was empty"
  finish
}

# ── §3.2 rollback ────────────────────────────────────────────────────────────
case_rollback_returns_to_prior_sha() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_flag '--rollback' || { ni "scripts/update.sh does not accept --rollback"; return; }
  fresh
  local before; before="$(cust_head)"
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  [ "$STATUS_TOK" = "updated" ] || { bad "setup: the update did not land ('${STATUS_LINE:-<none>}')"; finish; return; }
  run_update --rollback
  expect_status rolled_back
  expect_rc 0
  [ "$(cust_head)" = "$before" ] || bad "HEAD is not back at the pre-update sha"
  local t; t="$(field TO || true)"
  [ -n "$t" ] || bad "no TO= field (spec §2: STATUS=rolled_back TO=<sha>)"
  [ -n "$t" ] && { sha_matches "$t" "$before" || bad "TO=$t is not the restored sha"; }
  [ "$(cat "$CUST/skills/demo/SKILL.md" 2>/dev/null)" = "skill v1" ] || bad "worktree content not rolled back"
  finish
}

case_rollback_refuses_dirty() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_flag '--rollback' || { ni "scripts/update.sh does not accept --rollback"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  printf 'work in progress\n' > "$CUST/README.md"
  local h0; h0="$(cust_head)"
  run_update --rollback
  expect_status blocked
  expect_rc 1
  [ "$(field REASON)" = "dirty_unresolvable" ] || bad "want REASON=dirty_unresolvable, got '$(field REASON 2>/dev/null)'"
  [ "$(cust_head)" = "$h0" ] || bad "a refused rollback moved HEAD"
  [ "$(cat "$CUST/README.md" 2>/dev/null)" = "work in progress" ] || bad "a refused rollback destroyed uncommitted work"
  finish
}

case_rollback_preserves_env() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_flag '--rollback' || { ni "scripts/update.sh does not accept --rollback"; return; }
  fresh
  local ts=$(( $(now_epoch) - AGE_AGED ))
  (
    cd "$DEV" && printf 'NOVOADS_API_KEY=novo_REPLACE_ME\n' > .env &&
    "$REAL_GIT" add -f .env >/dev/null 2>&1 &&
    GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
      "$REAL_GIT" commit -q -m "add .env template" >/dev/null 2>&1 &&
    "$REAL_GIT" push -q origin main >/dev/null 2>&1
  )
  run_update
  run_update --rollback
  expect_env
  finish
}

# ── §3.3 lock ────────────────────────────────────────────────────────────────
case_lock_contested_blocks() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_lock || { ni "scripts/update.sh has no lock"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  mkdir -p "$CUST/.update-state/lock"
  local before; before="$(cust_head)"
  run_update
  expect_status blocked
  expect_rc 1
  [ "$(field REASON)" = "lock_held" ] || bad "want REASON=lock_held, got '$(field REASON 2>/dev/null)'"
  [ "$(cust_head)" = "$before" ] || bad "a contested run updated anyway"
  [ -d "$CUST/.update-state/lock" ] || bad "the contested run removed a lock it does not own"
  finish
}

case_lock_stale_reclaimed() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_lock || { ni "scripts/update.sh has no lock"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  mkdir -p "$CUST/.update-state/lock"
  touch -t "$(stamp_ago 7200)" "$CUST/.update-state/lock" 2>/dev/null
  run_update
  [ "$(field REASON 2>/dev/null)" = "lock_held" ] && bad "a >1h-old lock must be reclaimed, not honored"
  expect_status updated
  expect_rc 0
  finish
}

case_lock_released_on_exit() {
  have_update || { ni "scripts/update.sh missing"; return; }
  update_has_lock || { ni "scripts/update.sh has no lock"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  [ -d "$CUST/.update-state/lock" ] && bad "the lock outlived the run (trap must remove it on EXIT)"
  finish
}

# ── §3.4 credentials / network hygiene ───────────────────────────────────────
case_network_calls_are_credential_hardened() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  shim_reset
  run_update
  local total unhardened noprompt
  total="$(shim_net_calls)"
  [ "${total:-0}" -ge 1 ] || { bad "no network git call was observed at all"; finish; return; }
  unhardened="$(grep -E 'ARGS=([^ ]* )*(fetch|ls-remote|pull|clone|push)( |$)' "$SHIM_LOG" 2>/dev/null | grep -v -- '-c credential.helper=' | wc -l | tr -d ' ')"
  noprompt="$(grep -E 'ARGS=([^ ]* )*(fetch|ls-remote|pull|clone|push)( |$)' "$SHIM_LOG" 2>/dev/null | grep -v 'TERMPROMPT=0' | wc -l | tr -d ' ')"
  [ "${unhardened:-0}" = "0" ] || bad "$unhardened network call(s) without -c credential.helper= (§3.4)"
  [ "${noprompt:-0}" = "0" ] || bad "$noprompt network call(s) without GIT_TERMINAL_PROMPT=0"
  finish
}

# ── §3.7 what runs after a successful update ─────────────────────────────────
case_update_runs_sync_skill() {
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  [ "$STATUS_TOK" = "updated" ] || bad "setup: no update landed ('${STATUS_LINE:-<none>}')"
  [ -s "$CUST/.claude/skills/.sync-skill-ran" ] || bad "shared/scripts/sync-skill.sh was not run after the update (§3.7)"
  finish
}

case_update_runs_migrations() {
  have_update || { ni "scripts/update.sh missing"; return; }
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  mkdir -p "$CUST/.update-state"; printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_update
  [ "$STATUS_TOK" = "updated" ] || bad "setup: no update landed ('${STATUS_LINE:-<none>}')"
  [ -s "$CUST/migration-log.txt" ] || bad "the migration runner did not run after the update (§3.7)"
  finish
}

case_update_survives_failing_migration() {
  have_update || { ni "scripts/update.sh missing"; return; }
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  fake_migration "$DEV/migrations/v1.3.0.sh" 1
  upstream_commit migrations/v1.3.0.sh "$(cat "$DEV/migrations/v1.3.0.sh")"
  mkdir -p "$CUST/.update-state"; printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  run_update
  expect_status updated
  expect_rc 0
  # Without this the case passes vacuously against an update.sh that never
  # reaches the migration runner at all.
  case "$(migration_log)" in
    *v1.3.0*) : ;;
    *) bad "the failing migration was never reached, so nothing was proven non-fatal" ;;
  esac
  finish
}

# ── §5 kill switch, mutation-tested in both directions ───────────────────────
case_killswitch_on_check_context_fetches() {
  have_checkctx || { ni "shared/scripts/check-context.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'update_check=on' 'auto_apply=off'
  shim_reset
  run_checkctx
  [ "$(shim_net_calls)" -ge 1 ] 2>/dev/null || bad "with the switch ON the banner made no network call — the feature is dead, not switched"
  expect_rc 0
  finish
}

case_killswitch_off_silences_check_context() {
  have_checkctx || { ni "shared/scripts/check-context.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'update_check=off'
  shim_reset
  run_checkctx
  local n; n="$(shim_net_calls)"
  if [ "${n:-0}" != "0" ]; then
    grep -q 'update_check' "$CHECK_CONTEXT_SH" 2>/dev/null \
      || { ni "check-context.sh does not read .update-state/config"; return; }
    bad "$n network git call(s) with update_check=off"
  fi
  printf '%s\n' "$OUT" | grep -q 'update(s) available' && bad "the update banner printed with the switch off"
  expect_rc 0
  finish
}

case_killswitch_env_override_silences_check_context() {
  have_checkctx || { ni "shared/scripts/check-context.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'update_check=on'
  shim_reset
  NOVOADS_PACK_NO_UPDATE_CHECK=1 run_checkctx
  local n; n="$(shim_net_calls)"
  if [ "${n:-0}" != "0" ]; then
    grep -q 'NOVOADS_PACK_NO_UPDATE_CHECK' "$CHECK_CONTEXT_SH" 2>/dev/null \
      || { ni "check-context.sh does not read NOVOADS_PACK_NO_UPDATE_CHECK"; return; }
    bad "$n network git call(s) despite NOVOADS_PACK_NO_UPDATE_CHECK=1 (env override wins, §5)"
  fi
  expect_rc 0
  finish
}

case_killswitch_off_silences_auto_update() {
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'update_check=off' 'auto_apply=on'
  shim_reset
  local before; before="$(cust_head)"
  run_auto
  expect_rc 0
  [ -z "$OUT" ] || bad "auto-update wrote to stdout with the switch off"
  [ "$(shim_net_calls)" = "0" ] || bad "auto-update made network calls with update_check=off"
  [ "$(cust_head)" = "$before" ] || bad "auto-update applied an update with the switch off"
  finish
}

case_killswitch_off_keeps_manual_update_working() {
  # A kill switch that strands the manual path is not a kill switch (§5).
  have_update || { ni "scripts/update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'update_check=off' 'auto_apply=off'
  run_update
  expect_status updated
  expect_rc 0
  expect_env
  finish
}

# ── §4 the auto-apply hook ───────────────────────────────────────────────────
case_auto_update_off_is_silent() {
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  local before; before="$(cust_head)"
  run_auto
  expect_rc 0
  [ -z "$OUT" ] || bad "stdout must be empty when auto_apply is not on, got: $(printf '%s' "$OUT" | head -1)"
  [ "$(cust_head)" = "$before" ] || bad "notify-only is the default; the hook applied an update anyway"
  finish
}

case_auto_update_on_emits_one_json_line() {
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  [ -n "$PYTHON" ] || { fail "harness_limitation: python3 not available to validate the JSON line"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'auto_apply=on'
  local want; want="$(remote_tip)"
  run_auto
  expect_rc 0
  [ "$(cust_head)" = "$want" ] || bad "auto_apply=on did not install the available update"
  local verdict
  verdict="$("$PYTHON" - "$OUT_F" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
if len(lines) != 1:
    print("want exactly one stdout line, got %d" % len(lines)); raise SystemExit(0)
try:
    d = json.loads(lines[0])
except Exception as e:
    print("stdout line is not valid JSON: %s" % e); raise SystemExit(0)
h = d.get("hookSpecificOutput")
if not isinstance(h, dict):
    print("no hookSpecificOutput object"); raise SystemExit(0)
if h.get("hookEventName") != "SessionStart":
    print("hookEventName is %r, want 'SessionStart'" % h.get("hookEventName")); raise SystemExit(0)
if h.get("reloadSkills") is not True:
    print("reloadSkills is %r, want true" % h.get("reloadSkills")); raise SystemExit(0)
if not h.get("additionalContext"):
    print("additionalContext is empty"); raise SystemExit(0)
PY
)"
  [ -z "$verdict" ] || bad "$verdict"
  finish
}

case_auto_update_throttle_respected() {
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'auto_apply=on'
  mkdir -p "$CUST/.update-state"
  printf '%s\n' "$(now_epoch)" > "$CUST/.update-state/last-auto-update"
  local before; before="$(cust_head)"
  run_auto
  expect_rc 0
  [ -z "$OUT" ] || bad "throttled run wrote to stdout"
  [ "$(cust_head)" = "$before" ] || bad "the 3600s throttle stamp was ignored (§4)"
  finish
}

case_auto_update_never_takes_fresh_commit() {
  # The auto path never passes --fresh, so a commit inside the cooldown window
  # must not reach a customer who consented to unattended updates (§4, §3.1).
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2" "$AGE_FRESH"
  write_config 'auto_apply=on'
  local before; before="$(cust_head)"
  run_auto
  expect_rc 0
  [ "$(cust_head)" = "$before" ] || bad "auto-update installed a commit younger than the cooldown"
  [ -z "$OUT" ] || bad "stdout must stay silent when nothing was applied"
  finish
}

case_auto_update_exits_zero_when_blocked() {
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" checkout -q "$(cd "$CUST" && "$REAL_GIT" rev-parse HEAD)" ) >/dev/null 2>&1
  upstream_commit skills/demo/SKILL.md "skill v2"
  write_config 'auto_apply=on'
  run_auto
  expect_rc 0
  [ -z "$OUT" ] || bad "a blocked update must leave the hook silent, got: $(printf '%s' "$OUT" | head -1)"
  finish
}

case_auto_update_bounded_when_offline() {
  have_auto || { ni "shared/scripts/auto-update.sh missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" remote set-url origin https://10.255.255.1/pack.git ) >/dev/null 2>&1
  write_config 'auto_apply=on'
  run_auto
  expect_rc 0
  [ "$ELAPSED" -le 18 ] || bad "session start delayed ${ELAPSED}s; the self-imposed budget is 15s (§4)"
  [ -z "$OUT" ] || bad "offline must be silent"
  finish
}

case_settings_registers_auto_update_first() {
  [ -f "$SETTINGS_JSON" ] || { ni ".claude/settings.json missing"; return; }
  [ -n "$PYTHON" ] || { fail "harness_limitation: python3 not available to parse settings.json"; return; }
  local verdict
  verdict="$("$PYTHON" - "$SETTINGS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
groups = d.get("hooks", {}).get("SessionStart", [])
cmds = []
for g in groups:
    for h in g.get("hooks", []):
        cmds.append(h.get("command", ""))
if not cmds:
    print("no SessionStart hook commands registered"); raise SystemExit(0)
if "auto-update" not in cmds[0]:
    print("first SessionStart hook is %r; auto-update.sh must be registered FIRST" % cmds[0])
PY
)"
  [ -z "$verdict" ] || { ni "$verdict"; return; }
  pass
}

case_consent_skill_offers_four_options() {
  [ -f "$CONSENT_SKILL" ] || { ni "skills/novoads-update/SKILL.md missing"; return; }
  grep -qi 'update now' "$CONSENT_SKILL"              || bad "option 1 'Update now' absent"
  grep -qi 'always keep me up to date' "$CONSENT_SKILL" || bad "option 2 'Always keep me up to date' absent"
  grep -qi 'not now' "$CONSENT_SKILL"                 || bad "option 3 'Not now' absent"
  grep -qi 'never ask again' "$CONSENT_SKILL"         || bad "option 4 'Never ask again' absent"
  grep -q '\.claude/settings\.json' "$CONSENT_SKILL"  || bad "the skill must verify the reader is registered in .claude/settings.json (§4 option 2)"
  finish
}

# ── §6 migrations ────────────────────────────────────────────────────────────
# Either invocation form satisfies the gate: `bash migrations/run.sh`, or
# sourcing it and calling run_migrations. Spec §6 fixes neither.
run_migration_runner() {
  local before_marker before_log
  before_marker="$(cat "$CUST/.update-state/last-setup-version" 2>/dev/null || true)"
  before_log="$(cat "$CUST/migration-log.txt" 2>/dev/null || true)"
  run_subject "$SHIM_DIR:$PATH" bash migrations/run.sh
  local after_marker after_log
  after_marker="$(cat "$CUST/.update-state/last-setup-version" 2>/dev/null || true)"
  after_log="$(cat "$CUST/migration-log.txt" 2>/dev/null || true)"
  if [ "$before_marker" = "$after_marker" ] && [ "$before_log" = "$after_log" ]; then
    run_subject "$SHIM_DIR:$PATH" bash -c '. migrations/run.sh >/dev/null 2>&1; run_migrations'
  fi
}

migration_log() { cat "$CUST/migration-log.txt" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }

case_migration_fresh_install_writes_marker_without_replay() {
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  rm -f "$CUST/.update-state/last-setup-version"
  run_migration_runner
  expect_rc 0
  [ -f "$CUST/migration-log.txt" ] && bad "a fresh install replayed history: $(migration_log)"
  [ -f "$CUST/.update-state/last-setup-version" ] || bad "no .update-state/last-setup-version marker written"
  if [ -f "$CUST/.update-state/last-setup-version" ]; then
    [ "$(cat "$CUST/.update-state/last-setup-version")" = "$(cat "$CUST/VERSION")" ] \
      || bad "marker is '$(cat "$CUST/.update-state/last-setup-version")', want VERSION '$(cat "$CUST/VERSION")'"
  fi
  finish
}

case_migration_replays_sorted_above_marker() {
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  mkdir -p "$CUST/.update-state"; printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  run_migration_runner
  expect_rc 0
  local got; got="$(migration_log)"
  [ -n "$got" ] || { bad "no migration ran"; finish; return; }
  # v1.10.0 sorts BELOW v1.2.0 lexically and ABOVE it under sort -V. That is the
  # whole point of the clause, so the fixture is built to catch a plain sort.
  [ "$got" = "v1.0.1 v1.2.0 v1.10.0" ] || bad "replay order is '$got', want 'v1.0.1 v1.2.0 v1.10.0' (sort -V)"
  case "$got" in *v0.9.0*) bad "v0.9.0 is at or below the marker and must not replay" ;; esac
  finish
}

case_migration_touchfile_idempotent() {
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  mkdir -p "$CUST/.update-state"; printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  run_migration_runner
  local first; first="$(migration_log)"
  [ -n "$first" ] || { bad "no migration ran on the first pass"; finish; return; }
  # Reset the marker so only the touchfile can hold the replay back.
  printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  run_migration_runner
  expect_rc 0
  [ "$(migration_log)" = "$first" ] || bad "a second run re-ran migrations: '$(migration_log)' vs '$first'"
  ls "$CUST/.update-state/migrations/"*.done >/dev/null 2>&1 \
    || bad "no touchfile under .update-state/migrations/ (§6)"
  finish
}

case_migration_failure_is_non_fatal() {
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  fake_migration "$CUST/migrations/v1.3.0.sh" 1
  mkdir -p "$CUST/.update-state"; printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  run_migration_runner
  expect_rc 0
  local got; got="$(migration_log)"
  case "$got" in *v1.10.0*) : ;; *) bad "a failing migration stopped the ones after it: '$got'" ;; esac
  finish
}

case_migration_marker_advances() {
  have_migrations || { ni "migrations/run.sh missing"; return; }
  fresh migrations
  mkdir -p "$CUST/.update-state"; printf '1.0.0\n' > "$CUST/.update-state/last-setup-version"
  run_migration_runner
  [ "$(cat "$CUST/.update-state/last-setup-version" 2>/dev/null)" = "$(cat "$CUST/VERSION")" ] \
    || bad "marker did not advance to VERSION after a run"
  finish
}

# ── B1 structural pins ───────────────────────────────────────────────────────
case_check_context_recommends_update_script() {
  have_checkctx || { ni "shared/scripts/check-context.sh missing"; return; }
  fresh
  upstream_commit skills/demo/SKILL.md "skill v2"
  run_checkctx
  expect_rc 0
  printf '%s\n' "$OUT" | grep -q 'update(s) available' || bad "the behind-banner did not print at all"
  printf '%s\n' "$OUT" | grep -q 'scripts/update.sh' \
    || bad "the remediation still does not point at ./scripts/update.sh"
  printf '%s\n' "$OUT" | grep -qE '(^|[^.])git pull' \
    && bad "the banner still recommends raw 'git pull', which is the path that eats .env"
  finish
}

case_gitignore_ignores_update_state() {
  [ -f "$REPO_GITIGNORE" ] || { ni ".gitignore missing"; return; }
  fresh
  ( cd "$CUST" && "$REAL_GIT" check-ignore -q .update-state/lock ) \
    || bad ".update-state/ is not ignored — every customer's git status grows a stray directory"
  ( cd "$CUST" && "$REAL_GIT" check-ignore -q local-skills/mine/SKILL.md ) \
    || bad "local-skills/ is not ignored (spec §1: B1 owns both lines)"
  finish
}

# ══════════════════════════════════════════════════════════════════════════════
# MANIFEST — the authoritative list. The runner counts it against what actually
# executed, because a case that silently disappears is a hole in the gate.
# ══════════════════════════════════════════════════════════════════════════════
MANIFEST='
update_script_is_executable
clean_update
already_current
local_edit_preserved
untracked_collision_no_data_loss
conflict_to_stash
env_survives_upstream_tracking
env_survives_sigint_mid_merge
diverged_blocked
force_push_blocked
detached_head_blocked
offline_fail_open
offline_without_timeout_binary
no_such_remote_is_not_offline
blocked_leaves_repo_untouched
wire_single_status_line
wire_updated_from_to
wire_conflict_stash_ref
wire_blocked_reason_enum
cooldown_holds_fresh_commit
cooldown_installs_aged_commit
cooldown_stops_at_aged_commit
fresh_flag_installs_tip
fresh_flag_warns_on_stderr
rollback_returns_to_prior_sha
rollback_refuses_dirty
rollback_preserves_env
lock_contested_blocks
lock_stale_reclaimed
lock_released_on_exit
network_calls_are_credential_hardened
update_runs_sync_skill
update_runs_migrations
update_survives_failing_migration
killswitch_on_check_context_fetches
killswitch_off_silences_check_context
killswitch_env_override_silences_check_context
killswitch_off_silences_auto_update
killswitch_off_keeps_manual_update_working
auto_update_off_is_silent
auto_update_on_emits_one_json_line
auto_update_throttle_respected
auto_update_never_takes_fresh_commit
auto_update_exits_zero_when_blocked
auto_update_bounded_when_offline
settings_registers_auto_update_first
consent_skill_offers_four_options
migration_fresh_install_writes_marker_without_replay
migration_replays_sorted_above_marker
migration_touchfile_idempotent
migration_failure_is_non_fatal
migration_marker_advances
check_context_recommends_update_script
gitignore_ignores_update_state
'

# ── Runner ───────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--list" ]; then
  for n in $MANIFEST; do printf '%s\n' "$n"; done
  exit 0
fi

SELECTED=""
if [ "$#" -gt 0 ]; then
  for want in "$@"; do
    hit=no
    for n in $MANIFEST; do [ "$n" = "$want" ] && hit=yes; done
    if [ "$hit" = no ]; then
      printf 'harness: no such case: %s (try --list)\n' "$want" >&2
      exit 2
    fi
    SELECTED="$SELECTED $want"
  done
fi

selected() {
  [ -z "$SELECTED" ] && return 0
  for n in $SELECTED; do [ "$n" = "$1" ] && return 0; done
  return 1
}

printf 'pack upgrade harness — sandbox %s\n' "$SANDBOX"
printf 'subjects: update.sh=%s auto-update.sh=%s check-context.sh=%s migrations/run.sh=%s\n' \
  "$( [ -f "$UPDATE_SH" ] && echo present || echo ABSENT )" \
  "$( [ -f "$AUTO_UPDATE_SH" ] && echo present || echo ABSENT )" \
  "$( [ -f "$CHECK_CONTEXT_SH" ] && echo present || echo ABSENT )" \
  "$( [ -f "$MIGRATION_RUNNER" ] && echo present || echo ABSENT )"
printf 'host: bash %s · coreutils timeout %s\n\n' "${BASH_VERSION%%(*}" "$HAVE_TIMEOUT"
[ "$HAVE_TIMEOUT" = "no" ] && note "this host has no coreutils timeout(1); the subjects' own watchdog carried every bounded call"

MANIFEST_N=0; EXECUTED_N=0; SKIPPED_N=0; DUPES=""
SEEN=""
for name in $MANIFEST; do
  MANIFEST_N=$((MANIFEST_N + 1))
  for s in $SEEN; do [ "$s" = "$name" ] && DUPES="$DUPES $name"; done
  SEEN="$SEEN $name"
done

for name in $MANIFEST; do
  if ! selected "$name"; then SKIPPED_N=$((SKIPPED_N + 1)); continue; fi
  CASE_NAME="$name"; CASE_ERR=""; RESULT_SET=0
  RC=0; OUT=""; ERR=""; ELAPSED=0; STATUS_LINE=""; STATUS_TOK=""; STATUS_COUNT=0
  if ! type "case_$name" >/dev/null 2>&1; then
    fail "harness_bug: no function case_$name"
    EXECUTED_N=$((EXECUTED_N + 1))
    continue
  fi
  "case_$name"
  if [ "$RESULT_SET" -eq 0 ]; then
    fail "harness_bug: case recorded no result"
  fi
  EXECUTED_N=$((EXECUTED_N + 1))
done

printf '\n%s cases in the manifest · %s executed · %s not selected\n' "$MANIFEST_N" "$EXECUTED_N" "$SKIPPED_N"
printf '%s passed, %s failed\n' "$PASS_N" "$FAIL_N"

GAP=$(( MANIFEST_N - EXECUTED_N - SKIPPED_N ))
if [ "$GAP" -ne 0 ]; then
  printf 'HARNESS BUG: %s manifest case(s) neither ran nor were deselected\n' "$GAP" >&2
  FAIL_N=$((FAIL_N + 1))
fi
if [ "$(( PASS_N + FAIL_N ))" -ne "$EXECUTED_N" ] && [ "$GAP" -eq 0 ]; then
  printf 'HARNESS BUG: %s results for %s executed cases\n' "$(( PASS_N + FAIL_N ))" "$EXECUTED_N" >&2
fi
if [ -n "$DUPES" ]; then
  printf 'HARNESS BUG: duplicate manifest entries:%s\n' "$DUPES" >&2
  FAIL_N=$((FAIL_N + 1))
fi
[ -n "$NOTES" ] && printf '\nnotes:\n%s\n' "$NOTES"
[ -n "$FAILED_NAMES" ] && printf '\nfailed:%s\n' "$(printf ' %s' $FAILED_NAMES)"

[ "$FAIL_N" -eq 0 ]
