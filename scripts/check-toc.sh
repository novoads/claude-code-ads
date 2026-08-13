#!/usr/bin/env bash
# A table of contents must describe the file it sits in.
#
# The two biggest reference files got a `## Contents` in #90 because they are too
# long to skim: 2,111 lines and 1,055. A TOC in a file that size is not a
# courtesy, it is the index an agent uses to decide which 40 lines to read. So it
# has exactly one failure mode worth guarding, and it is silent both ways:
#
#   an entry pointing at a heading that is gone   the agent follows it, finds
#                                                 nothing, and either reads the
#                                                 whole file or gives up on the
#                                                 section it was sent to.
#
#   a heading that no entry lists                 the section is invisible. It is
#                                                 in the file, it is correct, and
#                                                 nothing will ever route to it.
#
# Both happen the same way: someone renames or adds a section and does not scroll
# back up. Neither is visible in a diff, because the TOC is hundreds of lines away
# from the change.
#
# Two checks, deliberately different severities:
#
#   FAIL  a file that HAS a TOC must have a correct one. Opting in is a promise.
#   warn  a long file with no TOC at all. 57 files are over 100 lines and only
#         three carry one; failing on that would redden main for a decision
#         nobody has made yet, and a guard that arrives with 57 violations is a
#         guard that gets deleted. Warn names them and lets the fixing happen at
#         whatever pace it happens.
#
# Usage: ./scripts/check-toc.sh   (exit 0 clean, 1 if a TOC is wrong)
set -uo pipefail
cd "$(dirname "$0")/.."

LONG_FILE_LINES=100

read -r -d '' PY_TOC <<'PY' || true
import re, subprocess, sys

LONG = 100
FENCE = chr(96) * 3


def slug(text):
    """GitHub's anchor rule: lowercase, strip anything but word chars, spaces and
    hyphens, then spaces to hyphens. Inline markdown is stripped first so that a
    heading like `## The `credits` field` slugs the way the renderer slugs it."""
    text = re.sub(r'`([^`]*)`', r'\1', text)
    text = re.sub(r'\*\*([^*]*)\*\*', r'\1', text)
    text = re.sub(r'\*([^*]*)\*', r'\1', text)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = text.strip().lower()
    text = re.sub(r'[^\w\s-]', '', text)
    # Each space becomes its own hyphen; runs are NOT collapsed. This is the
    # detail that matters: "T1 — Apple Notes" drops the em dash and keeps both
    # surrounding spaces, so the real anchor is "t1--apple-notes" with a double
    # hyphen. Collapsing the run produces "t1-apple-notes" and reports all
    # fourteen correct entries in the prompt library as broken.
    return re.sub(r'\s', '-', text).strip('-')


files = [f for f in subprocess.run(
    ["git", "ls-files", "*.md"], capture_output=True, text=True).stdout.split()
    if f.startswith(("skills/", "shared/"))]

problems = 0
warnings = 0
checked = 0

for path in sorted(files):
    lines = open(path).read().split("\n")

    headings = []          # (level, text, slug)
    toc_entries = []       # (anchor, label, lineno)
    in_toc = False
    fenced = False

    for lineno, line in enumerate(lines, 1):
        if line.lstrip().startswith(FENCE):
            fenced = not fenced
            continue
        if fenced:
            continue

        m = re.match(r'^(#{2,3})\s+(.*\S)\s*$', line)
        if m:
            level, text = len(m.group(1)), m.group(2)
            # The Contents heading itself is never one of its own entries.
            in_toc = (text.strip().lower() == "contents")
            if not in_toc:
                headings.append((level, text, slug(text)))
            continue

        if in_toc:
            link = re.match(r'^\s*[-*]\s*\[([^\]]+)\]\(#([^)]+)\)\s*$', line)
            if link:
                toc_entries.append((link.group(2), link.group(1), lineno))

    if not toc_entries:
        if len(lines) > LONG:
            print(f"WARN\t{path}\t{len(lines)} lines, no '## Contents' table of contents")
            warnings += 1
        continue

    checked += 1

    # GitHub disambiguates repeated headings by suffixing -1, -2, ... in document
    # order, so five "Failure modes" sections yield failure-modes, failure-modes-1
    # ... failure-modes-4. Without this, every anchor into a repeated heading
    # reads as broken — and this file has five of them.
    have = set()
    seen = {}
    for _, _, s in headings:
        n = seen.get(s, 0)
        have.add(s if n == 0 else f"{s}-{n}")
        seen[s] = n + 1

    listed = {a for a, _, _ in toc_entries}

    for anchor, label, lineno in toc_entries:
        if anchor not in have:
            print(f"FAIL\t{path}:{lineno}\tentry '{label}' -> #{anchor} matches no heading")
            problems += 1

    # Completeness is required at H2 only. Both TOCs shipped in #90 are H2-level
    # section indexes — reference.md carries five "Failure modes" H3s and a
    # "Pricing" H3 per endpoint, and listing those would turn a 45-line index
    # into a second copy of the document. Demanding it would fail the two files
    # the feature shipped with, which is a guard disagreeing with the design
    # rather than protecting it. H3s may be listed and are checked when they are;
    # they are not required.
    for level, text, s in headings:
        if level == 2 and s not in listed:
            print(f"FAIL\t{path}\tH2 '{text}' is in no TOC entry")
            problems += 1

print(f"SUMMARY\t{checked}\t{problems}\t{warnings}")
PY

OUT="$(printf '%s' "$PY_TOC" | python3 -)"

fail=0
while IFS=$'\t' read -r kind a b c; do
  case "$kind" in
    WARN) echo "warn  $a: $b" ;;
    FAIL) echo "FAIL  $a: $b"; fail=$((fail + 1)) ;;
    SUMMARY)
      echo
      [ "$c" -gt 0 ] && echo "$c file(s) over $LONG_FILE_LINES lines carry no table of contents (warning only)"
      if [ "$b" -gt 0 ]; then
        echo "$b TOC problem(s) across $a file(s) that have one" >&2
        echo "A file that opts into a TOC promises it is complete and resolvable." >&2
      else
        echo "OK: $a table(s) of contents, every entry resolves and every H2 is listed."
      fi
      ;;
  esac
done <<< "$OUT"

# exit 1, never `exit $fail`. An exit status is one byte: a count of 256 problems
# would exit 0 and report the tree clean at exactly the moment it is worst.
[ "$fail" -gt 0 ] && exit 1
exit 0
