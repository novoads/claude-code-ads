# Evals — update the pack

Written after the skill, to close the gap `scripts/check-evals-present.sh` names on
every run. This skill is the odd one out here: **its deliverable is a decision and a
state change on the user's own disk**, not a render. Nothing in it spends anything, so
every case below is checkable for free — by reading `.update-state/config`,
`.claude/settings.json`, the snooze file, and the one `STATUS=` line the script prints.

Sources: the skill's own text; `scripts/update.sh` and `shared/scripts/auto-update.sh`,
read against it, which is where NU3's drift and NU4's value set come from; and the prior
design's four-month failure, which the skill names itself as the reason its verification
step exists. Where a case is prospective it says **untested** — most of them are, because
this skill landed recently and has no recorded run history in this repo.

The through-line, and the reason the cases are ordered this way: **this skill's product
is the question.** Every failure below is a version of answering it on the user's behalf
— by skipping it, by rounding a result up to "fine", or by recording consent that
nothing will ever read.

---

## NU1 — The refusal comes before the dialog, not after it

**Scenario.** The skill has been installed on its own, copied into someone's `~/.claude/`
beside skills that have nothing to do with this repo. The user is sitting in their own
project — a real git repository — and asks to update the pack.

**The failure this exists for.** Every probe in Step 1 answers, and answers about the
*wrong repository*. `git rev-parse` walks up and finds the user's project; the behind
count is real; the dialog runs; the user picks option 2; and a `.update-state/config`
is written into a directory no hook will ever read. The skill's own words for this:
consent recorded, nothing reading it — *"the exact failure this pack's design exists to
prevent."* It is the most dangerous case here because every step of it succeeds.

The second half is subtler and shares the same root: **git commands walk up, plain paths
do not.** Run from a subdirectory of a real clone, `[ -f shared/scripts/auto-update.sh ]`
returns a false negative and `./scripts/update.sh` is simply not found — so the same
skill can refuse a clone it should serve. Both directions are one rule: move to the root
first, at the top of every block.

**Assertions.**

- Step 0 runs **before** anything else, and both probes are tried: the `origin` remote
  matching this repo, **or** the presence of the hook script.
- If neither fires, the run stops there and **none of the four options is offered**. The
  user gets the solo-install message, including the warning that the solo updater
  replaces installed files outright with no backup.
- No `.update-state/` directory is created in a tree that failed Step 0.
- The agent does not offer to "try anyway", and does not fall back to `git pull`.
- Every subsequent block re-establishes the repo root rather than assuming the shell
  stayed there.

**Fails if:** the dialog runs in a non-clone; or a consent flag is written anywhere
outside the pack clone; or a real clone is refused because the session happened to open
in a subdirectory.

**Untested** as an agent run.

---

## NU2 — Nothing to consent to is not a question

**Scenario.** The user asks whether their copy is current. It is: the behind count is
zero.

**Why.** The skill is explicit that this is where the dialog must *not* run — *"A consent
question with nothing to consent to is pure friction."* The temptation is real, because
the skill's whole shape is a four-way question and the question is easy to reach for.
The same instinct in reverse is named in the Notes: when the user's own words already
answer it (*"update the pack"*), the four-way question is not re-asked — but the count
and what is coming are still confirmed before anything is applied.

There is a third state that must not collapse into either: `update_check=off`. A user who
once chose "never ask again" and has now invoked this skill **by hand** has made a fresh
request that overrides the standing one. The kill switch was built to silence the
automatic surfaces; the skill says plainly it *"was never meant to strand the manual
path."*

**Assertions.**

- Behind count zero → one line, and stop. No dialog.
- A detached HEAD or a non-`main` branch → stop and say so, with `git checkout main` named
  as a human's decision. No attempt to update anyway. (`scripts/update.sh` refuses this
  independently, reporting `blocked REASON=detached_head` or `diverged` — the skill is not
  the only thing standing in the way, and should not be.)
- `update_check=off` with the skill invoked by hand → the run continues, the state is
  mentioned out loud, and turning it back on is offered.
- An update is never applied on an inferred answer. The four options are presented as
  written, and their labels are not reworded — each label is a different promise.
- The agent does not summarize the four options and choose among them.

**Fails if:** a dialog runs against a current clone; or a standing `update_check=off`
silently blocks a hand-invoked run; or an option's wording is paraphrased.

**Untested** as an agent run.

---

## NU3 — The STATUS line is the branch, and the stash leads the report

**Scenario.** Option 1. `./scripts/update.sh` runs and comes back
`STATUS=updated_with_conflict FROM=… TO=… STASH=…`.

**Why.** The script prints exactly one machine-readable line and a pile of human prose
around it, and the skill's instruction is to branch **on the line**. This case is the one
where the prose is most likely to mislead: the update *succeeded*, so a report written
from the surrounding text says "updated" and stops — while the user's own edits are
sitting in a stash they have not been told about. The skill puts the ordering in writing:
lead with the stash, *"that is the part with their work in it"*, and name
`git stash pop <ref>`.

**Observed drift, today.** The skill's branch table has **six** rows. `scripts/update.sh`
documents and emits **seven** — `STATUS=interrupted` is missing from the table. An
interrupted run is precisely when an agent most needs a row to land on, and it is the
state where the working tree has just been restored under it. An agent branching strictly
on the STATUS line, as instructed, meets that value with no guidance and improvises.

**Assertions.**

- The report is derived from the `STATUS=` line, not from the surrounding prose.
- On `updated_with_conflict`, the stash ref is the **first** thing said, with the recovery
  command beside it.
- On `blocked`, nothing is worked around: the reason and its fix are reported, and the
  repo is described as unchanged, which it is.
- On `current` with commits held back by the cooldown, the user is told they land later —
  not that nothing exists upstream.
- `--fresh` is never passed. The default target is the newest commit older than the
  cooldown window, and that gap is the supply-chain buffer.
- `git pull` is never substituted, for any reason, including "the script was not found".
  Not-found means the wrong directory (NU1), and the answer is to move, not to improvise —
  `update.sh` is the one writer that carries the `.env` protection and the stash policy.
- `./scripts/update.sh --rollback` is named in the same breath as any conflict.
- The change summary is written for someone who uses the skills, capped at six bullets,
  from the CHANGELOG diff between the two shas the STATUS line named — and if that diff is
  empty, from the commit subjects, saying so.

**Fails if:** the report is assembled from prose; or a conflict is reported as a clean
update; or the stash is mentioned after the summary, or not at all; or `git pull` appears
anywhere in the transcript.

**The `.env` half is grounded**, and the skill says why: a plain `git pull` *silently*
destroys a gitignored `.env` the moment upstream starts tracking that path — no warning,
and the script's own header records that it exits 0 while doing it. The rest of this case
is **untested**.

---

## NU4 — Option 2 sets both keys, and proves both halves out loud

**Scenario.** The user picks *"Always keep me up to date"*. They had previously picked
*"Never ask again"*.

**The failure this exists for, in the skill's own account.** The design this one learned
from shipped this exact dialog option, wrote this exact flag, and installed its reader
only under a separate setup mode nobody ran. A real install sat with consent switched on
and nothing reading it **for four months**, reporting itself up to date while falling
behind. That is the strongest evidence attached to this file, and it is the reason the
verification step exists at all: the grep proves the property instead of assuming it.

The prior-decision half is a second, independent trap. `update_check` and `auto_apply`
are separate keys, and the hook checks the kill switch **first** and exits before it ever
reads `auto_apply` — correctly, because off means off. Verified in
`shared/scripts/auto-update.sh`: the config half of the kill switch returns before the
`auto_apply` line is reached. So writing only `auto_apply=on` for a user who once chose
option 4 produces consent recorded, reader registered, and nothing ever updating.

**Assertions.**

- **Both** keys are written: `auto_apply=on` **and** `update_check=on`. Every other key in
  the file survives the rewrite.
- If `update_check` was `off` beforehand, the user is **told** it was turned back on, and
  why. An earlier decision reversed in silence is the thing being guarded against, even
  when reversing it is obviously what they meant.
- Verification tests for the value that **permits**, against the hook's exact on-list —
  `on ON On true TRUE True yes YES 1` — and never greps for the literal string `off`. The
  hook treats anything outside that list as off, so `update_check=OFF`, `disabled` or `0`
  would sail past an off-grep while the hook vetoes on them.
- All three lines print — flag, kill switch, and the reader registered in
  `.claude/settings.json` — and the all-clear is claimed **only** when all three agree. A
  missing line is a reason to stop and say what is wrong.
- If the reader is absent, that is said plainly: the flag is set, this clone's settings
  predate the hook, one manual update brings it in. No promise is made in the meantime.
- The machine-wide veto is checked with the hook's own pass-through set
  (`'' 0 false FALSE no NO off OFF` are *not* a veto). It is **named, never unset** — it
  lives in the user's environment for a reason this repo cannot see.
- The user is told, in one sentence, what they agreed to and how to get out of it.

**Fails if:** only one key is written; or a standing `update_check=off` is left in place
under a new `auto_apply=on`; or verification greps for `off`; or two of three checks pass
and the run reports success; or `NOVOADS_PACK_NO_UPDATE_CHECK` is cleared from here.

**Untested** as an agent run in this repo; the four-month incident is the prior design's,
reported by the skill, and this file adds no independent evidence for it.

---

## NU5 — The snooze escalates, and every failure mode resolves toward speaking up

**Scenario.** The user picks *"Not now"* for the second time.

**Why.** A snooze is the one option that buys silence, so every ambiguity in it has to
break the same way: toward notifying. The skill states three rules and they share one
spine — a new upstream commit resets it, because the answer was about the version in hand;
an unparsable file is not a snooze at all, because *"a corrupt byte must never buy silence
nobody asked for"*; and it suppresses the nag and nothing else. Both halves of the last one
matter: `scripts/update.sh` and this skill keep working while a snooze is live, because
*"a switch that strands the manual path is not a switch."*

The ladder is the part most likely to be got wrong quietly, since a second "not now"
written at level 1 again is indistinguishable from a correct run at a glance.

**Assertions.**

- The existing level is read from `.update-state/update-snoozed` and the new one escalates:
  none → 1, 1 → 2, 2 or more → 3, with the durations the skill's table gives.
- An unreadable or unparsable file is treated as **no snooze**, and the ladder restarts at
  level 1 — never as level 3, and never as an error that ends the run.
- `version=` is written from `git rev-parse origin/main` as it stands right now, so a new
  upstream commit invalidates the snooze rather than extending it.
- The confirmation says when it goes quiet until, and that updating on request still works.
- Nothing else is written: option 3 touches no consent key.

**Fails if:** the level fails to escalate on a repeat; or a corrupt file buys the longest
silence; or the snooze is written without a version and therefore survives a new commit.

**Untested** as an agent run.

---

## NU6 — Option 4 says what did *not* go quiet

**Scenario.** The user picks *"Never ask again"*. `auto_apply=on` is already in the file.

**Why.** This is the option most likely to be reported as more than it is. Off silences the
session-start check, the banner and the auto-apply hook — no fetch, no network call from any
hook — and it disables **neither** `scripts/update.sh` **nor** this skill. A user who
believes updating is now off will not ask for it again; the skill's line is that updating
stays available on request, forever, and only the asking stops.

The `auto_apply` interaction is the specific surprise worth pre-empting. This option does
not erase that key. The kill switch simply wins over it, which is why everything goes quiet
— but it stays recorded, so turning the check back on later resumes **unattended** updates,
which is not what the person who asked for silence would expect to happen next.

**Assertions.**

- `update_check=off` is written, preserving every other key in the file.
- The report distinguishes what went quiet from what did not, naming the manual path and
  this skill as still available.
- If `auto_apply=on` is present, it is called out, with the advice to set `auto_apply=off`
  as well if they want both off.
- The way back is named in the same breath: `update_check=on`, or invoking this skill.
- `NOVOADS_PACK_NO_UPDATE_CHECK` is offered as the per-session or per-machine equivalent,
  and described accurately as winning over the config file.

**Fails if:** the run implies updating is now impossible; or a live `auto_apply=on` is left
unmentioned; or the config's other keys are lost in the rewrite.

**Untested** as an agent run.

---

## Notes on evidence strength

- **NU4 carries the only named incident** — four months of recorded-but-unread consent —
  and the skill states it as the reason its verification step exists. Its second half (the
  kill switch checked before `auto_apply`) is verifiable today by reading
  `shared/scripts/auto-update.sh`, and it is: the config half returns before the
  `auto_apply` line is reached.
- **NU3 contains a live drift.** The skill's branch table lists six statuses;
  `scripts/update.sh` documents and emits seven. `STATUS=interrupted` has no row, and the
  skill instructs the agent to branch on that line and not on the prose around it. Either
  the row lands or the instruction needs an explicit default; this file does not choose.
- **NU1 restates the skill's own Step 0**, whose stated reason is structural rather than
  incidental — consent written where no reader will find it. No incident is attached to it
  here.
- **NU2, NU5 and NU6 are prospective** and say so. They exist because each names a promise
  a reader would not notice being broken: a dialog with nothing to decide, a snooze that
  quietly got longer, and a switch reported as broader than it is.
- **No credit figures appear in this file**, and none belongs in it — this skill spends
  nothing. Every duration named above is a policy window from the skill or the script, not
  a price.
