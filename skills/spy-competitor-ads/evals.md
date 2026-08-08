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
and stops — no `clone-ad` or `image-ad-clone` offer. Then invoke it directly and confirm the offer
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
