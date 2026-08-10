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

# And a clean prompt must NOT be refused by this lint — it should get as far as
# the env failure, which is the next gate.
out=$($V --prompt "a black scratch card reading INSTANT AI VIDEO JACKPOT" --model gpt-image-2 --aspect-ratio 1:1 "${E[@]}" 2>&1)
case "$out" in *placeholder*) bad C1 "a clean prompt was wrongly refused" ;;
  *) ok C1 "a clean prompt passes the lint" ;; esac

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
