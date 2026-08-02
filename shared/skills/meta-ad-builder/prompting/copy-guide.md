# Meta ad copy guide

How to write the body / title / description copy that `deploy-ad.py` rotates via
`TEXT_LIQUIDITY`. These frameworks are distilled from a media-buying account that
has launched thousands of ads — they are *structures*, not scripts. Always
rewrite for the actual brand, product, and audience in front of you.

## The output shape

`deploy-ad.py --copy-file` reads this JSON:

```json
{
  "bodies":       ["body 1", "body 2", "body 3", "body 4", "body 5"],
  "titles":       ["title 1", "title 2", "title 3", "title 4", "title 5"],
  "descriptions": ["description 1", "description 2", "description 3"]
}
```

**Proven shape: 5 bodies / 5 titles / 3 descriptions.** Meta mixes and matches
them per impression. Give it real variety — five near-identical bodies waste the
liquidity. Titles are short (≈40 chars, headline energy). Descriptions are the
shortest line (≈30–50 chars, a supporting proof point).

## The 5-body framework set

Write one body per angle so the five are genuinely different *bets*, not edits of
each other.

1. **The Reveal / Story** — first person, present tense, "here's what just
   happened." Walk through the concrete sequence of events. Highest-context
   variant; let it run long.
2. **The Math / Before-and-After** — quantify the old way vs the new way. Old
   workflow as a list of timed steps → total; new workflow → total. Numbers do
   the persuading.
3. **The Fresh Hook** — an angle nobody else is running. Lead with a
   pattern-breaking line ("I'm not building ads anymore. I'm talking them into
   existence."). Reframes the category.
4. **The Ultra-Short CTA** — tight and punchy. One claim, a few arrow bullets,
   one call to action. This is the variant that wins on cold traffic.
5. **The Authority / Community** — lead with credibility (years of experience,
   spend managed, member count, results) and what the audience joins/gets.

Other angles to swap in when they fit the offer: **Tool-Stack Reveal** (name the
exact stack), **Mechanism / Curriculum Reveal** (show *how* it works or what's
inside), **Objection-Handler** (name the doubt, dismantle it).

## Structural conventions

- **Choppy line breaks.** Short lines and frequent paragraph breaks (`\n\n`) — it
  reads as native social copy, not a press release.
- **Arrow bullets.** Use `→` for feature/benefit lists; it scans fast in-feed.
- **Close with a CTA line.** Every body ends on the action: `Get inside →`,
  `See the workflow →`, or a comment CTA.
- **Comment CTA for Reels-style placements.** "Comment WORD and I'll send you the
  link" — match the keyword to the video's spoken CTA if there is one.
- **Specificity beats adjectives.** "$150M in ad spend", "430+ members",
  "47 variations in 20 minutes" — concrete numbers, not "amazing results".
- **One offer, one link.** All five bodies point at the same destination URL.

## Modeling on winning copy

When `pull-top-ads.py` output is available, read the `copy` field of the top
ads first. Identify *why* each winner works — the hook pattern, the proof points,
the CTA style — and carry those patterns into the new variants. Mirror the
voice; do not copy the text. New creatives + proven copy DNA is the goal.

## Titles and descriptions

- **Titles** — five short headlines, each pairing naturally with the offer.
  Cover different angles: outcome ("60 Seconds → 3 Ads Built"), identity ("Join
  The …"), and direct CTA ("Comment SCHOOL for the Link").
- **Descriptions** — three short supporting lines: a social-proof stat, the
  tool/stack or what's included, and a value framing. Keep them skimmable.

## Compliance

If the offer touches credit, employment, housing, or social issues, the ad set /
campaign must declare a **Special Ad Category** and targeting is restricted — see
[meta-api-cheatsheet.md](../reference/meta-api-cheatsheet.md) §3.5. Copy that
makes income or results claims needs the usual disclaimers. Flag this to the user
rather than guessing.
