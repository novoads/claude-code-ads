---
name: image-ad-clone
description: >-
  Clones a STATIC IMAGE ad into a reusable prompt TEMPLATE. The deliverable is a
  parameterized library entry — placeholders, variables and per-model notes, appended to
  the shared image-ad library — not a finished ad. Reads the frame structurally,
  round-trips the draft prompt through gpt-image-2, nano-banana-pro or reve-2.1 until it
  reproduces, then replaces every brand-specific with a {placeholder} and proves the
  generalized version still renders on a different brand. Use when asked to "clone this ad
  as a template", "reverse engineer this ad", "turn this ad into a prompt", "extract a
  template", "make this ad reusable", "add this to my prompt library", or "study this ad
  and make a template". Two neighbours it is NOT: generating a finished image ad from a
  brief or an existing template is chatgpt-image-ad or nano-banana-image-ad, and cloning a
  VIDEO ad is clone-ad. If the source is a still and the user wants one finished picture
  rather than something reusable, they do not want this skill.
---

# image-ad-clone

Take an existing image ad and turn it into a reusable, parameterizable prompt template that
gets appended to the shared **40-template image-ad library**. The template is validated by
round-tripping it through a Novoads image model and comparing against the original.

## If the `shared/` files are not on disk

Then this skill was installed on its own from skills.sh, and the library it is supposed to append
to came with nothing. Fetch each missing file from
`https://raw.githubusercontent.com/novoads/claude-code-ads/main/<path>`, where `<path>` is one of
`shared/skills/image-ad-clone/prompting/guide.md`,
`shared/skills/image-ad-prompting/prompting/template-format.md`,
`shared/skills/image-ad-prompting/prompting/prompt-library.md` and
`shared/skills/image-ad-prompting/OVERVIEW.md`. Cloning the whole pack with
`git clone https://github.com/novoads/claude-code-ads.git` is the better move here, because the
deliverable is an entry written back into `prompt-library.md` and a raw fetch gives you nowhere to
save it. That install has no `scripts/check-novoads-env.sh` either, so set `NOVOADS_API_KEY` in the
environment yourself and let the first call report the key.

## Read order

Paths below are **from the repo root**. This skill is copied into `.claude/skills/` and
`.cursor/skills/` by `sync-skill.sh`, so a relative link out of it would break in those copies.

1. **This file** — model choice, the validator, what's fixed at the repo layer.
2. `shared/skills/image-ad-clone/prompting/guide.md` — the full 10-phase workflow (visual analysis → draft prompt → generate-with-reference → iterate → generalize → test → cross-model validate → document → save).
3. `shared/skills/image-ad-prompting/prompting/template-format.md` — entry skeleton.
4. `shared/skills/image-ad-prompting/prompting/prompt-library.md` — destination for the new entry. 40 validated templates already there; new entries go at T40+.
5. `shared/skills/image-ad-prompting/OVERVIEW.md` — ecosystem context.

## Hard rules

Inherits all 8 hard rules from the shared guide (strip platform chrome, validate by generating,
test the generalized version, no brand-specific text in the final template, a v1 clone is never
publishable, never silently overwrite, document model notes, price the whole run up front). Plus:

8. **Model is one of `gpt-image-2`, `nano-banana-pro`, `reve-2.1`.** Those are the three image models on this API. The choice happens in Phase 1 once the user picks (or the agent auto-detects).
9. **Never write a `Model notes` claim for a model you didn't actually run.** Mark it `untested`. An invented note is worse than a missing one.

10. **A v1 faithful clone never leaves this workflow.** Phase 4 reproduces the source *including* its wordmark, registered marks and any real customer testimonial — that is what makes it a structural check, and it makes it unpublishable. It is evidence, never creative: not into an ad account, a deck, a post or a case study. **Phase 6 is where brand-specifics and real testimonials die.** Invent the test fill; never inherit a real person's quoted review.

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
  --prompt "$(cat prompts/<tag>-v1.txt)" \
  --aspect-ratio <ratio> \
  --image-ref <reference.png> \
  --pin-block "<one-line product description>" \
  --out iterations/clone-tmp \
  --env-file .env
```

**`--pin-block` is how the brand pin gets counted.** It wraps your description in the shared
library's standard 346-character guard — front face only, no invented label copy, no
fabricated claims — and measures the result against **the cap of the `--model` you named**
*before* the network, naming the pin block's share if it overflows. Those caps are 32,000 on
`gpt-image-2`, 50,000 on `nano-banana-pro` and 4,000 on `reve-2.1` (deployed spec 2.16.0,
verified 2026-08-08), so an overflow here is almost always a `reve-2.1` run. When it happens,
the script also names the roomier models: switching `--model` is usually the better repair,
because trimming loses clone fidelity the cross-check was meant to test. A clone run
that skips it inherits the failure it exists to prevent: unpinned marks come back invented.

Why a separate script rather than the generators': the two generator skills are **model-locked
by brand contract**, so a production run can't drift models by accident. Cloning has the
opposite requirement — Phase 8 exists to run the same template on a second model. This script
takes `--model`, applies that model's own aspect-ratio grid, and is the only path to
`reve-2.1`, which has no generator skill.

It shares everything else with the generators: the same three always-on safety suffixes, the
same upload flow, each model's own reference cap (`gpt-image-2` 4, `nano-banana-pro` 14,
`reve-2.1` 8), the same local prompt-length check before spending.

### Editing a source (Phase 7's second instrument)

`POST /v1/images` accepts `sourceAssetId` — **`gpt-image-2` only** — which repaints the zones a
prompt names and leaves the rest of the frame alone:

```bash
./skills/image-ad-clone/scripts/validate_image.py \
  --model gpt-image-2 \
  --prompt "$(cat prompts/<tag>-swap.txt)" \
  --source-image original-ad.jpg \
  --out iterations/clone-<date>/T40/test-fill \
  --env-file .env
```

`--source-asset-id` takes an id already uploaded, including one this API generated.

**Use it in Phase 7, not Phase 4.** Measured 2026-08-06 on one source, three renders: given the
full faithful-reproduction prompt an edit came back *worse* than the reference-image arm at the
same price, and given a short brand-swap prompt it held texture, grid, barcode, fine print and
lighting through a wordmark transplant in a single call. It also restyled a headline typeface
nobody asked it to change — pin the type in the swap prompt. Full write-up in the guide's Phase 7.

Two refusals happen locally, before any spend: `--aspect-ratio` alongside a source (an edit's
output tracks the source's shape, and the API 400s the pair), and a source on any model but
`gpt-image-2`. The source also spends one slot of the reference cap, because that is what it
becomes at the provider.

## Dependencies

- `.env` with `NOVOADS_API_KEY` (`novo_` + 64 hex). Verify with `./scripts/check-novoads-env.sh`.
- Optional: `PRODUCT_ID` in `.env`. Omit it and jobs land in your default product; `productId` is organizational only and does not influence what is generated.
- Python 3.12+.

> **REST key required. A Novoads MCP connector is not a substitute.** If
> `NOVOADS_API_KEY` is missing or still the placeholder, stop before any
> generation work and tell the user: "Before continuing, create an API key at
> <https://novoads.ai/dashboard/settings?tab=api> and paste it into `.env`."
> That holds even when `mcp__novoads__*` tools are connected and authenticated in
> the session. Never call `mcp__novoads__*` tools from this repo's workflows: they
> are a different surface with different behavior, including the units they quote
> costs in. Repo installs verify with `./scripts/check-novoads-env.sh`; a solo
> install checks `NOVOADS_API_KEY` in the environment.

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

**On a batch, that tally is not the ledger — reconcile against the balance.** Summing
`creditsCharged` by hand across many calls is right per call and wrong in aggregate the moment
one response goes missing (a retry that printed to stdout instead of the log is enough). Read
the `balance` that `POST /v1/estimates` returns **before the first charged call and again after
the last** — the estimate is free, so this costs nothing — and report both numbers: the summed
`creditsCharged` and the balance delta. When they disagree, **the delta is the truth** and your
sum is missing a call; say so rather than reporting the smaller number.

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
3. **Phase 3: Draft v1 prompt** (brand-specifics intact). The three always-on safety suffixes take 1,575 characters off whatever the chosen model's cap is, leaving **30,425 on `gpt-image-2`, 48,425 on `nano-banana-pro`, 2,425 on `reve-2.1`**. On the first two, write the prompt the clone needs and stop thinking about length. On `reve-2.1`, 2,425 is the whole budget on default flags, and a faithful six-panel clone wants more than that. The validator prints the exact number when you overflow.
4. **Phase 4: Generate with reference.** Price the run and get a yes first. Pass `--image-ref <reference>` and the matched ratio. Synchronous; blocks 60–90s.
5. **Phase 5: Compare and iterate.** Refine on the deltas. Cap 4 iterations. Track running credits.
6. **Phase 6: Generalize into placeholders** (`{brand.name}`, `{brand.color_primary}`, etc.).
7. **Phase 7: Test the generalized template** against a DIFFERENT brand. If structure breaks, refine the placeholder set. Optionally cross-check the structure by *editing* the original with `--source-image` and a brand-swap prompt — see the validator section.
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
