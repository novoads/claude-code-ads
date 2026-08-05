---
name: image-ad-clone
description: Use when the user wants to reverse-engineer an existing image ad into a reusable prompt template. Validates via the Novoads API — picks gpt-image-2, nano-banana-pro, or reve-2.1 at Phase 1. Triggers on "clone this ad as a template", "reverse engineer this ad", "turn this ad into a prompt", "extract a template", "make this ad reusable", "add to my prompt library", "study this ad and make a template". Input is an EXISTING ad image; does NOT trigger for fresh generation (use chatgpt-image-ad or nano-banana-image-ad).
---

# image-ad-clone

Take an existing image ad and turn it into a reusable, parameterizable prompt template that
gets appended to the shared **37-template image-ad library**. The template is validated by
round-tripping it through a Novoads image model and comparing against the original.

## Read order

Paths below are **from the repo root**. This skill is copied into `.claude/skills/` and
`.cursor/skills/` by `sync-skill.sh`, so a relative link out of it would break in those copies.

1. **This file** — model choice, the validator, what's fixed at the repo layer.
2. `shared/skills/image-ad-clone/prompting/guide.md` — the full 10-phase workflow (visual analysis → draft prompt → generate-with-reference → iterate → generalize → test → cross-model validate → document → save).
3. `shared/skills/image-ad-prompting/prompting/template-format.md` — entry skeleton.
4. `shared/skills/image-ad-prompting/prompting/prompt-library.md` — destination for the new entry. 37 validated templates already there; new entries go at T40+.
5. `shared/skills/image-ad-prompting/OVERVIEW.md` — ecosystem context.

## Hard rules

Inherits all 7 hard rules from the shared guide (strip platform chrome, validate by generating,
test the generalized version, no brand-specific text in the final template, never silently
overwrite, document model notes, price the whole run up front). Plus:

8. **Model is one of `gpt-image-2`, `nano-banana-pro`, `reve-2.1`.** Those are the three image models on this API. The choice happens in Phase 1 once the user picks (or the agent auto-detects).
9. **Never write a `Model notes` claim for a model you didn't actually run.** Mark it `untested`. An invented note is worse than a missing one.

## Picking the model in Phase 1

Pick by what the reference ad is showing — most templates fall into one clear bucket.

**Use `gpt-image-2` when the reference is:**
- Typography-heavy / UI mimicry (Apple Notes lists, fake Google search, fake Slack threads, ChatGPT-conversation ads, iMessage screenshots, comparison tables, fake AirDrop dialogs, Hinge-style cards, calendar UI, weather forecast UI, magazine masthead)
- Brutalist / editorial typography heros (huge type makes the joke)
- Dense small text inside UI elements

**Use `nano-banana-pro` when the reference is:**
- Photoreal handheld objects (whiteboards, napkins, sticky notes, letter boards, scratch-off tickets)
- Aspirational lifestyle photography (sunset, kitchen at golden hour, OOH / transit)
- Multi-image reference blending (logo + product + style + character in one composition)
- Clay / claymation / Pixar-adjacent textures
- Anything at `3:2`, `3:4`, `4:3` or `5:4` — those ratios do not exist on `gpt-image-2`

**Use `reve-2.1` when:**
- The template rendered wrong on both of the above and you want a genuinely different interpretation rather than another tweak
- The user asks for it, or wants a third look before committing a template to the library

It is a deliberate choice, not a fallback tier, and it is the most expensive of the three per
image — so name it in the estimate when you use it.

**If the reference straddles buckets** (e.g. a UGC-style photo with rendered text overlays),
clone once and cross-validate in Phase 8, then ship the template with `Model notes` saying
which renders cleaner.

If the user explicitly names a model, honor that.

## The validator

This skill has its own caller: `skills/image-ad-clone/scripts/validate_image.py`.

```bash
./skills/image-ad-clone/scripts/validate_image.py \
  --model <gpt-image-2|nano-banana-pro|reve-2.1> \
  --prompt "$(cat /tmp/v1.prompt)" \
  --aspect-ratio <ratio> \
  --image-ref <reference.png> \
  --out iterations/clone-tmp \
  --env-file .env
```

Why a separate script rather than the generators': the two generator skills are **model-locked
by brand contract**, so a production run can't drift models by accident. Cloning has the
opposite requirement — Phase 8 exists to run the same template on a second model. This script
takes `--model`, applies that model's own aspect-ratio grid, and is the only path to
`reve-2.1`, which has no generator skill.

It shares everything else with the generators: the same three always-on safety suffixes, the
same upload flow, each model's own reference cap (`gpt-image-2` 4, `nano-banana-pro` 14,
`reve-2.1` 8), the same local prompt-length check before spending.

## Dependencies

- `.env` with `NOVOADS_API_KEY` (`novo_` + 64 hex). Verify with `./scripts/check-novoads-env.sh`.
- Optional: `PRODUCT_ID` in `.env`. Omit it and jobs land in your default product; `productId` is organizational only and does not influence what is generated.
- Python 3.12+.

The generator skills are **not** required to run a clone. They're where the finished template
gets used afterwards.

## Cost — read this before Phase 4

A clone is **six or more charged generations**: Phase 4, up to four Phase 5 iterations, the
Phase 7 test fill, and an optional Phase 8 cross-model run. Every one is billed and there are
no free re-rolls.

Price the run once, up front, with `POST /v1/estimates` (free), and present a **range** — floor
is two calls, ceiling is the full iteration cap. Get one explicit yes covering the run. Do not
ask six separate times, and do not surface the cost only at the end.

The schedules differ by more than 3× across the three models, so **name the model** in the
estimate body — a Phase 8 cross-check on `reve-2.1` is not priced by a `gpt-image-2` estimate.

A **batch** (several references cloned in one conversation) prices the same way, once: one free
estimate per distinct final prompt, presented as one combined range, one yes covering the whole
batch — not a consent per reference.

Report the **actual total** from each response's `creditsCharged` when the run finishes.

## Aspect ratio mapping

| Ratio | `gpt-image-2` | `nano-banana-pro` / `reve-2.1` |
|---|---|---|
| `1:1` `2:3` `4:5` `9:16` `16:9` `21:9` | ✅ | ✅ |
| `3:2` `3:4` `4:3` `5:4` | ❌ | ✅ |

When measuring the original ad's aspect in Phase 2, map to the nearest ratio **the chosen model
accepts**. A `1.91:1` ad maps to `16:9` and post-crops downstream. A `4:3` ad is native on two
of the three and needs a mapping on `gpt-image-2` — which is on its own a reason to route that
template to `nano-banana-pro`.

Document any fallback in the template's `Aspect ratio:` field so future users know they're
rendering at a mapped ratio, not the original.

## Workflow phases (see the shared guide for full detail)

1. **Phase 1: Preflight + model choice.** Reference image resolves; `.env` has `NOVOADS_API_KEY`; validator located. **Ask which model to validate against** (or auto-detect).
2. **Phase 2: Visual analysis.** Describe the reference structurally — aspect ratio, format type, layout, typography, color palette, photography style, every text string verbatim, decorative elements, chrome to strip, and `[BRAND]` vs `[STRUCTURE]` for each.
3. **Phase 3: Draft v1 prompt** (brand-specifics intact). Watch the 4,000-character cap — the safety suffixes add ~1,500.
4. **Phase 4: Generate with reference.** Price the run and get a yes first. Pass `--image-ref <reference>` and the matched ratio. Synchronous; blocks 60–90s.
5. **Phase 5: Compare and iterate.** Refine on the deltas. Cap 4 iterations. Track running credits.
6. **Phase 6: Generalize into placeholders** (`{brand.name}`, `{brand.color_primary}`, etc.).
7. **Phase 7: Test the generalized template** against a DIFFERENT brand. If structure breaks, refine the placeholder set.
8. **Phase 8: Cross-model validation (recommended).** Run the same template on another model. Document real deltas only.
9. **Phase 9: Document the template** per `template-format.md`.
10. **Phase 10: Save and confirm.** Append to the library, print the path, move PNGs to a permanent iteration dir, report total credits charged.

## Iteration directory layout

```
<cwd>/iterations/clone-2026-08-01/
  T40-lifestyle-hero/
    prompt.txt
    v1.png, v2.png, …                # against the source ref (chosen model)
    test-fill-v1.png, …              # Phase 7 generalization test against a different brand
    cross-<other-model>/v1.png       # Phase 8 cross-model validation (optional)
    notes.md
```

## Common `Model notes` patterns to write in Phase 9

```markdown
**Model notes:**
- **gpt-image-2:** {e.g. "clean — strong on UI mimicry and table text"; "tends to add a 4th Slack message — keep the prompt explicit about exactly N"; "small chart axis labels blur — bump font size feel"}
- **nano-banana-pro:** {e.g. "strong — preferred for handheld board photos"; "weak on dense table text — keep rows to 4 max"}
- **reve-2.1:** {e.g. "untested"; "different composition read — wider crop, warmer grade"}
```

If you validated against only one model, say so explicitly:

```markdown
**Model notes:**
- **gpt-image-2:** validated clean (see iteration path)
- **nano-banana-pro:** untested — validate before using on that model
- **reve-2.1:** untested
```

This block is the difference between a portable template and one nobody knows how to use.
Don't skip it, and don't fill it in with guesses.

## Files this skill owns

- `skills/image-ad-clone/SKILL.md` — this file
- `skills/image-ad-clone/scripts/validate_image.py` — the model-aware clone validator

## See also

- `shared/skills/image-ad-clone/prompting/guide.md` — full 10-phase workflow
- `shared/skills/image-ad-prompting/OVERVIEW.md` — ecosystem context
- the **`chatgpt-image-ad`** skill — where a gpt-image-2 template gets used in production
- the **`nano-banana-image-ad`** skill — where a nano-banana-pro template gets used in production
- the **`novoads-api`** skill — the API contract underneath all of this
