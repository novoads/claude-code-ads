# novoads-update evals

This skill's product is a **question**, not an update. Almost everything that can
go wrong with it goes wrong quietly: consent recorded that nothing reads, a
refusal that reads as an offer, a config written where no hook will look. None of
those announce themselves — the user is simply told they are up to date, forever.

So these evals are weighted toward the silent failures, and most of them are not
hypothetical. **U1, U3, U4 and U5 are failures that were actually found in this
skill during review**, and each says where it came from.

The mechanical half is already machine-checked. `tests/upgrade-harness.sh` covers
the hook that reads what this skill writes — `consent_skill_offers_four_options`
pins the four options and the registration check, and the `auto_update_*` and
`killswitch_*` cases pin the reader's behaviour against every flag state. What is
below is the half a harness cannot reach: whether the agent, reading this file,
does the right thing in a real session.

---

### U1 — "Always" after "Never ask again" actually updates

**Where this came from.** Found in review of #93. It is the same shape as the
dead gate this whole design exists to prevent, rebuilt one layer up: the upstream
pack this borrows from shipped an "always update" dialog whose flag had no
reader, and a real install sat consenting for four months while falling behind.

**Scenario.** The user picks "Never ask again". Later — a week, a month — they
change their mind and ask for automatic updates.

**Observed failure.** Option 4 writes `update_check=off`. Option 2 wrote only
`auto_apply=on`. The hook checks the kill switch first and exits **before** it
ever reads `auto_apply`, which is correct: off means off. So consent was
recorded, the reader was registered, the verification told the user it would
work — and nothing ever updated again. Reproduced by running option 4 then
option 2 and watching the hook exit silently with an update available.

**Assertions.**

- Option 2 writes `update_check=on` **and** `auto_apply=on`.
- If the switch had been off, the agent **says** it turned it back on, and why:
  asking for automatic updates supersedes an earlier "stop asking me".
- The session then actually applies on the next start.

**Fails if:** `.update-state/config` ends up holding `update_check=off` beside
`auto_apply=on`; or the flag flips with no word to the user that an earlier
decision was reversed.

**Check.** Run option 4. Then run option 2. `cat .update-state/config` — both
keys present and on. Open a new session with an update pending and confirm it
applies.

---

### U2 — the reader is verified, never assumed

**Where this came from.** The same upstream failure as U1, and the reason the
hook in this pack ships registered for everyone rather than being installed by
the dialog. The flag is not the feature; the reader is.

**Scenario.** The user picks option 2 on a clone old enough that its
`.claude/settings.json` predates the hook.

**Assertions.**

- Three separate facts are checked and reported: the hook is registered in
  `.claude/settings.json`, `auto_apply` is on, and `update_check` is not
  standing in the way. The agent claims it will work only when all three agree.
- `NOVOADS_PACK_NO_UPDATE_CHECK` is checked too, and if it is set to a value the
  hook vetoes on, the agent says the setting is recorded but nothing will apply
  until that variable is unset. It **names** the variable and leaves it alone.
- When the registration grep finds nothing, the agent says the flag is set but
  this clone's settings file predates the hook, and that one manual update
  brings it in. It does not promise unattended updates it cannot deliver.

**Fails if:** the agent reports success on the strength of the flag write alone;
or it clears the environment variable itself; or it says "you're all set" while
any of the three checks is failing.

**Check.** Point option 2 at a clone whose `.claude/settings.json` has been
emptied, and separately at a session with `NOVOADS_PACK_NO_UPDATE_CHECK=1`
exported. Both must produce an honest, specific report rather than a
confirmation.

---

### U3 — a solo install is refused, not half-served

**Where this came from.** Found in review of #93.

**Scenario.** The skill has been installed on its own into `~/.claude/skills/`,
with no pack clone anywhere. The user asks to update.

**Observed failure.** Nothing stopped the skill from proceeding. Step 1's git
commands ran against **the user's own project repository** and reported on it
happily; option 2 then wrote a consent flag into a directory no hook would ever
read. The user was told automatic updates were on. Nothing was.

**Assertions.**

- Step 0 establishes this is the pack clone before anything else runs.
- Failing that, the agent says this skill manages the cloned pack, names
  `npx skills update` as the path for a solo install, and warns that it replaces
  files outright with no backup so local edits should be copied out first.
- It then **stops**, offering none of the four options.

**Fails if:** any of the four options is offered outside a pack clone; or a
`.update-state/` directory is created; or the agent offers to "try anyway".

**Check.** Run the skill from an unrelated git project. It must refuse and name
the solo-install path. Confirm no `.update-state/` was written anywhere.

---

### U4 — every command runs from the clone root

**Where this came from.** Found by the end-to-end run before the v1.1.0 release.
Fixing it surfaced two further instances the original report had not reached.

**Scenario.** The session opened in a subdirectory of the clone — anywhere under
`skills/`, `shared/`, `references/`.

**Observed failure.** Git commands walk up to find the repository, so Step 0's
remote probe passed and every Step 1 command reported correctly. Plain paths do
not walk up. So the skill led the agent all the way to `./scripts/update.sh` and
an **exit 127**, at precisely the moment an agent reaches for `git pull` instead
— the one path that destroys a gitignored `.env`, and the reason `update.sh`
exists. The two further instances: Step 0's file probe returns a false *negative*
from a subdirectory, so a legitimate clone whose remote is a fork or a rename
gets refused as a solo install; and options 2 and 4 write `.update-state/config`
relative, so consent lands where no hook reads it — U1's dead gate, rebuilt by
working directory.

**Assertions.**

- Every command block that touches a plain path moves to the clone root first.
- Step 0 resolves the root **before** it probes, so the file check is meaningful.
- On exit 127 the agent moves to the root and re-runs. It does not substitute
  `git pull`.

**Fails if:** `update.sh` is invoked from a subdirectory; or a `.update-state/`
appears anywhere but the clone root; or `git pull` shows up in the transcript as
a workaround.

**Check.** `cd` into `skills/novoads-update/` and run the skill. `update.sh` must
execute, and `find . -name config -path '*/.update-state/*'` must return exactly
one path, at the root.

---

### U5 — the config is read the way the hook reads it

**Where this came from.** Found in the second review round of #93.

**Scenario.** Someone has hand-edited `.update-state/config` and written
`update_check=OFF`, or `disabled`, or `0`.

**Observed failure.** The verification grepped for the literal string
`update_check=off`. The hook treats anything outside its on-list as off. So
`OFF` sailed past the check while the hook vetoed on it, and the skill reported
all-clear on a clone that would never update. The environment check had the same
defect pointing the other way: it warned on any non-empty value, while the hook
passes `0`, `false`, `no` and `off` through — telling someone their updates were
blocked when they were not.

**Assertions.**

- The skill asserts each key **is on**, against the same set the hook accepts,
  rather than testing for one spelling of off. Checking for the value that
  permits catches every spelling of the value that forbids.
- The environment check mirrors the hook's pass-through set.

**Fails if:** the agent reports the switch is clear on any value the hook would
veto on; or warns about an environment variable the hook ignores.

**Check.** Set `update_check=OFF`, then `disabled`, then `0`, and run option 2's
verification at each. All three must be reported as a problem. Then export
`NOVOADS_PACK_NO_UPDATE_CHECK=0` and confirm it is **not** reported as blocking.

---

### U6 — "Not now" is a ladder, and a broken file speaks up

**Scenario.** The user declines twice in a fortnight, then a new version lands
upstream.

**Assertions.**

- The snooze climbs 24h, then 48h, then 7d, and the level is read from the
  existing file rather than restarted each time.
- A new upstream commit resets it: the answer was about the version in hand.
- A file that does not parse is treated as no snooze at all. Failing toward
  notifying is the rule — a corrupt byte must never buy silence nobody asked for.
- It suppresses the nag and nothing else: `./scripts/update.sh` and this skill
  both keep working while a snooze is live.

**Fails if:** a third decline still buys 24h; or a corrupt file is read as an
active snooze; or the agent refuses to update on request because a snooze exists.

**Check.** Decline three times, reading `.update-state/update-snoozed` between
each. Then corrupt the file and confirm the next session notifies.

**Not yet observed failing.** Unlike U1 and U3-U5 this is a design assertion, and
it carries a known gap worth stating rather than discovering: the snooze file is
written here and read by the auto-apply hook, but whether the session banner
honours it lives in `shared/scripts/check-context.sh`. If that file does not read
it, "Not now" quiets unattended applies while the banner keeps nagging — which
inverts what this option promises. Verify against the banner, not just the hook.

---

### U7 — `update.sh` is the only writer

**Scenario.** Any update, including the awkward ones — a dirty tree, a conflict,
a clone pinned to a commit.

**Assertions.**

- The skill never runs `git pull`, `git reset --hard`, or `git checkout` against
  the user's tree. `update.sh` is the one thing carrying the `.env` protection
  and the stash policy, and going around it goes around both.
- It branches on the `STATUS=` line, not on the prose around it.
- On `updated_with_conflict` the agent **leads with the stash ref**. That is the
  part with the user's work in it, and it is the one message that must not be
  buried under a summary of what changed.
- On any `blocked` reason it reports the reason and stops. It does not improvise
  a workaround.

**Fails if:** any raw git write appears in the transcript; or a conflict is
reported as a plain success; or a `blocked` outcome is worked around.

**Check.** Run against a clone with an uncommitted edit that collides upstream,
and against one on a detached HEAD. Read the transcript for raw git writes.

---

## Notes on evidence strength

**Strongest.** U1, U3, U4 and U5 are real failures found in review of this skill,
each reproduced before it was fixed. U4's two secondary instances were found by
reproducing the first one rather than by reading, which is the reason it is
written out at that length.

**Design assertions, not yet observed failing.** U2, U6 and U7. U2's failure mode
has been observed in the upstream pack this design learned from, but not here —
the registration ordering is meant to make it structurally impossible, and U2 is
the check that the claim stays true.

**Known gap.** U6's banner half spans two files and only one of them is covered
here. Stated in U6 rather than left for a future reader to discover.

**Not covered here.** Everything the harness already pins: throttle, budget,
silence on every non-`updated` status, the JSON control line, and the hook's
behaviour under each flag state. Those are machine-checked on every PR and do not
need a human run.
