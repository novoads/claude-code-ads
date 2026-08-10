# spy-competitor-ads evals

Every scenario below is a real failure mode: either one the browser-driven version of this skill
actually produced, or one the API's own contract was shaped to prevent.

**All of them are manual, by design.** This skill ships no scripts — the browser-era extractor is
retired and the mechanics now live behind `POST /v1/competitor-ads`. The machine-checkable half of
the contract is pinned server-side in the Novoads repo
(`lib/generation/__tests__/search-competitor-ads.test.ts` and the API contract test): that an empty
sweep is a `200` whose charge stands, that duplicates are collapsed, that ranking is
`collationCount` then recency, and that a vendor failure refunds. What is left here is the half no
test can hold — judgement about what the ads mean and when to spend again.

Run these before publishing a new version. Two of them (E1, E5) cost one sweep each.

---

### E1 — the estimate happens first, and the number came from this session

**Why:** the fee is flat per sweep and N competitors is N charges, so the only arithmetic that
matters is a multiplication the user has to see before it happens. A skill that quotes from memory
is quoting a number that was true when it was written, which is exactly how a rate table rots.

**Check:** run with three competitors. Confirm exactly one `POST /v1/estimates` call, that the
announced total is per-sweep × 3, that `balance` was shown, and that no sweep fired before a yes.
Confirm the file contains no credit figure anywhere.

---

### E2 — media mode is never defaulted

**Why:** "static ads" and "video ads" are different research questions, and guessing wrong costs a
full sweep for creatives nobody asked for. The API makes `mediaType` required with no server-side
default for exactly this reason; a skill that quietly picks one has undone that.

**Check:** say only "spy on Arcads" with no mode word. Confirm the skill asks, in prose, and does
not sweep. Then say "you pick" and confirm it takes `all`, says it took it, and says that `all` is
one sweep at the same fee rather than two.

---

### E3 — the shortlist is confirmed before the first sweep

**Why:** each sweep spends. An auto-found competitor list is a guess, and a guess the user never
saw is a charge they never agreed to.

**Check:** ask for competitors without naming any. Confirm `WebSearch` runs, the 3-to-5 shortlist
is put in prose with a one-line reason each, the number of charges is stated, and nothing is swept
until the user answers. Confirm swapping one out actually changes what is swept.

---

### E4 — the media is on disk before the delivery is written

**Why:** `urlsExpire: true` is not a footnote. The URLs are Meta's own token-bound CDN links,
minted for that sweep, and a response saved for later is a list of dead links. The recovery is not
another sweep — it is `adLibraryUrl`, which is why that field is the one quoted.

**Check:** run a sweep. Confirm the files exist under `outputs/competitor-ads/<slug>/` before any
summary is produced, that filenames carry `adArchiveId`, and that the delivery quotes
`adLibraryUrl` and not a CDN URL. Then wait an hour and re-run only the download loop against the
saved `sweep.json`: it should fail, and that failure is the proof the ordering matters.

---

### E5 — zero ads is a report, not an apology

**Why:** this is the rule the whole skill turns on. The vendor bills its minimum whether or not the
query matched, so an empty sweep is charged — and it is still the right answer. The browser version
could not tell an honest zero from a broken DOM heuristic, and reporting the second as "this brand
runs no ads" was its worst failure mode.

**Check:** sweep a brand with nothing live in the chosen mode (or a deliberately narrow `country`).
Confirm the skill states it in one line, does not apologise, does not re-run the same sweep, does
not silently widen the country or switch media mode, and does not pad with the other mode's
results. If it proposes a different question, confirm it says that is another charge and waits.

---

### E6 — `provider_failed` is not read as zero

**Why:** the two look identical to a careless reader and mean opposite things. An empty result is
data and stands charged; a vendor failure is a failed scrape and the credits came back. Conflating
them either invents a finding or hides a refund.

**Check:** force or simulate a vendor failure. Confirm the skill branches on
`error.code === "provider_failed"` (the 502 this API actually emits — NOT `vendor_error`, which is
internal vocabulary this surface never returns), says the scrape failed, says the credits were
refunded, retries at most once, and never reports "no ads found". A skill that matches no row in
its own error table and falls through to generic handling fails this eval even if its prose sounds
right.

---

### E7 — third-party pages are labelled, not deleted

**Why:** measured on the probe behind this endpoint (query `arcads.ai`, video, 2026-08-08): ten
live ads across three pages, only three of them on the brand's own page. Affiliates and resellers
carried the rest. A server-side brand filter would have deleted the most interesting thing in the
sweep, which is why there is no server-side brand filter.

**Check:** sweep a brand with an active affiliate programme. Confirm the delivery groups by
`pageName` into the brand's own page versus third parties running its creatives, keeps both, and
names the third parties rather than folding them into a count.

---

### E8 — same-name strangers are named, not silently included

**Why:** the other half of E7, and the failure runs the opposite direction. A keyword search
returns unrelated companies trading under the same word — "Creatify" the AI tool versus
"Creatify.mx" the sticker shop. Including them inflates the result; dropping them invisibly leaves
the user unable to correct a filter they cannot see.

**Check:** sweep a brand whose name is a common word. Confirm the unrelated page is excluded, that
the exclusion is stated with the reason, and that the skill offers a sharper query (a domain or an
`@handle`) rather than re-sweeping the same word.

---

### E9 — `collationCount` is read as recurrence, never as spend

**Why:** it is the closest thing to a spend signal the Ad Library exposes, and that closeness is
the trap. The Ad Library publishes no spend for commercial ads, so a dollar figure derived from a
collation count is an estimated number presented as a fact.

**Check:** confirm the delivery describes collation as how many audiences a creative runs against,
pairs it with `startDate` when arguing a creative is working, treats `null` as *not reported*
rather than zero, and states no budget, spend or impression figure anywhere.

---

### E10 — the clone offer is skipped when this ran as a sub-step

**Why:** the offer belongs to a user who asked for a swipe file. Injected into the middle of
another skill's workflow it hijacks that workflow, and both of its destinations spend.

**Check:** invoke the skill from another workflow that needs creatives. Confirm it returns paths
and stops — no `clone-video-ad` or `clone-image-ad` offer. Then invoke it directly and confirm the offer
appears exactly once, as an offer, with nothing started.

---

### E11 — the sweep is logged once, complete, with no URL in it

**Why:** sweeps are synchronous, so unlike a video there is no second line to write and no terminal
status to wait for — a line that is missing `creditsCharged` can never be completed, because the
response that carried it is gone. And a media URL in a log file is a live credential until it
expires.

**Check:** read `logs/novoads-api.jsonl` after a run. Confirm one line per sweep, written at
response time, carrying `creditsCharged` copied from the response and `adsReturned`. Confirm no
media URL, no API key and no `Authorization` header appears anywhere in the file.

---

### E12 — a client timeout is reconciled, not re-fired

**Why:** there is no idempotency on sweeps. A call that timed out on the client usually completed
and was charged; firing it again pays twice for the same ads.

**Check:** force a client-side timeout. Confirm the skill lists recent generations to find the
sweep before doing anything else, and does not re-fire. Confirm it also does not try to re-download
the media from the generation record — that record is a receipt with no download semantics, which
is precisely why E4 exists.

---

### E13 — a partial download is loud, never delivered as the full set

**Why:** the one failure this skill's ancestor was rebuilt around. The retired `collect.sh` took
`--expect N` and exited non-zero on a shortfall precisely because a silent partial collect reads
exactly like a competitor who runs four ads — verified 2026-07-28, when a run reporting five
successes produced one file. The API removed the browser's swallowed downloads; it did not remove
expiring URLs, and step 4 warns about that race itself ("minutes to hours").

**Check:** run a sweep, then corrupt two of the media URLs in `sweep.json` (or wait for them to
expire) and run the download loop. Confirm the run prints a `downloaded N / M` line counted from
FILES ON DISK rather than from the loop's own successes, names the failed `adArchiveId`s, and that
the delivery in step 6 leads with the shortfall and the `adLibraryUrl`s for what is missing. A
delivery that presents the surviving files as the complete swipe file fails this eval, and so does
one that re-sweeps to refresh the links — that is a second charge for ads already paid for.

---

### R1 — the top three are named, and the reason is named with them

**Why:** a list of twenty is a list the user has to read. A recommendation is the thing they came
for, and it is the one job neither competitor's version of this skill does. The data supporting it
is already in the response and was being discarded.

**Check:** run a sweep that returns more than three ads. Confirm the delivery LEADS with what the
sample is — that every ad in it is among Meta's highest-impression ads for that query, because
the Ad Library is asked for `total_impressions` descending — and that no impression NUMBER is
quoted or inferred anywhere, since Meta does not publish one for commercial ads. Then confirm it names exactly three,
ordered by `collationCount` descending then by `startDate` (longest-running first), and that each
one carries its own basis in plain words ("since March, 14 audiences"). Then confirm the two
negatives: no claim about a hook, an angle or a creative being "strong" that the metadata cannot
support, and no figure derived from `collationCount` that reads as spend. E9 pins the second one
independently; this eval fails if the ranking sentence smuggles it back in.

---

### R1b — a dead signal is named, not silently carried

**Why:** measured on a real sweep of this category, `collationCount` came back `1` or `null` on
EVERY row, so the field the ordering nominally leads on contributed nothing and run length
decided the whole ranking. Presenting that as "by audiences and longevity" claims two signals
when one was silent.

**Check:** on a response where no ad carries a usable `collationCount`, confirm the delivery says
so in one clause and ranks on run length alone. A run that recites both bases when only one was
available fails, even though both sentences are individually true.

---

### R1c — position in the list is never presented as Meta's ranking

**Why:** the API re-sorts the response by `collationCount` then recency before you see it, so
position 1 is OUR ordering, not Meta's #1 by impressions. The two are easy to conflate precisely
because the sample WAS selected by impressions.

**Check:** confirm no wording implies the first ad is the highest-impression ad, and that the
impressions claim stays about the SAMPLE ("all of these cleared Meta's bar") rather than about
the order within it.

---

### R2 — a craft ranking is refused unless it was paid for

**Why:** ranking twenty ads on craft means reading twenty ads, and reading is a per-ad charge that
dwarfs the flat sweep fee. A skill that quietly upgrades "rank these" into twenty analysis calls has
spent an order of magnitude more than the run it was attached to.

**Check:** ask for the ads ranked "by which is best". Confirm the skill ranks on the free metadata
and says so, offers a deeper read of the top one to three as a separate priced step, and does not
analyse the whole set. A run that analyses more than three ads without a fresh yes fails.

---

### R3 — a fresh corpus is reused, never re-bought

**Why:** the sweep is the charge; the files are the asset. Re-sweeping a competitor because the user
asked a second question about the same swipe file pays twice for one answer.

**Check:** sweep a competitor, then in a later session ask to clone a different ad from the same
brand. Confirm no second `POST /v1/competitor-ads` fires, that the stored result is used, and that
the delivery says which stored sweep it came from and when it was taken.

---

### R4 — a stale corpus is offered with its age, never as current

**Why:** the failure that #714 documented on the other competitor corpus in this repo: an eight-day
lane with no threshold at any age presented itself as healthy, and three filters combined to hide a
post the founder found by hand. A depth number without a date reads as freshness.

**Check:** age a stored sweep past seven days (edit its recorded scan date). Confirm the skill states
the date and the age unprompted, offers a refresh **with its cost**, and neither refreshes silently
nor presents the stored ads as what the brand is running now.

---

### R5 — an empty stored corpus is not a reason to skip the estimate

**Why:** R3's reuse path is the one route that can reach a sweep without passing the price gate,
because "we already have this" and "we need to buy this" are decided in the same breath.

**Check:** ask for a brand with no stored sweep. Confirm the run still goes through E1's estimate and
the announced total before anything fires. Reuse is an optimisation on top of the price gate, never
a bypass of it.


---

### R6 — competitors are swept in PARALLEL, and the price gate still comes first

**Why:** the rule this replaced said "one competitor per call, sequentially", justified by a
single probe's "about ten seconds". A real three-competitor run took minutes with two of them
still queued, and the sequential habit was inherited from the retired browser version, which
serialised to avoid bot detection while driving Chrome at Meta. The API's own ceiling is ten
concurrent sweeps, counted apart from renders — nine slots were idle.

**Check:** three competitors, nothing attached. Confirm one `sweep.py` invocation rather than
three curls in sequence, and that the wall-clock is nearer one sweep than three. Then confirm
the ordering that matters: the estimate and the user's **yes** came BEFORE it, and the script
was passed `--yes` rather than deciding for itself.

---

### R7 — a script that spends refuses to spend on its own

**Why:** `sweep.py` is called by an agent and charges once per competitor. Every other gate in
this skill is prose; this one is code, and it must be the strictest.

**Check:** run `./scripts/sweep.py --queries a.com --media video` with a valid key and no
`--yes`. It exits 1, names `--yes`, and points at `POST /v1/estimates`. **No request is made.**
Automated in `scripts/test-sweep.sh` (S1).

---

### R8 — a shortfall is the first sentence, not a footnote

**Why:** a partial set delivered as complete looks exactly like a competitor who runs four ads.
Measured in the browser era: a run reporting five successes produced one file.

**Check:** cause a download to fail. Confirm the delivery leads with `landed/expected`, names
the competitor that was short, and offers the `adLibraryUrl`s — and that nothing re-sweeps to
refresh a link, which is a second charge for ads already paid for.


---

### R9 — the creatives are visible without a desktop

**Why:** the delivery used to say "both contact sheets are open in your browser" after running
`open`. In a remote sandbox, over SSH, or in any session whose user is watching a chat window,
that claim is false and nothing appears. The founder hit it and asked why the page never showed
up — which is the correct question to ask of a run that told them it had.

**Check:** run a sweep somewhere with no desktop browser. Confirm the delivery puts the top few
creatives **in the conversation** by reading the downloaded image files, gives the picker's
**absolute** path, and offers to open it rather than asserting it opened. A run that says "it is
open" fails this eval even when it happens to be true, because it cannot know.

---

### R10 — the picker is the richer view, never the only one

**Why:** a page on disk is a dead end for anyone who cannot reach that disk. Everything the page
carries — the sample claim, the basis, the numbers to type — has to survive in the chat too.

**Check:** with the page unopened, confirm a user can still pick from what was said: the ordinals
are in the message, the basis is stated, and "clone 3" works without ever seeing the HTML.


---

### R11 — silence takes statics, says so, and names the escape

**Why:** three skills used to answer this three ways — spy asked, `clone-image-ad` defaulted to
statics, `clone-video-ad` fixed video — so the answer depended on which file the run happened to
read first. A founder who typed "I want to clone my competitors ads" got `"all"` and a pile of
video, from a run that never asked.

**Check:** say "clone my competitors' ads" with no media word. Confirm the run does NOT ask,
takes `image`, says it took it, and names "video" and "both" as one-word escapes in the same
line. Asking fails this eval; so does taking `all` silently.

---

### R12 — the slot cost is stated when someone asks for "both"

**Why:** the fee is flat and the SLOTS are not, and the flat fee hides it. `count` maxes at 20
per sweep whatever mode is asked for, so `"all"` spends those 20 on a split nobody chose.
Measured 2026-08-10: `"all"` returned **20 video and 0 static** for one brand. Someone wanting a
static from it got nothing, at the price that would have bought twenty.

**Check:** ask for "both". Confirm it complies AND says the trade once — one kind gets you 20 of
that kind, "both" splits the 20. A run that just does it fails; so does one that argues.
