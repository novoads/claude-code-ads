#!/usr/bin/env bash
# migrations/run.sh — replay the pack migrations this clone has not run yet.
#
# THE PROBLEM THIS SOLVES. A clone made months ago is not the same thing as a
# clone made today plus some commits. Files get renamed, config keys get
# renamed, generated output gets orphaned in a directory nothing looks at any
# more. `git merge --ff-only` brings the new files down; it does not clean up
# after the old ones. A migration is the one-time repair a fast-forward cannot
# perform, and this is the runner that replays them.
#
# THE CONTRACT (spec §6):
#   - Migrations are `migrations/v<major>.<minor>.<patch>.sh`. Anything else in
#     this directory is ignored, on purpose: a half-named file is skipped loudly
#     rather than run with a version nobody can order.
#   - A clone remembers the version it last ran, bare, in
#     `.update-state/last-setup-version` — the same string that is in VERSION,
#     with no `v` prefix.
#   - Each migration is gated a SECOND time by a touchfile,
#     `.update-state/migrations/<version>.done`. The marker is the cheap range
#     filter; the touchfile is the authority. Two gates because the marker is a
#     single number and can move for reasons that have nothing to do with any
#     one migration.
#   - A FRESH install (no marker at all) adopts the current VERSION and replays
#     NOTHING. There is no history to repair on a tree that was never old.
#   - Failure is NON-FATAL and never breaks the chain. A migration that exits
#     nonzero is reported, its touchfile is withheld so it is retried, the
#     marker is held back so it stays in range, and the runner carries on to the
#     next one and exits 0 regardless. An update that already landed is not
#     un-landed by a repair that did not.
#   - Every human word goes to STDERR. update.sh's stdout is a machine contract
#     (one STATUS= line) and this runner is called from inside it; a runner that
#     printed to stdout would corrupt a wire format it does not own.
#
# TWO INVOCATION FORMS, both supported, because two different callers want
# different things:
#
#     bash migrations/run.sh                 # a subprocess — setup.sh, update.sh
#     . migrations/run.sh && run_migrations  # sourced, for a caller that wants
#                                            # the function in its own shell
#
# Which is why this file sets NO shell options at file scope. `set -e` in a
# sourced file silently rewrites the caller's error handling, and `set -u` turns
# the caller's next unset variable into an exit. Safety lives inside the
# function instead.
#
# ORDERING is `sort -V` semantics — 1.10.0 sorts ABOVE 1.2.0, never below —
# implemented with a zero-padded numeric key rather than by calling `sort -V`.
# BSD sort gained -V late and busybox sort has never had it, and the failure
# mode of a missing -V is not an error: it is a silently lexical order that runs
# 1.10.0 before 1.2.0 and looks like it worked.

# ── Version helpers ──────────────────────────────────────────────────────────

# A version is exactly three dot-separated runs of digits. No `v`, no suffix.
_pack_is_semver() {
  case "$1" in
    *[!0-9.]* | '' | *..* | .* | *.) return 1 ;;
  esac
  local a b c rest
  IFS=. read -r a b c rest <<EOF
$1
EOF
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -z "$rest" ]
}

# A fixed-width all-digit key, so string comparison IS version comparison in
# every locale and every sort(1). 1.10.0 -> 000010001000000.
_pack_version_key() {
  local a b c
  IFS=. read -r a b c <<EOF
$1
EOF
  printf '%05d%05d%05d' "$((10#${a:-0}))" "$((10#${b:-0}))" "$((10#${c:-0}))"
}

# Trim whitespace and a stray leading `v`, so a hand-edited marker still parses.
_pack_read_version_file() {
  [ -f "$1" ] || return 1
  local raw
  raw="$(sed -e 's/[[:space:]]//g' "$1" 2>/dev/null | sed -n '/./{p;q;}')"
  raw="${raw#v}"
  [ -n "$raw" ] || return 1
  printf '%s' "$raw"
}

# ── The runner ───────────────────────────────────────────────────────────────
run_migrations() {
  # BASH_SOURCE[0] is this file whichever way it was entered, so the root is
  # derived from the script's own location and never from the caller's cwd.
  local self_dir root state_dir mig_dir done_dir marker_file version_file
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || {
    printf 'migrations: cannot resolve my own directory; skipping\n' >&2
    return 0
  }
  root="$(cd "$self_dir/.." 2>/dev/null && pwd)" || {
    printf 'migrations: cannot resolve the repo root; skipping\n' >&2
    return 0
  }

  case "${1:-}" in
    -h|--help)
      printf 'Usage: bash migrations/run.sh\n\n' >&2
      printf 'Replays migrations/v*.sh newer than .update-state/last-setup-version.\n' >&2
      printf 'Always exits 0. Reports to stderr. See migrations/README.md.\n' >&2
      return 0
      ;;
  esac

  mig_dir="$root/migrations"
  state_dir="${PACK_STATE_DIR:-$root/.update-state}"
  done_dir="$state_dir/migrations"
  marker_file="$state_dir/last-setup-version"
  version_file="$root/VERSION"

  local target
  if ! target="$(_pack_read_version_file "$version_file")" || ! _pack_is_semver "$target"; then
    # No anchor means no honest range and no honest marker to write. Say so and
    # leave the marker exactly as found — a guessed marker is worse than none,
    # because it silently retires migrations that were never run.
    printf 'migrations: no readable semver in %s; nothing replayed, marker untouched\n' \
      "$version_file" >&2
    return 0
  fi

  mkdir -p "$state_dir" 2>/dev/null || {
    printf 'migrations: cannot create %s; skipping\n' "$state_dir" >&2
    return 0
  }

  # ── Fresh install: adopt the version, replay nothing ───────────────────────
  if [ ! -f "$marker_file" ]; then
    printf '%s\n' "$target" > "$marker_file" 2>/dev/null \
      || printf 'migrations: could not write %s\n' "$marker_file" >&2
    printf 'migrations: fresh install at %s — nothing to replay.\n' "$target" >&2
    return 0
  fi

  local from
  if ! from="$(_pack_read_version_file "$marker_file")" || ! _pack_is_semver "$from"; then
    # A corrupt marker must not replay four months of repairs against a tree
    # that may already have had them. Fail toward doing nothing, and say which
    # file a human has to look at.
    printf 'migrations: %s is not a bare semver; nothing replayed.\n' "$marker_file" >&2
    printf '            Set it to the version this clone last ran, e.g. `echo %s > %s`\n' \
      "$target" "$marker_file" >&2
    return 0
  fi

  # ── Select: strictly above the marker, in sort -V order ────────────────────
  local from_key; from_key="$(_pack_version_key "$from")"
  local pending="" f base ver

  # Every *.sh here is a candidate, not just the v-prefixed ones. Globbing only
  # `v*.sh` would step over `1.5.0.sh` and `fix-thing.sh` in total silence —
  # a migration that never runs and never says it did not run, which is the
  # worst of the three outcomes. They are still skipped; they are just skipped
  # OUT LOUD, which is what README.md promises.
  for f in "$mig_dir"/*.sh; do
    [ -f "$f" ] || continue          # an unmatched glob is the literal pattern
    base="${f##*/}"
    case "$base" in run.sh) continue ;; esac
    base="${base%.sh}"
    ver="${base#v}"
    if [ "$ver" = "$base" ] || ! _pack_is_semver "$ver"; then
      printf 'migrations: SKIPPING %s — a migration must be named v<major>.<minor>.<patch>.sh\n' \
        "$base.sh" >&2
      printf '            Nothing in it will ever run until it is renamed.\n' >&2
      continue
    fi
    [ "$(_pack_version_key "$ver")" \> "$from_key" ] || continue
    pending="${pending}$(_pack_version_key "$ver") $ver $f
"
  done

  if [ -z "$pending" ]; then
    # Still advance: the clone is now at `target` even though nothing had to be
    # repaired to get it there. Without this the marker would sit at the last
    # version that HAPPENED to ship a migration and the range would keep growing.
    printf '%s\n' "$target" > "$marker_file" 2>/dev/null || true
    return 0
  fi

  # ── Replay ─────────────────────────────────────────────────────────────────
  mkdir -p "$done_dir" 2>/dev/null || true
  local ran=0 failed=0 skipped=0 key path rc
  while IFS=' ' read -r key ver path; do
    [ -n "${path:-}" ] || continue
    if [ -f "$done_dir/$ver.done" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    printf 'migrations: running v%s\n' "$ver" >&2

    # Exported so a migration can honor a user's opt-outs without re-deriving
    # any of this. The config file is B1/B2's schema; a migration reads it
    # itself — see migrations/README.md.
    (
      export PACK_ROOT="$root"
      export PACK_STATE_DIR="$state_dir"
      export PACK_VERSION="$target"
      export PACK_FROM_VERSION="$from"
      export PACK_MIGRATION_VERSION="$ver"
      bash "$path"
    )
    rc=$?

    if [ "$rc" -eq 0 ]; then
      : > "$done_dir/$ver.done" 2>/dev/null || true
      ran=$((ran + 1))
    else
      # No touchfile, so it is retried; and the marker is held back below, so it
      # stays inside the range that selects it. A migration that failed is a
      # repair still owed, not a repair spent.
      failed=$((failed + 1))
      printf 'migrations: warning — v%s exited %s. It will be retried on the next run.\n' \
        "$ver" "$rc" >&2
    fi
  done <<EOF
$(printf '%s' "$pending" | sort)
EOF

  if [ "$failed" -eq 0 ]; then
    printf '%s\n' "$target" > "$marker_file" 2>/dev/null || true
  else
    printf 'migrations: marker held at %s because %s migration(s) still owe a repair.\n' \
      "$from" "$failed" >&2
  fi

  [ "$ran" -gt 0 ] && printf 'migrations: %s applied, %s already done.\n' "$ran" "$skipped" >&2
  return 0
}

# Directly executed (`bash migrations/run.sh`) — but not when sourced, where the
# caller asked for the function and will call it when it wants it.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  run_migrations "$@"
fi
