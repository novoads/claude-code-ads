#!/usr/bin/env python3
"""Executable evals for the shared image-ad prompt library. No network, no credits.

Runs the mechanical half of EVALS-image-ad-prompting.md against
`prompting/prompt-library.md` and the skills that consume it:

  L1  every template + the always-on suffixes fits the 4,000-char prompt cap
  L1b the library publishes how many templates still have room for the pin block
  L2  no template states two different counts for the same countable element
  L3  a template whose art must be numerically true carries the approximation note
  L4  every skill whose output has spoken audio carries the transcribe-verify step
  L5  every template has the fields the format requires, with a real aspect ratio
  L6  every doc that states a library template count states the real one

The three always-on safety suffixes are IMPORTED from the generator script rather
than restated here, so this file cannot drift from the script it is checking. If
someone edits a suffix, L1's arithmetic moves with it.

L1 carries a dated BASELINE of templates that already exceed the cap. They are
grandfathered, not forgiven: the list may only shrink. A template that is not on
it must fit, and a template on it that starts fitting fails until it is removed —
which is how a ratchet stays a ratchet instead of becoming a suppression list.
Nothing here edits a prompt to buy a green check; every body in this library is a
validated artifact, and trimming one costs a re-validation render to prove the
render did not change.

  python3 check_library.py [--verbose]

exit 0 = every check passed · 1 = a check failed · 2 = could not run
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIBRARY = HERE.parent / "prompting" / "prompt-library.md"
REPO = HERE.parents[3]  # shared/skills/image-ad-prompting/scripts -> repo root

# The model cap every image model on this API enforces. The API 400s above it,
# before anything is charged, so an overflow costs a round trip and not credits.
MAX_PROMPT_CHARS = 4000

# The standard pin block's invariant half — the guard clause from the library
# header. The variable half (the product description) is budgeted separately,
# because that is the part a run writes and therefore the part it can overrun.
PIN_GUARD_CHARS = 346
PIN_DESCRIPTION_BUDGET = 54  # a terse product description; 400 all-in
PIN_BLOCK_CHARS = PIN_GUARD_CHARS + PIN_DESCRIPTION_BUDGET

# The library header publishes how many templates still have room for that block.
# It is one number in prose, and this is what stops it going stale.
PIN_ROOM_SENTENCE = re.compile(
    r"\*\*(\d+) of the (\d+) templates\*\* have room for the standard pin block"
)

# Aspect ratios that exist on at least one model. A template asking for anything
# else is a 400 from a strict request schema.
KNOWN_RATIOS = {"1:1", "4:5", "2:3", "3:2", "3:4", "4:3", "5:4", "9:16", "16:9", "21:9"}

REQUIRED_FIELDS = ("When to use", "Aspect ratio", "Reference image", "Variables", "Model notes")

# ── L1 baseline ───────────────────────────────────────────────────────────────
# Measured 2026-08-06 against the shipped library: three templates that the
# generator REFUSES as written, before any brand fill and before any pin block.
# Each value is the template's prompt-body length; the entry is grandfathered
# only while the body is unchanged. Fixing one means trimming the body AND
# re-rendering it to prove the trim was cosmetic — then delete the row. See
# EVALS-image-ad-prompting.md L1.
BASELINE_OVER_CAP = {
    "T8": 2595,
    "T11": 2802,
    "T14": 2909,
}

# ── L3 registry ───────────────────────────────────────────────────────────────
# Templates whose art encodes a number the viewer can read off the picture — a
# bar length, a plotted line, a filled gauge. gpt-image-2 draws these
# approximately (measured ~9% overshoot on T38's own axis, 2026-08-06), so each
# must say so where the consuming skill reads it: in Model notes.
NUMERIC_ART_TEMPLATES = {"T17", "T38"}
NUMERIC_ART_PHRASE = "approximat"

# ── L4 registry ───────────────────────────────────────────────────────────────
# Skills whose deliverable contains speech. Each must carry the transcribe-verify
# step: a reference image pins the LABEL, nothing pins the AUDIO, and the two fail
# independently. Measured 2026-08-06 — three clones of one source spoke a coined
# brand name three different wrong ways while every on-screen glyph was perfect.
SPOKEN_AUDIO_SKILLS = (
    "skills/novoads-api/SKILL.md",
    "skills/novoads-api/prompting/clone-ad/SKILL.md",
    "skills/novoads-pixar-ad/SKILL.md",
    "skills/novoads-pixar-storyboard-ad/SKILL.md",
    "skills/novoads-claymation-storyboard-ad/SKILL.md",
)
TRANSCRIBE_PATTERN = re.compile(r"transcri(be|pt)", re.I)

COUNT_WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6}
# Countable conversation elements, normalised to one class per synonym group so
# "message bubbles" and "bubbles" are not read as two independent counts.
ELEMENT_CLASSES = {
    "bubble": "bubble",
    "bubbles": "bubble",
    "message bubble": "bubble",
    "message bubbles": "bubble",
    "message": "message",
    "messages": "message",
    "comment": "comment",
    "comments": "comment",
    "reply": "reply",
    "replies": "reply",
}
# T34 and T11 mix the two vocabularies for one physical stack of chat rows. Any
# template that defines rows as "BUBBLE n:" is counting bubbles whatever the prose
# calls them, so those synonyms collapse into the defined class.
CHAT_CLASSES = {"bubble", "message", "comment", "reply"}


def load_suffixes() -> dict[str, str]:
    """The three always-on suffixes, read from the generator that appends them."""
    script = REPO / "skills" / "chatgpt-image-ad" / "scripts" / "generate_image.py"
    if not script.exists():
        raise SystemExit(f"error: cannot find the generator script at {script}")
    spec = importlib.util.spec_from_file_location("_gen", script)
    module = importlib.util.module_from_spec(spec)
    sys.argv = [str(script)]  # the module parses args only under __main__
    spec.loader.exec_module(module)
    return {
        "NO_CHROME": module.NO_CHROME_SUFFIX,
        "SAFE_ZONE": module.SAFE_ZONE_SUFFIX,
        "GLYPH_SAFETY": module.GLYPH_SAFETY_SUFFIX,
    }


def parse_templates(text: str) -> list[dict]:
    """Every `## T<n> — title` section with its prompt body and field set."""
    out = []
    for section in re.split(r"\n(?=## T\d+ — )", text):
        head = re.match(r"## (T\d+) — (.*)", section)
        if not head:
            continue
        body = re.search(
            r"\*\*Template prompt\*?\*?:?\*?\*?[^\n]*\n```\n(.*?)\n```", section, re.S
        )
        ratio = re.search(r"\*\*Aspect ratio:\*\*\s*`([^`]+)`", section)
        notes = re.search(r"\*\*Model notes:\*\*(.*?)(?=\n---|\Z)", section, re.S)
        out.append(
            {
                "tag": head.group(1),
                "title": head.group(2).strip(),
                "prompt": body.group(1) if body else None,
                "ratio": ratio.group(1) if ratio else None,
                "notes": notes.group(1) if notes else "",
                "section": section,
            }
        )
    return out


def stated_counts(prompt: str) -> dict[str, set[int]]:
    """Counts the prose asserts, e.g. 'EXACTLY THREE message bubbles' -> bubble:3."""
    found: dict[str, set[int]] = {}
    pattern = re.compile(
        r"\b(?:exactly\s+|exact\s+)?(" + "|".join(COUNT_WORDS) + r"|\d+)[\s-]+"
        r"(message bubbles|message bubble|bubbles|bubble|messages|message|"
        r"comments|comment|replies|reply)\b",
        re.I,
    )
    for raw, noun in pattern.findall(prompt):
        raw = raw.lower()
        n = COUNT_WORDS.get(raw, int(raw) if raw.isdigit() else None)
        if n is None:
            continue
        cls = ELEMENT_CLASSES[noun.lower()]
        found.setdefault(cls, set()).add(n)
    return found


def defined_count(prompt: str) -> tuple[str | None, int]:
    """Highest index of an explicitly defined row, e.g. 'BUBBLE 4:' -> (bubble, 4)."""
    best_cls, best_n = None, 0
    for cls_word, n in re.findall(r"^(BUBBLE|MESSAGE|COMMENT|REPLY)\s+(\d+)\s*[:(]", prompt, re.M):
        cls = ELEMENT_CLASSES[cls_word.lower()]
        if int(n) > best_n:
            best_cls, best_n = cls, int(n)
    return best_cls, best_n


def selftest() -> int:
    """Prove each check fires. A check that cannot fail is not a check.

    Every case is a mutation of the real library text, held in memory — nothing
    is written, so this runs against the shipped file without touching it.
    """
    text = LIBRARY.read_text()
    cases: list[tuple[str, bool]] = []

    # L2 — the T34 regression: reintroduce the upstream "THREE" opener.
    broken = text.replace("EXACTLY FOUR message bubbles", "EXACTLY THREE message bubbles", 1)
    t34 = next(t for t in parse_templates(broken) if t["tag"] == "T34")
    counts = {n for c, ns in stated_counts(t34["prompt"]).items() if c in CHAT_CLASSES for n in ns}
    cls, defined = defined_count(t34["prompt"])
    cases.append(("L2 catches a reintroduced conflicting count", len(counts) > 1 and defined == 4))

    # L2 — the prose stays self-consistent at four while a row goes missing. This
    # exercises the second branch: one stated count, and it is not the number of
    # rows the prompt actually defines. Dropping a bubble is the realistic edit.
    skewed = text.replace("BUBBLE 4 (incoming", "BUBBLE (incoming", 1)
    t34b = next(t for t in parse_templates(skewed) if t["tag"] == "T34")
    c2 = {n for c, ns in stated_counts(t34b["prompt"]).items() if c in CHAT_CLASSES for n in ns}
    _, d2 = defined_count(t34b["prompt"])
    cases.append(("L2 catches a stated count the rows do not match",
                  len(c2) == 1 and d2 not in c2))

    # L2 — the fixed library really is consistent (no false positive).
    ok = True
    for t in parse_templates(text):
        if not t["prompt"]:
            continue
        cc = {n for c, ns in stated_counts(t["prompt"]).items() if c in CHAT_CLASSES for n in ns}
        _, dd = defined_count(t["prompt"])
        if dd and len(cc) > 1:
            ok = False
    cases.append(("L2 is silent on the library as shipped", ok))

    # L1 — a body one character over the cap is caught; the baseline is exact.
    suffix_chars = sum(len(s) for s in load_suffixes().values())
    room = MAX_PROMPT_CHARS - suffix_chars
    cases.append(("L1 arithmetic matches the generator's own gate", room == 2425))
    bodies = {t["tag"]: len(t["prompt"]) for t in parse_templates(text) if t["prompt"]}
    cases.append(("L1 baseline lengths are the measured lengths",
                  all(bodies.get(k) == v for k, v in BASELINE_OVER_CAP.items())))
    cases.append(("L1 baseline is exactly the set over the cap",
                  {k for k, v in bodies.items() if v > room} == set(BASELINE_OVER_CAP)))

    # L1b — the published number moves when the library does.
    stated_pin = PIN_ROOM_SENTENCE.search(text)
    measured = sum(1 for v in bodies.values() if v <= room - PIN_BLOCK_CHARS)
    cases.append(("L1b header number is present and correct",
                  bool(stated_pin) and int(stated_pin.group(1)) == measured))

    # L3 — losing the limit from T38's Model notes fails. The whole paragraph has
    # to go, which is what a well-meaning "tighten the docs" edit would actually do.
    t38_live = next(t for t in parse_templates(text) if t["tag"] == "T38")
    stripped = text.replace(t38_live["notes"], "\n- **gpt-image-2:** clean.\n", 1)
    t38 = next(t for t in parse_templates(stripped) if t["tag"] == "T38")
    cases.append(("L3 catches a dropped approximation note",
                  NUMERIC_ART_PHRASE in t38_live["notes"].lower()
                  and NUMERIC_ART_PHRASE not in t38["notes"].lower()))

    # L4 — the registry points at files that exist and every one mentions it.
    cases.append(("L4 registry paths all resolve",
                  all((REPO / p).exists() for p in SPOKEN_AUDIO_SKILLS)))

    # L6 — a stale count is caught, and a run size is not mistaken for one.
    count_claim = re.compile(r"\b(\d+)[- ](?:ready-to-use )?validated"
                             r"(?: full| prompt| parameterizable| ad)?[- ](?:templates?|prompts)\b")
    run_size = re.compile(r"\b(\d+)-template run\b")
    cases.append(("L6 catches a stale library count",
                  count_claim.findall("a 37-template library of 37 validated templates") == ["37"]))
    cases.append(("L6 leaves a measured run size alone",
                  not count_claim.findall("across 34 templates on one real product")
                  and run_size.findall("the 34-template run") == ["34"]))

    width = max(len(n) for n, _ in cases)
    failed = 0
    print("\nselftest — each row proves a check can fail\n")
    for name, passed in cases:
        print(f"  {'PASS' if passed else 'FAIL'}  {name:<{width}}")
        failed += not passed
    print()
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--verbose", action="store_true", help="print every template's budget")
    ap.add_argument("--selftest", action="store_true", help="prove each check can fail")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    if not LIBRARY.exists():
        print(f"error: no library at {LIBRARY}", file=sys.stderr)
        return 2

    suffixes = load_suffixes()
    suffix_chars = sum(len(s) for s in suffixes.values())
    templates = parse_templates(LIBRARY.read_text())
    if not templates:
        print("error: parsed zero templates — the library format changed", file=sys.stderr)
        return 2

    failures: list[str] = []
    notes: list[str] = []

    # ── L1 — the template is usable at all ───────────────────────────────────
    # The generator appends the suffixes and refuses above the cap, so a body
    # over this line cannot be sent verbatim by anyone, for any brand.
    room_bare = MAX_PROMPT_CHARS - suffix_chars
    room_pinned = room_bare - PIN_BLOCK_CHARS
    if args.verbose:
        print(f"cap {MAX_PROMPT_CHARS} − suffixes {suffix_chars} = {room_bare} for a body")
        print(f"  …minus the standard pin block ({PIN_BLOCK_CHARS}) = {room_pinned} pinned\n")
    over_bare, over_pinned = set(), set()
    for t in templates:
        if t["prompt"] is None:
            failures.append(f"L1 {t['tag']} — no template prompt block to measure")
            continue
        n = len(t["prompt"])
        if args.verbose:
            state = "OVER CAP" if n > room_bare else (
                "no pin room" if n > room_pinned else f"{room_pinned - n} spare pinned")
            print(f"  {t['tag']:<4} body {n:>5}  {state}")
        if n > room_pinned:
            over_pinned.add(t["tag"])
        if n <= room_bare:
            if t["tag"] in BASELINE_OVER_CAP:
                failures.append(
                    f"L1 {t['tag']} — now fits ({n} chars) but is still in BASELINE_OVER_CAP. "
                    f"Delete the row; the baseline may only shrink."
                )
            continue
        over_bare.add(t["tag"])
        if t["tag"] not in BASELINE_OVER_CAP:
            failures.append(
                f"L1 {t['tag']} — body is {n} chars; with the always-on suffixes ({suffix_chars}) "
                f"that is {n + suffix_chars}, over the {MAX_PROMPT_CHARS} cap by "
                f"{n + suffix_chars - MAX_PROMPT_CHARS}. The generator refuses this template as "
                f"written, for every brand. Trim it, or baseline it with the reason."
            )
        elif BASELINE_OVER_CAP[t["tag"]] != n:
            failures.append(
                f"L1 {t['tag']} — body changed from the baselined {BASELINE_OVER_CAP[t['tag']]} "
                f"to {n} chars while still over the cap. Re-measure and update the baseline."
            )
    for tag in BASELINE_OVER_CAP:
        if tag not in {t["tag"] for t in templates}:
            failures.append(f"L1 {tag} — baselined but no longer in the library; delete the row")
    if over_bare:
        notes.append(
            f"L1: {len(over_bare)} template(s) exceed the cap as written "
            f"({', '.join(sorted(over_bare, key=lambda s: int(s[1:])))}) — grandfathered, see EVALS L1"
        )

    # ── L1b — the published pin-block headroom is the measured one ───────────
    # Half the library is too long to carry the pin block the library itself
    # makes mandatory. That is a fact a run needs BEFORE it writes a fill, so it
    # is published in the header — and this is what stops the number going stale.
    with_room = len(templates) - len(over_pinned)
    stated = PIN_ROOM_SENTENCE.search(LIBRARY.read_text())
    if not stated:
        failures.append(
            f"L1b — the library header no longer states the pin-block headroom. Restore the "
            f"sentence '**{with_room} of the {len(templates)} templates** have room for the "
            f"standard pin block'."
        )
    elif (int(stated.group(1)), int(stated.group(2))) != (with_room, len(templates)):
        failures.append(
            f"L1b — the header says {stated.group(1)} of {stated.group(2)} templates have room "
            f"for the standard pin block; measured {with_room} of {len(templates)}."
        )

    # ── L2 — one count per countable element ─────────────────────────────────
    for t in templates:
        if not t["prompt"]:
            continue
        stated = stated_counts(t["prompt"])
        cls, defined = defined_count(t["prompt"])
        chat_counts = {n for c, ns in stated.items() if c in CHAT_CLASSES for n in ns}
        if cls and defined:
            if len(chat_counts) > 1:
                failures.append(
                    f"L2 {t['tag']} — the prompt states {sorted(chat_counts)} for one stack of "
                    f"chat rows while defining {defined} of them. GLYPH_SAFETY_SUFFIX enforces "
                    f"'the EXACT count the prompt specifies' and is being handed two."
                )
            elif chat_counts and defined not in chat_counts:
                failures.append(
                    f"L2 {t['tag']} — the prompt states {sorted(chat_counts)[0]} chat rows but "
                    f"defines {defined} ({cls.upper()} 1..{defined})."
                )
        for element, counts in stated.items():
            if element in CHAT_CLASSES:
                continue
            if len(counts) > 1:
                failures.append(
                    f"L2 {t['tag']} — two different counts stated for '{element}': {sorted(counts)}"
                )

    # ── L3 — numerically-true art is a documented limit ──────────────────────
    by_tag = {t["tag"]: t for t in templates}
    for tag in sorted(NUMERIC_ART_TEMPLATES, key=lambda s: int(s[1:])):
        t = by_tag.get(tag)
        if not t:
            failures.append(f"L3 {tag} — registered as numeric art but not in the library")
            continue
        if NUMERIC_ART_PHRASE not in t["notes"].lower():
            failures.append(
                f"L3 {tag} — draws a value the viewer reads off the picture, but Model notes "
                f"never says the model draws it approximately. Record the limit where the "
                f"consuming skill reads it."
            )

    # ── L4 — spoken audio implies transcribe-verify ──────────────────────────
    for rel in SPOKEN_AUDIO_SKILLS:
        path = REPO / rel
        if not path.exists():
            failures.append(f"L4 {rel} — registered as a spoken-audio skill but missing")
            continue
        if not TRANSCRIBE_PATTERN.search(path.read_text()):
            failures.append(
                f"L4 {rel} — ships spoken audio with no transcribe-verify step. A reference "
                f"asset pins the label, not the voice."
            )

    # ── L6 — every stated template count is the real one ─────────────────────
    # The library said "37 templates" in 26 places across 12 files while shipping
    # 40: T40-T42 were appended and no counter moved. Every one of those claims is
    # load-bearing — a session reads "37 validated templates" and stops looking.
    # A claim must name the LIBRARY, not a run. "34 templates on one real product"
    # is a measured historical fact and stays 34 forever; "34 validated templates"
    # would be a lie about the file. The patterns below only match the latter.
    counted = len(templates)
    claims = [
        re.compile(r"\b(\d+)[- ](?:ready-to-use )?validated"
                   r"(?: full| prompt| parameterizable| ad)?[- ](?:templates?|prompts)\b"),
        re.compile(r"\b(\d+)-template (?:image-ad )?library\b"),
        re.compile(r"\b(\d+) templates in this file\b"),
    ]
    for path in sorted(REPO.rglob("*")):
        if path.is_dir() or path.suffix not in {".md", ".sh"} or ".git" in path.parts:
            continue
        for line_no, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
            for claim in claims:
                for stated in claim.findall(line):
                    if int(stated) != counted:
                        failures.append(
                            f"L6 {path.relative_to(REPO)}:{line_no} — claims {stated} library "
                            f"templates; the library has {counted}"
                        )

    # ── L5 — the entry format holds ──────────────────────────────────────────
    for t in templates:
        for field in REQUIRED_FIELDS:
            if f"**{field}" not in t["section"]:
                failures.append(f"L5 {t['tag']} — missing the '{field}' field")
        if t["ratio"] and t["ratio"] not in KNOWN_RATIOS:
            failures.append(f"L5 {t['tag']} — aspect ratio '{t['ratio']}' is on no model's grid")

    print(f"\nchecked {len(templates)} templates in {LIBRARY.name}")
    for n in notes:
        print(f"  note: {n}")
    if failures:
        print(f"\n{len(failures)} failure(s):\n", file=sys.stderr)
        for f in failures:
            print(f"  · {f}", file=sys.stderr)
        print("", file=sys.stderr)
        return 1
    print("  L1 prompt cap · L1b pin headroom · L2 element counts · L3 documented limits · "
          "L4 transcribe-verify · L5 entry format · L6 stated counts — all pass\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
