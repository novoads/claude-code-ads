#!/usr/bin/env bash
# Open a file in the user's GUI text editor — or decline, and say so with a
# status code rather than a sentence.
#
#   bash shared/scripts/open-env.sh <path-to-file>
#
#     exit 0   the file was actually opened in a GUI editor
#     exit 3   deliberately skipped, for any of the reasons guarded below
#     exit 2   called wrong (no argument, or more than one)
#
# It prints NOTHING on 0 and 3, and that silence is the point. Two callers use
# it — scripts/setup.sh, which opens .env so a first-time user can paste their
# Novoads API key, and shared/skills/meta-ad-builder/scripts/check-meta-env.sh,
# which opens the same file when the Meta credentials are missing — and the
# sentence each one owes the user is different ("paste the key on the
# NOVOADS_API_KEY line" versus the Meta variables). Anything printed here would
# be the wrong sentence for one caller, or a duplicate for both. The exit status
# is the entire return value; each caller writes its own message from it.
#
# Why it is a file and not a function: this logic used to live inline in
# setup.sh's open_env_file(). A second caller means a second copy, and a second
# copy is a second place for the SSH guard to be forgotten by whoever is in a
# hurry. One implementation, one set of guards, one thing to fix.
set -euo pipefail

# Every guard below is a REASON TO SKIP, and each one ends the script with 3.
# Not opening an editor is an ordinary outcome, never an error: the caller has a
# fallback sentence for exactly this case, and a non-zero-but-not-3 status would
# make a normal Tuesday look like a broken install.
#
# They are written as explicit `if ... then ... fi`, never as `[[ ... ]] && exit`.
# Under `set -e` a bare AND-list hands its own exit status to the shell when the
# test fails, which is how a script that did everything right ends on 1. This
# repo has been bitten by that before (see the closing branch of setup.sh).
skip_quietly() {
  exit 3
}

if [[ $# -ne 1 ]]; then
  # Usage errors are the one thing worth printing, and they go to stderr so a
  # caller capturing stdout still sees a clean empty capture. The name is a
  # literal rather than `basename "$0"` because this script promises three exit
  # codes and nothing else — spawning a helper here would let a 127 from a
  # broken PATH escape in place of the 2 the caller is branching on.
  echo "Usage: open-env.sh <path-to-file>" >&2
  exit 2
fi
target="$1"

# A path beginning with a dash is read as an OPTION by either opener. macOS
# `open` honours `--`, but xdg-open has no end-of-options terminator and rejects
# an unrecognised -* outright — so passing `--` there would make every Linux call
# fail, and because a failed open is a silent skip, the feature would be quietly
# dead on Linux with no CI able to see it (the guards are greps, and this script
# skips whenever $CI is set). Normalising the path is the fix that works on both.
case "$target" in
  -*) target="./$target" ;;
esac

# The documented opt-out. Someone who does not want a window stealing focus in
# the middle of a run sets this once and every caller honours it; the name is
# part of the contract, so keep it exactly as spelled.
if [[ "${NOVOADS_SETUP_NO_OPEN:-}" == "1" ]]; then
  skip_quietly
fi

# CI has no desktop and no human watching it. Opening anything there is at best
# a no-op and at worst a process that never returns.
if [[ -n "${CI:-}" ]]; then
  skip_quietly
fi

# Over SSH the editor would open on the machine we are logged in FROM — or,
# worse, nowhere at all while the command sits there. Three variables because no
# single one is set by every client and jump-host combination; concatenating them
# is an OR across all three in one test, which also keeps this readable on the
# bash 3.2 that ships with macOS.
if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ]]; then
  skip_quietly
fi

# Nothing to open. Checked here rather than left to the opener, because a
# missing file is a caller bug worth reporting in the caller's own words, and
# `open` on a nonexistent path is a GUI error dialog on someone's screen.
if [[ ! -f "$target" ]]; then
  skip_quietly
fi

# GUI editors ONLY — deliberately no $EDITOR / $VISUAL fallback.
#
# The primary caller runs with no TTY attached (an agent driving setup, a piped
# run, CI). In that world $EDITOR is vim with no terminal: it either hangs
# forever or dies immediately, and either way the run stops being about the API
# key and starts being about a stuck process. A terminal editor is not a
# degraded version of this feature; it is a different and worse outcome than
# doing nothing, and doing nothing is already handled — the caller prints the
# path and the user opens it themselves.

# `|| echo unknown` so a PATH too broken to resolve `uname` lands in the
# catch-all arm below and skips, instead of taking `set -e` and a 127 out with
# it. The callers branch on 0/2/3; any fourth status is a bug report about this
# script rather than the missing key it was supposed to be about.
os="$(uname -s 2>/dev/null || echo unknown)"

case "$os" in
  Darwin)
    if ! command -v open >/dev/null 2>&1; then
      skip_quietly
    fi
    # -t is REQUIRED, not a nicety. It forces the default TEXT editor. `.env`
    # has no extension, so without it macOS resolves the open against a file
    # type nothing is registered for.
    #
    # stdin is closed for the same reason the whole script exists: an opener
    # that inherits the caller's stdin is an opener that can block it.
    if ! open -t -- "$target" </dev/null >/dev/null 2>&1; then
      skip_quietly
    fi
    ;;
  Linux)
    # No display server means no GUI editor to open into. Tested BEFORE
    # xdg-open's existence, because on a headless box xdg-open is often still
    # installed and cheerfully falls back to a terminal editor — the exact hang
    # the block above refuses.
    if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
      skip_quietly
    fi
    if ! command -v xdg-open >/dev/null 2>&1; then
      skip_quietly
    fi
    if ! xdg-open "$target" </dev/null >/dev/null 2>&1; then
      skip_quietly
    fi
    ;;
  *)
    # Some other OS. There is no opener here we have ever tested, and guessing
    # at one is how a setup run ends in a process nobody can see and nobody
    # thought to quit.
    skip_quietly
    ;;
esac

# Reached only when an opener was found, ran, and returned success. This is the
# single claim the callers are allowed to make on our behalf: the file is open.
exit 0
