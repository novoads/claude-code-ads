#!/usr/bin/env bash
# Unit tests for make-picker.py. Spends nothing, touches no network.
#
# P4 is the one that matters most: page names and ad copy are third-party text
# scraped from a competitor's ads. Interpolating them raw into HTML executes
# whatever they contain in the browser that opens the file.
set -uo pipefail
cd "$(dirname "$0")/.."

M=./scripts/make-picker.py
R=./scripts/rank-ads.py
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { printf '  ok    %-5s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad() { printf '  FAIL  %-5s %s\n' "$1" "$2"; fail=$((fail+1)); }
want(){ if [ "$2" = "$3" ]; then ok "$1" "$4"; else bad "$1" "$4 (want '$3', got '$2')"; fi }
has() { if grep -qF -- "$2" "$3"; then ok "$1" "$4"; else bad "$1" "$4"; fi }
hasnt(){ if grep -qF -- "$2" "$3"; then bad "$1" "$4"; else ok "$1" "$4"; fi }

echo "make-picker tests"

# 14 ads so the default cap of 12 has something to cut.
python3 - "$WORK/sweep.json" <<'PY'
import json, sys
ads = [{"adArchiveId": f"id{i}", "pageName": f"Page {i}",
        "collationCount": 1 if i % 2 else None,
        "startDate": f"2026-{(i % 12) + 1:02d}-01",
        "adLibraryUrl": f"https://facebook.com/ads/library/?id={i}",
        "bodyText": f"copy for ad {i}", "isActive": True} for i in range(1, 15)]
json.dump({"query": "arcads.ai", "mediaType": "image", "ads": ads},
          open(sys.argv[1], "w"))
PY
mkdir -p "$WORK/media"
: > "$WORK/media/slug-id1.jpg"
: > "$WORK/media/slug-id2.mp4"

$M "$WORK/sweep.json" --media-dir "$WORK/media" --out "$WORK/p.html" >/dev/null 2>&1
rc=$?

# P1 -- the default caps at 12 even when more came back.
want P1 "$rc" "0" "a normal sweep writes a page"
want P1b "$(grep -c 'class="card"' "$WORK/p.html")" "12" "12 cards from 14 ads"

# P2 -- ordinals run 1..12 and the copy string matches the badge. If these ever
# disagree, "clone 3" clones a different ad than the one the user clicked.
want P2 "$(grep -c 'data-pick="clone ' "$WORK/p.html")" "12" "every card carries a pick line"
want P2b "$(grep -o 'data-pick="clone 12"' "$WORK/p.html" | head -1)" 'data-pick="clone 12"' "the last card is 12"
python3 - "$WORK/p.html" <<'PY' && ok P2c "badge number matches its own pick line" || bad P2c "badge and pick line disagree"
import re, sys
h = open(sys.argv[1]).read()
cards = re.findall(r'data-pick="clone (\d+)"[^>]*>\s*<div class="n">(\d+)</div>', h)
sys.exit(0 if cards and all(a == b for a, b in cards) and len(cards) == 12 else 1)
PY

# P3 -- the ordering matches rank-ads exactly. Two scripts, one sort: if they
# drift, the page and the chat disagree about which ad is #1.
$R "$WORK/sweep.json" --top 1 2>/dev/null | grep -oE 'Page [0-9]+' | head -1 > "$WORK/first.txt"
first_in_page=$(grep -o '<strong>Page [0-9]*</strong>' "$WORK/p.html" | head -1 | sed 's/<[^>]*>//g')
want P3 "$first_in_page" "$(cat "$WORK/first.txt")" "page and list agree on the first pick"

# P4 -- SECURITY. Scraped page names and ad copy are third-party text.
python3 - "$WORK/xss.json" <<'PY'
import json, sys
json.dump({"query": "x", "mediaType": "image", "ads": [{
    "adArchiveId": "x1",
    "pageName": "<script>alert(1)</script>",
    "bodyText": "<img src=x onerror=alert(2)>",
    "adLibraryUrl": "javascript:alert(3)",
    "startDate": "2026-01-01"}]}, open(sys.argv[1], "w"))
PY
$M "$WORK/xss.json" --media-dir "$WORK/media" --out "$WORK/x.html" >/dev/null 2>&1
hasnt P4  "<script>alert(1)</script>" "$WORK/x.html" "a page name cannot inject a script tag"
hasnt P4b "<img src=x onerror"         "$WORK/x.html" "ad copy cannot become a live tag"
has   P4c "&lt;script&gt;"            "$WORK/x.html" "the hostile name is present, escaped"
hasnt P4d "javascript:"               "$WORK/x.html" "a javascript: url is dropped, not escaped"

# P5 -- a missing media file degrades to a labelled placeholder. A broken <img>
# in a grid of twelve reads as "this ad is bad", not "this file is missing".
has P5 "no file downloaded" "$WORK/p.html" "a missing file becomes a placeholder"

# P5b -- a grid of placeholders DIAGNOSES itself. Twelve empty cards read as a
# broken tool rather than an empty folder; the founder hit exactly that on a demo
# built before any download, and asked why the ads were missing.
$M "$WORK/sweep.json" --media-dir "$WORK/nothing" --out "$WORK/none-md.html" >"$WORK/nm.out" 2>&1
has P5b "None of the 12 creatives are on disk" "$WORK/none-md.html" "an empty grid says why on the page"
has P5c "WARNING: none of the 12" "$WORK/nm.out" "and warns on stderr, where the agent reads it"

# P5d -- a PARTIAL download is named too, with the reason (links expire).
mkdir -p "$WORK/partial" && : > "$WORK/partial/slug-id1.jpg"
$M "$WORK/sweep.json" --media-dir "$WORK/partial" --out "$WORK/part.html" >/dev/null 2>&1
has P5d "1 of 12 creatives are on disk" "$WORK/part.html" "a partial download is counted on the page"

# P5e -- and a COMPLETE set says nothing. A banner that always shows is noise.
mkdir -p "$WORK/full" && for i in $(seq 1 14); do : > "$WORK/full/slug-id$i.jpg"; done
$M "$WORK/sweep.json" --media-dir "$WORK/full" --out "$WORK/full.html" >/dev/null 2>&1
hasnt P5e "class=\"notice\"" "$WORK/full.html" "a complete set shows no banner"

# P6 -- a video is playable in the picker rather than shown as a filename.
has P6 "<video" "$WORK/p.html" "an mp4 renders as a video element"

# P7 -- the sample claim survives into the page.
has P7 "highest-impression" "$WORK/p.html" "the impressions-selected sample is stated"

# P8 -- and no impression NUMBER is ever printed. Meta does not publish one.
hasnt P8 "impressions:" "$WORK/p.html" "no impression figure appears"

# P9 -- a dead collationCount is named on the page, not just in the chat.
has P9 "run length only" "$WORK/p.html" "a dead signal is stated on the page"

# P10 -- brand tokens, both themes. A picker that ignores the palette is a
# different product's page.
has P10  "#121212" "$WORK/p.html" "the light primary token is present"
has P10b "prefers-color-scheme: dark" "$WORK/p.html" "the dark palette is defined"

# P11 -- an empty sweep writes NO page and exits 2. A picker with zero cards is
# worse than none: it looks like a broken run rather than an honest empty result.
echo '{"query":"nobody","mediaType":"video","ads":[]}' > "$WORK/empty.json"
$M "$WORK/empty.json" --out "$WORK/none.html" >/dev/null 2>&1
want P11 "$?" "2" "an empty sweep exits 2"
[ -f "$WORK/none.html" ] && bad P11b "an empty sweep wrote a page anyway" || ok P11b "no page written for an empty sweep"

# P12 -- typing the number works without the clipboard, so the ordinal is always
# visible. The click is the convenience; the number is the contract.
has P12 "clone 3" "$WORK/p.html" "the typed fallback is documented on the page"

# P13 -- unreadable input fails with guidance, not a traceback.
$M "$WORK/nope.json" > "$WORK/miss.out" 2>&1
want P13 "$?" "1" "a missing sweep exits 1"
hasnt P13b "Traceback" "$WORK/miss.out" "no traceback on a missing file"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
