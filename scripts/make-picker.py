#!/usr/bin/env python3
"""Build a clickable picker page from a competitor sweep.

Why a page and not a prose list: choosing which of twelve ads to clone is a
compare-and-choose task, and comparing twelve creatives as filenames is not
comparing them. The creatives are already on disk after the download step; this
puts them side by side at real size with the metadata under each.

Why generated HTML and not the harness's own option UI: an option modal blocks
the run, and the whole flow this belongs to is "propose and proceed with a
one-word veto". A page is a file — it opens in any editor's environment, blocks
nothing, and the run keeps its shape.

Selection comes back by clipboard, not by callback. A file:// page cannot write
to disk, and a local server is machinery to start, secure and clean up for one
click. Clicking a card copies `clone N`; every card also carries a big ordinal,
so typing `clone 3` works when the clipboard does not.

Usage:
  make-picker.py <sweep.json> [--media-dir DIR] [--out FILE] [--top N]

Exit codes:
  0  page written
  1  unreadable input
  2  the sweep is empty — nothing to pick from, and no page written
"""

import argparse
import html
import json
import re
import sys
from pathlib import Path

# rank-ads.py has a hyphen, so it is not importable by name. Load it by path
# rather than copying its two constants: the sort order and what counts as "no
# signal" must be identical in the list and in the page, or the numbers on the
# cards will not match the numbers the other script prints.
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "rank_ads", Path(__file__).parent / "rank-ads.py")
_rank = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rank)
NO_SIGNAL = _rank.NO_SIGNAL
sort_key = _rank.sort_key

DEFAULT_TOP = _rank.DEFAULT_TOP  # one default, not two

# Brand tokens, from app/globals.css. Kept as a table rather than inlined so a
# palette change is one edit and so the dark values cannot drift from the light
# ones by being written in two places.
LIGHT = {
    "bg": "#ffffff", "fg": "#17140e", "primary": "#121212",
    "on-primary": "#fafafa", "muted": "#f6f6f8", "muted-fg": "#6b5d4c",
    "border": "#e8e8ec", "card": "#ffffff", "radius": "10px",
}
DARK = {
    "bg": "#17161e", "fg": "#fafafa", "primary": "#e8e8ec",
    "on-primary": "#17161e", "muted": "#302e38", "muted-fg": "#9b95a8",
    "border": "#302e38", "card": "#121212", "radius": "8px",
}

VIDEO_EXT = {".mp4", ".mov", ".webm"}


def tokens(d: dict) -> str:
    return "\n".join(f"      --{k}: {v};" for k, v in d.items())


def find_media(media_dir: Path, ad_id: str) -> Path | None:
    """The download step names files <slug>-<adArchiveId>.<ext>. Match on the id
    rather than rebuilding the slug, so a renamed directory still resolves."""
    if not media_dir.is_dir():
        return None
    for f in sorted(media_dir.iterdir()):
        if f.is_file() and ad_id in f.name:
            return f
    return None


def card(i: int, ad: dict, media: Path | None, out_dir: Path) -> str:
    # Every field below is third-party text scraped from an ad. It is DATA:
    # escaped on the way in, never interpolated raw. A page name containing
    # markup would otherwise execute in the browser that opens this file.
    page = html.escape(ad.get("pageName") or "(unnamed page)")
    body = html.escape((ad.get("bodyText") or "")[:180])

    # Escaping the URL is not enough: `javascript:alert(1)` contains no character
    # html.escape touches, so it survives into href and runs on click. Scraped
    # fields are third-party data, so the SCHEME is allowlisted, not sanitised.
    raw_url = ad.get("adLibraryUrl") or ""
    url = html.escape(raw_url, quote=True) if raw_url[:8].lower().startswith(
        ("http://", "https://")) else ""

    facts = []
    if ad.get("startDate"):
        facts.append(f"live since {html.escape(str(ad['startDate']))}")
    cc = ad.get("collationCount")
    if cc not in NO_SIGNAL:
        facts.append(f"{int(cc)} audiences")
    if ad.get("isActive") is False:
        facts.append("no longer running")
    meta = html.escape(" · ".join(facts) or "no dates reported")

    if media is None:
        # Degrade to a labelled placeholder. A broken <img> in a grid of twelve
        # reads as "this ad is bad" rather than "this file did not download".
        frame = ('<div class="ph">no file downloaded<br>'
                 '<span>open the Ad Library link</span></div>')
    else:
        rel = html.escape(str(Path(media.name)), quote=True)
        if media.suffix.lower() in VIDEO_EXT:
            frame = f'<video src="{rel}" controls preload="metadata"></video>'
        else:
            frame = f'<img src="{rel}" alt="" loading="lazy">'

    link = f'<a href="{url}" target="_blank" rel="noopener">Ad Library</a>' if url else ""
    return f"""      <figure class="card" data-pick="clone {i}" tabindex="0">
        <div class="n">{i}</div>
        <div class="frame">{frame}</div>
        <figcaption>
          <strong>{page}</strong>
          <span class="meta">{meta}</span>
          <p class="body">{body}</p>
          {link}
        </figcaption>
      </figure>"""


def build(data: dict, media_dir: Path, out: Path, top: int) -> int:
    ads = data.get("ads") or []
    if not ads:
        print("Nothing to pick from: the sweep returned no ads. No page written.",
              file=sys.stderr)
        return 2

    picks = sorted(ads, key=sort_key)[:top]
    signal_alive = any(a.get("collationCount") not in NO_SIGNAL for a in ads)
    query = html.escape(str(data.get("query") or "this query"))
    media_type = html.escape(str(data.get("mediaType") or "all"))

    basis = ("audience count, then run length" if signal_alive
             else "run length only — no audience-count data on any of these")

    found = [find_media(media_dir, str(ad.get("adArchiveId", ""))) for ad in picks]
    resolved = sum(1 for f in found if f is not None)
    cards = "\n".join(card(i, ad, f, out.parent)
                      for i, (ad, f) in enumerate(zip(picks, found), 1))

    # A grid of placeholders reads as a broken tool rather than an empty folder.
    # Say which it is, on the page, at the top: the page shows what was
    # DOWNLOADED, and the usual cause of an empty one is that step 4 has not run.
    if resolved == 0:
        notice = (f'<div class="notice"><strong>None of the {len(picks)} creatives are on '
                  f'disk.</strong> This page shows what was downloaded, not what was found — '
                  f'run the download loop (step 4) against <code>{html.escape(str(media_dir))}'
                  f'</code>, then rebuild. The Ad Library links below still work.</div>')
    elif resolved < len(picks):
        notice = (f'<div class="notice">{resolved} of {len(picks)} creatives are on disk. '
                  f'The rest did not download — their CDN links expire within the hour, so '
                  f're-fetch from <code>sweep.json</code> rather than re-sweeping.</div>')
    else:
        notice = ""

    page = f"""<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{query} — pick an ad to clone</title>
<style>
  :root {{
{tokens(LIGHT)}
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
{tokens(DARK)}
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 32px 24px 64px;
    background: var(--bg); color: var(--fg);
    font: 400 15px/1.55 Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    -webkit-font-smoothing: antialiased;
  }}
  header {{ max-width: 1400px; margin: 0 auto 28px; }}
  h1 {{ font-size: 22px; font-weight: 600; margin: 0 0 6px; letter-spacing: -0.01em; }}
  .sub {{ color: var(--muted-fg); font-size: 14px; margin: 0 0 4px; }}
  .grid {{
    max-width: 1400px; margin: 0 auto;
    display: grid; gap: 16px;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  }}
  .card {{
    margin: 0; background: var(--card);
    border: 1px solid var(--border); border-radius: var(--radius);
    overflow: hidden; position: relative; cursor: pointer;
    transition: border-color .12s ease, transform .12s ease;
  }}
  .card:hover, .card:focus-visible {{ border-color: var(--primary); transform: translateY(-2px); outline: none; }}
  .card.copied {{ border-color: var(--primary); }}
  .card.copied::after {{
    content: "copied — paste it in the chat";
    position: absolute; inset: auto 0 0 0; padding: 8px 12px;
    background: var(--primary); color: var(--on-primary); font-size: 13px;
  }}
  .n {{
    position: absolute; top: 10px; left: 10px; z-index: 2;
    min-width: 26px; height: 26px; padding: 0 7px; border-radius: 999px;
    background: var(--primary); color: var(--on-primary);
    font-size: 13px; font-weight: 600; display: grid; place-items: center;
  }}
  .frame {{ background: var(--muted); display: grid; place-items: center; min-height: 300px; }}
  .frame img, .frame video {{ width: 100%; height: auto; display: block; }}
  .ph {{ padding: 40px 16px; text-align: center; color: var(--muted-fg); font-size: 13px; }}
  .ph span {{ font-size: 12px; opacity: .8; }}
  figcaption {{ padding: 12px 14px 16px; display: grid; gap: 4px; }}
  figcaption strong {{ font-size: 14px; font-weight: 600; }}
  .meta {{ color: var(--muted-fg); font-size: 13px; }}
  .body {{ color: var(--muted-fg); font-size: 12.5px; margin: 4px 0 0;
           display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }}
  figcaption a {{ color: var(--muted-fg); font-size: 12.5px; margin-top: 2px; }}
  footer {{ max-width: 1400px; margin: 32px auto 0; color: var(--muted-fg); font-size: 13px; }}
  .notice {{
    max-width: 1400px; margin: 0 auto 20px; padding: 12px 16px;
    border: 1px solid var(--primary); border-radius: var(--radius);
    background: var(--muted); color: var(--fg); font-size: 13.5px; line-height: 1.5;
  }}
  .notice code {{ font-size: 12.5px; }}
</style>

<header>
  <h1>{len(picks)} ads for {query}</h1>
  <p class="sub">All of these are among Meta's highest-impression ads for this query
     ({media_type}). Meta publishes no per-ad impression number for commercial ads,
     so there is no figure to show.</p>
  <p class="sub">Ordered by {basis}. That is metadata, not craft — nobody has watched these.</p>
</header>

{notice}
<div class="grid">
{cards}
</div>

<footer>
  Click a card to copy its pick line, then paste it in the chat. Or just type
  <strong>clone 3</strong> — the number on each card is the one to use.
</footer>

<script>
  // Click-to-copy, with a typed fallback. The page cannot write to disk and a
  // local server is machinery for one click, so the clipboard is the channel and
  // the ordinal is the fallback when it is blocked.
  for (const el of document.querySelectorAll('.card')) {{
    const pick = () => {{
      const text = el.dataset.pick;
      const done = () => {{
        for (const o of document.querySelectorAll('.copied')) o.classList.remove('copied');
        el.classList.add('copied');
      }};
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, done);
      else done();
    }};
    el.addEventListener('click', pick);
    el.addEventListener('keydown', e => {{ if (e.key === 'Enter' || e.key === ' ') {{ e.preventDefault(); pick(); }} }});
  }}
</script>
"""
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"{out}")
    if resolved == 0:
        # Loud on stdout too: the agent reads this before it writes the delivery,
        # and "12 candidates" over an empty grid is a claim that does not hold.
        print(f"WARNING: none of the {len(picks)} creatives were found in {media_dir}.",
              file=sys.stderr)
        print("The download loop (step 4) has probably not run. Say so rather than "
              "presenting an empty grid as the shortlist.", file=sys.stderr)
    elif resolved < len(picks):
        print(f"note: {resolved} of {len(picks)} creatives on disk; the rest did not "
              f"download.", file=sys.stderr)
    print(f"{len(picks)} candidates. Open it, click one, or say 'clone 3'.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Build a clickable picker from a sweep.")
    p.add_argument("sweep", type=Path)
    p.add_argument("--media-dir", type=Path, default=None,
                   help="where the downloads landed (default: the sweep's directory)")
    p.add_argument("--out", type=Path, default=None,
                   help="default: picker.html beside the sweep")
    p.add_argument("--top", type=int, default=DEFAULT_TOP)
    args = p.parse_args()

    try:
        data = json.loads(args.sweep.read_text())
    except FileNotFoundError:
        print(f"error: no such file: {args.sweep}", file=sys.stderr)
        print("Pass the sweep.json written in step 3.", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"error: {args.sweep} is not valid JSON ({e})", file=sys.stderr)
        return 1
    if not isinstance(data, dict) or "ads" not in data:
        print(f"error: {args.sweep} has no `ads` key — is this a sweep response?",
              file=sys.stderr)
        return 1

    media = args.media_dir or args.sweep.parent
    out = args.out or args.sweep.parent / "picker.html"
    return build(data, media, out, args.top)


if __name__ == "__main__":
    sys.exit(main())
