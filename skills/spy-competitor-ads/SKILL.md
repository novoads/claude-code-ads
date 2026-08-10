---
name: spy-competitor-ads
description: >-
  Downloads a competitor's live ad creatives — the actual MP4s and JPEGs — from the Meta Ad
  Library into a local swipe folder, through the Novoads API. One sweep per competitor,
  priced by a live estimate before anything is charged, media pulled the moment the response
  lands because the CDN links expire, and every ad carried with its permanent Ad Library
  URL, the page running it, and how many audiences the creative is running against, closing
  with the three most established and why. Use when asked to spy on competitors, find what
  ads a brand is running, pull a competitor's video or static creatives, build or refresh a
  swipe file, check who is outspending you on Meta, or source a reference ad to recreate.
  It finds, ranks and files ads; it does not rebuild them — a static becomes your own ads,
  or a reusable template, via clone-image-ad. It writes no craft analysis and no creative
  brief. A sweep that finds nothing is a result, never an apology.
---

# Spy Competitor Ads

Find what a competitor is actually running, and put the files on disk. That is the whole job.

It ranks what it finds, on evidence the Ad Library actually publishes — how long a creative has
run and how many audiences it runs against. It does **not** judge craft, explain "why it's
winning", or write a brief; it has not watched these ads and neither have you. What you do with
them belongs to `clone-image-ad`, which turns a static into your own ads, a reusable template,
or both.

The mechanics are one HTTP call per competitor. Everything that makes a run good or bad is
judgement: which competitors, which media mode, and which of the returned ads are actually the
brand's rather than somebody else's.

## Before anything: this runs on a Novoads account

- **Base URL:** `https://api.novoads.ai/v1` (host overridable with `NOVOADS_BASE_URL` — host
  only, you append `/v1`).
- **Auth:** `Authorization: Bearer $NOVOADS_API_KEY`, read from `.env` at the repo root. The key
  is `novo_` plus 64 hex.
- **Check:** `./scripts/check-novoads-env.sh`
- **Never** print API keys, commit `.env`, or paste a key into `MASTER_CONTEXT.md`.

> **REST key required. A Novoads MCP connector is not a substitute.** If
> `NOVOADS_API_KEY` is missing or still the placeholder, stop before any
> generation work and tell the user: "Before continuing, create an API key at
> <https://novoads.ai/dashboard/settings?tab=api> and paste it into `.env`."
> That holds even when `mcp__novoads__*` tools are connected and authenticated in
> the session. Never call `mcp__novoads__*` tools from this repo's workflows: they
> are a different surface with different behavior, including the units they quote
> costs in. Repo installs verify with `./scripts/check-novoads-env.sh`; a solo
> install checks `NOVOADS_API_KEY` in the environment.

A `401` means the key is wrong, revoked, or from another account. A `403` with
`error.details.reason` of `plan_required` or `subscription_inactive` means the key is fine and
the account has no live subscription. Different problems, different fixes — say which one it is.

No account yet? **<https://novoads.ai/?utm_source=claude-code&utm_medium=github&utm_campaign=skill-pack>**
The entry offer is a **$1 trial**. Never call it free.

**If this deployment does not offer sweeps yet.** The endpoint is behind a flag that is off by
default. With it off, `POST /v1/competitor-ads` and a `kind: "competitor-ads"` estimate both
answer **`400 invalid_input`**, and the message names what the API *does* offer — it is not a
`404`, and the path existing is not evidence it is enabled. Read that as "this deployment does not
sell sweeps yet", say so plainly, and stop. Do not retry it, do not work around it with a
browser, and do not treat the 400 as a body you got wrong.

`POST /v1/competitor-ads` is the only sweep this skill runs. Verified live 2026-08-08 against
spec `2.19.0`: `HTTP 200`, ads returned, `creditsCharged: 0.2`, matching a
`{"kind":"competitor-ads"}` estimate taken in the same session.

## Golden rules

1. **Price it live, every time.** Every credit number you say out loud came from a
   `POST /v1/estimates` call in this session. There are no rate tables in this file, in this
   repo, or in the logs, and a remembered fee is a lie waiting to happen.
2. **The fee is flat per sweep.** Never quote a per-ad price. Asking for 5 ads costs exactly
   what asking for 20 costs, because the vendor bills a ten-result minimum underneath. N
   competitors is N charges, and that multiplication is the only arithmetic you do out loud.
3. **Download before you write a word.** The response carries `urlsExpire: true` and Meta's own
   token-bound CDN links. A response filed away for later is a list of dead links. `curl` every
   media URL the moment the sweep returns; `adLibraryUrl` is the durable one and it is what you
   quote.
4. **Zero ads is a report, not an apology.** An empty sweep is a success, it is charged, and it
   is said in one line. See *Zero* below — this is the rule this skill exists to hold.
5. **The results are not filtered for you, and filtering them is your job.** A keyword search
   returns third-party pages running the brand's creatives, and sometimes an unrelated company
   trading under the same name. Both arrive as `200 OK`. See *Reading the result*.
6. **Ask in prose, one question at a time.** No option menus. Carry a default so silence is
   never a blocker, name an escape hatch, and never ask twice about the same thing.

## Step 1 — resolve the sweep

Four things decide a run. Take each in order, take it in one line, and only ask about the ones
you genuinely cannot resolve.

**Brand.** Named in the request, or obvious from the repo's `MASTER_CONTEXT.md` or the product
you have been working on → use it, and say which one you took. Otherwise ask once: *"Which
brand am I spying for?"* Do not guess the brand — every downstream judgement about what counts
as pollution depends on it.

**Media mode.** This is the one field with no default, on purpose. Look for an explicit trigger:

| They said | `mediaType` |
|---|---|
| "video ads", "their videos", "hooks", "UGC they're running" | `"video"` |
| "static ads", "image ads", "posters", "creatives to print" | `"image"` |
| "both", "everything", "the full swipe file" | `"all"` |

Silent → **ask, do not default.** The API mirrors this: `mediaType` is required and has no
server-side default, precisely so a silent request cannot become a guess that spends. If they
hand the choice back to you ("you pick"), take `"all"`, say you took it, and say why it is
cheap: `"all"` is still **one** sweep at the same flat fee, not two.

**Competitors.** Named → use them exactly as given, including the ones you would not have
picked. Not named → find 3 to 5 with `WebSearch` (brands selling something similar to a similar
audience that plausibly run paid social), then put the shortlist in front of the user before
opening a single sweep, in prose:

> I'd sweep Arcads, Creatify and Icon — all three sell AI UGC ads to performance marketers.
> Three sweeps, three charges. Swap or add any before I start.

That confirmation is not politeness. Each sweep spends, and a list the user has never seen is a
list you invented.

**Count and country.** `count` defaults to **20**, and 20 is right almost always: the fee is
flat, so a smaller number buys less for the same money. Honor an explicit smaller number, and
say once that it does not save anything. `country` defaults to `"ALL"`; narrow it to an ISO
3166-1 alpha-2 code only when the question is genuinely about one market, and say that narrowing
can empty a sweep you still pay for.

## Step 2 — price it before you sweep

```bash
curl -sS -X POST https://api.novoads.ai/v1/estimates \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"kind":"competitor-ads"}'
```

Returns `credits`, `balance` and `sufficient`; when the balance is short it also returns
`shortBy` and `topUpUrl`. It spends nothing and it runs the same access checks the paid call
runs, which is why it is worth calling every time rather than only when you are unsure.

The estimate body is strict and only takes fields that move the price. The fee is flat per
sweep, so `kind` is the whole body. If the arm asks for more, the `400` names what is missing —
send it and re-quote. **Never fall back to a number you remember.**

Then announce, in one line, and get a yes before the first sweep:

> 3 competitors × 1 sweep each = 3 charges at N credits, N total (balance: B). Starting?

Two cases change it. `sufficient: false` is a blocker, not a warning: stop, say exactly what is
short, and give `topUpUrl`. And if the balance covers this run but not a second one, say so in
one clause before firing — a user who knows that picks their competitors more carefully.

## Step 3 — sweep, one competitor at a time

```bash
SLUG=arcads
DIR="outputs/competitor-ads/$SLUG"
mkdir -p "$DIR"

curl -sS -X POST https://api.novoads.ai/v1/competitor-ads \
  -H "Authorization: Bearer $NOVOADS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"arcads.ai","mediaType":"video","country":"ALL","count":20}' \
  > "$DIR/sweep.json"
```

The response lands on disk before anything else can go wrong. `mkdir -p` is not boilerplate:
`outputs/` is gitignored and absent on a fresh clone, and curl's failure when the directory is
missing is `curl: (56) Failure writing output to destination`, which reads like a broken call on
a sweep that actually succeeded and was already billed.

**One competitor per call, sequentially.** Sweeps have their own concurrency ceiling on the API,
deliberately separate from the render budget, and there is nothing to win by fanning out: the
call is synchronous and returns in seconds. Measured on the probe behind this endpoint,
2026-08-08: a ten-ad sweep came back in about ten seconds. Quote that as an observation, not a
promise.

**`query` is a keyword search, not a page lookup.** A domain (`arcads.ai`) or an `@handle` is a
sharper query than a bare word, for the same reason it was in the browser era: bare words collide
with unrelated companies. It takes 2 to 200 characters.

### What comes back

```
POST /v1/competitor-ads
  request   query       brand name or domain, 2..200 chars          required
            mediaType   "video" | "image" | "all"                   required, no default
            country     ISO 3166-1 alpha-2, or "ALL"                default "ALL"
            count       1..20                                       default 20

  response  ads[]       adArchiveId     the Ad Library's own id for this ad
                        pageName        the page RUNNING it — not necessarily the brand
                        pageId
                        adLibraryUrl    permanent, public, the durable record
                        bodyText        the ad's primary copy, or null
                        collationCount  how many audiences this creative runs against, or null
                        startDate       when it went live, or null
                        endDate         or null
                        isActive
                        platforms[]     FACEBOOK, INSTAGRAM, THREADS, …
                        media           { kind: "video" | "image",
                                          videoHdUrl?, videoSdUrl?,
                                          previewImageUrl?, imageUrl? }
            query, mediaType, country   echoed back, so a saved sweep.json is self-describing
            urlsExpire  always true     the media URLs are already dying. See step 4
            creditsCharged              what this sweep cost. Log this, never recompute it
```

Ads arrive **ranked**: `collationCount` descending, then most recent first, deduplicated,
truncated to `count`. That ordering is mechanical. There is no server-side "which ad is
winning" — that judgement is yours and it is step 5.

Two things the list will not contain, so you do not go looking for them: the same creative twice
(it is collapsed on Meta's ad id, on Meta's collation id, and — for ads Meta groups under nothing —
on the opening of the ad's own copy), and ads with no fetchable file. Carousels and dynamic
creative are often published without a video or image on the ad itself, and an entry you cannot
download is not a creative to study. So `ads` can be shorter than what the Ad Library shows in a
browser, and a brand whose whole live set is that shape comes back as `ads: []`.

## Step 4 — download immediately

Before you write a sentence of delivery, before you sweep the next competitor:

```bash
EXPECTED=$(jq '.ads | length' "$DIR/sweep.json")
FAILED=""

jq -r '.ads[] | [.adArchiveId, .media.kind,
        (.media.videoHdUrl // .media.videoSdUrl // .media.imageUrl // .media.previewImageUrl)]
       | @tsv' "$DIR/sweep.json" |
while IFS=$'\t' read -r id kind url; do
  [ "$kind" = video ] && ext=mp4 || ext=jpg
  curl -sSL --fail -o "$DIR/$SLUG-$id.$ext" "$url" || echo "$id" >> "$DIR/.failed"
done

# THE RECONCILIATION. Count what is ON DISK, not what the loop thought it did.
LANDED=$(find "$DIR" -name "$SLUG-*.mp4" -o -name "$SLUG-*.jpg" | wc -l | tr -d ' ')
echo "downloaded $LANDED / $EXPECTED"
[ -s "$DIR/.failed" ] && { echo "DEAD LINKS:"; cat "$DIR/.failed"; }
[ "$LANDED" -lt "$EXPECTED" ] && echo "SHORTFALL — do NOT deliver these $LANDED as the full set"
```

Prefer `videoHdUrl`, fall back to `videoSdUrl`; images are `imageUrl`, with `previewImageUrl` as
the poster frame when you want a thumbnail of a video.

**Read the reconciliation line before you write anything.** `LANDED` versus `EXPECTED` is the only
honest count in this pipeline, and it is counted from the filesystem because every other number is
a claim: the loop's own successes, the response's `ads` length, your memory of how many you saw go
by. The browser era proved how far apart those drift — a run reporting 5 successes produced exactly
1 file (2026-07-28), and nothing said so.

On a shortfall you have exactly two moves, and delivering quietly is not one of them:

- **Re-fetch the named ids once**, from the SAME `sweep.json` — the URLs are still whatever the
  response carried, and a transient failure often works on the second try. Never re-sweep to
  refresh a link: that is a second charge for ads you already paid for.
- **Or deliver with the shortfall named** in the first line of the delivery: how many landed, how
  many did not, and which `adLibraryUrl`s to open for the rest.

A partial set delivered as complete is the failure mode this step exists to prevent. It looks
exactly like a competitor who runs four ads.

Naming files `<slug>-<adArchiveId>.<ext>` keeps every file traceable to a permanent record. It is
worth more than a sequence number, because the CDN URL in `sweep.json` is dead within the hour
and `adArchiveId` is not.

**A plain `curl` is enough — no cookies, no browser.** Verified 2026-08-08: both a
`videoHdUrl` MP4 and an `imageUrl` JPEG downloaded with an unauthenticated `curl`. This
contradicts what the browser-era version of this skill said, and the contradiction is real: in
the extension the CDN URL was masked and could never be seen, so there was nothing to curl. The
API returns the URL itself.

If a link is already dead, do not re-sweep to refresh it — that is a second charge for the same
ads. Open its `adLibraryUrl`, which never expires.

Then log the sweep. One line, appended to `logs/novoads-api.jsonl` the moment the response
lands — the sweep is synchronous, so the line is written once, complete, the way image lines are:

```json
{ "timestamp": "…", "endpoint": "POST /v1/competitor-ads",
  "request": { "query": "arcads.ai", "mediaType": "video", "country": "ALL", "count": 20 },
  "response": { "status": "succeeded", "creditsCharged": 0, "adsReturned": 10, "error": null } }
```

`creditsCharged` comes off the response and is never computed locally (the `0` above is a
placeholder shape, not a price). **Never log a media URL** — it is a credential while it lives —
and never log the key or the `Authorization` header. The log is observability: latency, spend
history, failure patterns. It is never a pricing source. Prices come from `/v1/estimates`,
always.

## Step 5 — read the result with judgement

### `pageName` is who is running the ad, not who makes the product

Nothing is filtered server-side, and that is deliberate. On the probe behind this endpoint
(query `arcads.ai`, video, 2026-08-08) ten live ads came back across **three** pages, and only
three of the ten sat on the brand's own page. The rest were affiliate and reseller pages running
the brand's creatives, one of them carrying more live ads than the brand itself.

That is signal, not noise. An affiliate outspending the brand on the brand's own creatives is
one of the more useful things a sweep can tell you, and a server-side brand filter would have
silently deleted it.

So read `pageName` and `bodyText` on every ad and sort them into three groups:

- **The brand's own page** — what they are running themselves.
- **Third parties running the brand's creatives** — affiliates, resellers, agencies. Keep these.
  Say who they are.
- **Same-name strangers** — a genuinely unrelated company trading under the same word. The
  canonical case is "Creatify" the AI tool versus "Creatify.mx" a sticker shop. Drop these.

**Name the groups in the delivery and say what you dropped and why.** A filter the user cannot
see is a filter they cannot correct, and the correction is usually one sharper query away.

### The sample is already the strongest thing you can say

**Every ad in a sweep is one of Meta's own top ads by impressions for that query.** The Ad
Library is asked for `total_impressions` descending — the same "Impressions: high to low" sort
a human gets in the Ad Library UI — and the response is the head of that list, capped at
`count`. So a 20-ad sweep is not a sample of what the brand runs. It is the twenty Meta ranks
highest, and every one of them cleared that bar before you saw it.

Say that first, because it is stronger than anything you can compute afterwards:

> 20 ads, and all 20 are among Meta's highest-impression ads for this query.

**What you never get is the impression NUMBER.** Meta publishes per-ad impressions only for
political and issue ads, and in the EU under its transparency rules — never as a field on a
commercial ad. So the count is a thing you can sort by and never a thing you can quote. Never
write "50k impressions", never infer one from the position, and never imply the order encodes a
size you can see.

### Then name a top three, and name the basis honestly

A list of twenty is still a list the user has to read. Close with a pick:

> Top 3 by how long they have run and how many audiences they run against:
> 1. Creatify, live since March, 14 audiences
> 2. Arcads, since May, 9 audiences
> 3. Icon, since June, 6 audiences

Order them by `collationCount` descending, then longest-running first. **State the basis in the
same breath as the pick** — a ranking whose reason is invisible is an opinion, and this one does
not have to be.

**When `collationCount` is null or 1 across the whole response, say so and rank on run length
alone.** That is common, not exceptional: on a real sweep of this category every row came back
`1` or `null`, so the field the ordering nominally leads on contributed nothing and longevity
decided everything. A ranking presented as two signals when one of them was silent is a
ranking that claims more than it has. One clause covers it:

> No audience-count data on any of these, so this is run length only.

Two more honesties about what the ordering is worth. The response arrives sorted by
`collationCount` then recency — **that re-sort is ours, not Meta's**, so position 1 in the list
is not Meta's #1 by impressions. And the cap means the head of the impressions list is all you
ever see: a brand's decade-old evergreen is out of the sample if Meta ranks twenty others above
it. Both are reasons to lead with the sample and treat the top three as a reading of it.

Two things that ranking is not allowed to become:

- **A craft judgement.** You have not watched these ads. "Strong hook", "better angle" and
  "this one is working" are claims the metadata cannot carry. Reading an ad properly is
  `analyze_ad`, it is charged **per ad**, and against a twenty-ad sweep that is an order of
  magnitude more than the sweep itself cost. Offer it on the top one to three as its own
  priced step; never quietly upgrade "rank these" into twenty reads.
- **A spend figure.** See the next section — it survives being turned into a ranking.

### `collationCount` is recurrence, not spend

It is the closest thing to a spend signal the Ad Library exposes: one creative shown against
twelve audiences appears as `collationCount: 12`. High collation plus an old `startDate` is the
strongest available evidence that a creative is working, because nobody keeps paying to run a
loser for months.

Two honesties about it. `null` is common and means *not reported*, not zero. And it is not a
budget: never turn a collation count into a dollar figure or a "they're spending X" claim. The
Ad Library does not publish spend for commercial ads, and inventing the number is worse than
leaving it out.

### Zero

**An empty sweep is a result. It is charged, and it is correct.** The vendor underneath bills its
minimum whether or not the query matched anything, so `ads: []` arriving as a `200` means the Ad
Library genuinely has nothing live for that brand, in that media mode, in that country.

Say it in one line and move on:

> No live video ads for BrandX in ALL right now.

Then stop. Specifically:

- **Do not apologise for it.** It is often the most valuable line in the whole run — a
  competitor who has gone dark is a finding.
- **Do not re-run the same sweep** hoping for a different answer. It is the same query against
  the same index, and it is a second charge.
- **Do not quietly widen the country or switch the media mode** to manufacture a result. If a
  different question is worth asking, ask it out loud, say it is another charge, and get a yes.
- **Do not pad it** with older creatives, a different brand, or the other media mode.

This rule is the reason this skill survived its rewrite. The browser-driven version could not
tell an honest zero from a broken DOM heuristic, and reporting the second as "this brand runs no
ads" was its worst failure mode. That ambiguity is now gone: a scrape that fails is a
`provider_failed` (HTTP 502) with the credits refunded, and it never reaches you as an empty list.

One honest zero has a second cause worth naming when you see it: some ad formats — carousels and
dynamic creative — are published with no downloadable file on the ad itself, and those are left
out of `ads`. So a brand whose entire live set is that shape comes back as `ads: []` on a charged
call. It is still a finding ("nothing fetchable is running right now"), and `adLibraryUrl` on the
Ad Library search page is where a human can still look.

## Step 6 — deliver, then offer the clone once

Deliver per competitor: the files on disk with their paths, the `pageName` groups, and one line
of what is live versus dark.

**Say the count first, and say it from the reconciliation in step 4** — "9 of 10 creatives
downloaded", not "here is their swipe file". If files are missing, that goes in the same sentence
with the `adLibraryUrl`s for the ones that did not land. A set delivered without its count reads as
complete, and the user studies four ads believing they are the whole answer they paid for.

Then offer the next step **once**, in one line, naming a skill that exists in this checkout:

- A **static** you want rebuilt as your own ads, or turned into a reusable template, or both
  → `clone-image-ad`.

Offer, do not start. It spends, and it is not what was asked for here. There is no video
equivalent in this pack yet — for a video you found, hand over the file path and say so.

**Skip the offer entirely when this skill was invoked as a sub-step of something else.** If
another skill or workflow asked for a swipe file, hand back the file paths **and the ranked top
three** and stop — the caller owns what happens next, and an offer injected into the middle of
its flow hijacks it.

## Step 7 — file the corpus so it is not re-bought

The sweep is the charge; the files are the asset. Record beside the downloads, in
`$DIR/sweep.json`'s own directory, what was swept and **when**:

```bash
jq -n --arg q "$QUERY" --arg m "$MEDIA" --arg c "$COUNTRY" --arg at "$(date -u +%FT%TZ)" \
  '{query:$q, mediaType:$m, country:$c, sweptAt:$at}' > "$DIR/swept.json"
```

`sweep.json` already echoes the query, media mode and country back, which is why a saved sweep
is self-describing. The scan **date** is the part it does not carry, and it is the part that
decides everything below.

**Before sweeping anything, look for an existing corpus for that brand and media mode.**

- **Under 7 days old** — reuse it. Do not sweep, do not charge. Say which stored sweep you are
  using and when it was taken.
- **7 days or older** — say the date and the age unprompted, offer a refresh **with its price**,
  and wait. Never refresh silently, and never present stored ads as what the brand is running
  now. The freshness number is not arbitrary: the other competitor corpus in this repo sat at
  eight days with no threshold at any age and presented itself as healthy while three filters
  hid a post the founder found by hand.
- **Absent** — sweep, after the estimate and the announced total. Reuse is an optimisation on
  top of the price gate, never a way around it.

A stored corpus is re-minable: "clone the second one too" costs nothing. The media URLs are dead
within the hour, but the downloaded files are not, and `adLibraryUrl` never expires.

## Errors: branch on `error.code`, never on the message

These are the codes this surface actually emits. `error.code` is the string in the JSON envelope;
the HTTP status is shown beside it because both are worth logging.

| `error.code` | Status | What it means | What to do |
|---|---|---|---|
| `invalid_input` | 400 | Either this deployment does not offer sweeps (the message names what it does offer), or a field is wrong: `mediaType` missing, `country` not alpha-2 or `ALL`, `count` outside 1..20, `query` outside 2..200 | Read the message; it says which. Fix the field, or stop |
| `insufficient_credits` | 402 | Carries `required` and `available`, in credits | Report both and the top-up path. Do not retry |
| `provider_failed` | 502 | The Ad Library query failed, timed out, or came back in a shape the server would not trust. **The credits were refunded** — the message says so, and says "queued" instead if the refund has not landed yet | This is NOT an empty result. Say the scrape failed and the charge was returned. Retry once; if it fails again, stop and say the source is down |
| `rate_limited`, `error.details.reason` = `competitor_ads_concurrency_limit` | 429 | The SWEEP ceiling: you already have the maximum number of sweeps in flight for this organization. Its own queue, counted separately from renders | Wait about ten seconds — `error.details.retryAfterSeconds` and the `Retry-After` header carry the number — then retry. Do not lengthen the backoff; a slot frees when a sweep returns |
| `rate_limited`, `error.details.reason` = `concurrency_limit` | 429 | The RENDER budget, not this endpoint's: the organization has too many video generations in flight. A sweep does not consume one and cannot cause this | Not your queue. Say what is actually blocked, and wait on the renders — sweeping again will not clear it |
| `rate_limited`, any other reason | 429 | Per-key or per-org REQUEST rate, or another endpoint's ceiling | Back off by `Retry-After` and retry. Different problem, different fix |
| `forbidden`, `error.details.reason` = `plan_required` / `subscription_inactive` | 403 | Good key, no live subscription | Say which. It is not a key problem |
| `unauthorized` | 401 | The key is wrong, revoked, or from another account | Stop. Do not retry with the same key |

There is **no `vendor_error` code** on this API. A refunded vendor failure arrives as
`provider_failed`; `vendor_error` is internal vocabulary and branching on it matches nothing, which
sends the whole case into unknown-error handling and re-fires a sweep that pays the fee twice.

**A call that times out on your side is not a call that failed.** There is no idempotency on
sweeps, so re-firing can pay twice. The sweep is recorded as a generation: list your recent
generations and look for it before you retry anything (its `prompt` is the query you sent, which is
how you recognise it). Note that the generation record is a receipt, not a mirror — it carries no
`outputUrl` at all, there is nothing to watch or download, and the media lives only in the
response you already have. That is the whole reason step 4 downloads first.

## Background

`references/background.md` — installing this skill outside the pack, and where the retired
browser-driven version went. Neither is needed to run a sweep.

## Legal note

The Meta Ad Library is public. **This skill does not scrape it.** It calls the Novoads API, and
Novoads queries the Ad Library through a commercial scraping vendor and returns the results under
its own API — the same shape as Foreplay, Motion or AdSpy.

The browser-driven version of this skill left that stance as an open decision, flagged in the
file itself: fine for internal research, not automatically fine behind a product surface. **That
decision was taken on 2026-08-08** — Apify approved as the vendor, Novoads named as the party
querying, results returned under the Novoads API. It is recorded internally in
`.agents/plans/competitor-ads-api/plan.md` §0, and this file inherits it rather than re-litigates
it.

Two things that decision did not change:

- Meta's **official** Ad Library API still only covers political and issue ads. It is not a
  substitute for this, which is the reason a vendor is in the picture at all.
- The creatives you download are **somebody else's copyrighted work**. Studying a swipe file and
  rebuilding an idea for your own product is not the same act as re-running a competitor's ad,
  and this skill only does the first.

## Hard rules

- Every credit number comes from a live estimate in this session. No rate tables, ever.
- Never quote a per-ad price. The fee is flat per sweep.
- Download the media before writing the delivery. `adLibraryUrl` is what you quote.
- One sweep per competitor, sequentially, against a list the user has seen.
- Never ask twice about the same thing, and never with a menu.
- An empty sweep is reported in one line and never retried.
- Never turn `collationCount` into a spend figure.
- Never invent an ad, pad a thin result, or deliver a group you filtered without saying so.
- Close with a ranked top three and the basis for it. Never rank on craft you have not paid
  to read.
- Check for a stored corpus before sweeping. Under 7 days, reuse it and charge nothing; older,
  say its age and price the refresh; absent, sweep after the estimate. Reuse never skips the
  price gate.
