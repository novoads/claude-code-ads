# Migrations

A migration is the one-time repair a fast-forward cannot perform.

`./scripts/update.sh` brings new files down and takes old ones away. What it
cannot do is clean up after a file that moved, a config key that was renamed, or
a directory of generated output that nothing reads any more — those are states
that only exist in a clone that is already old, and the new commits know nothing
about them. That gap is what this directory is for.

`run.sh` replays them. It is called from `./scripts/setup.sh` and from
`./scripts/update.sh`, so a customer who updates with either path gets the same
repairs, and a customer who does neither and just runs setup by hand still does.

## Do I need one?

Almost always: **no.**

| Change | Migration? | Why |
|---|---|---|
| A new skill, a new script, a new reference file | **No** | The fast-forward delivers it, and `sync-skill.sh` registers it. Nothing about the old tree is wrong. |
| Editing an existing skill | **No** | Same file, new bytes. Git already did it. |
| A skill or directory **renamed** | **Yes** | The old path is still sitting in the customer's `.claude/skills/`, and both now answer to the router. |
| A `.env` or `.update-state/config` **key renamed** | **Yes** | The old key still parses, still reads as set, and now means nothing. |
| Generated output **orphaned** by a move | **Yes** | Nothing points at it, nothing deletes it, and it will be there in a year. |
| A default that changed **and must not be re-applied** to someone who already opted out | **Yes** | Only a migration can tell "never set it" from "set it, then turned it off". |

The test is not "did something change". It is: **is there a state a months-old
clone can be in that the new code reads wrongly, and that no amount of pulling
files fixes?** If you cannot name that state, you do not need a migration.

## Writing one

Name it `v<major>.<minor>.<patch>.sh` — the version it ships in, no suffix.
`run.sh` skips anything it cannot order, and says so, so a file called
`v2.sh` or `fix-thing.sh` is a migration that will never run.

```bash
#!/usr/bin/env bash
# v1.2.0 — the clone-hook skill moved out of shared/, so the old copy in
# .claude/skills/ answers to the router alongside the new one.
set -u

old="$PACK_ROOT/.claude/skills/clone-hook-old"
[ -d "$old" ] || exit 0     # already gone, or never existed. Both are success.
rm -rf "$old"
```

Three requirements, in the order they bite:

1. **Idempotent.** It will run more than once. A retried failure re-runs it, a
   customer with two clones runs it twice, and a hand-reset marker replays the
   lot. Every migration starts by checking whether the work is already done and
   exiting 0 if it is. "Already done" is a success, not a no-op to apologise for.

2. **Non-destructive by default, and never silent when it is.** You are deleting
   things on someone else's disk. Delete only what the pack generated. If you
   must touch something a customer could have edited, move it aside rather than
   removing it, and print where it went.

3. **Respect opt-outs.** If a migration re-enables something, it must first ask
   whether the customer turned it off on purpose. `.update-state/config` is
   `key=value` lines; read it. Re-enabling a switch someone deliberately set to
   `off` is the one failure mode that turns an upgrade into a betrayal.

Exit 0 for success and for "nothing to do". Exit nonzero only for a repair that
genuinely did not happen — the runner will report it and try again next time.

## What the runner guarantees

- **Environment.** Every migration is run with `PACK_ROOT` (repo root),
  `PACK_STATE_DIR` (`.update-state`), `PACK_VERSION` (the version being moved
  to), `PACK_FROM_VERSION` (the marker it started from) and
  `PACK_MIGRATION_VERSION` (your own version) exported. Derive paths from
  `PACK_ROOT`, never from `$PWD` — the runner is called from several places and
  the working directory is not yours to assume.
- **Order.** `sort -V` semantics, so `1.10.0` runs after `1.2.0` and not before
  it. Only versions strictly above `.update-state/last-setup-version` are
  selected. There is deliberately no upper bound at `VERSION`: a migration
  present in the tree is a repair the tree needs, and holding it back until a
  later release would mean shipping code and its repair on different days.
- **Two gates.** The marker is the range filter; `.update-state/migrations/<version>.done`
  is the authority. A migration that has its touchfile never runs again, even if
  the marker moves backwards.
- **Fresh installs replay nothing.** A clone with no marker adopts the current
  `VERSION` and skips the history. There is no old state to repair on a tree
  that was never old.
- **Failure is contained.** A nonzero exit is reported to stderr, the touchfile
  is withheld so it is retried, the marker is held back so it stays in range,
  and the migrations after it still run. The runner always exits 0: an update
  that landed is not un-landed by a repair that did not.
- **stderr only.** `update.sh` prints a machine-readable `STATUS=` line on
  stdout and calls this runner from inside. Nothing here writes to stdout.

## Running it by hand

```bash
bash migrations/run.sh
```

To see what a clone thinks it has already done:

```bash
cat .update-state/last-setup-version     # the version it last ran
ls  .update-state/migrations/            # one <version>.done per applied repair
```

**Both gates have to agree before anything runs**, so re-running one migration
takes two edits, not one: delete its `.done` touchfile *and* lower the marker
below its version. Deleting the touchfile alone does nothing if the marker has
already moved past it, and lowering the marker alone does nothing while the
touchfile is still there.
