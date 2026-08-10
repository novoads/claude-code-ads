# image-ad-clone evals

Every scenario below is a real failure mode: one this skill or its house sibling actually
produced, or one the flow was reshaped to prevent.

The machine-checkable half of the brand-context contract lives in
`scripts/test-brand-context.sh` (16 cases, spends nothing). What is left here is the half no
script can hold: which deliverable the user actually wanted, and whether the run asked for
things it already knew.

Two of these spend credits (D1, D2). The rest do not.

---

## The deliverable

### D1 — "clone this ad for my product" produces ADS

**Why:** the defect this mode exists to fix. The skill's only deliverable used to be a
parameterized library entry, so a customer who asked for an ad received a `{placeholder}`
block and a single test render against an invented brand. They asked for an ad.

**Check:** attach a static and say "clone this for my product". Confirm three rendered
variants filled with the stored brand, the product pinned to `product.photo` as a reference
image, rendered at the SOURCE's ratio — **and** a library entry written. A run that produces
only a template fails, and so does one that produces only ads.

---

### D2 — the library entry is written in ads mode too, and it costs no extra render

**Why:** the compounding this workflow is built on, and the sanitisation step. Phase 4
reproduces the source *including* its wordmark, registered marks and any real customer
testimonial. Phase 6 is where those die. Skipping the write-out in ads mode does not skip a
nice-to-have — it leaves the competitor's marks alive in the only artifact anyone keeps.

**Check:** after D1, grep the new entry for the competitor's brand name, wordmark, and any
proof number or testimonial from the source. All absent, every BRAND zone a placeholder.
Then count renders: the three variants and the faithful v1 iterations, and **nothing extra
for the template**. A fourth render taken solely to validate the entry fails this.

---

### D3 — "turn this into a template" does NOT render three ads

**Why:** the mirror of D1. Ads mode spends two extra renders; running it for someone who
wanted a library entry charges them for output they did not ask for.

**Check:** say "turn this ad into a reusable template". Confirm template mode: one test
render against an invented brand, no product photo demanded, and no three-variant fill.

---

### D4 — the extra renders are quoted before they are spent, not after

**Why:** ads mode is strictly more expensive than template mode. A mode chosen silently is a
charge chosen silently.

**Check:** in ads mode, confirm the Phase 4 estimate covers the three variants, and that the
announced total is the one from `POST /v1/estimates` in this session rather than a number
from any file.

---

## No reference supplied

### H1 — an attached ad is cloned, and nothing is swept

**Why:** someone who handed over an image has already answered the question a sweep would
ask. Sweeping anyway spends their credits to learn what is on screen.

**Check:** attach an image, ask for a clone. Zero calls to `POST /v1/competitor-ads`, and no
`{"kind":"competitor-ads"}` estimate either.

---

### H2 — no reference means go and find one, with the price stated first

**Why:** the friction this branch exists to remove. The old behaviour was to ask "which ad?"
and stop, which puts the work back on the user at the moment they asked us to do it.

**Check:** say "clone my competitors' ads" with nothing attached and a brand stored. Confirm
the run does NOT ask which ad; states the competitors, the live-estimate total and a one-word
stop in a single line; then acts. **Confirm it is one line and not a menu** — a menu makes the
user classify their own situation, which is the shape this deliberately avoids.

---

### H3 — "stop" costs nothing

**Check:** answer "stop" at H2's line. `POST /v1/estimates` may have run;
`POST /v1/competitor-ads` did not, and nothing rendered.

---

### H4 — an unknown brand is one question, asked before the price

**Why:** a sweep needs something to search for, and quoting a price for a sweep whose target
is unknown quotes a number for work that cannot start.

**Check:** on a checkout with no `brand.name`, run H2. Confirm exactly one short question
("What's your brand or product?"), then the veto line, then the sweep. Two questions before
the first ad fails this.

---

## Brand context — asked once, ever

### B1 — the first run asks for what blocks, and only that

**Why:** the product photo and its one-line description are the gate; neither can be
inferred. Everything else waits until something needs it. A skill that interviews the user
for eight fields up front is a skill nobody finishes.

**Check:** on a checkout with no `MASTER_CONTEXT.md`, ask for a clone in ads mode. Confirm it
asks for the photo and the description, does NOT ask for tone, colours or fonts, and does not
render before it has the photo. Automated half: `./scripts/brand-context.py check
image-ad-clone` exits 2 naming exactly those two.

---

### B2 — the second run asks nothing

**Why:** this is the entire point. The lazy-fill rule has been in `MASTER_CONTEXT.template.md`
since the pack shipped and no skill obeyed it, so the file existed and the interrogation
happened anyway.

**Check:** run B1 to completion, then ask for a second clone. Zero brand questions, and the
run names which stored values it used rather than using them silently. Re-asking anything
answered in B1 fails.

---

### B3 — a partially filled file is topped up, not restarted

**Why:** the realistic state is half-filled. A check that only distinguishes empty from
complete re-asks for answers it already has, which reads as the file not working at all.

**Check:** store tone and colours, leave the product photo empty. Confirm the run asks for the
photo alone and leaves the rest untouched.

---

### B4 — template mode does not ask for a product at all

**Why:** a template is filled with a stand-in brand by design. Demanding a real product photo
to build one blocks a workflow that never needed it.

**Check:** run D3 on a checkout with no stored product. It completes without asking.

---

### B5 — the URL shortcut is offered before the interview, and writes nothing

**Why:** one input instead of seven is the difference between a setup someone finishes and
one they abandon. But a wrong brand fact baked silently into ten ads is worse than an empty
field, so drafting and writing are separate acts.

**Check:** on a first run, confirm the website shortcut is offered alongside the two-field
minimum. Run `from-url` against a real site and confirm **nothing is written** — every value
is printed for confirmation, and image candidates carry the warning that a site hero is
usually a lifestyle shot rather than a packshot.

---

### B6 — a scraped image never satisfies the product gate on its own

**Why:** the failure `from-url` is one step away from causing. A hero image with burned-in
text or a lifestyle crop is not a packshot, and the clone renders the product from whatever
it is given.

**Check:** point `from-url` at a site, take its image candidate, and try to clone. Confirm the
candidate is downloaded and LOOKED AT before use, and that an unsuitable one is rejected
rather than passed to the render because it was the only thing available.

---

## Routing — ten sentences, one skill each

**Why this table exists:** four skills now answer some form of "clone this ad", and the
collision is what let `clone-ad` sit undiscovered while `image-ad-clone`'s description
claimed the phrase outright. Descriptions edited one at a time is how that happened. Edit
this table and all four descriptions in the same pass, or not at all.

**The rule: the source's medium decides, not the wording.** Nothing attached defaults to
statics, because a static sweep returns more usable creatives and a static render costs a
fraction of a video one — and the offer names the video escape in the same line, so the user
picks in one word rather than answering a question.

**Check:** say each sentence in a fresh session. Exactly one skill triggers, and it is this
one. A sentence that fires two skills, or fires none, is a failing row.

| # | The user says | Must resolve to |
|---|---|---|
| 1 | "clone this ad" **+ a .jpg/.png attached** | `image-ad-clone` |
| 2 | "clone this ad" **+ an .mp4 attached** | `clone-ad` |
| 3 | "clone my competitors' ads" **with nothing attached** | `image-ad-clone`, which sweeps statics and names the video escape |
| 4 | "clone my competitors' video ads" | `clone-ad` |
| 5 | "clone this ad for my product" + a still | `image-ad-clone`, ads mode |
| 6 | "turn this ad into a reusable template" + a still | `image-ad-clone`, template mode |
| 7 | "recreate this video for my brand" + a clip | `clone-ad` |
| 8 | "I want to make videos like this" + a clip | `analyze-video` |
| 9 | "what are Arcads running right now" | `spy-competitor-ads` |
| 10 | "clone the hook of this ad" | none in this pack — say so and offer `clone-ad` for the whole ad |

Row 10 is a deliberate hole, not an oversight: hook-only cloning is unpublished here. Saying
"we do not have that, here is the nearest thing" beats silently cloning the whole ad when the
user asked for three seconds of it.
