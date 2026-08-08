#!/usr/bin/env bash
# Verify Meta Marketing API credentials for the meta-ad-builder skill.
#
# Checks, in order:
#   1. META_ACCESS_TOKEN and META_AD_ACCOUNT_ID are set
#   2. the token is valid and not expired            (/me)
#   3. the token actually carries ads_management     (/me/permissions)
#   4. the ad account is reachable *with this token* (/act_<id>)
#   5. META_PAGE_ID, if set, is reachable
#
# Steps 3 and 4 are the ones that matter: a token with no ads scopes passes a
# /me check and then fails at deploy time. Verified 2026-08-03.
#
# When check 1 fails this script SETS THE USER UP rather than only complaining.
# The Meta key is deliberately lazy: this pack never asks for it during setup —
# one Novoads key is the whole point — so the first time anyone hears about it is
# the moment they ask to publish. That moment has to carry everything they need.
# So a missing credential uncomments the two required lines in .env, opens the
# file, and prints where each value comes from.
#
# What this CANNOT check: whether the Meta app is published (Live). There is no
# Graph endpoint that reports app mode for a user token. A development-mode app
# fails at ad creation with code 100 / subcode 1885183 — see SKILL.md
# Prerequisites. That warning therefore leads the setup text below, at the one
# moment it can still be acted on cheaply.
#
# Usage:  bash check-meta-env.sh
set -euo pipefail

# Locate a .env: prefer an explicit ENV_FILE, else walk up from this script
# looking for a repo-root .env or the gen-ai-core workspace .env.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in \
    "$SCRIPT_DIR/../../../../.env" \
    "$SCRIPT_DIR/../../../.env" \
    "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)/.env" \
    "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)/workspace/.env"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      ENV_FILE="$candidate"
      break
    fi
  done
fi

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  echo "Loading env from: $ENV_FILE"
  set -a; source "$ENV_FILE"; set +a
else
  echo "No .env found — relying on already-exported environment variables."
fi

API_VERSION="${META_API_VERSION:-v23.0}"
GRAPH="https://graph.facebook.com/${API_VERSION}"
fail=0

if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "  MISSING: META_ACCESS_TOKEN"
  fail=1
else
  echo "  OK: META_ACCESS_TOKEN is set"
fi

if [[ -z "${META_AD_ACCOUNT_ID:-}" ]]; then
  echo "  MISSING: META_AD_ACCOUNT_ID"
  fail=1
else
  echo "  OK: META_AD_ACCOUNT_ID = ${META_AD_ACCOUNT_ID}"
fi

# ── Setup path, used only when a required credential is missing ──────────────
#
# The Meta block in .env.example ships COMMENTED OUT, and that is the most
# likely way this whole feature fails in practice: a user opens .env, sees
# "# META_ACCESS_TOKEN=", types their token onto that line, re-runs, and gets
# the identical failure — because they edited a comment. Uncommenting the two
# required lines for them is therefore the load-bearing step, not a nicety.

# The exact placeholder values .env.example ships, defined ONCE: the rewrite and
# the "you typed onto a comment" detector below must agree on what counts as a
# pristine template line, or one of them starts editing the user's own value.
META_TOKEN_PLACEHOLDER="your_long_lived_token_here"
META_ACCOUNT_PLACEHOLDER="act_1234567890"

placeholder_for() {
  case "$1" in
    META_ACCESS_TOKEN)  printf '%s\n' "$META_TOKEN_PLACEHOLDER" ;;
    META_AD_ACCOUNT_ID) printf '%s\n' "$META_ACCOUNT_PLACEHOLDER" ;;
    *)                  printf '\n' ;;
  esac
}

# Permission bits in octal. BSD stat first (macOS is this repo's first target),
# then GNU stat. Empty if neither answers.
env_file_mode() {
  stat -f '%OLp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || printf ''
}

# Follow symlinks to the real file: `mv` onto a symlink replaces the link with a
# regular file and leaves the shared target holding the old content.
resolve_path() {
  local p="$1" d hops=0
  while [[ -L "$p" && "$hops" -lt 8 ]]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    [[ "$p" == /* ]] || p="$d/$p"
    hops=$(( hops + 1 ))
  done
  printf '%s\n' "$p"
}

# Turn the EXACT .env.example template forms — "# KEY=" or "# KEY=<placeholder>"
# — into live, EMPTY assignments, for the named keys only.
#
# Empty rather than placeholder-valued on purpose: uncommenting
# "# META_AD_ACCOUNT_ID=act_1234567890" as-is would satisfy the is-it-set check
# above and then fail at check 3 with an unreachable-account error, which reads
# as a permissions problem rather than as "you never filled this in".
#
# The match is deliberately narrow. A line the user has already typed into does
# not match, and neither does a line that is already uncommented, so this can
# only ever move a pristine template line.
#
# Returns 0 rewrote, 1 could not write, 2 nothing matched.
uncomment_required_keys() {
  local file="$1"; shift
  local tmp mode after
  tmp="$(mktemp "${file}.meta-env.XXXXXX")" || return 1
  if ! awk -v keys="$*" \
          -v ph_token="$META_TOKEN_PLACEHOLDER" \
          -v ph_acct="$META_ACCOUNT_PLACEHOLDER" '
    BEGIN {
      n = split(keys, kk, " ")
      for (i = 1; i <= n; i++) want[kk[i]] = 1
      ph["META_ACCESS_TOKEN"]  = ph_token
      ph["META_AD_ACCOUNT_ID"] = ph_acct
    }
    {
      line = $0
      for (key in want) {
        bare = "^[ \t]*#[ \t]*" key "[ \t]*=[ \t]*$"
        tmpl = "^[ \t]*#[ \t]*" key "[ \t]*=[ \t]*" ph[key] "[ \t]*$"
        if (line ~ bare || line ~ tmpl) { line = key "="; break }
      }
      print line
    }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 2
  fi

  mode="$(env_file_mode "$file")"
  if [[ -n "$mode" ]]; then
    chmod "$mode" "$tmp"
  fi
  mv "$tmp" "$file"

  # Verify rather than assume: this file holds secrets and must stay 600.
  after="$(env_file_mode "$file")"
  if [[ -n "$mode" && "$after" != "$mode" ]]; then
    echo "  WARNING: $file is now mode ${after}, was ${mode}."
    echo "  Fix it before pasting a token in:  chmod ${mode} \"$file\""
  fi
  return 0
}

# The case the rewrite above deliberately will NOT touch: a commented line the
# user has already typed a value onto. That is the trap this whole path exists
# to close, and it is the one shape of it we must not silently "fix" — the value
# is theirs and the line is not the template any more. So name it instead, by
# key and line number only. The value never reaches the terminal: it is a live
# token, and this script's whole job is to be safe to run in front of anyone.
warn_commented_with_value() {
  local file="$1"; shift
  local key hit ph
  for key in "$@"; do
    ph="$(placeholder_for "$key")"
    # The shipped placeholder is not a user value: a still-pristine template
    # line is the rewrite's business, not this warning's.
    hit="$(grep -n "^[[:space:]]*#[[:space:]]*${key}[[:space:]]*=[[:space:]]*[^[:space:]]" "$file" 2>/dev/null \
           | grep -v "=[[:space:]]*${ph}[[:space:]]*$" \
           | cut -d: -f1 | tr '\n' ',' || true)"
    hit="${hit%,}"
    if [[ -n "$hit" ]]; then
      echo "  HEADS UP: ${key} is commented out and already has a value on it"
      echo "  (line ${hit}). A value on a commented line does nothing. Delete the"
      echo "  leading # on that line and re-run — do not retype the value."
    fi
  done
}

# Locate shared/scripts/open-env.sh. It is OPTIONAL: these skills install
# standalone, with no repo scripts/ directory anywhere on disk. Absent helper
# means we print the path instead of opening it — never an error.
find_open_env_helper() {
  local cand
  for cand in \
    "$SCRIPT_DIR/../../../scripts/open-env.sh" \
    "$SCRIPT_DIR/../../../../shared/scripts/open-env.sh" \
    "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)/shared/scripts/open-env.sh"; do
    if [[ -n "$cand" && -f "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

if [[ "$fail" -ne 0 ]]; then
  missing=()
  if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then missing+=(META_ACCESS_TOKEN); fi
  if [[ -z "${META_AD_ACCOUNT_ID:-}" ]]; then missing+=(META_AD_ACCOUNT_ID); fi

  env_path=""
  if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    env_path="$(resolve_path "$ENV_FILE")"
  fi

  echo
  echo "Meta credentials are not set yet. Nothing has been uploaded, no ad or"
  echo "creative exists, and nothing has been charged."
  echo

  # (a) Make the file editable-in-the-way-people-expect before asking for edits.
  if [[ -n "$env_path" ]]; then
    if [[ ! -w "$env_path" ]]; then
      echo "  NOTE: $env_path is not writable, so its two required lines were"
      echo "  left commented. Uncomment them yourself before filling them in."
    else
      rc=0
      uncomment_required_keys "$env_path" "${missing[@]}" || rc=$?
      case "$rc" in
        0) echo "  Uncommented in $env_path: ${missing[*]}" ;;
        2) : ;;  # already live, hand-edited, or this .env has no Meta block
        *) echo "  NOTE: could not rewrite $env_path. Uncomment the two required"
           echo "  lines yourself — a value typed onto a commented line does"
           echo "  nothing, and the next run fails exactly like this one." ;;
      esac
    fi
    warn_commented_with_value "$env_path" "${missing[@]}"
  fi

  # (b) Put the file in front of the user.
  if [[ -n "$env_path" ]]; then
    opened=0
    helper="$(find_open_env_helper || true)"
    if [[ -n "$helper" ]]; then
      rc=0
      bash "$helper" "$env_path" || rc=$?
      case "$rc" in
        0) opened=1 ;;
        3) : ;;  # the helper deliberately declined; it stays silent, so we talk
        2) echo "  NOTE: open-env.sh rejected the call (exit 2)." ;;
        *) : ;;
      esac
    fi
    if [[ "$opened" -eq 1 ]]; then
      echo "  Opened $env_path — paste each value after its = sign."
    else
      echo "  Open $env_path and paste each value after its = sign."
    fi
  else
    echo "  No .env on this install. Export both values in your shell instead:"
    echo "    export META_ACCESS_TOKEN=... META_AD_ACCOUNT_ID=act_..."
  fi

  # (c) What the user actually has to go and get. Unlike the Novoads key, a Meta
  # token is not one click, and the Live-app requirement is invisible until it
  # fails — so it leads.
  cat <<'META_SETUP'

FIRST, AND UNCHECKABLE FROM HERE: the Meta app that issues the token must be
published (Live). A development-mode app passes every check in this script and
then fails at ad creation with code 100 / subcode 1885183. No Graph endpoint
reports app mode for a user token, so nothing here can test it for you.
  Fix: App Dashboard -> your app -> toggle Development to Live.
  Allowlisting the ad account under App settings -> Advanced -> Authorized ad
  account IDs does NOT work around it. Tested live, 2026-08-03.

META_ACCESS_TOKEN  (required)
  A long-lived token carrying the ads_management scope specifically. ads_read
  alone is not enough: it passes /me and then dies at ad creation, which is
  exactly what check 2 below exists to catch before you upload anything.
  Where:
    Graph API Explorer — https://developers.facebook.com/tools/explorer
      pick your app, add the ads_management permission, Generate Access Token,
      then extend it to 60 days in the Access Token Debugger:
      https://developers.facebook.com/tools/debug/accesstoken
    Or a non-expiring one — Business Settings -> Users -> System Users ->
      Add -> Generate new token, with ads_management ticked.

META_AD_ACCOUNT_ID  (required)
  The ad account the ads are created in, e.g. act_1234567890.
  Where: the Ads Manager account picker (top left), or the act_... segment of
  any Ads Manager URL. Business Settings -> Accounts -> Ad Accounts lists it
  too. The act_ prefix is optional; the scripts add it if it is missing.
  The token's user needs a role on THIS account or check 3 fails.

Optional, and left commented on purpose: META_PAGE_ID, META_IG_USER_ID,
META_PIXEL_ID, META_API_VERSION (default v23.0).

Then re-run:  bash scripts/check-meta-env.sh
META_SETUP
  exit 1
fi

# Normalize the act_ prefix the same way meta_api.get_ad_account_id() does.
ACCT="$META_AD_ACCOUNT_ID"
[[ "$ACCT" == act_* ]] || ACCT="act_${ACCT}"

echo
echo "1/4  Validating token against Graph API ${API_VERSION}..."
resp="$(curl -s "${GRAPH}/me?fields=id,name&access_token=${META_ACCESS_TOKEN}")"
if echo "$resp" | grep -q '"error"'; then
  echo "  TOKEN CHECK FAILED:"
  echo "$resp"
  exit 1
fi
echo "  OK: token is valid — $resp"

echo
echo "2/4  Checking granted permissions (ads_management)..."
perms="$(curl -s "${GRAPH}/me/permissions?access_token=${META_ACCESS_TOKEN}")"
if echo "$perms" | grep -q '"error"'; then
  echo "  PERMISSION CHECK FAILED:"
  echo "$perms"
  exit 1
fi
for scope in ads_management ads_read; do
  # Granted entries look like {"permission":"ads_management","status":"granted"}
  if echo "$perms" | tr '}' '\n' | grep -q "\"${scope}\".*granted"; then
    echo "  OK: ${scope} granted"
  elif [[ "$scope" == "ads_management" ]]; then
    echo "  MISSING SCOPE: ads_management is not granted on this token."
    echo "  deploy-ad.py cannot create ads without it. Re-issue the token with"
    echo "  ads_management (Graph API Explorer or your Business System User)."
    fail=1
  else
    echo "  NOTE: ${scope} not granted — pull-top-ads.py insights may be limited."
  fi
done

echo
echo "3/4  Checking ad account ${ACCT} is reachable with this token..."
acct_resp="$(curl -s "${GRAPH}/${ACCT}?fields=name,account_status,currency,timezone_name&access_token=${META_ACCESS_TOKEN}")"
if echo "$acct_resp" | grep -q '"error"'; then
  echo "  AD ACCOUNT UNREACHABLE:"
  echo "$acct_resp"
  echo
  echo "  The token is valid but cannot see ${ACCT}. Usual causes: the token"
  echo "  belongs to a user without a role on this account, or the ad account"
  echo "  is not assigned to the app's business."
  fail=1
else
  echo "  OK: $acct_resp"
  # account_status 1 = ACTIVE. Anything else cannot serve ads (cheatsheet §13).
  # The trailing [,}] matters: a bare '"account_status":1' also matches 100
  # (PENDING_CLOSURE) and 101.
  if ! echo "$acct_resp" | grep -q '"account_status":1[,}]'; then
    echo "  WARNING: account_status is not 1 (ACTIVE) — see cheatsheet §13"
    echo "  'Account Status Codes'. Ads may be created but will not deliver."
  fi
fi

echo
echo "4/4  Checking META_PAGE_ID..."
if [[ -z "${META_PAGE_ID:-}" ]]; then
  echo "  SKIPPED: META_PAGE_ID not set — deploy-ad.py then needs --page-id."
else
  page_resp="$(curl -s "${GRAPH}/${META_PAGE_ID}?fields=name&access_token=${META_ACCESS_TOKEN}")"
  if echo "$page_resp" | grep -q '"error"'; then
    echo "  PAGE UNREACHABLE:"
    echo "$page_resp"
    fail=1
  else
    echo "  OK: $page_resp"
  fi
fi

echo
if [[ "$fail" -ne 0 ]]; then
  echo "Meta env is NOT ready — fix the items above before running deploy-ad.py."
  exit 1
fi
echo "Meta env looks good. You can run deploy-ad.py / pull-top-ads.py."
echo
echo "One thing this script cannot verify: your Meta app must be published"
echo "(Live). A development-mode app fails at ad creation with code 100 /"
echo "subcode 1885183, and allowlisting the ad account does not work around it."
echo "See SKILL.md Prerequisites."
