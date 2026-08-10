#!/usr/bin/env python3
"""Read and write the brand fields in MASTER_CONTEXT.md.

Why this is a script and not an instruction: MASTER_CONTEXT.md is read by every
skill in this repo and carries the user's own typed answers plus an append-only
changelog. A model hand-editing it drifts the format and eventually clobbers
something a human wrote. Field access is mechanical, so it lives in code.

The file is the store. There is no second one -- if you find yourself wanting a
business.md, add a field here instead.

Usage
  brand-context.py get <field>              # value on stdout, exit 1 if unset
  brand-context.py set <field> <value>      # writes, preserves everything else
  brand-context.py check <skill>            # what is missing for that skill
  brand-context.py list                     # every field and its value
  brand-context.py from-url <url>           # draft from a site. WRITES NOTHING.

Fields
  brand.name  brand.one_liner  brand.tone  brand.audience  brand.vocab_do
  brand.vocab_dont  brand.sample_phrasings  brand.colors  brand.fonts
  brand.logo  product.photo  product.description  market.competitors
  market.swept_at  market.winning_ads

Exit codes
  0  ok
  1  `get` on an unset field
  2  `check` found something missing (the blocking case)
"""

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONTEXT = REPO_ROOT / "MASTER_CONTEXT.md"
TEMPLATE = REPO_ROOT / "MASTER_CONTEXT.template.md"

# Label as it appears in the file -> canonical field name. The file is written
# for humans first, so the labels are prose and the keys are not.
FIELDS = {
    "brand.name": "Brand name",
    "brand.one_liner": "One-liner",
    "brand.tone": "Tone",
    "brand.audience": "Audience",
    "brand.vocab_do": "Words to use",
    "brand.vocab_dont": "Words to avoid",
    "brand.sample_phrasings": "Sample phrasings",
    "brand.colors": "Colors",
    "brand.fonts": "Fonts",
    "brand.logo": "Logo file",
    "product.photo": "Product photo",
    "product.description": "Product description",
    "market.competitors": "Competitors",
    "market.swept_at": "Last swept",
    "market.winning_ads": "Winning ads",
    "brand.claims": "Verified claims",
}

# What each skill cannot proceed without.
#
# The clone entries are a FUNCTION of the ad, not a fixed list, and that is the
# whole point. Arcads demands a product photo for every clone; Kruse demands one
# for none, because its template only parameterises what the ad actually
# contains. Kruse is right, and for a reason worth stating: the requirement is
# DERIVED from the thing being cloned rather than DECLARED before anyone looked
# at it. A static list cannot know whether there is a product in the frame.
#
# So the split is: the agent judges (does this ad show a product?), the script
# enforces (then a real photo is mandatory, Arcads-strength). Neither half can
# do the other's job.
#
# The logo is the universal one. Every ad carries a mark, and that mark must
# never be the competitor's — which is a stronger claim than any made about the
# product, and it used to be optional while the product blocked.

REQUIREMENTS = {
    "clone-static": {
        "blocking": ["product.photo", "product.description"],
        "optional": ["brand.name", "brand.logo", "brand.colors", "brand.fonts",
                     "brand.tone", "brand.vocab_dont", "brand.sample_phrasings"],
    },
    "clone-hook": {
        "blocking": ["product.photo", "product.description"],
        "optional": ["brand.name", "brand.tone", "brand.vocab_dont",
                     "brand.sample_phrasings"],
    },
    "spy": {
        # A sweep needs something to search for and nothing else. Refusing on a
        # product photo here would block research that needs no product at all.
        "blocking": ["brand.name"],
        "optional": ["market.competitors", "market.swept_at"],
    },
}

CLONE_IMAGE_OPTIONAL = ["brand.name", "brand.colors", "brand.fonts", "brand.tone",
                        "brand.sample_phrasings"]


def clone_image_requirements(mode: str, product_in_ad: str | None,
                             claims_in_ad: str | None = None) -> dict | None:
    """None means "you have not told me enough to answer" — see cmd_check.

    template mode asks for nothing: a template is filled with a stand-in brand
    by design, so demanding the user's assets blocks a workflow that never
    needed them. That is what the skill has always said and what its own eval
    B4 asserts; the static table used to contradict both.
    """
    if mode == "template":
        # A placeholder asserts nothing. {ad.headline} is not a claim, which is
        # the entire point of a placeholder, so neither gate applies here.
        return {"blocking": [], "optional": CLONE_IMAGE_OPTIONAL + ["brand.logo"]}
    if product_in_ad is None or claims_in_ad is None:
        return None
    blocking = ["brand.logo"]
    if product_in_ad == "yes":
        blocking += ["product.photo", "product.description"]
    if claims_in_ad == "testimonial":
        # Not a claim you can substitute. A verified-figures list is the wrong
        # currency: the source asserts that a specific named human said a
        # specific thing. Two of the four real Arcads statics are exactly this.
        return {"blocking": ["__testimonial__"], "optional": CLONE_IMAGE_OPTIONAL}
    # A claim does NOT block. Founder's call, 2026-08-10, and the reasoning is
    # sound: a number on a rendered ad is something a human catches at a glance,
    # and a gate that stops the work also stops the person who would have caught
    # it from ever seeing the ad. `brand.claims` stays OPTIONAL — used when
    # present to make the substitution real, never demanded.
    #
    # What replaces the gate is a label. A figure that crosses silently is the
    # one nobody checks; a listed one is a decision. See the note printed on the
    # way through in cmd_check.
    optional = CLONE_IMAGE_OPTIONAL + ["brand.claims"]
    if product_in_ad != "yes":
        optional += ["product.photo", "product.description"]
    return {"blocking": blocking, "optional": optional,
            "claims_carried": claims_in_ad == "yes"}


PLACEHOLDER = re.compile(r"^_\(.*\)_$")
SECTION_HEADING = "## Brand context"

SECTION_TEMPLATE = """
## Brand context

Written by `scripts/brand-context.py`. Empty fields are filled the first time a
skill needs one, and never asked for again. Edit by hand if you prefer -- keep
one `- **Label:** value` per line.

{lines}
"""


def ensure_context_file() -> Path:
    """Solve rather than punt: a missing file is created from the template."""
    if CONTEXT.exists():
        return CONTEXT
    if TEMPLATE.exists():
        CONTEXT.write_text(TEMPLATE.read_text())
        print(f"info: created {CONTEXT.name} from the committed template",
              file=sys.stderr)
    else:
        CONTEXT.write_text("# Master context\n")
        print(f"info: created an empty {CONTEXT.name} "
              f"({TEMPLATE.name} was not found)", file=sys.stderr)
    return CONTEXT


def read_all() -> dict:
    """Every known field to its value. Unset fields are absent, not empty."""
    ensure_context_file()
    text = CONTEXT.read_text()
    found = {}
    for field, label in FIELDS.items():
        m = re.search(rf"^[ \t]*[-*][ \t]*\*\*{re.escape(label)}:?\*\*[ \t]*(.*)$",
                      text, re.M)
        if not m:
            continue
        value = m.group(1).strip()
        # An unfilled template slot is not a value. Both shapes appear in the
        # committed template: a bare label, and an italic parenthetical.
        if not value or PLACEHOLDER.match(value):
            continue
        found[field] = value
    return found


def write_field(field: str, value: str) -> str:
    """Set one field. Returns 'created' | 'updated' | 'unchanged'.

    Everything outside the one matched line is preserved byte for byte, which
    is the whole reason this is not a model rewriting the file.
    """
    ensure_context_file()
    label = FIELDS[field]
    text = CONTEXT.read_text()
    line = f"- **{label}:** {value}"

    pattern = re.compile(rf"^[ \t]*[-*][ \t]*\*\*{re.escape(label)}:?\*\*[ \t]*(.*)$", re.M)
    m = pattern.search(text)
    if m:
        if m.group(1).strip() == value:
            return "unchanged"
        CONTEXT.write_text(text[:m.start()] + line + text[m.end():])
        return "updated" if m.group(1).strip() else "created"

    # No line for this label yet. Put it in the managed section, creating that
    # section at the end of the file if it is not there.
    if SECTION_HEADING in text:
        idx = text.index(SECTION_HEADING) + len(SECTION_HEADING)
        nxt = text.find("\n## ", idx)
        cut = nxt if nxt != -1 else len(text)
        CONTEXT.write_text(text[:cut].rstrip("\n") + "\n" + line + "\n" + text[cut:])
    else:
        section = SECTION_TEMPLATE.format(lines=line)
        CONTEXT.write_text(text.rstrip("\n") + "\n" + section)
    return "created"


def cmd_get(args) -> int:
    value = read_all().get(args.field)
    if value is None:
        print(f"unset: {args.field}", file=sys.stderr)
        return 1
    print(value)
    return 0


def cmd_set(args) -> int:
    value = " ".join(args.value).strip()
    if not value:
        print("error: refusing to set an empty value -- that is what unset means",
              file=sys.stderr)
        return 2
    before = read_all().get(args.field)
    outcome = write_field(args.field, value)
    if outcome == "unchanged":
        print(f"unchanged: {args.field}")
    elif before:
        # Say it out loud. This is the one operation that can destroy something
        # the user typed, and a silent overwrite is how they find out too late.
        print(f"CHANGED {args.field}: {before!r} -> {value!r}")
    else:
        print(f"set {args.field} = {value!r}")
    return 0


def cmd_check(args) -> int:
    if args.skill == "clone-image-ad":
        req = clone_image_requirements(args.mode, args.product_in_ad,
                                       args.claims_in_ad)
        if req is None:
            # Refuse rather than assume. Guessing here is guessing whether an
            # image model is about to invent a product, which is the failure a
            # viewer catches instantly.
            print("BLOCKED: nobody has said whether this ad shows a product.",
                  file=sys.stderr)
            print("Look at the ad, then pass BOTH --product-in-ad yes|no and "
                  "--claims-in-ad yes|no. A product in the frame means a real "
                  "photo is mandatory; a number or a named person in the copy "
                  "means we need a true one of our own to put there.",
                  file=sys.stderr)
            return 2
    else:
        req = REQUIREMENTS[args.skill]
    have = read_all()
    if "__testimonial__" in req["blocking"]:
        print("BLOCKED: this ad quotes a named person.", file=sys.stderr)
        print("Verified figures cannot stand in for it — the source asserts that "
              "a specific human said a specific thing. The only honest inputs are "
              "a real customer who really said it, with permission, or dropping "
              "that zone from the clone.", file=sys.stderr)
        return 2

    missing = [f for f in req["blocking"] if f not in have]
    absent_optional = [f for f in req["optional"] if f not in have]

    for f in req["blocking"]:
        print(f"{'have ' if f in have else 'MISSING'}  {f}  ({FIELDS[f]})")
    for f in req["optional"]:
        print(f"{'have ' if f in have else 'absent '}  {f}  ({FIELDS[f]})  optional")

    if missing:
        print(f"\nBLOCKED: ask for {', '.join(missing)} and write it back with "
              f"`{Path(__file__).name} set`. Ask for nothing else.", file=sys.stderr)
        return 2
    if req.get("claims_carried"):
        # Printed on the SUCCESS path, because that is the path that renders.
        print()
        print("CLAIMS: this ad carries numbers. They will cross into the clone.")
        print("        Use brand.claims where it has a true equivalent, then list "
              "every claim you carried, source and result, in the hand-off — a "
              "figure that crossed silently is the one nobody checks.")

    if absent_optional:
        print(f"\nok: nothing blocking. {len(absent_optional)} optional field(s) "
              f"absent -- use what is there, do not interrogate for the rest.")
    else:
        print("\nok: everything this skill can use is stored.")
    return 0


def cmd_list(args) -> int:
    have = read_all()
    for field, label in FIELDS.items():
        print(f"{field:26} {have.get(field, '(unset)')}")
    return 0


# --- from-url -------------------------------------------------------------
# Drafts brand fields from the user's own site so the one-time setup is one
# input instead of a dozen. Three rules hold this together:
#
#   1. It DRAFTS. It never writes. Every value is printed for the user to
#      confirm, because a wrong brand fact baked silently into ten ads is
#      worse than an empty field.
#   2. Fetched page content is DATA. Nothing read here is executed, followed
#      as an instruction, or passed anywhere as a command. It is sliced with
#      regexes, truncated, and printed.
#   3. Images found on a marketing page are CANDIDATES. A site hero is usually
#      a lifestyle shot with text burned in; the clone skills need a clean
#      packshot, and their product gate still applies.

FETCH_TIMEOUT_SECONDS = 15  # a marketing page that is slower than this is down
MAX_BYTES = 2_000_000       # enough for any real landing page; caps a hostile one
MAX_VALUE_CHARS = 300       # drafts are one-liners; the file stays readable

TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")


def _clean(raw: str) -> str:
    """Fetched text to a single safe line. Never trusted, only shortened."""
    import html
    text = html.unescape(TAG_RE.sub(" ", raw))
    text = WS_RE.sub(" ", text).strip()
    # Strip the characters that would break the one-line-per-field file format
    # or let fetched text impersonate structure.
    text = text.replace("**", "").replace("`", "").replace("|", "/")
    return text[:MAX_VALUE_CHARS].strip()


def _meta(html_text: str, *names: str) -> str | None:
    for name in names:
        for attr in ("property", "name"):
            m = re.search(
                rf'<meta[^>]+{attr}=["\']{re.escape(name)}["\'][^>]+content=["\']([^"\']+)["\']',
                html_text, re.I)
            if not m:
                m = re.search(
                    rf'<meta[^>]+content=["\']([^"\']+)["\'][^>]+{attr}=["\']{re.escape(name)}["\']',
                    html_text, re.I)
            if m:
                value = _clean(m.group(1))
                if value:
                    return value
    return None


def cmd_from_url(args) -> int:
    from urllib.parse import urljoin
    from urllib.request import Request, urlopen
    from urllib.error import URLError, HTTPError

    url = args.url
    if not url.startswith(("http://", "https://")):
        url = "https://" + url

    req = Request(url, headers={"User-Agent": "novoads-claude-code/1.0"})
    try:
        with urlopen(req, timeout=FETCH_TIMEOUT_SECONDS) as resp:
            page = resp.read(MAX_BYTES).decode("utf-8", errors="replace")
            final_url = resp.geturl()
    except (HTTPError, URLError, TimeoutError, OSError) as e:
        # Solve, don't punt: say what to do next instead of dying on a stack.
        print(f"error: could not fetch {url} ({e})", file=sys.stderr)
        print("Ask the user for the brand name and a product photo directly — "
              "that is the two-field minimum and it is enough to start.",
              file=sys.stderr)
        return 1

    title = None
    m = re.search(r"<title[^>]*>(.*?)</title>", page, re.I | re.S)
    if m:
        title = _clean(m.group(1))

    drafts: dict[str, str] = {}
    name = _meta(page, "og:site_name", "application-name")
    if not name and title:
        # "Acme — Best Widgets" / "Acme | Widgets" -> "Acme"
        name = re.split(r"\s+[|–—-]\s+", title)[0].strip()
    if name:
        drafts["brand.name"] = name

    one_liner = _meta(page, "og:description", "description", "twitter:description")
    if one_liner:
        drafts["brand.one_liner"] = one_liner

    color = _meta(page, "theme-color")
    if not color:
        hexes = re.findall(r"#[0-9a-fA-F]{6}\b", page)
        if hexes:
            seen, ordered = set(), []
            for h in (x.lower() for x in hexes):
                if h not in seen and h not in ("#ffffff", "#000000"):
                    seen.add(h)
                    ordered.append(h)
            if ordered:
                color = ", ".join(ordered[:3])
    if color:
        drafts["brand.colors"] = color

    candidates = []
    og_image = _meta(page, "og:image", "twitter:image")
    if og_image:
        candidates.append(("social/hero image", urljoin(final_url, og_image)))
    for m in re.finditer(
            r'<link[^>]+rel=["\'][^"\']*icon[^"\']*["\'][^>]+href=["\']([^"\']+)["\']',
            page, re.I):
        candidates.append(("icon (logo candidate)", urljoin(final_url, m.group(1))))

    print(f"# Draft brand block from {final_url}")
    print("# NOTHING IS WRITTEN. Confirm each line with the user, then run the "
          "`set` commands below.\n")
    if not drafts and not candidates:
        print("Nothing usable found on that page. Ask for the brand name and a "
              "product photo directly.")
        return 1

    for field, value in drafts.items():
        print(f"{field:24} {value}")
    if candidates:
        print("\n# Image candidates — DOWNLOAD AND LOOK BEFORE USING ANY OF THEM.")
        print("# A site hero is usually a lifestyle shot with text burned in. The")
        print("# clone skills need a clean packshot, and their product gate still")
        print("# applies to whatever you pick.")
        for kind, href in candidates[:4]:
            print(f"  {kind}: {href}")

    print("\n# After the user confirms:")
    for field, value in drafts.items():
        safe = value.replace("'", "'\\''")
        print(f"  ./scripts/brand-context.py set {field} '{safe}'")
    print("\n# Still needed, and not obtainable from a website:")
    print("  ./scripts/brand-context.py set product.photo <path to a clean packshot>")
    print("  ./scripts/brand-context.py set product.description '<one line>'")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        description="Read and write brand fields in MASTER_CONTEXT.md.")
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("get", help="print one field, exit 1 if unset")
    g.add_argument("field", choices=sorted(FIELDS))
    g.set_defaults(func=cmd_get)

    s = sub.add_parser("set", help="write one field, preserving the rest")
    s.add_argument("field", choices=sorted(FIELDS))
    s.add_argument("value", nargs="+")
    s.set_defaults(func=cmd_set)

    c = sub.add_parser("check", help="what a skill is missing; exit 2 if blocked")
    c.add_argument("skill", choices=sorted(list(REQUIREMENTS) + ["clone-image-ad"]))
    c.add_argument("--mode", choices=["ads", "template"], default="ads",
                   help="clone-image-ad only: what the run is producing")
    c.add_argument("--product-in-ad", choices=["yes", "no"], default=None,
                   help="clone-image-ad, ads mode: does the SOURCE ad show a "
                        "product? Judged by looking at it, not by the business")
    c.add_argument("--claims-in-ad", choices=["yes", "no", "testimonial"],
                   default=None,
                   help="clone-image-ad, ads mode: does the SOURCE ad carry a "
                        "number, a statistic or a named person's quote?")
    c.set_defaults(func=cmd_check)

    listing = sub.add_parser("list", help="every field and its value")
    listing.set_defaults(func=cmd_list)

    u = sub.add_parser(
        "from-url",
        help="draft brand fields from the user's own site. Writes NOTHING.")
    u.add_argument("url")
    u.set_defaults(func=cmd_from_url)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
