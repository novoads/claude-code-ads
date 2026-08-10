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

# ---- G: the gate follows the AD, not the business -------------------------
# Written before the change, and G3 fails today: the skill says template mode
# needs no product, its own eval B4 says the same, and the script blocks anyway.
# Whichever of the three the run consults decides — which is the bug.
#
# The split is deliberate. The agent JUDGES whether the ad has a product in it
# (prose, a look at the frame); the script ENFORCES the consequence (code). That
# is what makes these runnable at all: a gate keyed on a zone map could not be
# tested here, because this pack has no zone reader — Phase 2 is prose.

fresh
$B set brand.logo refs/logo.png >/dev/null

# G1 -- ads mode, the ad HAS a product. Arcads' rule, unchanged and hard: an
# image model invents a plausible bottle with invented label text if you let it.
$B check clone-image-ad --mode ads --product-in-ad yes >/dev/null 2>&1
check G1 "$?" "2" "a product ad still blocks without a real photo"

# G2 -- ads mode, the ad has NO product. The founder's Creatify \$500-vs-\$1
# static: a price comparison in type. Nothing to pin, so nothing to fabricate,
# so nothing to ask for. Arcads refuses this ad outright; Kruse handles it by
# only parameterising what the ad contains.
$B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad no >/dev/null 2>&1
check G2 "$?" "0" "a productless ad does not demand a product photo"

# G3 -- template mode never asks. FAILS BEFORE THE CHANGE.
$B check clone-image-ad --mode template >/dev/null 2>&1
check G3 "$?" "0" "template mode never demands a product"

# G4 -- the logo is the universal gate. Every ad carries a mark, and that mark
# must never be the competitor's. Today the product blocks and the logo is
# optional, which is exactly inverted.
fresh
$B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad no >/dev/null 2>&1
check G4 "$?" "2" "no stored logo blocks, whatever the ad contains"

# G5 -- in ads mode the judgement is REQUIRED, not assumed. An unasked question
# that leads to a spend is the whole class being fixed here.
fresh
$B set brand.logo refs/logo.png >/dev/null
$B check clone-image-ad --mode ads >/dev/null 2>&1
check G5 "$?" "2" "ads mode refuses when nobody said whether the ad has a product"

# G6 -- and it says WHICH judgement it is missing, rather than listing fields.
fresh
$B set brand.logo refs/logo.png >/dev/null
msg=$($B check clone-image-ad --mode ads 2>&1 | grep -c "product-in-ad")
check G6 "$msg" "1" "the refusal names the missing judgement"

# ---- C: claims -------------------------------------------------------------
# Found by looking at four REAL Arcads statics rather than fixtures. Every one
# carries a number or a named human: "300 AI Actors", "6,000+ teams", "99%
# reduction in cost", a CMO quoted by name. The skill kills testimonials at
# Phase 6 and says nothing at all about the numbers, so a clone would rewrite
# "300 Natural AI Actors" into a Novoads figure nobody verified — a claim
# invented to preserve a layout.
#
# The script cannot read an ad, so what it enforces is the SOURCE of a claim:
# a run may only use figures it can point at. The agent lists the claims; this
# decides whether there is anything true to put in their place.

fresh
$B set brand.logo refs/logo.png >/dev/null

# C1 -- with no verified claims on file, an ad carrying claims cannot be cloned
# whole. Not a refusal of the ad: a refusal to invent the numbers in it.
$B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad yes >/dev/null 2>&1
check C1 "$?" "0" "claims in the source do NOT block — a human judges the render"

# C2 -- and the refusal names the field, so the fix is obvious.
# Capture first, THEN grep. Piping straight from `check` makes pipefail return
# that command's exit 2, so the match is drowned by the very refusal it is
# testing for — the harness failing where the thing under test did not.
# C2 -- it proceeds, and it tells the run to LIST what it carried. A number that
# crossed silently is the one nobody checks; a listed one is a decision.
out=$($B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad yes 2>&1)
case "$out" in *"list every claim"*) ok C2 "it instructs the run to list the claims it carried" ;;
                *) bad C2 "proceeding says nothing about listing the claims" ;; esac

# C3 -- once real ones are on file, it proceeds. The gate is about having a
# source, not about avoiding claims.
# C3 -- stored figures are USED when present, never demanded. They make the
# substitution better; their absence does not stop the ad.
$B set brand.claims "5 languages; renders in minutes" >/dev/null
$B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad yes >/dev/null 2>&1
check C3 "$?" "0" "stored figures are used, not required"

# C4 -- an ad with NO claims never asks. Most layout clones carry none.
fresh
$B set brand.logo refs/logo.png >/dev/null
$B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad no >/dev/null 2>&1
check C4 "$?" "0" "a claimless ad does not ask for claims"

# C5 -- template mode never asks. A placeholder is not a claim; {ad.headline}
# asserts nothing, which is the whole point of the placeholder.
fresh
$B check clone-image-ad --mode template --claims-in-ad yes >/dev/null 2>&1
check C5 "$?" "0" "template mode never asks for claims"

# C6 -- the judgement is required in ads mode, like the product one. Assuming a
# source has no claims is how an unverified number ships.
fresh
$B set brand.logo refs/logo.png >/dev/null
$B check clone-image-ad --mode ads --product-in-ad no >/dev/null 2>&1
check C6 "$?" "2" "ads mode refuses when nobody said whether the ad makes claims"

# C7 -- a named person's quote is NOT substitutable, and stored claims must not
# unblock it. Two of the four real Arcads statics are testimonials from named
# executives; a verified-figures list is the wrong currency for those. The only
# honest inputs are a real customer who really said it, or dropping the zone.
fresh
$B set brand.logo refs/logo.png >/dev/null
$B set brand.claims "5 languages; renders in minutes" >/dev/null
$B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad testimonial >/dev/null 2>&1
check C7 "$?" "2" "a testimonial is not unblocked by verified figures"

out=$($B check clone-image-ad --mode ads --product-in-ad no --claims-in-ad testimonial 2>&1)
case "$out" in *"really said it"*) ok C7b "and it says what the only honest input is" ;;
                *) bad C7b "the testimonial refusal does not say what to do" ;; esac

# ---- L: the logo has to REACH the renderer ---------------------------------
# The first real clone rendered a generic white square where the mark should be.
# brand.logo was stored, it BLOCKED the run, and nothing passed it to the model
# — a gate on an asset no renderer ever received. Arcads has had this right all
# along: the logo goes in as a reference image, after the product.
#
# Which refs, in which order, is arithmetic, so it moves into the script. What
# stays prose is what the prompt SAYS about the mark.

fresh
$B set brand.logo /tmp/logo.png >/dev/null
$B set product.photo /tmp/shot.jpg >/dev/null

# L1 -- product first, logo second. Order is load-bearing: reference 1 is the
# strongest identity signal at the provider, and the product is what must not
# drift.
RSHOT=$(python3 -c "import pathlib;print(pathlib.Path('/tmp/shot.jpg').resolve())")
RLOGO=$(python3 -c "import pathlib;print(pathlib.Path('/tmp/logo.png').resolve())")
out=$($B refs clone-image-ad 2>/dev/null | tr '\n' '|')
check L1 "$out" "$RSHOT|$RLOGO|" "product first, logo second, one per line"

# L2 -- a stored logo with no product still goes. The mark is the universal one.
fresh
$B set brand.logo /tmp/logo.png >/dev/null
check L2 "$($B refs clone-image-ad 2>/dev/null)" "$RLOGO" "the logo alone is still passed"

# L3 -- nothing stored prints nothing, and exits 1 so a caller can branch. It
# must not print an empty flag that the renderer would choke on.
fresh
out=$($B refs clone-image-ad 2>/dev/null); rc=$?
check L3 "$rc:$out" "1:" "no assets prints nothing and exits 1"

# L4 -- paths are absolute. The render runs from wherever the agent happens to
# be, and a relative ref resolves to nothing there.
fresh
$B set brand.logo ./rel/logo.png >/dev/null
case "$($B refs clone-image-ad 2>/dev/null)" in
  /*) ok L4 "a relative stored path is emitted absolute" ;;
  *) bad L4 "a relative path is passed through relative" ;;
esac

# L5 -- a path with a SPACE survives. The first format space-joined the flags,
# which cannot represent one, and user folders are full of them.
fresh
mkdir -p "/tmp/my brand"; : > "/tmp/my brand/logo.png"
$B set brand.logo "/tmp/my brand/logo.png" >/dev/null
n=0; while IFS= read -r line; do n=$((n+1)); done < <($B refs clone-image-ad 2>/dev/null)
check L5 "$n" "1" "a path containing a space is one line, not two"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
