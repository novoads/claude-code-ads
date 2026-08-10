# spy-competitor-ads — recovering a partial download

`scripts/sweep.py` downloads every creative inside its own sweep, so this is the RECOVERY path:
read it when the run reported a shortfall, or when a sweep landed but its media did not.

The rule that matters, before any command: **re-fetch from the sweep.json you already have.
Never re-sweep to refresh a link.** That is a second charge for ads you have already paid for.
If the links are dead, `adLibraryUrl` never expires — quote those instead.

---

## The manual loop

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

