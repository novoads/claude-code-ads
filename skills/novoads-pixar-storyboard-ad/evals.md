# novoads-pixar-storyboard-ad evals

Every scenario is a real failure mode of MULTI-SHOT assembly — the class of
problem the sibling skill's single-call doctrine avoids by construction, and the
price this one pays for an arc.

The machine-checkable half runs in CI as
`lib/generation/__tests__/pixar-storyboard-skill-prompts.test.ts` and spends
nothing. It covers two things: the worked beat prompt against the same rule
engine `estimate_cost` lints with, and **every number this skill quotes**,
derived from the config the server actually reads. That second half is unusual
for a skill eval and it is the important one — a cost table or a concurrency
limit that drifts does not fail loudly, it fails on someone's sixth paid call.

The rest are human checks against a real run. Do them before publishing a new
version.

> **The style family is not something this skill sends.** `styleFamily` was
> deleted from the whole API in spec `2.0.0`, along with the blocking prompt
> rules it scoped. Nothing a reader of this skill can call takes it.

---

### E1 — the worked beat prompt lints clean

**Why:** the skill is prompt text a stranger's Claude feeds to our rule engine.
If the worked example trips `chained_motion` — two actions joined by "then" —
the file is demonstrating the exact mistake its central rule exists to prevent.

**Check:** zero errors and zero warnings under the UGC default, which is the only
family anything can ask for. Automated.

---

### E2 — the quoted prices are the charged prices

**Why:** Gate 2's table is what an operator approves the run against, and it is
six numbers that live in four different config files. A stale one is a promise
the invoice breaks.

**Check:** each row derived from `calculateSeedanceCredits`,
`IMAGE_TO_AD_CREDIT_COST_PER_IMAGE`, `calculateTtsCredits` and
`MUSIC_CREDIT_COST`, and the total re-added. Automated.

---

### E3 — the wave size is the real concurrency cap

**Why:** the one misquote that turns into a refused call halfway through a paid
run. "Waves of five" against a cap of three means five clips submitted, three
accepted, two refused, and an operator watching a partial ad.

**Check:** `MAX_CONCURRENT_API_GENERATIONS` is 5 and the skill says five.
Automated.

---

### E4 — the board gate actually stops

**Why:** it is the reason this skill is survivable. Eighteen centi-credits to
learn the character is wrong, versus a hundred and eighty-seven. A run that
renders the stills and keeps going has removed the only cheap decision point in
a flow that is eight times the price of its sibling.

**Check:** human. Run it end to end and confirm it shows all six images together
and waits. Reviewer says "beat 3 does not follow beat 2" and confirms no clip was
rendered.

---

### E5 — the character survives five separate renders

**Why:** this is THE failure mode of multi-shot generation and the entire reason
for the cast sheet. Five beats with five differently-imagined leads is not an ad,
and nothing recovers it after the clips exist.

**Check:** human. Put beat 1 and beat 5 side by side at full size. Same face,
same wardrobe, same proportions. If not, the stills were chained wrong — and the
fix is 15 centi-credits of stills, not 150 of clips.

---

### E6 — the grade does not drift

**Why:** the style lock is pasted verbatim precisely because rewording it between
beats is invisible while writing and obvious on playback.

**Check:** human. Watch the cut with the sound off. Palette, light direction and
lens should read as one film. A beat that looks like a different afternoon means
its still needs re-rendering, not its clip.

---

### E7 — no dead air at the seams

**Why:** the most reliable tell that an ad was assembled rather than shot, and
the one Gate 7 exists to prevent. A clip is as long as you asked for; the line
inside it is whatever length it is.

**Check:** human. Every beat's audio should carry to within about half a second
of its cut. Silence at the end of a beat means the trim was skipped.

---

### E8 — the narration is intelligible over the clip audio

**Why:** every beat renders with `audioEnabled: true`, so the clips carry their
own dialogue and ambience. Two voices at similar levels is a mix nobody can
follow, and the fix is counter-intuitive — lower the clip, do not raise the voice.

**Check:** human, on phone speakers rather than headphones. Every narration word
should be legible. If not, the clip track is above 28%.

---

### E9 — the master says what the script says

**Why:** measured, and not theoretical: a render once delivered "And wake up,
we're rested" for a scripted "And wake up rested", confirmed across five
transcription passes. At five beats there are five chances for it.

**Check:** human, from the transcript. Read it against the beat board line by
line. A dropped or altered word in the offer line is worth re-rendering that
beat.

---

### E10 — one voice across every line

**Why:** `list_voices` is read once and the id reused. A second call that happens
to pick a different voice produces an ad that changes narrator mid-story, which
reads as a mistake rather than a choice.

**Check:** human. Listen to beat 2 and beat 5 back to back. Same voice. Confirm
the transcript of the run shows ONE `voiceId` across every `generate_voiceover`
call.

---

### E11 — a missing flagged tool degrades, and says so

**Why:** `generate_music` and `transcribe_video` are behind flags. On a
deployment without them the skill must skip the step in one sentence and finish
the ad, not stall or invent a workaround.

**Check:** human, on an account without music. Confirm the run says so plainly,
mixes without a bed, and still delivers a finished master.

---

### E12 — the cost announcement matches what was spent

**Why:** the skill announces a number before spending 18 credits. If that number
is wrong the announcement is worse than none, because the operator stopped
checking.

**Check:** human. Compare the announced total with the balance delta after a full
run. They should differ by zero. A voice-over line longer than the estimate's
sample is the likeliest source of a gap — and it should be pennies, not credits.

---

### E13 — a timed-out call is recovered, not re-run

**Why:** the recovery path matters more here than in the sibling skill, because
there are fifteen or more paid calls per run rather than three. A blind retry at
beat 4 pays twice for the same clip.

**Check:** human. Force or wait for a timeout, then confirm the skill called
`list_generations`, found the job, and took its `outputUrl` — and did NOT
generate again.
