# TODOS

## Video QA has no step that looks at the picture

- **What:** Add a visual check to `skills/novoads-api/SKILL.md` §7 — an ffmpeg contact sheet of
  the beat that carries the action, read before the video is handed over. The image path already
  mandates "look at it"; video does not.
- **Why:** every check in §7 today is audio or container — duration, dimensions, audio stream,
  levels, silence, transcript. A render can pass all of them and not contain the shot that was
  paid for. Measured: across 6 renders of a "bat swings into a monitor" hook, outcomes ranged
  from a full impact with persistent glass debris, to a screen that stayed lit, to a monitor
  already dark before the swing. All 6 passed every existing check.
- **Pros:** costs nothing and takes a second; catches the one defect class that is invisible to
  every other check in the file; closes an asymmetry with image QA that has no principled reason
  to exist.
- **Cons:** it needs the agent to actually read an image rather than parse a number, so it is a
  weaker gate than the mechanical ones; picking the right time window is a judgement call.
- **Context:** see `FIELD-REPORT-2026-08-11.md` finding 2 for the command and the six-render
  evidence table.
- **Depends on / blocked by:** nothing — ffmpeg only, no credits, no API call.
- **Origin:** UGC production session, 2026-08-11.

## A clean transcript is treated as proof, and it is not

- **What:** Demote the transcript in `skills/novoads-api/SKILL.md` §7 from verdict to screening
  tool, and add a step that reports the word-level timestamp of each fragile term so a human can
  verify by ear.
- **Why:** §7 calls the transcript "the only check that hears the brand name" and treats a clean
  one as a pass. A transcriber normalizes toward contextually plausible words, so it writes the
  term you expected whether the render said it or not. Two defects in one session were caught by
  the user's ear on renders whose transcripts read clean. The tell that they were real: a third
  byte-identical take degraded far enough that the transcriber itself wrote "Claus code".
- **Pros:** stops the pack from reporting a pass on an ad that cannot ship; a timestamp turns
  human verification into a two-second scrub instead of a re-watch.
- **Cons:** the honest version of this rule ends in "a human must listen", which is weaker than
  the current file promises and cannot be automated away.
- **Context:** see `FIELD-REPORT-2026-08-11.md` finding 1.
- **Depends on / blocked by:** nothing.
- **Origin:** UGC production session, 2026-08-11.

## The phonetic-spelling rule names the wrong class of word

- **What:** Rewrite gate 1's trigger in `skills/novoads-api/SKILL.md` from "invented brand names"
  to cover compound proper nouns and words whose final consonant carries the meaning. Add the
  homophone-respelling technique for monosyllables, which neither documented technique fits.
- **Why:** both pronunciation failures in the session were on **real** words, not invented ones:
  `GitHub` → "GidgePub"/"GitHep"/"GitHip" (compound fusing at the internal boundary) and
  `Claude Code` → "Claus code" (final /d/ devoicing). `Claude Code` is a term nearly every user
  of this pack will speak in nearly every ad, and the current rule does not flag it.
- **Pros:** covers the two failures this pack is most likely to hit; the homophone technique
  (`Claude` → `Clawed`) went 3/3 where the unprotected term had failed.
- **Cons:** n=3, one term, one model, `en` only — thinner evidence than the rule it sits beside,
  and it must be written with that caveat rather than as a law.
- **Context:** see `FIELD-REPORT-2026-08-11.md` findings 3 and 4.
- **Depends on / blocked by:** nothing.
- **Origin:** UGC production session, 2026-08-11.

## seedance-2.5's documented price, wait and selection criteria are all stale

- **What:** Re-verify and correct three `seedance-2.5` claims in `skills/novoads-api/SKILL.md`:
  that it is dearer than 2.0 at equal length, that its wait is unmeasured, and the absence of
  any row recommending it for high-motion shots. Add its measured leading-silence penalty.
- **Why:** at 15s/720p the two models quoted the same number on four separate estimate calls
  across two prompts, so the "dearer at the same length" claim did not hold at the cell most ads
  use. There are now 8 timings for 2.5 (134–402s) against 2.0's 4 (166–379s) — 2.5 was not
  slower, and its fastest was the fastest render of the session. Undocumented: 2.5 renders at
  roughly double the bitrate (~7.4 vs ~3 Mbps at 720p), which is a real reason to choose it for
  debris, splash or particle shots, and it costs ~0.5s more leading silence.
- **Pros:** turns "unknown, and probably dearer" into a defensible selection rule; gives the
  decision tree a row it lacks for high-motion work.
- **Cons:** pricing drifts, so the correction needs its own date stamp and will need re-checking;
  the bitrate figure is n=4 and from one resolution.
- **Context:** see `FIELD-REPORT-2026-08-11.md` findings 6, 7 and 8. **Re-price live before
  editing** — do not copy the report's relative claims without confirming them.
- **Depends on / blocked by:** nothing — estimates and `GET /v1/models` are free.
- **Origin:** UGC production session, 2026-08-11.

## Prompt-fix findings rest on n=1 A/Bs, and render variance is larger than that

- **What:** Add a short "how to test a prompt fix here" note — where it lands is an open question,
  `shared/references/craft.md` or SKILL.md gate 1 — stating that a single render is a sample, and
  that the way to buy reliability on a fragile term is N identical takes and select, not one take
  per candidate spelling.
- **Why:** the `NO-vo-ads` and `Novo Ads` findings each rest on a single A/B pair. This session
  measured the same spelling passing and failing across byte-identical renders in the same round
  (`GIT-hub`: 2/4 one round, 3/3 the next). When between-render variance exceeds between-prompt
  variance, a one-render-per-arm A/B is reading noise — including, possibly, the two the repo
  already relies on.
- **Pros:** makes the pack's evidence standard match its own observed variance; gives users a
  documented way to make a must-be-right term reliable.
- **Cons:** N identical takes costs N renders, and saying so out loud makes the pack look more
  expensive; it also weakens two findings currently stated with more confidence than they earned.
- **Context:** see `FIELD-REPORT-2026-08-11.md` finding 5, and Appendix A for the identical-payload
  groups that show the variance.
- **Depends on / blocked by:** nothing.
- **Origin:** UGC production session, 2026-08-11.

## Pack-wide freshness sweep of dated spec-version claims

- **What:** A documented procedure (or small script) that greps every dated "verified live
  against spec X.Y.Z" stamp across `skills/` and `shared/skills/`, re-verifies each claim
  against the live `https://api.novoads.ai/v1/openapi.json`, and re-dates or fixes it.
- **Why:** clone-video-ad cited "spec 2.0.0" while the deployed spec was 2.7.0 — the claims held
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

## ~~The cloning primitives are split, and neither surface has both~~ CLOSED 2026-08-08

Both halves of this are gone. Server-side ad analysis shipped as **`POST /v1/analyses`** in
deployed spec `2.19.0` (flat 1 credit, synchronous, priced with `{"kind":"analysis"}`), so
the reader that returns layout zones is now reachable from the same key everything else in
this pack uses, and the entry's central claim ("there is no `/analyses` path in the deployed
spec") is false as of that release. The other half stopped being a question when the repo
went single-path: this pack has exactly one executable surface, so a second surface's tool
schema is not its problem. `clone-image-ad` Phase 2 can now offer `/analyses` as a priced
alternative to its own vision pass, the way `clone-video-ad` step 3 and `analyze-video` do.

- **Left over:** wire `/analyses` into `clone-image-ad` Phase 2 as the same offer-with-a-price
  the two video skills carry. Small, and blocked on nothing.
- **Origin:** image-clone chapter parity analysis, 2026-08-06 (finding #5). Closed by the
  REST-only pass, 2026-08-08.

## Two structural holes under `clone-image-ad`: no evals, and no drift guard can reach it

- **What:** (a) `clone-image-ad` ships with **no evals file**, while `clone-video-ad`, `music-mix`,
  `broll-overlay` and `ugc-base-and-broll` all have one. (b) It cannot be added to the CI
  drift guard at all. `novoads.ai`'s `scripts/check-public-skill-drift.mjs` hash-compares
  each entry in `.claude/public-skills.json` against a **canonical copy in that repo**, and
  today that manifest lists only the two Pixar skills. Census of published skills with **no
  canonical copy in novoads.ai**, and therefore outside the guard by construction:
  **`novoads-api`, `clone-image-ad`, `claymation-ad`**.
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
- **Pros:** an `EVALS-clone-image-ad.md` gives the workflow a red/green it currently lacks;
  a canonical-copy decision closes the drift hole for three skills at once.
- **Cons:** the guard is one-way from a local canonical, so covering these three means either
  creating canonical copies in novoads.ai for skills that live only here (duplication with a
  real sync cost) or teaching the guard a "public-only, verify against the deployed spec
  instead" mode — a design decision, not a config edit.
- **Depends on / blocked by:** the canonical-vs-public-only design call. The evals file does
  not depend on it and can land first.
- **Origin:** image-clone chapter parity analysis, 2026-08-06 (findings #6 and #7).
