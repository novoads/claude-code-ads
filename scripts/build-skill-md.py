#!/usr/bin/env python3
"""Build the storyboard skills' SKILL.md from their sections/ directories.

Why a generator, and why only for these two: pixar-ad is 1,124 lines.
Nobody hand-edits a document that size safely -- a change to Gate 7's mix levels
lands in the same file as the routing description, the diff is unreadable, and
two people editing different gates conflict over a file neither of them touched
the same part of. So the sections become the source and the SKILL.md becomes a
build artifact. The rest of the pack's skills are short enough to edit directly
and are deliberately NOT wired through here; this is the escape hatch for a file
that outgrew hand authorship, not a new house style.

WHAT IT IS NOT: a templating language. The concatenation is dumb on purpose --
manifest order, verbatim bytes, one substitution. Every clever thing a generator
could do to a skill file is a way for the shipped text to differ from the text
someone reviewed.

The one substitution is {{PACK_VERSION}}, resolved from the repo's VERSION file.
It exists because scripts/release.sh stamps `metadata.packVersion` directly into
every SKILL.md. Without the placeholder there would be two writers for that one
line, and the release commit itself would leave the generated file out of sync
with its own sections -- CI red on the release PR, every release. With it, the
generator reads what release.sh just wrote to VERSION and lands on the same
bytes.

Section files are `.md.in`, not `.md`, and that is load-bearing. Their relative
links (`references/formulas.md`, `../novoads-api/SKILL.md`) are written for the
depth SKILL.md sits at, one directory up, so check-links.sh would resolve every
one of them from sections/ and report the lot as broken. `.md.in` keeps the
build inputs out of every guard that globs `*.md`, and leaves the generated
SKILL.md as the single document those guards see.

The AUTO-GENERATED banner is injected AFTER the frontmatter block, not at byte
zero. That is not a stylistic choice: scripts/release.sh only recognises a file
whose first four bytes are `---\\n`, so a banner above the frontmatter would make
every stamping pass silently SKIP these two skills.

Usage
  build-skill-md.py                  write skills/*/SKILL.md from sections/
  build-skill-md.py --check          build in memory; exit 1 if the file on disk
                                     differs (this is what CI runs)
  build-skill-md.py --list           print the section map and exit

Exit codes
  0  ok
  1  --check found a SKILL.md that does not match its sections
  2  the sections themselves are malformed (missing file, manifest drift,
     unresolved placeholder, frontmatter not where it must be)
"""

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = REPO_ROOT / "VERSION"

# The skills whose SKILL.md is generated. Adding one here is a deliberate act:
# it takes that file out of hand-editing for good.
GENERATED_SKILLS = [
    "pixar-ad",
    "claymation-ad",
]

SECTION_GLOB = "*.md.in"

# A directive line. `#!` cannot open an ATX heading (markdown wants a space after
# the hashes) and no line in either body starts with it, so the prefix can never
# collide with content that is meant to be emitted.
DIRECTIVE = re.compile(r"^#!(?:\s+(?P<key>[a-z]+):\s*(?P<value>.*?)\s*)?$")

PLACEHOLDER = re.compile(r"\{\{([A-Z_]+)\}\}")

BANNER = (
    "<!-- AUTO-GENERATED FILE. Do not edit it: the next build overwrites you.\n"
    "     Source of truth is sections/, registered in sections/manifest.json.\n"
    "     Edit the section, then run: python3 scripts/build-skill-md.py -->\n"
)


class SectionError(Exception):
    """The sections are malformed. Exit 2, never a diff."""


def pack_version() -> str:
    return VERSION_FILE.read_text(encoding="utf-8").strip()


def read_section(path: Path) -> tuple[dict[str, str], str]:
    """Split a section file into its `#!` header and its verbatim body.

    Everything after the last directive line is emitted byte for byte. No blank
    line is consumed and none is added -- the slices have to tile the output
    exactly, so the generator is not allowed an opinion about whitespace.
    """
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    header: dict[str, str] = {}
    i = 0
    for i, line in enumerate(lines):  # noqa: B007 - i is used after the loop
        if not line.startswith("#!"):
            break
        m = DIRECTIVE.match(line.rstrip("\n"))
        if not m:
            raise SectionError(f"{path}: unreadable directive line: {line.rstrip()}")
        if m.group("key"):
            header[m.group("key")] = m.group("value")
    else:
        i = len(lines)
    if not header:
        raise SectionError(f"{path}: no `#!` header. Every section names its id, title and read cue.")
    for key in ("section", "title", "read"):
        if key not in header:
            raise SectionError(f"{path}: header is missing `#! {key}:`")
    return header, "".join(lines[i:])


def load(skill: str) -> tuple[list[dict], Path]:
    sections_dir = REPO_ROOT / "skills" / skill / "sections"
    manifest_path = sections_dir / "manifest.json"
    if not manifest_path.is_file():
        raise SectionError(f"{manifest_path}: no manifest")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("skill") != skill:
        raise SectionError(f"{manifest_path}: `skill` says {manifest.get('skill')!r}, not {skill!r}")

    entries = manifest.get("sections") or []
    if not entries:
        raise SectionError(f"{manifest_path}: no sections listed")
    if entries[0]["id"] != "frontmatter":
        raise SectionError(
            f"{manifest_path}: the first section must be `frontmatter` -- the banner is injected "
            "after it, and release.sh only stamps a file that opens with the frontmatter block"
        )

    listed = [e["file"] for e in entries]
    if len(set(listed)) != len(listed):
        raise SectionError(f"{manifest_path}: a section file is listed twice")
    on_disk = sorted(p.name for p in sections_dir.glob(SECTION_GLOB))
    orphans = sorted(set(on_disk) - set(listed))
    if orphans:
        raise SectionError(
            f"{manifest_path}: {', '.join(orphans)} sit in sections/ and are in no manifest row, "
            "so nothing would ever read them. List them or delete them."
        )

    out = []
    for entry in entries:
        path = sections_dir / entry["file"]
        if not path.is_file():
            raise SectionError(f"{manifest_path}: lists {entry['file']}, which is not there")
        header, body = read_section(path)
        # The manifest and the section header say the same three things. That is
        # duplication on purpose -- the header is what an editor sees when they
        # open the file, the manifest is what they see when they are looking for
        # it -- so the generator holds them equal rather than trusting nobody
        # will drift them.
        for man_key, hdr_key in (("id", "section"), ("title", "title"), ("trigger", "read")):
            if entry.get(man_key) != header[hdr_key]:
                raise SectionError(
                    f"{path}: `#! {hdr_key}:` reads {header[hdr_key]!r} but the manifest's "
                    f"`{man_key}` reads {entry.get(man_key)!r}. Make them agree."
                )
        out.append({**entry, "path": path, "body": body})
    return out, REPO_ROOT / "skills" / skill / "SKILL.md"


def build(skill: str) -> tuple[str, Path, list[dict]]:
    sections, target = load(skill)
    version = pack_version()

    front = sections[0]["body"]
    if not front.startswith("---\n") or "\n---\n" not in front:
        raise SectionError(
            f"{sections[0]['path']}: the frontmatter section must open with `---` and close with `---`"
        )
    rest = "".join(s["body"] for s in sections[1:])
    text = front + BANNER + rest

    text = PLACEHOLDER.sub(lambda m: version if m.group(1) == "PACK_VERSION" else m.group(0), text)
    left = sorted(set(PLACEHOLDER.findall(text)))
    if left:
        raise SectionError(
            f"{skill}: unresolved placeholder(s) {', '.join('{{%s}}' % p for p in left)} -- "
            "the only one this generator resolves is {{PACK_VERSION}}"
        )
    return text, target, sections


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="do not write; exit 1 if a SKILL.md differs from its sections")
    ap.add_argument("--list", action="store_true", help="print the section map and exit")
    args = ap.parse_args()

    stale = 0
    for skill in GENERATED_SKILLS:
        try:
            text, target, sections = build(skill)
        except (SectionError, KeyError, json.JSONDecodeError) as exc:
            print(f"MALFORMED  {exc}", file=sys.stderr)
            return 2

        if args.list:
            print(f"{skill}  ({len(sections)} sections -> {target.relative_to(REPO_ROOT)})")
            for s in sections:
                print(f"  {s['file']:<32} {s['id']:<20} {s['trigger']}")
            print()
            continue

        current = target.read_text(encoding="utf-8") if target.is_file() else ""
        if args.check:
            if current == text:
                print(f"OK         {target.relative_to(REPO_ROOT)} matches its sections")
                continue
            stale += 1
            print(f"STALE      {target.relative_to(REPO_ROOT)} does not match sections/")
            print("           Someone edited the generated file, or edited a section and did not rebuild.")
            print("           Fix: put the change in the section, then run scripts/build-skill-md.py")
            diff = list(difflib.unified_diff(
                current.splitlines(keepends=True), text.splitlines(keepends=True),
                fromfile="on disk", tofile="from sections/", n=1))
            sys.stdout.writelines(diff[:40])
            if len(diff) > 40:
                print(f"           ... {len(diff) - 40} more diff line(s)")
        else:
            wrote = current != text
            target.write_text(text, encoding="utf-8")
            print(f"{'wrote     ' if wrote else 'unchanged '} {target.relative_to(REPO_ROOT)} "
                  f"({len(sections)} sections, {len(text.splitlines())} lines)")

    if args.check and stale:
        print(f"\n{stale} generated SKILL.md file(s) out of date with sections/")
        return 1
    if args.check:
        print("\nOK: every generated SKILL.md matches the sections it is built from.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
