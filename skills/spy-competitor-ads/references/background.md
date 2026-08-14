# spy-competitor-ads — background

Neither section here is needed to run a sweep. Read them when installing the skill outside the
pack, or when something in the flow makes you wonder why it is shaped the way it is.

## Contents
- [Install it on its own](#install-it-on-its-own)
- [Where the browser version went](#where-the-browser-version-went)

---

## Install it on its own

This skill ships in the Novoads ad skill pack. To install just this one:

```bash
npx skills add novoads/agent-skills@spy-competitor-ads
```

Installed solo, it expects four things the pack normally provides. None of them are large:

| Shared file | What it is | Solo |
|---|---|---|
| `.env` at the repo root | `NOVOADS_API_KEY=novo_…` | Create it yourself, `chmod 600` |
| `scripts/check-novoads-env.sh` | Connectivity check that tells a `401` from a `403` | Skip it, or read the failure codes above |
| `logs/novoads-api.jsonl` | Append-only local spend log, gitignored | `mkdir -p logs && touch logs/novoads-api.jsonl` |
| `outputs/` | Where sweeps land, gitignored | Created by the `mkdir -p` in step 3 |

The step-6 hand-off targets `clone-image-ad`, a separate skill in the same pack. Installed solo
it is not there — say so instead of offering a route that goes nowhere, and hand over the file
paths and the ranked top three.

## Where the browser version went

This skill used to drive browser automation: open the Ad Library in a tab, run an in-page extractor,
and download through the tab's own credentials. That version is retired. Its `extract.js` and
`collect.sh` remain in the Novoads repo's git history if anyone ever needs them, and the whole
class of failures they carried — DOM drift, Chrome silently swallowing repeated downloads, a
masked CDN URL — is gone with them. Nothing in the flow above needs a browser.

**Internal teardown workflows keep working**: pass the target directory explicitly and this skill
writes there (for example `.agents/competitor-teardowns/<slug>-ads-<date>/`) instead of the
default `outputs/competitor-ads/<slug>/`. The directory is the only thing that changed.

