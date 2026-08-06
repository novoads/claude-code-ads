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

## The cloning primitives are split across MCP and REST, and neither surface has both

- **What:** `sourceAssetId` (image edit) exists on `POST /v1/images` but **not** on the MCP
  `generate_image` tool — verified against the live tool schema, 2026-08-06. `analyze_ad`
  runs the other way: it reads an uploaded **image** ad into on-screen text, layout zones and
  casting, and it is **MCP-only** — there is no `/analyses` path in the deployed spec
  (2.12.0). So each surface is missing the other's cloning asset. Decide whether to publish
  `analyze_ad` on `/v1`, add `sourceAssetId` to the MCP tool, both, or neither.
- **Why:** this pack's `image-ad-clone` is REST-based, so its Phase 2 visual analysis is done
  by the agent's own vision — which is parity with the walkthrough this chapter mirrors, and
  therefore not a gap in the demo. But it means the one first-party thing we have that the
  competitor does not (a server-side ad reader returning layout zones) is unreachable from
  the skill that would most benefit. Symmetrically, an MCP-only consumer cannot edit an image
  at all, so the Phase 7 instrument added in this PR has no MCP equivalent.
- **Pros:** closing either half removes an "it depends which door you came in" caveat from
  the docs; `analyze_ad` on `/v1` would let Phase 2 stop being purely client-side.
- **Cons:** `analyze_ad` is unbounded Gemini spend with no plan gate today (see the novoads.ai
  note on MCP-only analyses) — publishing it on `/v1` is a cost-surface decision, not a
  docs one. Adding `sourceAssetId` to MCP is smaller but still a tool-schema change.
- **Depends on / blocked by:** founder call on `analyze_ad` pricing/gating before it can be
  published anywhere.
- **Origin:** image-clone chapter parity analysis, 2026-08-06 (finding #5).

## Two structural holes under `image-ad-clone`: no evals, and no drift guard can reach it

- **What:** (a) `image-ad-clone` ships with **no evals file**, while `clone-ad`, `music-mix`,
  `broll-overlay` and `ugc-base-and-broll` all have one. (b) It cannot be added to the CI
  drift guard at all. `novoads.ai`'s `scripts/check-public-skill-drift.mjs` hash-compares
  each entry in `.claude/public-skills.json` against a **canonical copy in that repo**, and
  today that manifest lists only the two Pixar skills. Census of published skills with **no
  canonical copy in novoads.ai**, and therefore outside the guard by construction:
  **`novoads-api`, `image-ad-clone`, `claymation-ad`**.
- **Why:** the guard exists because the shipped public Pixar skill kept instructing a
  `styleFamily` parameter deleted from the API a month earlier — the API moved and only one
  copy followed. The three skills above are exposed to exactly that failure with nothing
  watching, and this PR is an instance of it: `guide.md` asserted "there is no image-edit
  path on this API" for two deployed spec releases after `sourceAssetId` shipped, and a
  sibling PR had already corrected the same sentence in four other files without reaching
  this one — and a sweep run while writing this PR found **three more** live copies of the
  same falsehood (`claymation-ad/prompting/storyboard-gpt-image-2.md`, and hard rule 7 in
  BOTH `chatgpt-image-ad` and `nano-banana-image-ad` guides, the first of which contradicted
  a correct statement 149 lines below it in its own file). Eight sites, one API change,
  corrected in three separate passes across three days. The evals gap is the same shape one level up — nothing executable states what a
  correct clone run looks like, so a regression in the workflow is invisible until a run.
- **Pros:** an `EVALS-image-ad-clone.md` gives the workflow a red/green it currently lacks;
  a canonical-copy decision closes the drift hole for three skills at once.
- **Cons:** the guard is one-way from a local canonical, so covering these three means either
  creating canonical copies in novoads.ai for skills that live only here (duplication with a
  real sync cost) or teaching the guard a "public-only, verify against the deployed spec
  instead" mode — a design decision, not a config edit.
- **Depends on / blocked by:** the canonical-vs-public-only design call. The evals file does
  not depend on it and can land first.
- **Origin:** image-clone chapter parity analysis, 2026-08-06 (findings #6 and #7).
