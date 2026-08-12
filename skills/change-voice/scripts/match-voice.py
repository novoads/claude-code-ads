#!/usr/bin/env python3
"""Rank catalog voices by how closely they match the SOURCE voice, by measurement.

    curl -sS "https://api.novoads.ai/v1/voices?gender=male&age=middle_aged&language=en" \\
      -H "Authorization: Bearer $NOVOADS_API_KEY" -A novoads-skill/change-voice > voices.json

    python3 match-voice.py --source ad.mp4 --voices voices.json --top 3 [--json]

Downloads each candidate's `previewUrl`, measures its pitch the same way it
measures the source's, and prints a ranked shortlist with the local path of every
preview so a human can listen to them.

WHY THIS EXISTS. Casting from the written labels alone miscasts, and it did:
picking by description on this skill's own reference ad returned a first choice
measured at 113 Hz with a 16 Hz spread -- a flat monotone -- and a second choice
at 188 Hz, most of an octave above the 132 Hz actor it was replacing. Neither
sounded like the person on screen. `gender`, `age` and `accent` narrow the field
correctly; they say nothing about register, and register is what a viewer hears
as "that is not his voice".

WHAT IT RANKS ON.

  pitch distance   |median f0 of the preview - median f0 of the source|, in
                   SEMITONES rather than Hz, because pitch is heard on a log
                   scale. Under about 2 semitones reads as the same register.
  spread           the preview's own pitch IQR beside the source's. A voice with
                   a far narrower spread than the source is flatter than the
                   performance it is replacing, whatever its median. Reported,
                   not scored: a flatter read is sometimes what you want.

WHAT IT IS NOT. It is not the decision. It shortlists two or three, and a human
listens and picks. A preview is a few seconds of unrelated copy, so it carries
register and timbre but not the delivery this ad needs -- and no measurement here
has ever heard the ad.

A voice with no `previewUrl` cannot be auditioned or measured; those are listed
separately rather than dropped, because your own organization's cloned voices are
exactly the ones the catalog has no sample for.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

import voiceprint


def preview_path(cache, url):
    """Where a preview is cached: a hash of its URL, never a string the catalog
    supplied.

    `voice["id"]` used to be the filename, and a remote string as a path
    component is an arbitrary file write. Verified against this script: an id of
    `/tmp/x/ESCAPED` makes os.path.join DISCARD the --cache prefix outright, and
    `../ESCAPED` climbs out of it -- in both cases the cache directory was left
    empty and the bytes the preview URL served landed wherever the id pointed.
    Keying on the URL also closes the smaller hole beside it: a file already
    sitting at the expected path short-circuits the download and is measured and
    ranked as if it were that voice.
    """
    return os.path.join(cache, hashlib.sha256(url.encode("utf-8")).hexdigest()[:20] + ".mp3")


def fetch(url, dest):
    # `--` ends option parsing: a previewUrl beginning with a dash is read by curl
    # as an OPTION otherwise (verified: `-K/path` was taken as --config). --proto
    # holds it to https, so a catalog value of `file:///Users/you/.env` cannot
    # quietly become the thing we measure and hand back a path to.
    r = subprocess.run(
        ["curl", "-sS", "-L", "--proto", "=https", "--proto-redir", "=https",
         "--max-time", "30", "-A", "novoads-skill/change-voice", "-o", dest, "--", url],
        capture_output=True, text=True,
    )
    return r.returncode == 0 and os.path.exists(dest) and os.path.getsize(dest) > 0


def pick(voices, size, include):
    """Which voices to actually download and measure.

    Even a hard filter leaves hundreds: `gender=male&age=young&accent=american&
    language=en` returned 875 on 2026-08-12. Downloading every preview is minutes
    of work for a shortlist of three, so this takes an evenly spread slice of the
    filtered list plus any id the operator named. Evenly spread rather than the
    first N, because the catalog is ordered by name and the first N is one letter
    of the alphabet. It IS a sample -- the caller is told so in the output, since
    the best voice in the catalog may simply not have been measured.
    """
    forced = [v for v in voices if v.get("id") in set(include)]
    rest = [v for v in voices if v.get("id") not in set(include)]
    if size <= 0 or size >= len(rest):
        return forced + rest, False
    step = len(rest) / float(size)
    slice_ = [rest[int(i * step)] for i in range(size)]
    return forced + slice_, True


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True, help="the ad whose voice is being replaced")
    ap.add_argument("--voices", required=True, help="JSON body from GET /v1/voices")
    ap.add_argument("--top", type=int, default=3)
    ap.add_argument("--sample", type=int, default=24,
                    help="how many catalog voices to actually download and measure")
    ap.add_argument("--include", action="append", default=[],
                    help="a voiceId to measure whatever the sample picks. Repeatable")
    ap.add_argument("--cache", default=None, help="where previews are kept (default: a temp dir)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            print(f"ERROR: {tool} is not on PATH. Measuring a voice is local ffmpeg work.")
            return 1
    try:
        voiceprint.require_readable(args.source)
    except voiceprint.Unreadable as exc:
        print(f"ERROR: {exc}")
        return 1

    src = voiceprint.measure(args.source)
    if not src["f0Median"]:
        print("ERROR: no pitch could be measured in the source. Run check-speech.py first "
              "-- a source with no speech has no voice to match.")
        return 1

    with open(args.voices) as fh:
        payload = json.load(fh)
    # Order matters: `payload.get(...)` is evaluated before its default, so the
    # documented top-level-array form used to die on AttributeError instead of
    # taking the fallback it was written for.
    voices = payload if isinstance(payload, list) else payload.get("voices", [])
    if not voices:
        print("ERROR: no voices in that file. Did the filters return an empty list?")
        return 1

    cache = args.cache or tempfile.mkdtemp(prefix="voice-previews-")
    os.makedirs(cache, exist_ok=True)
    candidates, sampled = pick(voices, args.sample, args.include)

    ranked, unauditionable = [], []
    for v in candidates:
        if not v.get("id"):
            # pick() already tolerates this; the download loop used to subscript
            # v["id"] and take the whole audition down with a KeyError after other
            # previews had been fetched.
            unauditionable.append(dict(v, note="catalog entry carries no id"))
            continue
        url = v.get("previewUrl")
        if not url:
            unauditionable.append(v)
            continue
        if not str(url).lower().startswith("https://"):
            # curl is held to https as well; this arm exists so the reason is a
            # sentence rather than a generic download failure.
            unauditionable.append(dict(v, note="preview URL is not https"))
            continue
        dest = preview_path(cache, url)
        if not os.path.exists(dest) and not fetch(url, dest):
            unauditionable.append(dict(v, note="preview would not download"))
            continue
        try:
            m = voiceprint.measure(dest)
        except voiceprint.NoAudio:
            unauditionable.append(dict(v, note="preview had no audio"))
            continue
        if not m["f0Median"]:
            unauditionable.append(dict(v, note="no pitch measurable in the preview"))
            continue
        ranked.append({
            "id": v["id"], "name": v.get("name", ""), "source": v.get("source", ""),
            "labels": v.get("labels", {}), "previewUrl": url, "previewFile": dest,
            "f0Median": m["f0Median"], "f0Iqr": m["f0Iqr"],
            "semitonesFromSource": round(voiceprint.semitones(m["f0Median"], src["f0Median"]), 2),
        })
    ranked.sort(key=lambda r: r["semitonesFromSource"])
    shortlist = ranked[:args.top]

    if args.json:
        print(json.dumps({"source": src, "shortlist": shortlist,
                          "measured": len(ranked), "unauditionable": unauditionable}, indent=2))
        return 0

    print(f"SOURCE  {os.path.basename(args.source)}: median {src['f0Median']:.0f} Hz, "
          f"spread {src['f0Iqr']:.0f} Hz ({src['f0Q1']:.0f}-{src['f0Q3']:.0f})")
    print(f"        measured {len(ranked)} voice(s)"
          + (f", an even sample of the {len(voices)} the filters returned"
             if sampled else f", every one of the {len(voices)} the filters returned") + "\n")
    print(f"{'#':>2}  {'name':<22} {'median':>7} {'spread':>7} {'apart':>7}  labels")
    for i, r in enumerate(shortlist, 1):
        labels = ", ".join(f"{k}={v}" for k, v in sorted(r["labels"].items())
                           if k in ("gender", "age", "accent", "descriptive"))
        print(f"{i:>2}  {r['name'][:22]:<22} {r['f0Median']:>6.0f}H {r['f0Iqr']:>6.0f}H "
              f"{r['semitonesFromSource']:>5.1f}st  {labels}")
        print(f"    {r['id']}")
        print(f"    listen: {r['previewFile']}")
    if unauditionable:
        print(f"\n{len(unauditionable)} voice(s) carry no usable sample and were not ranked "
              "(normal for your own clones):")
        for v in unauditionable[:10]:
            print(f"    {v.get('name', '?')}  {v.get('id', '?')}  {v.get('note', 'no previewUrl')}")
    print("\nPlay the shortlist against the ad and PICK ONE. Nothing here casts for you.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
