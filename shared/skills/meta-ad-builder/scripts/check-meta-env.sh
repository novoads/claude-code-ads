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
# What this CANNOT check: whether the Meta app is published (Live). There is no
# Graph endpoint that reports app mode for a user token. A development-mode app
# fails at ad creation with code 100 / subcode 1885183 — see SKILL.md
# Prerequisites.
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

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Add the missing keys to your .env (see .env.example). Required:"
  echo "  META_ACCESS_TOKEN=    META_AD_ACCOUNT_ID="
  echo "Optional: META_PAGE_ID  META_IG_USER_ID  META_PIXEL_ID  META_API_VERSION"
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
