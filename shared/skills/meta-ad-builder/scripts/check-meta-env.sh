#!/usr/bin/env bash
# Verify Meta Marketing API credentials for the meta-ad-builder skill.
# Checks that META_ACCESS_TOKEN and META_AD_ACCOUNT_ID are set, then makes one
# live Graph API call to confirm the token is valid and not expired.
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

echo
echo "Validating token against Graph API ${API_VERSION}..."
resp="$(curl -s "https://graph.facebook.com/${API_VERSION}/me?fields=id,name&access_token=${META_ACCESS_TOKEN}")"
if echo "$resp" | grep -q '"error"'; then
  echo "  TOKEN CHECK FAILED:"
  echo "$resp"
  exit 1
fi
echo "  OK: token is valid — $resp"
echo
echo "Meta env looks good. You can run deploy-ad.py / pull-top-ads.py."
