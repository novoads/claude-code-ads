#!/usr/bin/env bash
# Ratchet: this repo may tell an agent what to DO. It may not tell an agent what
# to HIDE from the user.
#
# The failure, in full, because it is counter-intuitive enough that someone will
# otherwise re-add the wording in good faith. Until 2026-08-08 the setup close
# opened by telling the agent the block was its "ENTIRE closing message,
# verbatim", and that a connected Novoads MCP connector "must not be mentioned".
# The intent was reasonable: setup asks a human for one thing, and a menu of key
# paths is how people end up with no key. The result was the opposite of the
# intent. A setup session read those lines, correctly recognised an instruction
# to withhold information from the user, and opened its reply by reporting the
# attempt — so the connector got a paragraph of the user's attention instead of
# none, and the close itself was framed as marketing copy the agent had declined
# to read out.
#
# That is not a quirk of one model. An instruction to conceal something from the
# person being served is the one category of instruction a well-aligned assistant
# is expected to surface rather than follow, so the more forcefully a repo asks
# for silence, the louder the disclosure. Brevity has to be requested as brevity.
#
# What replaced it: state the preference, state the reason, and say plainly that
# nothing here is confidential. Same close, no disclosure.
#
# Scope note: this guards PHRASING, not policy. "Never call mcp__novoads__*
# tools" is a routing rule about which surface the skills run on, it is enforced
# by scripts/check-no-mcp.sh, and it is deliberately NOT matched here — telling
# an agent which API to call is not telling it what to hide.
#
# Usage: ./scripts/check-no-gag.sh   (exit 0 clean, 1 on any un-allowlisted hit)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Banned phrasings ─────────────────────────────────────────────────────────
# Case-insensitive, matched as substrings. Deliberately narrow and literal: the
# thing being caught is prose drifting back one sentence at a time, and a clever
# matcher would either miss the next phrasing or drown the repo in false hits.
#
# "verbatim" alone is NOT here and must not be added. The prompt libraries use it
# ~90 times for the thing it actually means — repeat the actor tag verbatim,
# paste the style lock verbatim — and banning it would delete real craft to catch
# a phrase that always appears with other words attached.
BANNED=(
  'must not be mentioned'
  'must never be mentioned'
  'should not be mentioned'
  'do not mention'
  "don't mention"
  'never mention it'
  'do not tell the user'
  "don't tell the user"
  'without telling the user'
  'do not reveal'
  'do not disclose'
  'entire closing message'
  'verbatim as your entire'
  'as your entire response'
)

# ── Allowlist ────────────────────────────────────────────────────────────────
# Each entry: <path-glob>::<extended-regex the line must match>
# Only for lines that DOCUMENT the ban. A rule has to be able to name the thing
# it forbids, the same exemption check-no-mcp.sh carries for the same reason.
ALLOW=(
  # The three files that explain why this guard exists.
  'AGENTS\.md::This section used to end with "must not be mentioned", and with the close described as the'
  'AGENTS\.md::agent.s "ENTIRE closing message, verbatim"\. Both were counterproductive'
  'scripts/setup\.sh::its "ENTIRE closing message, verbatim" and that a connected connector "must not'
  'scripts/check-no-mcp\.sh::.*must not be mentioned.*'

  # This script, and the workflow that runs it.
  #
  # LINE patterns, not a whole-file wildcard. A wildcard here exempted the guard
  # from itself, and this is the one file an author editing guards is most likely
  # to be sitting in — the same hole the sibling guard had for this file, closed
  # in the same review. The three shapes below are the only ones that legitimately
  # carry a banned phrase: the BANNED array literals, the ALLOW array literals,
  # and the header prose that quotes the 2026-08-08 wording it replaced.
  'scripts/check-no-gag\.sh::^  .(must not be mentioned|must never be mentioned|should not be mentioned|do not mention|don.t mention|never mention it|do not tell the user|don.t tell the user|without telling the user|do not reveal|do not disclose|entire closing message|verbatim as your entire|as your entire response).$'
  'scripts/check-no-gag\.sh::^  .[A-Za-z][A-Za-z0-9_/-]*(\\\.[a-z]+)?(\\\.[a-z]+)?::'
  'scripts/check-no-gag\.sh::^# (opened by telling the agent|verbatim", and that a connected)'
  '\.github/workflows/guard\.yml::.*'
)

# ── Scan ─────────────────────────────────────────────────────────────────────
violations=0
allowed=0

# One grep per phrase rather than one alternation, so the failure message can
# name the phrase that matched instead of making the reader diff it out.
for phrase in "${BANNED[@]}"; do
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"

    ok=0
    for entry in "${ALLOW[@]}"; do
      glob="${entry%%::*}"
      pattern="${entry#*::}"
      if [[ "$glob" == "*" ]] || [[ "$file" =~ ^${glob}$ ]]; then
        if [[ "$content" =~ $pattern ]]; then
          ok=1
          break
        fi
      fi
    done

    if [[ $ok -eq 1 ]]; then
      allowed=$(( allowed + 1 ))
    else
      if [[ $violations -eq 0 ]]; then
        echo "FAIL: an instruction telling the agent what to hide from the user." >&2
        echo "" >&2
        echo "This repo may say what an agent should DO, not what it should HIDE." >&2
        echo "Asking for silence backfires: an aligned agent surfaces the request" >&2
        echo "instead of complying, so the topic gets MORE of the user's attention" >&2
        echo "than saying nothing would have. See the header of this script for the" >&2
        echo "2026-08-08 case." >&2
        echo "" >&2
        echo "Rewrite it as a preference with its reason, e.g. 'keep the close short," >&2
        echo "the user owes exactly one thing here' — and say outright that nothing" >&2
        echo "in this repo is confidential." >&2
        echo "" >&2
      fi
      echo "  $file:$lineno: [$phrase] $content" >&2
      violations=$(( violations + 1 ))
    fi
  done < <(git grep -in -e "$phrase" -- . || true)
done

if [[ $violations -gt 0 ]]; then
  echo "" >&2
  echo "$violations un-allowlisted gag instruction(s); $allowed allowlisted." >&2
  exit 1
fi

echo "OK: no gag instructions ($allowed allowlisted)."
