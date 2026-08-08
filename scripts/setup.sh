#!/usr/bin/env bash
# First-run setup for the Novoads skill pack.
# Creates .env, MASTER_CONTEXT.md, syncs skills, and verifies API connectivity.
#
# The credential is validated against a live endpoint BEFORE it is written to
# disk. A .env holding a key that has never been probed is the most expensive
# state to debug, because every later failure looks like a different bug.
#
# TWO MODES, because an agent is a first-class user of this script:
#
#   interactive      (a TTY on stdin) prompts for the key, hidden, up to 3 times.
#   non-interactive  (--non-interactive, or stdin is not a TTY) prompts for
#                    NOTHING. It creates the files, syncs the skills, reports
#                    the exact remaining human step, and exits 0.
#
# The second mode is not a convenience. An agent driving this repo cannot type
# into a hidden `read -rs`, so without it the agent either hangs or reimplements
# the script by hand, and the setup that ships is not the setup anyone runs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Host only — every request below appends /v1/…
BASE_URL="${NOVOADS_BASE_URL:-https://api.novoads.ai}"
SIGNUP_URL="https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack"
KEYS_URL="https://novoads.ai/dashboard/settings?tab=api"
BILLING_URL="https://novoads.ai/dashboard/settings?tab=billing"
KEY_PLACEHOLDER="novo_your_key_here"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup.sh [--non-interactive]

  --non-interactive, -n   Never prompt. Create .env and MASTER_CONTEXT.md, sync
                          skills, print the remaining step, exit 0. This is also
                          the automatic behavior when stdin is not a terminal.
  --help, -h              This text.

Environment:
  NOVOADS_BASE_URL   Override the API host (default https://api.novoads.ai).
EOF
}

INTERACTIVE=1
# No TTY means nobody can answer a prompt. Detected rather than assumed, so an
# agent, a CI step and a `| tee` all get the same non-blocking behavior.
[[ -t 0 ]] || INTERACTIVE=0

while (( $# > 0 )); do
  case "$1" in
    -n|--non-interactive) INTERACTIVE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

echo "=== Novoads Skill Pack Setup ==="
if [[ "$INTERACTIVE" == "0" ]]; then
  echo "(non-interactive: nothing will prompt)"
fi
echo ""

# `novo_` + 64 lowercase hex. Checked locally first so an obvious typo costs a
# reprompt instead of a round trip. There is exactly one key format now — the
# Basic-auth guessing this replaces existed only because the old API's Basic auth had two formats.
key_shape_ok() {
  [[ "$1" =~ ^novo_[0-9a-f]{64}$ ]]
}

# ONE probe, body and status together, into two globals.
#
# `-w $'\n%{http_code}'` rather than `-o /dev/null -w "%{http_code}"`: the
# latter emits `000` with no trailing newline on a connection failure, so a
# `|| echo "000"` fallback produces `000000`, misses the `000)` arm, and tells
# an offline user their key returned "HTTP 000000". Probing once rather than
# twice matters too — a transient failure followed by a 200 announced
# "Unexpected response from Novoads (HTTP 200)".
#
# GET /v1/models is free, read-only, and still requires a valid key, so a 200
# proves auth while generating nothing and charging nothing.
PROBE_CODE=""
PROBE_BODY=""
probe_key() {
  local response
  response="$(curl -sS -m 20 -w $'\n%{http_code}' \
    -H "Authorization: Bearer $1" "$BASE_URL/v1/models" 2>/dev/null || printf '\n000')"
  PROBE_CODE="${response##*$'\n'}"
  PROBE_BODY="${response%$'\n'*}"
}

# Explain a non-200 probe. Every arm names a DIFFERENT fix, which is the only
# reason to have arms at all.
#
# The two 403s are genuinely different account-level states and the API tells
# them apart in the body: a plan problem carries `"reason":"plan_required"`,
# and the rollout-disabled answer carries no reason at all. Reading only the
# status code blames billing for both.
explain_probe_failure() {
  local code="$1" body="$2"
  case "$code" in
    401)
      echo "✗ Novoads rejected that key (401). It is mistyped, revoked, or from another account."
      echo "  Create a fresh one at $KEYS_URL"
      ;;
    403)
      if [[ "$body" == *"plan_required"* ]]; then
        echo "⚠️  The key is valid (403). This organization has no plan with API access yet."
        echo "  Check your plan at $BILLING_URL"
      else
        echo "⚠️  The key is valid (403), but the REST API is not enabled for this account yet."
        echo "  Nothing to fix on your side. $body"
      fi
      ;;
    429)
      echo "✗ Rate limited (429). Wait a minute and run this again."
      ;;
    000)
      echo "✗ Could not reach $BASE_URL. Check your network."
      ;;
    *)
      echo "✗ Unexpected response from Novoads (HTTP $code)."
      [[ -n "$body" ]] && echo "  $body"
      ;;
  esac
}

# Everything but the last 4 characters becomes `*`.
#
# Two `local` statements, not one. `local s="$1" n=${#s}` expands ${#s} BEFORE
# the builtin runs, so `n` reads the outer scope and comes back 0, and every key
# masks to a bare `****`.
mask_secret() {
  local s="$1"
  local n=${#s}
  if (( n <= 4 )); then
    printf '****'
  else
    printf '%s%s' "$(printf '%*s' $((n - 4)) '' | tr ' ' '*')" "${s: -4}"
  fi
}

write_key_to_env() {
  # Rewrite the single line rather than appending, so re-running setup on a
  # placeholder .env does not leave two NOVOADS_API_KEY rows.
  sed "s|^NOVOADS_API_KEY=.*|NOVOADS_API_KEY=$1|" "$ROOT/.env" > "$ROOT/.env.tmp" \
    && mv "$ROOT/.env.tmp" "$ROOT/.env"
  chmod 600 "$ROOT/.env" 2>/dev/null || true
}

# What the pack makes, said at the end of both successful exit paths. Setup's
# last words used to be about files; the user's next move is an ask, so the
# close names the asks. Plain text rather than a prompt or a menu on purpose:
# the same block has to land in Claude Code, Cursor, and a bare terminal, and
# setup asks a human for exactly one thing — the key, never the product. The
# product question belongs to the first ad request (see AGENTS.md), where the
# answer is used immediately and saved to MASTER_CONTEXT.md.
print_orientation() {
  echo ""
  echo "── What you can ask for ─────────────────────────────────────────────"
  echo "  Open this folder in Claude Code or Cursor and describe the ad:"
  echo "    • \"Make a UGC video ad for my product\"    — Seedance 2.0/2.5, Veo 3.1, Sora 2"
  echo "    • \"Make a static image ad from this photo\" — 40-template library"
  echo "    • \"Clone this ad\" plus an image of one you like"
  echo "    • Pixar or claymation story ads, YouTube thumbnails, burned-in captions, generated music"
  echo "  Drop product photos into references/products/ — the agent asks about"
  echo "  your product the first time you ask for an ad, not before."
  echo "─────────────────────────────────────────────────────────────────────"
}

# The same close, addressed to the AI agent driving setup — printed INSTEAD of
# the human-facing blocks in non-interactive mode, never alongside them. Two
# reasons it lives here and not only in AGENTS.md:
#
#   1. The advertised flow starts in an EMPTY directory ("<repo url> help me
#      set this up"), so no agent-instruction file is loaded when that session
#      begins, and nothing guarantees one is read after the clone. This
#      script's stdout is the one channel that flow always reads — which is
#      how a session at a commit that already carried the AGENTS.md template
#      (#41/#42) still closed with an engineering log, a two-option key menu,
#      and an MCP digression (2026-08-08).
#
#   2. An agent shown two phrasings of the same remaining step relays both as
#      a menu. One block, one phrasing, stated as the whole message.
#
# Mirrors AGENTS.md "First-time setup" — change the two together.
print_agent_close() {
  local variant="$1"
  echo "AGENT: the block between the markers is your ENTIRE closing message to the"
  echo "user, verbatim — at most one short status line above it. Nothing else: no"
  echo "git or sync mechanics, no file inventories, no MCP or connector notes, no"
  echo "optional installs, no second way to provide the key, and no questions"
  echo "about their product — that belongs to their first ad request."
  echo "A connected Novoads MCP connector does NOT replace the key and must not be"
  echo "mentioned: it is a different surface, this repo's skills never call it, and"
  echo "offering it turns the one remaining step into a menu the user can pick wrong."
  echo ""
  echo "──── FINAL MESSAGE START ────"
  if [[ "$variant" == "ready" ]]; then
    echo "Setup's done — your key works."
  else
    echo "One step left, the only one I can't do: create an API key at"
    echo "$KEYS_URL"
    echo "paste it into .env, and tell me — I'll verify it."
    echo "(No account yet? The \$1 trial: $SIGNUP_URL)"
  fi
  echo ""
  echo "What you can ask for now:"
  echo "- \"Make a UGC video ad for my product\" — Seedance 2.0/2.5, Veo 3.1, Sora 2"
  echo "- \"Make a static image ad from this photo\" — 40-template library"
  echo "- \"Clone this ad\" plus an image of one you like"
  echo "- Pixar or claymation story ads, YouTube thumbnails, burned-in captions, generated music"
  echo ""
  echo "Drop product photos into references/products/ and describe the ad you want."
  echo "Every generation is priced by a live estimate and shown to you before"
  echo "anything is spent."
  echo "──── FINAL MESSAGE END ────"
}

# ── Step 1: .env ──────────────────────────────────────────────────────────────
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env" 2>/dev/null || true
  echo "Created .env from template (chmod 600)."
  needs_key=1
elif grep -q "$KEY_PLACEHOLDER" "$ROOT/.env"; then
  echo ".env exists but still has the placeholder key."
  needs_key=1
else
  echo ".env already exists with a key. Skipping prompt."
  needs_key=0
fi

if [[ "$needs_key" == "1" && "$INTERACTIVE" == "1" ]]; then
  echo ""
  echo "Need a Novoads account? Start your \$1 trial here:"
  echo "  $SIGNUP_URL"
  echo ""
  echo "Then create an API key at:"
  echo "  $KEYS_URL"
  echo ""

  attempts=0
  while (( attempts < 3 )); do
    attempts=$((attempts + 1))
    # -s so the key never echoes or lands in shell scrollback.
    printf "Paste your Novoads API key (input hidden, Enter to skip): "
    # Tested, not assumed: a bare `read` returns non-zero at EOF, and under
    # `set -e` that kills the run right here — Ctrl-D at this prompt would skip
    # MASTER_CONTEXT.md and the skill sync and report nothing about either.
    if ! read -rs input; then
      printf "\n"
      echo "No input. Add your key to .env before using the skill."
      break
    fi
    printf "\n"

    if [[ -z "$input" ]]; then
      echo "Skipped. Add your key to .env before using the skill."
      break
    fi

    if ! key_shape_ok "$input"; then
      echo "✗ That does not look like a Novoads key. Expected novo_ followed by 64 hex characters."
      echo "  Attempts left: $((3 - attempts))"
      unset input
      continue
    fi

    echo "Validating against $BASE_URL/v1/models ..."
    probe_key "$input"

    if [[ "$PROBE_CODE" == "200" ]]; then
      write_key_to_env "$input"
      echo "✓ Valid. Saved to .env as $(mask_secret "$input")"
      unset input
      break
    fi

    # A 403 is a real key against an account that cannot call the API yet.
    # Saving it is correct: re-prompting would only collect the same key again,
    # and the fix is on the billing page, not in this file. A 401 is never
    # saved — that key is wrong and .env would just memorialize the typo.
    if [[ "$PROBE_CODE" == "403" ]]; then
      write_key_to_env "$input"
      explain_probe_failure "$PROBE_CODE" "$PROBE_BODY"
      echo "  Saved to .env anyway as $(mask_secret "$input") — the key is real, the plan is the blocker."
      echo "  Re-run ./scripts/check-novoads-env.sh once the plan is active."
      unset input
      break
    fi

    explain_probe_failure "$PROBE_CODE" "$PROBE_BODY"
    echo "  Attempts left: $((3 - attempts))"
    unset input
  done
fi

echo ""

# ── Step 2: MASTER_CONTEXT.md ────────────────────────────────────────────────
if [[ ! -f "$ROOT/MASTER_CONTEXT.md" ]]; then
  cp "$ROOT/MASTER_CONTEXT.template.md" "$ROOT/MASTER_CONTEXT.md"
  echo "Created MASTER_CONTEXT.md from template."
  echo "The agent asks for your default product the first time you request an ad,"
  echo "and saves the answer here so it never asks again."
else
  echo "MASTER_CONTEXT.md already exists. Skipping."
fi

echo ""

# ── Step 3: Sync skills to .claude/ and .cursor/ ─────────────────────────────
bash "$ROOT/scripts/sync-skill.sh"

echo ""

# ── Step 4: Verify API connectivity ──────────────────────────────────────────
# In non-interactive mode this step REPORTS and never fails the run. Asserting
# connectivity is check-novoads-env.sh's job and it exits non-zero for exactly
# that; this script's contract here is "prepare the workspace and say what is
# left", and a missing key on a fresh clone is the expected state, not an error.
if grep -q "$KEY_PLACEHOLDER" "$ROOT/.env" 2>/dev/null; then
  echo "No key set in .env yet. Skipping the connectivity check."
  echo ""
  if [[ "$INTERACTIVE" == "0" ]]; then
    print_agent_close needs_key
    exit 0
  fi
  echo "── What is left for a human ─────────────────────────────────────────"
  echo "  1. Create a key at $KEYS_URL"
  echo "     No Novoads account yet? Start the \$1 trial: $SIGNUP_URL"
  echo "  2. Open $ROOT/.env and replace $KEY_PLACEHOLDER on the"
  echo "     NOVOADS_API_KEY= line with that key. Keys are novo_ plus 64 hex characters."
  echo "  3. Run ./scripts/check-novoads-env.sh to confirm it works."
  echo "─────────────────────────────────────────────────────────────────────"
  echo ""
  echo "Everything else is done: .env, MASTER_CONTEXT.md, and the synced skills."
  print_orientation
  exit 0
fi

# Do not let `set -e` swallow the closing message. A user who ends on a bare
# error and no next step is a user who has to guess whether anything worked.
if bash "$ROOT/scripts/check-novoads-env.sh"; then
  echo ""
  if [[ "$INTERACTIVE" == "0" ]]; then
    print_agent_close ready
    exit 0
  fi
  echo "Setup complete."
  print_orientation
  exit 0
fi

echo ""
echo "Setup wrote your files, but the key in .env cannot call the API yet."
echo "The check above says whether that is the key (401 — replace it) or the"
echo "account (403 — activate a plan). Re-run ./scripts/check-novoads-env.sh after fixing."
# Non-interactive callers get the diagnosis on stdout and a 0, because in that
# mode this script reports state rather than asserting it. An `if` rather than a
# trailing `&&`: under `set -e` a final AND-list whose test fails takes the exit
# status with it, which is how a "succeeded" run ends on 1.
if [[ "$INTERACTIVE" == "1" ]]; then
  exit 1
fi
echo ""
echo "AGENT: report the diagnosis above and its one fix in a sentence or two, then"
echo "stop. No orientation, no alternatives — nothing works until the key does."
exit 0
