#!/usr/bin/env bash
# Unit tests for brand-context.py. Spends nothing, touches no network.
#
# Run before changing the script or the MASTER_CONTEXT template. Every case
# below is a real failure mode: the first one caught a regex that swallowed a
# newline and reported the NEXT field's label as this field's value, which made
# an empty template look fully populated.
set -uo pipefail

cd "$(dirname "$0")/.."
B=./scripts/brand-context.py
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -f "$WORK.bak" ] && mv "$WORK.bak" MASTER_CONTEXT.md' EXIT

# Preserve a real MASTER_CONTEXT.md if the user has one.
[ -f MASTER_CONTEXT.md ] && cp MASTER_CONTEXT.md "$WORK.bak"

pass=0; fail=0
ok()   { printf '  ok    %-4s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %-4s %s\n' "$1" "$2"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1" "$4"; else bad "$1" "$4 (want '$3', got '$2')"; fi; }

fresh() { rm -f MASTER_CONTEXT.md; $B list >/dev/null 2>&1; }

echo "brand-context tests"

# U1 -- an empty template reports every field unset.
# The regression: `\s*` matched across the newline, so `- **Tone:**` captured
# the following line and every field read as populated on a clean checkout.
fresh
set_count=$($B list 2>/dev/null | grep -cv '(unset)')
check U1 "$set_count" "0" "empty template has no set fields"

# U2 -- check blocks on a clean checkout, exit 2.
fresh
$B check clone-static >/dev/null 2>&1
check U2 "$?" "2" "check exits 2 when blocked"

# U3 -- check names ONLY the blocking fields. A check that demands optional
# fields turns lazy-fill back into an interview.
fresh
missing=$($B check clone-static 2>/dev/null | grep -c '^MISSING')
check U3 "$missing" "2" "exactly the two blocking fields are missing"

# U4 -- once the blocking fields are set, check passes with optionals absent.
fresh
$B set product.photo p.png >/dev/null
$B set product.description "a thing" >/dev/null
$B check clone-static >/dev/null 2>&1
check U4 "$?" "0" "check passes on blocking fields alone"

# U5 -- get on an unset field exits 1 and prints nothing on stdout.
fresh
out=$($B get brand.tone 2>/dev/null)
rc=$?
check U5 "$rc:$out" "1:" "get on unset exits 1, stdout empty"

# U6 -- set is idempotent.
fresh
$B set brand.name Acme >/dev/null
check U6 "$($B set brand.name Acme)" "unchanged: brand.name" "re-set is a no-op"

# U7 -- an overwrite is announced, never silent. This is the one operation
# that can destroy something the user typed.
fresh
$B set brand.name Acme >/dev/null
check U7 "$($B set brand.name Other | cut -d' ' -f1)" "CHANGED" "overwrite is announced"

# U8 -- filling a label the template already carries edits THAT line, in place.
# The template ships `- **Tone:**` empty. Appending a second Tone line instead
# would leave the file with two, and a later reader would pick the first.
fresh
cp MASTER_CONTEXT.md "$WORK/before.md"
$B set brand.tone "direct, warm" >/dev/null
changed=$(diff "$WORK/before.md" MASTER_CONTEXT.md | grep -c '^[<>]')
dupes=$(grep -c '^\- \*\*Tone:' MASTER_CONTEXT.md)
check U8 "$changed:$dupes" "2:1" "an existing label is filled in place, not duplicated"

# U8b -- a field with no line anywhere is appended, and nothing above it moves.
# The template now carries every label, so this path only fires on a file
# someone has edited down. Delete the line to reach it.
fresh
grep -v '^\- \*\*Product photo:' MASTER_CONTEXT.md > "$WORK/trimmed.md"
cp "$WORK/trimmed.md" MASTER_CONTEXT.md
$B set product.photo p.png >/dev/null
# The insert lands inside the Brand context section, which sits mid-file, so a
# prefix comparison is the wrong shape. Assert the real property instead: every
# existing line survives, in order, and exactly one line is added.
removed=$(diff "$WORK/trimmed.md" MASTER_CONTEXT.md | grep -c '^<')
added=$(diff "$WORK/trimmed.md" MASTER_CONTEXT.md | grep -c '^>')
check U8b "$removed:$added" "0:1" "an added field removes nothing and adds one line"

# U8c -- every field the template ships has a label this script recognises.
# The failure this catches is a rename on one side only: the template says
# "Words to use / avoid", the script looks for "Words to use", and the field
# silently reads as unset forever.
fresh
unmatched=0
for f in $($B list | awk '{print $1}'); do
  $B set "$f" "probe-value" >/dev/null 2>&1
  grep -c "probe-value" MASTER_CONTEXT.md >/dev/null || unmatched=$((unmatched+1))
done
dupe_labels=$(grep -o '^\- \*\*[^:*]*:' MASTER_CONTEXT.md | sort | uniq -d | wc -l | tr -d ' ')
check U8c "$unmatched:$dupe_labels" "0:0" "every field maps to exactly one template line"

# U9 -- a missing file is created rather than erroring. Solve, don't punt.
rm -f MASTER_CONTEXT.md
$B get brand.name >/dev/null 2>&1
if [ -f MASTER_CONTEXT.md ]; then ok U9 "a missing file is created from the template"
else bad U9 "a missing file was not created"; fi

# U10 -- an empty value is refused. Empty is what unset means; writing it
# would make `get` report a field as set with nothing in it.
fresh
$B set brand.name "" >/dev/null 2>&1
check U10 "$?" "2" "an empty value is refused"

# U11 -- multi-word values survive unquoted argv (the shape agents type).
fresh
$B set brand.sample_phrasings "Ship it. Then measure." >/dev/null
check U11 "$($B get brand.sample_phrasings)" "Ship it. Then measure." "multi-word values round-trip"

# U12 -- spy blocks on the brand only. A sweep needs something to search for;
# demanding a product photo would block research that needs no product.
fresh
$B set brand.name Acme >/dev/null
$B check spy >/dev/null 2>&1
check U12 "$?" "0" "spy needs the brand and nothing else"

# U13 -- from-url never writes, even when it succeeds. Drafting is the whole
# contract: a wrong brand fact baked silently into ten ads is worse than an
# empty field. Offline-safe: an unresolvable host takes the failure path, and
# the assertion (nothing written) is the same on both paths.
fresh
$B from-url https://this-host-does-not-exist.invalid >/dev/null 2>&1
rc=$?
written=$($B list | grep -cv '(unset)')
check U13 "$rc:$written" "1:0" "from-url on an unreachable host exits 1 and writes nothing"

# U14 -- the failure message points somewhere useful rather than dying on a
# stack trace. Scripts solve; they do not punt to the model.
fresh
msg=$($B from-url https://this-host-does-not-exist.invalid 2>&1 >/dev/null | grep -c "two-field minimum")
check U14 "$msg" "1" "a failed fetch names the fallback"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
