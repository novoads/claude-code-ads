# TODOS

## Pack-wide freshness sweep of dated spec-version claims

- **What:** A documented procedure (or small script) that greps every dated "verified live
  against spec X.Y.Z" stamp across `skills/` and `shared/skills/`, re-verifies each claim
  against the live `https://api.novoads.ai/v1/openapi.json`, and re-dates or fixes it.
- **Why:** clone-ad cited "spec 2.0.0" while the deployed spec was 2.7.0 — the claims held
  only because nothing relevant changed in seven releases. The last batch of stale stamps
  (the 12-site `resolution` falsehood) was caught by a hand audit, not by procedure.
- **Pros:** the next resolution-style drift is caught by a grep + one curl instead of a
  debugging session or a customer report; keeps the pack's probe-backed credibility real.
- **Cons:** one more standing doc/script to maintain; the sweep itself needs re-running on
  each API release to be worth anything.
- **Context:** see `~/Developer/novoads-claude/fork-parity-audit.md` §D1 for the 12-site
  falsehood this prevents, and `VIDEO-CLONE-CHAPTER-PLAN.md` F3 for the stale-stamp shape.
  The deployed spec is world-readable without auth (verified 2026-08-04), so the sweep needs
  no credentials.
- **Depends on / blocked by:** nothing — read-only against the deployed spec.
- **Origin:** /plan-eng-review of VIDEO-CLONE-CHAPTER-PLAN.md, 2026-08-04 (decision D6).
