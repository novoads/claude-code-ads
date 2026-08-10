#!/usr/bin/env python3
"""Rank a competitor sweep and state the basis, from sweep.json.

Why this is a script and not an instruction: ranking is sort, truncate, and a
null check. That is the deterministic side of the line -- the same class as
"sort+dedupe" -- and asking prose to do it means the answer is right when the
model is paying attention and wrong when it is not. The judgement that stays in
the skill is which of these to actually clone, which no sort can decide.

It also holds three claims that are easy to get subtly wrong in prose:

  1. The SAMPLE is impressions-selected. The Ad Library is queried with
     sort_data[mode]=total_impressions descending, so every ad in a sweep is
     among Meta's highest-impression ads for that query. That is the strongest
     honest thing available and it belongs first.

  2. There is no impressions NUMBER. Meta publishes per-ad impressions only for
     political/issue ads and in the EU. This script never prints one and has no
     field to print, so a number cannot leak from here.

  3. The ORDER is ours, not Meta's. The API re-sorts by collationCount then
     recency before we see it, so position 1 is not Meta's #1. Measured on a real
     sweep, collationCount was 1 or null on every row -- the field the ordering
     nominally leads on contributed nothing. When that happens the ranking is run
     length alone and must say so.

Usage:
  rank-ads.py <sweep.json> [--top N] [--json]

Exit codes:
  0  ranked
  1  unreadable or unexpected input
  2  the sweep is empty (a charged, valid result -- not an error to retry)
"""

import argparse
import json
import sys
from pathlib import Path

# 12 fills a 4x3 contact sheet in make-picker.py, which is how these are meant
# to be compared. A text list of 12 is long; a grid of 12 is one glance.
DEFAULT_TOP = 12

# collationCount is "how many audiences Meta collated under this creative". A
# value of 1 carries no more information than null: one audience is the floor,
# not a signal. Treating 1 as data is what let a corpus of all-1s look ranked.
NO_SIGNAL = (None, 0, 1)


def load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        print(f"error: no such file: {path}", file=sys.stderr)
        print("Pass the sweep.json written in step 3, not the media directory.",
              file=sys.stderr)
        raise SystemExit(1)
    except json.JSONDecodeError as e:
        print(f"error: {path} is not valid JSON ({e})", file=sys.stderr)
        print("A truncated sweep.json usually means curl was interrupted; the "
              "sweep was still charged, so recover it rather than re-sweeping.",
              file=sys.stderr)
        raise SystemExit(1)
    if not isinstance(data, dict) or "ads" not in data:
        print(f"error: {path} has no `ads` key — is this a sweep response?",
              file=sys.stderr)
        raise SystemExit(1)
    return data


def sort_key(ad: dict):
    """collationCount descending, then longest-running first.

    startDate is YYYY-MM-DD; lexical order is chronological, so the earliest
    string sorts first and that is the longest-running ad. A missing date sorts
    last rather than crashing or silently winning.
    """
    cc = ad.get("collationCount")
    cc = cc if isinstance(cc, (int, float)) else -1
    start = ad.get("startDate") or "9999-99-99"
    return (-cc, start)


def rank(data: dict, top: int) -> dict:
    ads = data.get("ads") or []
    usable = [a for a in ads if a.get("collationCount") not in NO_SIGNAL]
    signal_alive = bool(usable)

    ordered = sorted(ads, key=sort_key)
    picks = ordered[:top]

    pages = {}
    for a in ads:
        pages.setdefault(a.get("pageName") or "(unnamed page)", 0)
        pages[a.get("pageName") or "(unnamed page)"] += 1

    return {
        "total": len(ads),
        "signalAlive": signal_alive,
        "withSignal": len(usable),
        "basis": ("audience count, then run length" if signal_alive
                  else "run length only"),
        "picks": picks,
        "pages": pages,
        "query": data.get("query"),
        "mediaType": data.get("mediaType"),
    }


def describe(ad: dict) -> str:
    bits = []
    if ad.get("startDate"):
        bits.append(f"live since {ad['startDate']}")
    cc = ad.get("collationCount")
    if cc not in NO_SIGNAL:
        bits.append(f"{cc} audiences")
    if ad.get("isActive") is False:
        bits.append("no longer running")
    return ", ".join(bits) or "no dates reported"


def main() -> int:
    p = argparse.ArgumentParser(
        description="Rank a competitor sweep and state the basis.")
    p.add_argument("sweep", type=Path, help="the sweep.json written in step 3")
    p.add_argument("--top", type=int, default=DEFAULT_TOP,
                   help=f"how many to name (default {DEFAULT_TOP})")
    p.add_argument("--json", action="store_true",
                   help="machine-readable, for a caller that formats its own")
    args = p.parse_args()

    data = load(args.sweep)
    r = rank(data, args.top)

    if args.json:
        print(json.dumps(r, indent=2))
        return 2 if r["total"] == 0 else 0

    if r["total"] == 0:
        # A charged, correct result. Say it in one line and stop -- this is the
        # rule the skill exists to hold, so the script must not dress it up.
        print(f"No live ads for {r['query']!r} in {r['mediaType']} right now.")
        print("This sweep was charged and this is the answer. Do not re-run it.")
        return 2

    # The sample claim goes first: it is stronger than anything computed below.
    print(f"{r['total']} ads, and all {r['total']} are among Meta's "
          f"highest-impression ads for this query.")
    print("(Meta publishes no per-ad impression number for commercial ads, so "
          "there is no figure to quote.)")
    print()

    if not r["signalAlive"]:
        print("No audience-count data on any of these, so the ranking below is "
              "run length only.")
        print()

    print(f"Top {len(r['picks'])} by {r['basis']}:")
    for i, ad in enumerate(r["picks"], 1):
        print(f"  {i}. {ad.get('pageName') or '(unnamed page)'} — {describe(ad)}")
        print(f"     {ad.get('adLibraryUrl') or '(no library url)'}")

    if len(r["pages"]) > 1:
        print()
        print("Pages running these — read them before you clone; a third party "
              "running the brand's creative is signal, a same-name stranger is "
              "not the brand:")
        for name, n in sorted(r["pages"].items(), key=lambda kv: -kv[1]):
            print(f"  {n:3d}  {name}")

    print()
    print("That is metadata, not craft. Nobody has watched these ads.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
