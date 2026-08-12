# Contributing

Two kinds of contribution are genuinely useful here, and one needs a slower review than its size
suggests.

## Bug reports

Open an [issue](https://github.com/novoads/claude-code-ads/issues). The
[bug report template](.github/ISSUE_TEMPLATE/bug_report.md) asks for the skill you ran, the
request and response ids, and what the estimate said before the call. Those three turn "it did
the wrong thing" into something reproducible without access to your account.

Skill requests are welcome as issues too. Say what ad you were trying to make and where the pack
made you improvise, which is more useful than a proposed file layout.

## Eval cases

Every skill carries an `evals.md` of real failure modes: things this pack or its house sibling
actually produced, or shapes the flow was rebuilt to prevent. A new case is one of the cheapest
contributions here, because it states a red or green that no script can hold.

A good case names the scenario, the run that produced it, and what a correct result looks like.
If it spends credits, say so at the top of the case, the way the existing ones do.

## Pull requests to prompt libraries

These get a careful review, and it is not about style. The files under `skills/*/prompting/` and
`shared/skills/*/prompting/` are executed against a paid API: a sentence that changes what the
agent sends changes what a stranger is charged, and a caption that quotes a number from memory
becomes a quoted price the moment someone reads it aloud.

So a prompt change is reviewed as spend, and three things get checked every time:

- **No number that a live estimate should answer.** Prices and rates go stale in a file. Quote the
  tool at the moment of the spend.
- **One executable path.** This pack runs on REST plus `NOVOADS_API_KEY`. A ratchet in CI fails the
  build when the docs drift toward any other surface.
- **Nothing that tells the agent what to hide.** A second ratchet covers this. Asking an agent for
  silence backfires: it surfaces the request instead of complying.

## Before you push

CI runs `.github/workflows/guard.yml`. Every check in it works offline: none need an API key and
none spend anything, so the whole set runs locally:

```bash
./scripts/check-links.sh              # every relative link resolves
./scripts/check-skill-frontmatter.sh  # SKILL.md registered, description within budget
./scripts/test-brand-context.sh
./scripts/test-rank-ads.sh
./scripts/test-make-picker.sh
./scripts/test-sweep.sh
./scripts/test-placeholder-lint.sh
./scripts/test-parity-i2m.sh
```

`guard.yml` also runs two prose ratchets over the docs. Those are greps across **tracked** files,
so `git add` your work before you trust a local pass: a green from an unstaged file means nothing,
and that exact gap once shipped a red CI after a clean local run.

Add a skill and `check-skill-frontmatter.sh` is the one to watch. A nested `SKILL.md` is never
registered at all, and a description past the length budget truncates exactly where the "not for
X" disambiguation lives.

By contributing you agree your work ships under this repo's [MIT license](LICENSE).
