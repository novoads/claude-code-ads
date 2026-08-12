# Contributing

Two kinds of contribution are genuinely useful here, and one needs a slower review than its size
suggests.

## Bug reports

Open an [issue](https://github.com/novoads/claude-code-ads/issues). The
[bug report template](.github/ISSUE_TEMPLATE/bug_report.md) asks for the skill you ran, the
generation id, and what the estimate said before the call. Those three turn "it did the wrong
thing" into something reproducible without access to your account.

Skill requests are welcome as issues too. Say what ad you were trying to make and where the pack
made you improvise, which is more useful than a proposed file layout.

## Eval cases

Most skills carry an evals file of real failure modes: things this pack actually produced, or
shapes the flow was rebuilt to prevent. A new case is one of the cheapest contributions here,
because it states a red or green that no script can hold.

A good case names the scenario, the run that produced it, and what a correct result looks like.
If it spends credits, say so at the top of the case, the way the existing ones do.

Naming follows the directory: `evals.md` under `skills/`, `EVALS.md` under `shared/skills/`.
Several skills have none yet, and those are the best place to start. This lists them, so no
hand-kept list here goes stale the moment one lands:

```bash
for d in skills/*/ shared/skills/*/; do
  [ -f "$d/SKILL.md" ] && ! ls "$d" | grep -qi '^evals.*\.md$' && echo "$d"
done
```

## Pull requests to skills

These get a careful review, and it is not about style. Everything an agent reads at runtime is
executed against a paid API: `SKILL.md` above all, plus the evals, any `prompting/` library, and
the skill's own `references/` docs. A sentence that changes what the agent sends changes what a
stranger is charged, and a caption that quotes a number from memory becomes a quoted price the
moment someone reads it aloud.

So a change to any of those is reviewed as spend, and three things get checked every time:

- **No number that a live estimate should answer.** Prices and rates go stale in a file. Quote the
  tool at the moment of the spend.
- **One executable path.** This pack runs on REST plus `NOVOADS_API_KEY`. A ratchet in CI fails the
  build when the docs drift toward any other surface.
- **Nothing that tells the agent what to hide.** A second ratchet covers this. Asking an agent for
  silence backfires: it surfaces the request instead of complying.

## Before you push

CI runs `.github/workflows/guard.yml`, and all ten of its checks run locally: none need an API key
and none spend anything.

```bash
git add -A && git status          # stage, then look at what you are about to push
for f in ./scripts/check-no-*.sh; do "$f"; done
./scripts/check-links.sh
./scripts/check-skill-frontmatter.sh
./scripts/test-brand-context.sh
./scripts/test-rank-ads.sh
./scripts/test-make-picker.sh
./scripts/test-sweep.sh
./scripts/test-placeholder-lint.sh
./scripts/test-parity-i2m.sh
```

Three things about that, each of which has bitten someone:

- **Stage first, including new files.** Several checks read only TRACKED files, so a green from an
  unstaged file means nothing, and a brand-new skill or evals file is invisible to them until it
  is added. That gap once shipped a red CI after a clean local run. Your own outputs, logs and
  reference media are gitignored, so `git add -A` will not sweep them in, but read the
  `git status` before you push anyway.
- **Read the whole output, not the last line.** These do not stop at the first failure, so a
  failure can scroll off above a hundred passing cases.
- **This list is maintained by hand, on purpose.** Do not replace it by piping `guard.yml` through
  `grep` into a shell. That file is heavily commented, a script named in a comment is
  indistinguishable from one in a `run:` step, and on a fork branch it is attacker-editable, so
  the pipeline would run a stranger's script with your environment attached.

Adding a skill? `check-skill-frontmatter.sh` is the one to watch. A nested `SKILL.md` is never
registered at all, and a description past the length budget truncates exactly where the "not for
X" disambiguation lives.

By contributing you agree your work ships under this repo's [MIT license](LICENSE).
