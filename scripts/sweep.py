#!/usr/bin/env python3
"""Sweep several competitors at once and download every creative as it lands.

Why this is a script: the sequence is fragile and order-sensitive — fan out to a
ceiling, download each response's media before its CDN links expire, reconcile
what landed against what was promised, and back off by Retry-After rather than
guessing. Prose asked to hold that reliably will hold it on a good day.

It replaces a rule that was wrong. The skill said "one competitor per call,
sequentially", justified by "the call returns in about ten seconds, so there is
nothing to win by fanning out". That number came from a single probe, a live run
of three competitors took minutes, and the sequential habit itself was inherited
from the RETIRED browser version, which serialised to avoid bot detection while
driving Chrome at Meta. Apify does the scraping now and the API has its own
ceiling of ten concurrent sweeps, deliberately separate from the render budget.
Nine of those ten slots were sitting idle.

WHAT THIS DOES NOT DO: decide to spend. The estimate, the competitor list and the
user's yes all stay with the agent, because they are judgement and consent. This
runs after the yes and refuses to run without --yes, so there is no path where it
spends on its own.

Usage:
  sweep.py --queries a.com,b.com --media video|image|all --out DIR --yes
           [--count 20] [--country ALL] [--max-parallel 10]

Exit codes:
  0  every sweep returned and every creative that could be downloaded was
  1  bad input, missing key, or refused for want of --yes
  3  at least one sweep or download failed; the rest still completed
"""

import argparse
import concurrent.futures
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_ROOT = os.environ.get("NOVOADS_BASE_URL", "https://api.novoads.ai").rstrip("/")

# The API's own sweep ceiling, counted apart from renders so holding sweeps open
# cannot starve a caller's next clip. Ten is the contract's number, not a guess;
# going above it earns a 429 with competitor_ads_concurrency_limit.
API_SWEEP_CEILING = 10

# One retry on a 429, paced by the server's own Retry-After. Two would be a queue
# we are pretending not to have; zero would fail a run for a slot that frees in
# seconds.
RETRY_ATTEMPTS = 1
RETRY_FALLBACK_SECONDS = 10  # only when the header is missing or unparseable

SWEEP_TIMEOUT = 180   # a sweep is synchronous and vendor-bound; measured in minutes
MEDIA_TIMEOUT = 60


def slugify(q: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", q.lower()).strip("-") or "competitor"


def post(path: str, body: dict, key: str) -> tuple[int, dict, dict]:
    req = urllib.request.Request(
        f"{API_ROOT}/v1{path}",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}",
                 "Content-Type": "application/json",
                 "User-Agent": "novoads-claude-code/1.0"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=SWEEP_TIMEOUT) as r:
            return r.status, json.loads(r.read().decode()), dict(r.headers)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw), dict(e.headers)
        except json.JSONDecodeError:
            return e.code, {"error": {"code": "unparseable", "message": raw[:300]}}, dict(e.headers)


def retry_after(headers: dict, payload: dict) -> int:
    """The server tells us how long. Take its number, never invent one."""
    h = headers.get("Retry-After") or headers.get("retry-after")
    if h and str(h).strip().isdigit():
        return int(str(h).strip())
    d = (payload.get("error") or {}).get("details") or {}
    if isinstance(d.get("retryAfterSeconds"), (int, float)):
        return int(d["retryAfterSeconds"])
    return RETRY_FALLBACK_SECONDS


def media_url(ad: dict) -> str | None:
    m = ad.get("media") or {}
    return (m.get("videoHdUrl") or m.get("videoSdUrl")
            or m.get("imageUrl") or m.get("previewImageUrl"))


def download(url: str, dest: Path) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "novoads-claude-code/1.0"})
        with urllib.request.urlopen(req, timeout=MEDIA_TIMEOUT) as r, open(dest, "wb") as f:
            f.write(r.read())
        return dest.stat().st_size > 0
    except Exception:
        dest.unlink(missing_ok=True)
        return False


def sweep_one(query: str, media: str, country: str, count: int,
              out_root: Path, key: str, stamp: str) -> dict:
    """One competitor: sweep, then download ITS media before returning.

    The download lives here, inside the same unit of work, so each response's
    creatives are fetched the moment that response lands rather than after every
    sweep has finished. That is the whole reason the old rule gave for being
    sequential, and doing it this way honours it without paying wall-clock.
    """
    slug = slugify(query)
    d = out_root / slug
    d.mkdir(parents=True, exist_ok=True)
    body = {"query": query, "mediaType": media, "country": country, "count": count}

    status, payload, headers = post("/competitor-ads", body, key)
    for _ in range(RETRY_ATTEMPTS):
        if status != 429:
            break
        wait = retry_after(headers, payload)
        print(f"  {slug}: rate limited, waiting {wait}s (the server's number)", flush=True)
        time.sleep(wait)
        status, payload, headers = post("/competitor-ads", body, key)

    if status != 200:
        err = (payload.get("error") or {})
        return {"query": query, "slug": slug, "ok": False,
                "status": status, "code": err.get("code", "unknown"),
                "message": err.get("message", "")[:300],
                "expected": 0, "landed": 0, "credits": 0}

    (d / "sweep.json").write_text(json.dumps(payload, indent=2))
    (d / "swept.json").write_text(json.dumps(
        {"query": query, "mediaType": media, "country": country, "sweptAt": stamp}, indent=2))

    ads = payload.get("ads") or []
    failed = []
    for ad in ads:
        url = media_url(ad)
        if not url:
            continue
        ext = ".mp4" if (ad.get("media") or {}).get("kind") == "video" else ".jpg"
        if not download(url, d / f"{slug}-{ad.get('adArchiveId')}{ext}"):
            failed.append(str(ad.get("adArchiveId")))

    # Count what is ON DISK. Every other number here is a claim: the loop's own
    # successes, the response's length, a memory of what went by.
    landed = len([f for f in d.iterdir() if f.suffix in (".mp4", ".jpg")])
    expected = len([a for a in ads if media_url(a)])
    if failed:
        (d / ".failed").write_text("\n".join(failed) + "\n")

    return {"query": query, "slug": slug, "ok": True, "status": 200,
            "expected": expected, "landed": landed,
            "credits": payload.get("creditsCharged", 0),
            "ads": len(ads), "failed": failed, "dir": str(d)}


def main() -> int:
    p = argparse.ArgumentParser(description="Sweep competitors in parallel and download as they land.")
    p.add_argument("--queries", required=True, help="comma-separated brands or domains")
    p.add_argument("--media", required=True, choices=["video", "image", "all"])
    p.add_argument("--out", type=Path, default=Path("outputs/competitor-ads"))
    p.add_argument("--count", type=int, default=20)
    p.add_argument("--country", default="ALL")
    p.add_argument("--max-parallel", type=int, default=API_SWEEP_CEILING)
    p.add_argument("--yes", action="store_true",
                   help="required: this SPENDS, one charge per competitor")
    p.add_argument("--stamp", default=None, help="scan date to record (default: now, UTC)")
    args = p.parse_args()

    queries = [q.strip() for q in args.queries.split(",") if q.strip()]
    if not queries:
        print("error: --queries was empty", file=sys.stderr)
        return 1

    if not args.yes:
        # Refuse rather than prompt: this is called by an agent, and a script that
        # spends when nobody said yes is the one failure worth being rude about.
        print(f"Refusing to sweep {len(queries)} competitor(s) without --yes.", file=sys.stderr)
        print("Each is a separate charge. Price it with POST /v1/estimates, show the",
              file=sys.stderr)
        print("total, get a yes, then pass --yes.", file=sys.stderr)
        return 1

    key = os.environ.get("NOVOADS_API_KEY", "")
    if not key or key.startswith("novo_your"):
        print("error: NOVOADS_API_KEY is unset or still the placeholder.", file=sys.stderr)
        print("Create one at https://novoads.ai/dashboard/settings?tab=api", file=sys.stderr)
        return 1

    stamp = args.stamp or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    workers = max(1, min(args.max_parallel, API_SWEEP_CEILING, len(queries)))
    if args.max_parallel > API_SWEEP_CEILING:
        print(f"note: capping parallelism at {API_SWEEP_CEILING}, the API's sweep ceiling.")

    print(f"Sweeping {len(queries)} competitor(s), {workers} at a time, media={args.media}.")
    started = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(sweep_one, q, args.media, args.country, args.count,
                               args.out, key, stamp): q for q in queries}
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            results.append(r)
            if r["ok"]:
                print(f"  {r['slug']}: {r['ads']} ads, {r['landed']}/{r['expected']} downloaded")
            else:
                print(f"  {r['slug']}: FAILED {r['status']} {r['code']} — {r['message']}")

    elapsed = int(time.time() - started)
    ok = [r for r in results if r["ok"]]
    bad = [r for r in results if not r["ok"]]
    short = [r for r in ok if r["landed"] < r["expected"]]

    print()
    print(f"{len(ok)}/{len(results)} swept in {elapsed}s. "
          # Summed from the responses, never computed from a rate.
          f"{sum(r['credits'] for r in ok)} credits charged.")
    for r in short:
        print(f"SHORTFALL {r['slug']}: {r['landed']} of {r['expected']} landed. "
              f"Do NOT present these as the full set; re-fetch from its sweep.json "
              f"or quote the adLibraryUrls in {r['dir']}/.failed")
    for r in bad:
        if r["code"] == "provider_failed":
            print(f"{r['slug']}: the scrape failed and the credits were REFUNDED. "
                  f"This is not an empty result.")
    print()
    print("Next: ./scripts/rank-ads.py <dir>/sweep.json and "
          "./scripts/make-picker.py <dir>/sweep.json")
    return 3 if (bad or short) else 0


if __name__ == "__main__":
    sys.exit(main())
