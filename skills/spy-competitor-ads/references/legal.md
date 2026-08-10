# spy-competitor-ads — the legal stance

Read when someone asks whether this is allowed. Not needed to run a sweep.

## Why this is not scraping

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

