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
want P2 "$(grep -c 'role="checkbox"' "$WORK/p.html")" "12" "every card is a toggle"
want P2b "$(grep -c 'aria-checked="false"' "$WORK/p.html")" "12" "nothing is selected by default"
python3 - "$WORK/p.html" <<'PY' && ok P2c "badge number matches its own pick line" || bad P2c "badge and pick line disagree"
import re, sys
h = open(sys.argv[1]).read()
cards = re.findall(r'data-i="(\d+)"[^>]*>\s*<div class="n">(\d+)</div>', h)
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
has P12 "clone 3" "$WORK/p.html" "the single typed fallback is documented"
has P12b "clone 1, 4, 7" "$WORK/p.html" "the multi typed fallback is documented"

# P14 -- multi-select controls exist and start in the safe state. "Select all"
# queues one clone run per card, so Clear and Copy must be dead until something
# is actually chosen.
has P14  'id="all"'   "$WORK/p.html" "select all exists"
has P14b 'id="clear" disabled' "$WORK/p.html" "clear starts disabled"
has P14c 'id="copy" class="primary" disabled' "$WORK/p.html" "copy starts disabled"
has P14d "Nothing selected" "$WORK/p.html" "the bar opens saying nothing is selected"

# P15 -- the bar states the SHAPE of the spend and never a figure. This page is
# static; it cannot price a run, and the live estimate is the only thing allowed
# to quote one.
has   P15  "priced before it spends" "$WORK/p.html" "the spend line is present"
hasnt P15b "credits"                 "$WORK/p.html" "no credit figure on the page"

# P16 -- the brand mark is inlined, not linked. The page opens from file:// with
# no network; a logo that 404s is worse than none.
has   P16  'class="mark"'  "$WORK/p.html" "the novoads mark is present"
hasnt P16b "<img src=\"http" "$WORK/p.html" "nothing is loaded over the network"

# P17 -- the path printed is ABSOLUTE. A relative path in a delivery is a path
# the reader cannot use, and the reader may be in a different directory or on a
# different machine entirely.
$M "$WORK/sweep.json" --media-dir "$WORK/media" --out "$WORK/abs.html" > "$WORK/abs.out" 2>/dev/null
case "$(head -1 "$WORK/abs.out")" in /*) ok P17 "the printed path is absolute" ;;
  *) bad P17 "the printed path is relative" ;; esac

# P18 -- the script never claims the page opened, and never opens it. A remote
# sandbox, an SSH session and a CI box all have no browser the user can see; the
# founder hit exactly this and asked why nothing appeared.
hasnt P18  "open in your browser" "$WORK/abs.out" "stdout does not claim a browser opened"
$M "$WORK/sweep.json" --media-dir "$WORK/media" --out "$WORK/abs.html" 2>"$WORK/abs.err" >/dev/null
has   P18b "in the conversation"  "$WORK/abs.err" "it tells the caller to show them inline instead"

# P13 -- unreadable input fails with guidance, not a traceback.
$M "$WORK/nope.json" > "$WORK/miss.out" 2>&1
want P13 "$?" "1" "a missing sweep exits 1"
hasnt P13b "Traceback" "$WORK/miss.out" "no traceback on a missing file"

# ---- --embed: the artifact path ------------------------------------------
# An artifact's CSP blocks every external host, so a page that references a file
# beside it renders as twelve broken frames. These cases are the difference
# between a page that publishes and one that publishes empty.
mkdir -p "$WORK/emb"
python3 - <<'PY2'
import base64, json, pathlib
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
d = pathlib.Path("/tmp/pick-emb"); d.mkdir(exist_ok=True)
ads = []
for i in range(1, 5):
    kind = "video" if i in (3, 4) else "image"
    ads.append({"adArchiveId": f"e{i}", "pageName": f"P{i}", "collationCount": None,
                "startDate": "2026-01-01", "adLibraryUrl": f"https://x/{i}",
                "media": {"kind": kind}})
    if kind == "video":
        (d / f"s-e{i}.mp4").write_bytes(b"\x00" * 64)
        if i == 3:                      # 3 has a poster, 4 deliberately does not
            (d / f"s-e{i}-poster.jpg").write_bytes(png)
    else:
        (d / f"s-e{i}.jpg").write_bytes(png)
json.dump({"query": "q", "mediaType": "all", "ads": ads}, open(d / "sweep.json", "w"))
PY2
$M /tmp/pick-emb/sweep.json --embed --out "$WORK/e.html" >/dev/null 2>&1

# E1 -- nothing external. The single most important property of this mode.
hasnt E1 'src="s-'      "$WORK/e.html" "no relative file references survive --embed"
hasnt E1b 'src="http'   "$WORK/e.html" "no remote references either"
want  E1c "$(grep -c 'src="data:image' "$WORK/e.html")" "3" "3 of 4 embed (one video has no poster)"

# E2 -- a video embeds as its POSTER and is labelled as such. Twelve mp4s as
# data URIs is ~47MB against a 16MB ceiling; the poster is a few KB.
has E2 "video · poster frame" "$WORK/e.html" "an embedded video is badged as a poster"

# E3 -- a video with no poster degrades with the REASON, not a broken frame.
has E3 "video, no poster frame" "$WORK/e.html" "a posterless video says why"

# E4 -- the budget drops rather than blowing the cap, and the page says so.
$M /tmp/pick-emb/sweep.json --embed --out "$WORK/tiny.html" >/dev/null 2>&1
python3 - <<'PY2' && ok E4 "the embed budget is under the artifact ceiling" || bad E4 "budget is set above the ceiling"
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("mp", pathlib.Path("scripts/make-picker.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.exit(0 if m.EMBED_BUDGET_BYTES < 16 * 1024 * 1024 else 1)
PY2

# E5 -- all THREE theme states. "System" stamps nothing, so a token defined only
# behind [data-theme] never applies there and the page renders one theme's text
# on the other theme's ground.
has E5  "prefers-color-scheme: dark"        "$WORK/e.html" "the system-dark state is handled"
has E5b ':root:not([data-theme="light"])'   "$WORK/e.html" "an explicit light choice beats a dark OS"
has E5c ':root[data-theme="dark"]'          "$WORK/e.html" "an explicit dark choice is handled"

# E6 -- motion is opt-out, per the same contract.
has E6 "prefers-reduced-motion" "$WORK/e.html" "reduced motion is respected"

# E7 -- REGRESSION: the default (non-embed) page still uses relative paths, so
# the on-disk view keeps working for Cursor and anywhere without an artifact.
has E7 'src="slug-id1.jpg"' "$WORK/p.html" "the on-disk page still references files"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
