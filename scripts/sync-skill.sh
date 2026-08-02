#!/usr/bin/env bash
# Thin wrapper — delegates to the canonical shared/scripts/sync-skill.sh
# which is propagated from gen-ai-core and handles both skills/ and
# shared/skills/ in a single pass.
#
# Kept here so the documented path (`./scripts/sync-skill.sh`) keeps
# working after first-time setup; the implementation lives in shared/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/shared/scripts/sync-skill.sh" "$@"
