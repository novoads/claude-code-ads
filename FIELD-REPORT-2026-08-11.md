# Field report — 2026-08-11 UGC production session

**Status:** findings only. Nothing in `skills/` or `shared/` has been changed. This document is
the work order; the edits it proposes are unmade.

**What produced it:** one real ad-production session against this pack — a UGC launch ad for
this repo itself. 12 renders on `seedance-2.0` and `seedance-2.5`, all 15s / 9:16 / 720p / `en`,
no reference assets (software product, so the `references/`-not-needed route). It surfaced
several things the skill files get wrong, state too narrowly, or don't cover at all.

**The evidence is in Appendix A of this file, not in `logs/`.** `logs/*.jsonl` is gitignored, so
the session log cannot travel with this document — Appendix A carries the run table instead.
Per the repo's own guardrail, **no credit figures are recorded anywhere in this file**; every
pricing statement below is relative, and re-pricing is the reader's job.

## How to use this document

Open a fresh session in this repo and work the findings in the order given at the end. Ground
rules:

- **Verify before you write.** Every pricing or capability claim below must be re-confirmed with
  a live `POST /v1/estimates` or `GET /v1/models` call before it is committed to a file. Do not
  copy this document's claims on faith — that is precisely the failure mode the no-rate-table
  rule exists to prevent, and these findings are already days old by the time you read them.
- **Respect the repo's evidence standard.** Where n is small, say so in the file. Several
  findings here are n=1 to n=3. Write them as observations carrying their sample size, not laws.
- **Do not add a rate table anywhere**, and do not write credit numbers into any file.
- **Nothing here needs a paid render to verify.** Estimates, `GET /v1/models`, `ffprobe` on any
  existing MP4, and Appendix A cover all of it.
- **Agree file placement before writing** — see the note at the end. Some of this is craft
  doctrine that may belong in `shared/` rather than in the API skill.

---

## 1. HIGH — `skills/novoads-api/SKILL.md` §7 overstates what a transcript proves

The QA doctrine says the transcript is "the only check that hears the brand name" and treats a
clean transcript as a pass. **It is not sufficient, and it failed twice in one session.**

A transcriber normalizes toward contextually plausible words. Given ambiguous audio in the
phrase "a skill pack for ___ Code", it writes "Claude Code" whether the render said that or
not. Both defects below were caught by the *user's ear* on a render whose transcript read clean:

- Renders `d-swing-take2` / `d-swing-take3`: transcript said "Claude Code", user heard it
  mangled. The tell that it was real: the third byte-identical take, `d-swing-take1`, degraded
  far enough that the transcriber itself gave up and wrote **"Claus code"**. Same prompt, same
  model — so the weak final /d/ was present in all three and only crossed the legibility
  threshold in one.
- Earlier in the same session the user reported hearing the brand as "novoabs" on renders whose
  transcripts all read "novoads".

**Proposed change to §7 step 3:**

- Demote the transcript from verdict to **screening tool**. A transcript that comes back *wrong*
  is conclusive proof of a defect. A transcript that comes back *right* is weak evidence, because
  the transcriber's language model is doing error correction you cannot see.
- Add: when a render contains a brand name, product name or URL, **report the word-level
  timestamp of each fragile term** (from `POST /v1/transcripts` `words[]`) so a human can scrub
  straight to it. Two seconds of human listening beats any amount of transcript reading.
- State the asymmetry plainly: **the human ear is the acceptance test on pronunciation; the
  transcript is the cheap pre-filter.**

## 2. HIGH — `skills/novoads-api/SKILL.md` has no VISUAL QA step for video

§7 checks container, dimensions, audio stream, levels, silence, and transcript. **Every one of
those is audio or container.** Nothing checks whether the picture contains what was asked for.

This bit hard: the session's hero shot was a man swinging a baseball bat into a monitor. All
structural checks passed on all takes. The only way to know whether the bat *made contact*, and
whether the screen was lit before the hit (the before/after that sells the gag), was to extract
frames and look at them. Across 6 swing renders the outcomes ranged from a full impact with
sparks and persistent glass debris, to a screen that stayed blown-out white, to a monitor that
was already dark before the swing.

Note the existing image path already has this — "Image QA (mandatory) … **look at it**". Video
has no equivalent and needs one.

**Proposed addition to §7 — a step 0 or step 4, "Look at the picture":**

```bash
# contact sheet of the first N seconds — costs nothing, takes a second
ffmpeg -v error -y -i ad.mp4 \
  -vf "select='lt(t,3)*not(mod(n,6))',scale=320:-1,tile=4x3" \
  -frames:v 1 /tmp/ad-sheet.png
```

Then actually read the image. Check that the specific action named in the prompt occurs, that
props described as present are present, and that continuity holds across the jump cuts. Tile the
window that contains the action — the first 3s for a hook beat, a different range for a later
one. Say in the file that a video can pass every existing check and still not contain the shot
that was paid for.

## 3. HIGH — the phonetic-spelling rule is scoped to the wrong class of word

SKILL.md gate 1 says to spell **"invented brand names"** phonetically, and gives `Novoads` as
the example. That framing missed two real failures in this session, both on **ordinary, real
words**:

| Term | Rendered as | What it is |
|---|---|---|
| `GitHub` | "GidgePub", "GitHep", "GitHip" | real compound, two words fused |
| `Claude Code` | "Claus code" | real proper noun, final /d/ devoiced |

Neither is invented. The actual risk classes are **(a) compound proper nouns**, where the
internal boundary collapses, and **(b) words whose final consonant carries the meaning**, where
it devoices or shifts place of articulation (`ads` → `abs`, `Claude` → `Claus`).

**Proposed change:** rewrite the trigger from "invented brand names" to something like: *any
proper noun the model may not know, any compound run together, and any word whose final
consonant distinguishes it from a near neighbour.* Keep `Novoads` as an example but add
`GitHub` and `Claude Code` as the cases that prove the wider scope. Note that **`Claude Code`
is a term this pack's own users will say in almost every ad they make**, so it deserves an
explicit line.

## 4. MEDIUM — a third phonetic technique, for monosyllables

The repo documents two fixes: hyphenated syllables (`NO-vo-ads`, en) and an orthographic word
break (`Novo Ads`, es). **Neither fits a one-syllable word with a weak final consonant** — there
are no syllable boundaries to hyphenate and no word to split.

The technique that worked: **respell as an English homophone that forces the consonant.**
`Claude` → `Clawed`. "Clawed" is an ordinary word pronounced identically (/klɔːd/), so a reader
cannot say it wrong, and the /d/ is load-bearing in a way it is not in a proper noun.

Evidence, and please write the limits in as prominently as the technique:

- **n=3, one term, one model (`seedance-2.5`), `en` only.** Before: 3 takes with `Claude Code`,
  one transcribed "Claus code" and the user heard the other two as wrong. After: 3 takes with
  `Clawed Code`, all three transcribed "Claude Code" and none degraded.
- This is **weaker evidence than it looks** — see finding 5. The user's ear confirmed the after
  set; that is the acceptance test, not the transcript.
- Untested on `seedance-2.0`, untested in `es`/`pt`, untested on any other term.
- Same caveat the repo already applies to `NO-vo-ads`: the actor is re-cast between renders, so
  part of any delta is voice-casting luck.

Also worth recording: `GIT-hub` (hyphen technique on a compound) went **2/4** in one round and
**3/3** in the next. It reduced *severity* — unprotected failure was "GidgePub", unrecognisable;
protected failures were "GitHep"/"GitHip", which a listener reads as GitHub in context — but it
did not reliably eliminate the failure.

## 5. MEDIUM — the repo's own A/B evidence standard is underpowered

The `NO-vo-ads` finding is recorded from a single A/B pair (`6329f29a` vs `ff69d118`), and the
`es` finding from another single pair, with an honest "n=1" caveat. **This session shows why
that caveat needs to be stronger.**

Pronunciation on identical payloads is close to a coin flip. `GIT-hub` passed and failed on
`seedance-2.0` in the same round, and passed and failed on `seedance-2.5` in the same round.
With that much variance, **a one-render-per-arm A/B is reading noise.** The existing findings may
still be correct, but they are not established by the evidence attached to them.

**Proposed addition — a short "how to test a prompt fix here" note in SKILL.md or
`shared/references/craft.md`:**

- A single render is a sample, not a result. Do not promote an n=1 A/B to a rule without saying
  so at the point of use.
- For a term that must be right, the correct protocol is **N identical takes, then select** —
  not one take per candidate spelling. Selection beats optimization when the variance between
  renders exceeds the variance between prompts.
- Say plainly that N identical takes is the *documented* way to buy reliability on a fragile
  term, and that it costs N × the render.

## 6. MEDIUM — two pricing/capability claims in SKILL.md are contradicted by live calls

**Re-verify both with live `POST /v1/estimates` calls before editing.** As measured 2026-08-11:

- SKILL.md says of `seedance-2.5`: *"at the same length it is dearer than `seedance-2.0`"*.
  At **15s / 720p** the two models quoted **the same number**, on four separate estimate calls
  across two different prompts. The claim may hold at other lengths, but it is stated
  unconditionally and did not hold at the cell most ads in this pack actually use. Consider
  naming the lengths where it holds, or dropping the comparison and letting the estimate speak.
- SKILL.md says of `seedance-2.5`: *"nobody has timed one — quote its wait as unknown."*
  There are now **8 timings** (Appendix A): 134, 162, 163, 166, 227, 244, 387, 402s. Alongside
  `seedance-2.0`'s 4 from the same session (166, 174, 215, 379s), **2.5 was not slower — its
  fastest was the fastest render of the session.** Worth replacing "unknown" with a measured
  range and its n, keeping the range-not-a-promise framing the file already uses for 2.0.

## 7. MEDIUM — undocumented: `seedance-2.5` renders at roughly double the bitrate

At identical settings (15s, 9:16, 720p) measured with `ffprobe`:

| Model | Video bitrate | File size |
|---|---|---|
| `seedance-2.0` | ~2.9–3.5 Mbps | 5.5–6.6 MB |
| `seedance-2.5` | ~7.4 Mbps | 13–15 MB |

This is a real selection criterion that appears nowhere in the decision tree: **fast motion with
fine detail — debris, shards, splashes, particles — is exactly where low bitrate mushes.** Given
finding 6 (same price at 15s), "high-motion shot" becomes a positive reason to choose 2.5 at
equal length, which the current decision tree has no row for.

## 8. LOW — `seedance-2.5` leading silence runs ~0.5s longer than `2.0`

Two byte-identical prompt pairs, differing only in model:

| Prompt | 2.0 first word | 2.5 first word |
|---|---|---|
| marketer + coffee | 0.579s | 1.019s |
| dev + bat aftermath | 0.819s | 1.319s |

Consistent +0.44s and +0.50s. n=2 pairs. Worth a line in the 2.5 section: it buys bitrate and
costs hook latency, which matters on a 15s vertical ad and matters not at all on a longer one.

## 9. LOW — an action beat in beat 1 costs ~2s of speech start

Not currently anywhere in `seedance-2-ugc-v2.md`. Measured first-word times across the session:

- Talking-head opener (no action): **0.16s – 0.82s**
- Coffee pour concurrent with the line: **~0.58s** (cheap — the action is small and continuous)
- Baseball-bat swing in beat 1: **1.60s, 2.04s, 2.18s, 2.20s, 2.22s, 2.52s** (n=6)

So a large physical action in the hook beat delays the first word by roughly 1.5–2s, about 15%
of a 15s ad. **That is not automatically a defect** — when the action *is* the hook, the visual
carries the opening and the words do not need to. But v2's checklist currently pushes hard for
speech filling the runtime without noting this trade. Suggest a line: *a physical hook beat
spends ~2s of speech time to buy attention; budget the script for it, and do not also try to
fill 15s with 40 words.*

## 10. LOW — add `"bottle"` to the `label_without_hold` false-positive table

SKILL.md gate 2 documents `"screen"` as a false positive. Add the one this session hit first:
the rule fired on **`"bottle"` matched inside "a water bottle"** listed as ordinary desk clutter
in the setting layer — background dressing, not the advertised product, and the ad had no
printed label anywhere. Same substring-matcher limitation, different noun. Worth adding because
the setting layer of the UGC formula actively encourages naming clutter objects, so this class
of false positive is structurally likely in exactly this workflow.

---

## Suggested order of work

1. Findings **1 and 2** first — they are the ones where the current file will let a defective
   ad ship while reporting a pass.
2. Finding **3**, then **4** — same section of gate 1, edit together.
3. Findings **6, 7, 8** — all in the `seedance-2.5` material, edit together, **re-verify pricing
   live first**.
4. Findings **5, 9, 10** — smaller notes.

Read `skills/novoads-api/SKILL.md`, `skills/novoads-api/reference.md`,
`skills/novoads-api/prompting/prompt-library/seedance-2-ugc-v2.md` and
`shared/references/craft.md` before editing, and say which file each finding belongs in before
writing — some of this is craft doctrine that may belong in `shared/` rather than in the API
skill, and the placement is worth agreeing first.

---

## Appendix A — the run table

Every render from the session. `logs/*.jsonl` is gitignored, so this is the portable copy.
**Credit figures are deliberately omitted** per the repo guardrail; re-price with
`POST /v1/estimates` at call time.

All rows: 15s, `9:16`, `720p`, `en`, no reference assets, `POST /v1/videos`.

| variant | model | prompt words | elapsed | QA outcome |
|---|---|---:|---:|---|
| ugc-a-dev | seedance-2.0 | 397 | 174s | pass |
| ugc-b-marketer | seedance-2.0 | 390 | 379s | defect: GitHub → "GidgePub" @12.06s |
| b2-marketer-coffee-20 | seedance-2.0 | 419 | 166s | pass: GitHub clean |
| b3-marketer-coffee-25 | seedance-2.5 | 419 | 166s | defect: GitHub → "GitHep" |
| c2-dev-bat-20 | seedance-2.0 | 423 | 215s | defect: GitHub → "GitHip" |
| c3-dev-bat-25 | seedance-2.5 | 423 | 134s | pass: GitHub clean |
| d-swing-take1 | seedance-2.5 | 426 | 162s | impact OK; defect: Claude Code → "Claus code" |
| d-swing-take2 | seedance-2.5 | 426 | 227s | pass: impact OK, key terms clean |
| d-swing-take3 | seedance-2.5 | 426 | 402s | pass: full impact + debris, key terms clean |
| e-swing-clawed-take1 | seedance-2.5 | 426 | 387s | audio clean; weak visual: monitor dark from frame 1 |
| e-swing-clawed-take2 | seedance-2.5 | 426 | 163s | audio clean; impact OK but screen stays blown-white |
| e-swing-clawed-take3 | seedance-2.5 | 426 | 244s | **winner**: best impact + debris, all key terms clean |

**Groups of byte-identical prompts** (this is what makes the variance claims in findings 4 and 5
readable): `b2`/`b3` differ only by model. `c2`/`c3` differ only by model. `d-swing-take1/2/3`
are three identical payloads. `e-swing-clawed-take1/2/3` are three identical payloads, and
differ from the `d-` group by exactly one token (`Claude Code` → `Clawed Code`).

### A.2 — the script under test

The fragile terms are the point; the rest is context.

```
1. [HOOK]    "I'm done editing ads by hand."                              (over the bat impact)
2. [SHOW]    "I open sourced what I use instead — a skill pack for Clawed Code."
3. [DEMO]    "This video? Made with it. One prompt."
4. [VERDICT] "Free on GIT-hub under NO-vo-adds. Go take it."
```

Three protected terms in one 35-word script: a compound proper noun (`GIT-hub`), a
monosyllable with a weak final consonant (`Clawed`), and an invented brand
(`NO-vo-adds`). Findings 3 and 4 come out of watching which of the three techniques held.

### A.3 — first-word timings (source for findings 8 and 9)

From `POST /v1/transcripts` `words[0].start`:

| shape | model | first word |
|---|---|---:|
| talking head, no action | 2.0 | 0.159s, 0.399s |
| coffee pour under the line | 2.0 | 0.579s |
| coffee pour under the line | 2.5 | 1.019s |
| bat aftermath (static prop) | 2.0 | 0.819s |
| bat aftermath (static prop) | 2.5 | 1.319s |
| bat swing (full action) | 2.5 | 1.599s, 2.039s, 2.179s, 2.200s, 2.220s, 2.519s |
