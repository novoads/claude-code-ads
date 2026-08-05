# novoads-pixar-ad evals

Every scenario is a real failure mode, either from the renders behind
`references/seedance-prompt-rules.md` or from the review that produced this skill.

The machine-checkable half runs in CI as
`lib/generation/__tests__/pixar-skill-prompts.test.ts`, and spends no credits — it runs the
worked prompts from this skill against the same `validatePrompt` the server calls. That
test is the seam between this skill and the prompt rules; without it the two were designed
together and verified separately.

The rest are human checks against a real render. Run them before publishing a new version.

---

> **The style family is not something this skill sends.** `styleFamily` was deleted from
> the whole API in spec `2.0.0`, along with the blocking prompt rules it scoped. It
> survives only as a parameter of the internal rule engine, which the three automated
> evals below drive directly. Nothing a reader of this skill can call takes it.

### E1 — the worked prompt survives the rules under the stylized family

**Why:** the whole skill is prompt text that a stranger's Claude feeds to our rule engine —
today through `estimate_cost`, which reports every hit as advice. If a doctrine paragraph
here produces a prompt that trips `chained_motion`, nobody finds out from a TypeScript
test; they find out reading a wall of warnings on a prompt this file told them to write.

**Check:** the SKILL.md worked example validates with zero errors under the `pixar` family.
Automated.

---

### E2 — the same shapes DO trip the rules under the `ugc` default

**Why:** the lint `estimate_cost` runs is the `ugc` one. The worked prompt does NOT trip it
— measured, zero warnings — so it is the wrong probe for this mechanism, and Gate 2's claim
that a disciplined prompt scores clean rests on that measurement. What these four pin is
the other half of the same sentence: the shortcuts this genre reaches for are exactly what
does fire, so a reader who sees one knows they drifted from this file.

**Check:** four shapes this genre genuinely produces — a terse narrator line, a timecoded
table, the word "cinematic", two beats joined by "then" — each error under the default
family and each pass under `pixar`. Automated.

---

### E3 — a silent render still errors under the stylized family

**Why:** scoping was never an escape hatch. `no_spoken_line` is universal because a silent
actor is a wasted render in any style, and it became an error only after it fired *after*
42 credits were already spent. It refuses nothing now, but it is still the one warning to
take every time.

**Check:** a stylized prompt with no quoted line and no silent/b-roll statement errors.
Automated.

---

### E3b — a timed-out image is recovered, not re-generated

**Why:** measured in prod 2026-07-29 — two `generate_image` calls took 74s and 66s against
a client that gave up around 60. Both succeeded, both were charged, neither result reached
the caller. Recovering them took an SSH into prod. The failure is not the timeout, it is
that a caller who times out cannot name the work it paid for.

**Check:** human. Force or wait for a timeout on a still, then call `list_generations` and
confirm the job is there with an `outputUrl`. Confirm the skill did NOT generate again.

---

### E4 — the still gate actually stops

**Why:** the gate is the reason this skill is survivable on a trial balance. Six
centi-credits to learn the direction is wrong, versus seventy-six. A skill that renders the
character sheet and keeps going has removed the only cheap decision point in the flow.

**Check:** human. Run the skill end to end and confirm it stops after the key frame and
waits. Reviewer says "no, warmer" and confirms nothing was rendered.

---

### E5 — Doctrine D does not grow a face

**Why:** the constraint is the whole pitch. Every expressive beat is supposed to double as
a real feature demo, and the moment the product has eyes it is a mascot rather than a
demonstration.

**Check:** human. Render a Doctrine D product and confirm no eyes, mouth, eyebrows, limbs
or hopping — only movements the real product makes.

---

### E6 — the low point lands

**Why:** it is the two seconds the ad lives on, and it is the first thing to go when the
word budget is tight. QC lists it first for that reason.

**Check:** human. Watch 0:06–0:08 with the sound off. If the emotional state is not legible
on the face (or the mechanism), the render failed regardless of how good the rest looks.

---

### E7 — the cost announcement matches what was actually spent

**Why:** the skill announces a number before spending. If that number is wrong the
announcement is worse than none, because the operator stopped checking.

**Check:** human. Compare the `estimate_cost` figure with the balance delta after a full
run. They should differ by zero.

---

### E8 — the no-retry warning fires on a thin balance

**Why:** one run is 76 of a 100-credit trial grant. A trial user gets exactly one render and
no retry, and the skill is supposed to say so *before* firing rather than let them discover
it.

**Check:** human, on a trial account. Confirm the skill says the balance covers one render
and not a retry.

---

### E9 — no invented brands

**Why:** house rule, and the failure is subtle: a blank-label product looks like a
deliberate style choice rather than a mistake, so it ships.

**Check:** human. The rendered product carries the real brand from the uploaded photo, not
a plausible-looking invention and not a blank label.
