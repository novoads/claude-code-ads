# tests/

## `upgrade-harness.sh`

The executable gate for the pack's update system. It lands **before** the
features it gates, so on a fresh checkout most of its cases are red with the
reason `not_implemented`. That is the intended starting state: the red table is
the specification, in a form that can be run.

```sh
./tests/upgrade-harness.sh                  # every case
./tests/upgrade-harness.sh clean_update     # a subset, any number of names
./tests/upgrade-harness.sh --list           # the manifest
```

Exit status is 0 only when every selected case passes. Each case prints one
line: `PASS <name>` or `FAIL <name> <reason>`.

### What it tests

| Subject | Cases about |
|---|---|
| `scripts/update.sh` | the STATUS wire contract, exit codes, `.env` protection, conflicts, cooldown, `--fresh`, `--rollback`, the lock, network hygiene |
| `shared/scripts/auto-update.sh` | silence by default, the single JSON control line, the throttle, the 15s budget |
| `shared/scripts/check-context.sh` | the update remediation, and the kill switch in both directions |
| `migrations/run.sh` | `sort -V` replay above the marker, touchfile idempotency, fresh-install marker, non-fatal failure |
| `.gitignore`, `.claude/settings.json`, `skills/novoads-update/SKILL.md` | structural pins |

A subject that does not exist yet is not an error: its cases report
`not_implemented` and the run continues.

### How it stays safe

Nothing touches this repository's remote, refs or working tree. Every case
builds its own fixtures inside a `mktemp` sandbox with its own `HOME` and its
own git config: a bare "origin", an author clone that pushes into it, and a
customer clone that plays the part of the repo under test. No case makes a real
network call — "offline" is an unroutable address with a bounded wait.

### Rules the harness holds itself to

- **A grep can never turn a case green.** Capability probes (does the script
  accept `--rollback`, does it carry a lock) exist only to soften a `FAIL` into
  `not_implemented`, so a builder can tell "not built yet" from "built wrong".
  Every `PASS` comes from observed behavior.
- **Every subject invocation is bounded.** A hung script is a `FAIL` with
  `subject_timed_out`, never a hung harness.
- **The manifest is counted against what ran.** A case that quietly disappears
  is reported as a harness bug, because a gate with a hole is worse than no gate.
- **Stock macOS bash 3.2 is the floor**, and coreutils `timeout(1)` is assumed
  absent — one case masks it out of `PATH` on purpose, to prove the subject's own
  watchdog carries the bounded calls.

### Notes for the builders

- The fixture copies this repo's `.gitignore` verbatim, so whether
  `.update-state/` is ignored is a real input to several cases, not just to the
  one that pins it.
- `shared/scripts/sync-skill.sh` is replaced by a stub inside the fixture. The
  question those cases answer is whether `update.sh` called it, not what it did.
- Cases that need "an update is available" commit at 48 hours old, because a
  tip-dated commit legitimately reads as `current` once the cooldown is in.
- Two environment overrides help while a feature is half-built:
  `PACK_UPDATE_SH=/path/to/update.sh` tests a script from elsewhere, and
  `PACK_REPO_ROOT=/path/to/pack` points the whole harness at another checkout.
  `PACK_HARNESS_KEEP=1` keeps the sandbox for inspection.

### Known gaps

- `STATUS=interrupted`'s wire shape is not asserted. What is asserted is the
  contract underneath it: after an interrupt delivered at the exact window
  between the merge and the restore, `.env` survives and no partial merge is
  left behind.
- The consent skill's snooze escalation (24h / 48h / 7d) is prose an agent
  follows, not script behavior, so nothing here can execute it. Only the four
  option strings and the registration self-check are pinned.
