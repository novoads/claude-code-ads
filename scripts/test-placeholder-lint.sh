#!/usr/bin/env bash
# Placeholder lint — the render must never ship scaffolding.
set -uo pipefail
cd "$(dirname "$0")/.."
V="python3 skills/clone-image-ad/scripts/validate_image.py"
pass=0; fail=0
ok(){ printf '  ok    %-5s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad(){ printf '  FAIL  %-5s %s\n' "$1" "$2"; fail=$((fail+1)); }
want(){ if [ "$2" = "$3" ]; then ok "$1" "$4"; else bad "$1" "$4 (want $3, got $2)"; fi }
echo "placeholder lint"

# A bogus env file so any network path would die anyway — these must die EARLIER,
# on the lint, so a placeholder can never reach a paid call.
E=(--env-file /nonexistent/.env)

for p in "Placeholder Name in bold" "a card reading Lorem ipsum dolor" \
         "the wordmark {brand.name} at the top" "a name reading Your Name Here" \
         "a link to example.com" "text reading TBD"; do
  out=$($V --prompt "$p" --model gpt-image-2 --aspect-ratio 1:1 "${E[@]}" 2>&1); rc=$?
  case "$out" in *placeholder*|*Placeholder*) ok "P" "refused: ${p:0:34}" ;;
    *) bad "P" "NOT refused: ${p:0:34} (rc=$rc)" ;; esac
done

# Slot-shaped VALUES. The word "placeholder" is the easy tell; these are the ones
# that shipped anyway. Every string below was observed in a real render or the
# prompt behind it, not imagined:
#   agency.com      — sat directly under "Placeholder Name" in the pair that
#                     motivated the lint, and no pattern matched it.
#   @creatorhandle  — the TikTok-mockup ad's author handle.
# A slot does not have to look like a slot to be one.
for p in "the subline reads agency.com - partner" \
         "a byline reading brand.com" \
         "the handle @creatorhandle above the caption" \
         "a profile reading @username" \
         "the author is John Doe" \
         "a card reading Jane Doe, Head of Growth" \
         "the headline slot reads Your Company Here" \
         "a label reading Name Goes Here" \
         "body copy reading Text Goes Here" \
         "a caption reading Sample Text" \
         "a name reading Dummy Name" \
         "the strapline reads Insert Headline" \
         "the mark sits inside a [BRAND_MARK] block" \
         "a card reading xxxx" \
         "two grey skeleton bars under the name"; do
  out=$($V --prompt "$p" --model gpt-image-2 --aspect-ratio 1:1 "${E[@]}" 2>&1); rc=$?
  case "$out" in *placeholder*|*Placeholder*) ok "S" "refused: ${p:0:38}" ;;
    *) bad "S" "NOT refused: ${p:0:38} (rc=$rc)" ;; esac
done

# The other half of the guard, and the half that is easy to forget: finished
# content must still get through. Every string below is real output this skill
# produced and shipped — if a future pattern refuses one of these, the lint has
# started blocking the thing it exists to require.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  out=$($V --prompt "$p" --model gpt-image-2 --aspect-ratio 1:1 "${E[@]}" 2>&1)
  case "$out" in *placeholder*) bad "C" "wrongly refused: ${p:0:38}" ;;
    *) ok "C" "passes: ${p:0:38}" ;; esac
done <<'CLEAN'
a black scratch card reading INSTANT AI VIDEO JACKPOT
the name "Dana Whitfield" in bold dark grey beside a LinkedIn badge
a grey subline reading brightfoldmedia.com - Performance agency
a testimonial from Camille Rousseau, Head of Growth at Lumen
the company name is set in bold condensed caps
the brand name appears once, lowercase, at the foot of the card
a performance agency case study with a named client
CLEAN

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
