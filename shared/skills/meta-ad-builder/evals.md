# Evals — meta ad builder

Written when the pack started advertising "publish this to Meta Ads" in its setup
close (2026-08-08). Advertising it is what created these cases: before that, the
only people who reached this skill already had Meta credentials, and the missing-
credential path was a dead end that printed "add the missing keys to your .env"
and stopped.

The Meta key is **deliberately lazy** — never requested during setup, because one
Novoads key instead of three pasted vendor keys is the pack's whole advantage over
the competitor flow. The cost of that choice is that the first time a user hears
about a Meta token is the instant they ask to publish. So the moment of failure
has to be the moment of setup, and these three evals are the check on that.

All three are **text-and-flow evals against a real run of
`scripts/check-meta-env.sh`**, not mechanical assertions in a test file. M0 and M2
need no Meta account and make no Graph call at all. M1 needs a real token that is
genuinely missing the scope; it reads `/me` and `/me/permissions` and creates
nothing.

The shared invariant, and the reason all three PASS conditions end the same way:
**a credential failure must cost nothing.** An upload that succeeds before ad
creation is rejected leaves an orphaned asset in a live ad account, which is the
user's problem to clean up. So the check runs before the first byte moves.

---

## M0 — "Publish this to Meta" with zero Meta vars set

**Setup.** A repo install with a `.env` copied from `.env.example`: the Novoads key
filled in, the Meta block still exactly as shipped — **commented out**, placeholders
intact. No `META_*` variable exported in the shell. `.env` is `chmod 600`. A finished
creative on disk, so the only thing standing between the user and a deploy is the
credentials.

This is the ordinary first-timer, and the commented block is the whole trap: a user
who opens `.env`, sees `# META_ACCESS_TOKEN=`, types their token onto that line and
re-runs gets the **identical** failure, because they edited a comment. That is the
most likely way this feature fails in practice, and it fails looking like the
script is broken rather than like the file is.

**Run.** The user says "publish this to Meta". The agent reaches the deploy phase
and runs `bash scripts/check-meta-env.sh` before anything else.

**PASS.**
- Exit status is **1**, and the two `MISSING:` lines name both required keys.
- `.env` now carries `META_ACCESS_TOKEN=` and `META_AD_ACCOUNT_ID=` **uncommented
  and empty** — uncommented so a typed value takes effect, empty because
  uncommenting `# META_AD_ACCOUNT_ID=act_1234567890` as shipped would satisfy the
  is-it-set check and then fail two checks later as an unreachable account, which
  reads as a permissions problem rather than as "you never filled this in".
- The four optional keys (`META_PAGE_ID`, `META_IG_USER_ID`, `META_PIXEL_ID`,
  `META_API_VERSION`) are **still commented**. Uncommenting an empty
  `META_API_VERSION` would override the `v23.0` default with an empty string.
- `.env` is **still `chmod 600`**, verified by `stat` after the write, not assumed.
  The rewrite goes through a temp file in the same directory and a `mv`, and follows
  a symlinked `.env` to its target rather than replacing the link.
- The `.env` was **opened** for the user (via `shared/scripts/open-env.sh`), and the
  message matches what actually happened: "Opened …" only when the helper reported
  it opened the file, "Open …" otherwise.
- The printed text carries all three things a user cannot get from the script alone:
  the **Live-app warning first** (a development-mode app fails at ad creation with
  code 100 / subcode 1885183, no Graph endpoint reports app mode for a user token,
  and allowlisting the ad account does not work around it — tested live 2026-08-03);
  where each of the two values comes from, by name and by page; and that the token
  needs **`ads_management` specifically**.
- The agent relays that to the user instead of paraphrasing it into "add your Meta
  credentials". The ask that reaches the user is "paste these two values into the
  file that just opened".
- **Nothing was uploaded.** No image or video reached Meta, no creative was created,
  no ad exists in any state, nothing was charged, and no orphaned asset needs
  cleaning up.

**FAIL.** Any of: the script prints instructions but leaves the two lines commented
(the user then edits a comment and hits the same wall); it uncomments the optional
keys too; `.env` comes back mode `644` or as a regular file that used to be a
symlink; a line the user had already typed a value onto gets rewritten and their
value is lost; the Live-app requirement is omitted or buried under the value list,
where it is read after the app has already been built in development mode; the
token requirement is stated as "a Meta token" with no scope named; or the creative
was uploaded first and the credential check ran after, leaving an orphan.

## M1 — Token present, `ads_management` missing

**Setup.** `META_ACCESS_TOKEN` and `META_AD_ACCOUNT_ID` are both set and the token
is genuinely valid — it just carries no ads scopes (a Graph API Explorer token
generated without adding the permission is the natural way to get one). The user
asks to publish.

**Why this one exists.** It is the documented real-world failure, verified live on
2026-08-03: a token like this **passes `/me`**. Every naive check — "is the variable
set", "is the token valid" — goes green, and the run dies at ad creation, after the
upload, with an orphaned asset left behind. Checks 2 and 3 of the script (scope,
then ad-account reachability with *this* token) exist for precisely this, which is
why their ordering is load-bearing and why the deploy path is not allowed to skip
straight to Phase 3 because "the token is set".

**Run.** `bash scripts/check-meta-env.sh`, before the first upload.

**PASS.**
- Check 1 passes (both variables set) and check 2 fails: `MISSING SCOPE:
  ads_management is not granted on this token`, naming the fix — re-issue the token
  with `ads_management` from the Graph API Explorer or a Business System User.
- Exit status is **1**, and the failure is **caught before any upload**. No image or
  video was sent to Meta, no creative, no ad, no orphan.
- `ads_read` missing is reported as a `NOTE`, not a failure: it limits
  `pull-top-ads.py` insights and does not block a deploy. The two are not collapsed
  into one message.
- The agent stops and asks the user to re-issue the token. It does not try the
  deploy anyway to "see if it works", and it does not report the scope gap as a
  transient error to retry.
- The `.env` rewrite path does **not** fire: both keys are present, so there is
  nothing to uncomment and nothing is written to the file.

**FAIL.** The script exits 0 on a scopeless token; the deploy proceeds and fails at
`POST /act_*/ads` with an asset already uploaded; the missing scope is reported as
"invalid token" (which sends the user to re-authenticate rather than to add a
permission); or `ads_read` missing is escalated into a blocking failure.

## M2 — Standalone install: no `.env`, no `open-env.sh`

**Setup.** The skill directory copied on its own into `~/.claude/skills/` — no repo
around it, no `.env` anywhere on disk, no `shared/scripts/open-env.sh`, no
`.env.example`. Credentials, if any, would live in the exported environment. Here
there are none. This is a supported install shape, not a broken one.

**Why it matters.** Both new steps in the missing-credential path assume files that
this install does not have. A path that only works inside the repo turns a
supported install into a stack trace at the exact moment the user is being asked
for a credential — the worst possible moment to look broken.

**Run.** `bash scripts/check-meta-env.sh` with no `META_*` variables exported.

**PASS.**
- The script reports `No .env found — relying on already-exported environment
  variables`, then the two `MISSING:` lines, then exits **1**.
- It **does not create a `.env`**, does not write to a path it guessed, and does not
  fail because there was nothing to write to. There is no file to uncomment, so
  that step is skipped silently.
- The absent helper is a **silent fallback, never an error**: no "command not found",
  no non-zero exit sourced from the missing file. A helper that exists but is broken
  is also survivable — the script prints the fallback text and still exits 1 with
  its full message.
- The message names the right fix for **this** install: export the two variables in
  the shell, rather than "paste them into `.env`", which would send the user looking
  for a file that does not exist.
- The same three facts as M0 still reach the user — Live-app warning first, where
  each value comes from, `ads_management` by name. The setup text is not part of the
  file-editing branch.
- Nothing uploaded, nothing charged, no partial ad.

**FAIL.** A crash, an unbound-variable error, or a non-zero exit that comes from the
missing helper rather than from the missing credential; a `.env` conjured into
existence next to the skill; the user told to edit a file that is not there; or the
Live-app warning and the value sources appearing only when a `.env` was found.

---

## Notes on evidence strength

- **M0's uncomment step is the load-bearing one**, and it is deliberately the
  narrowest possible rewrite: only a line matching the exact `.env.example` template
  form (`# KEY=` or `# KEY=<shipped placeholder>`) is ever touched. A line the user
  has typed into is reported by key and line number — never rewritten, and never
  echoed back, because the value on it is a live token.
- The **`chmod 600` assertion is measured, not argued**. The script re-stats the file
  after the `mv` and warns with the exact `chmod` command if the mode moved. A
  secrets file that quietly becomes world-readable during a convenience feature is a
  worse outcome than the friction the feature removed.
- **M1 is the only one of the three grounded in a live observation** (2026-08-03).
  M0 and M2 are grounded in the file shapes the pack itself ships, which is why they
  are runnable by anyone with no Meta account at all.
- **Not covered here, on purpose:** whether the app is Live. No Graph endpoint
  reports app mode for a user token, so no eval can assert it and no script can
  check it. It survives every automated check there is, which is exactly why the
  warning leads the printed text instead of closing it.
