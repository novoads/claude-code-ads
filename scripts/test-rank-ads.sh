#!/usr/bin/env bash
# Unit tests for rank-ads.py. Spends nothing, touches no network.
#
# Every case is a real property the prose version was asked to hold and could
# only hold when the model was paying attention. R1 is the one measured live:
# collationCount came back 1 or null on every row of a real sweep, so the field
# the ordering nominally leads on contributed nothing.
set -uo pipefail
cd "$(dirname "$0")/.."

R=./scripts/rank-ads.py
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { printf '  ok    %-5s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad() { printf '  FAIL  %-5s %s\n' "$1" "$2"; fail=$((fail+1)); }
want(){ if [ "$2" = "$3" ]; then ok "$1" "$4"; else bad "$1" "$4 (want '$3', got '$2')"; fi }
has() { if grep -qi -- "$2" "$3"; then ok "$1" "$4"; else bad "$1" "$4"; fi }
hasnt(){ if grep -qi -- "$2" "$3"; then bad "$1" "$4"; else ok "$1" "$4"; fi }

echo "rank-ads tests"

# A corpus where collationCount is 1 or null on every row -- the measured case.
cat > "$WORK/dead.json" <<'JSON'
{"query":"arcads.ai","mediaType":"video","ads":[
 {"adArchiveId":"1","pageName":"Arcads AI","collationCount":1,"startDate":"2026-05-27","adLibraryUrl":"https://x/1","isActive":true},
 {"adArchiveId":"2","pageName":"Mr. Paid Social","collationCount":null,"startDate":"2026-02-18","adLibraryUrl":"https://x/2","isActive":true},
 {"adArchiveId":"3","pageName":"Creatify","collationCount":1,"startDate":"2026-04-10","adLibraryUrl":"https://x/3","isActive":true},
 {"adArchiveId":"4","pageName":"Creatify","collationCount":null,"startDate":"2026-07-01","adLibraryUrl":"https://x/4","isActive":true}]}
JSON

# A corpus where the signal is real.
cat > "$WORK/live.json" <<'JSON'
{"query":"brand","mediaType":"image","ads":[
 {"adArchiveId":"1","pageName":"Brand","collationCount":3,"startDate":"2026-06-01","adLibraryUrl":"https://x/1"},
 {"adArchiveId":"2","pageName":"Brand","collationCount":12,"startDate":"2026-07-01","adLibraryUrl":"https://x/2"},
 {"adArchiveId":"3","pageName":"Affiliate","collationCount":7,"startDate":"2026-01-01","adLibraryUrl":"https://x/3"}]}
JSON

echo '{"query":"nobody","mediaType":"video","ads":[]}' > "$WORK/empty.json"

# R1 -- a dead signal is DETECTED, not assumed present. The prose version had to
# notice this by reading every row; here it is a computation.
$R "$WORK/dead.json" > "$WORK/dead.out" 2>&1
has R1 "run length only" "$WORK/dead.out" "an all-1/null corpus is called run length only"

# R1b -- and the basis line does not claim audience count as a basis.
hasnt R1b "audience count, then run length" "$WORK/dead.out" "the dead basis is not recited"

# R2 -- with a real signal, the higher count wins regardless of dates.
$R "$WORK/live.json" --top 1 > "$WORK/live.out" 2>&1
has R2 "12 audiences" "$WORK/live.out" "highest audience count ranks first when the signal is alive"

# R3 -- longest-running wins the tiebreak. In dead.json the oldest is
# Mr. Paid Social (2026-02-18), NOT the first row in the file.
$R "$WORK/dead.json" --top 1 > "$WORK/first.out" 2>&1
has R3 "Mr. Paid Social" "$WORK/first.out" "longest-running wins when there is no other signal"

# R4 -- the SAMPLE claim leads, because it is the strongest honest statement.
has R4 "highest-impression" "$WORK/dead.out" "the impressions-selected sample is stated first"

# R5 -- and no impression NUMBER is ever printed. Meta does not publish one for
# commercial ads; a script with no such field cannot leak one.
hasnt R5 "impressions:" "$WORK/dead.out" "no impression figure is quoted"

# R6 -- an empty sweep is a charged, correct result. Exit 2 marks it as
# distinct from an error without turning it into one.
$R "$WORK/empty.json" > "$WORK/empty.out" 2>&1
want R6 "$?" "2" "an empty sweep exits 2, not 0 and not 1"
has R6b "do not re-run" "$WORK/empty.out" "an empty sweep says not to retry"

# R7 -- pages are surfaced so third parties can be told from the brand.
has R7 "Creatify" "$WORK/dead.out" "the page breakdown names who is running what"

# R8 -- the craft disclaimer survives. It is the line that keeps a metadata
# ordering from reading as an editorial verdict.
has R8 "not craft" "$WORK/dead.out" "the metadata-not-craft line is present"

# R9 -- a missing file fails with guidance, not a traceback.
$R "$WORK/nope.json" > "$WORK/miss.out" 2>&1
want R9 "$?" "1" "a missing file exits 1"
hasnt R9b "Traceback" "$WORK/miss.out" "a missing file does not print a traceback"

# R10 -- a response that is not a sweep is refused by shape, not by crashing
# halfway through formatting.
echo '{"nope":true}' > "$WORK/wrong.json"
$R "$WORK/wrong.json" > "$WORK/wrong.out" 2>&1
want R10 "$?" "1" "a non-sweep payload is refused"

# R11 -- --json is machine-readable and carries the flag a caller branches on.
$R "$WORK/dead.json" --json > "$WORK/j.out" 2>&1
python3 -c "
import json,sys
d=json.load(open('$WORK/j.out'))
sys.exit(0 if d['signalAlive'] is False and d['total']==4 else 1)" \
  && ok R11 "--json carries signalAlive and the count" \
  || bad R11 "--json shape is wrong"

# R12 -- --top is honoured rather than always printing three.
$R "$WORK/dead.json" --top 2 > "$WORK/two.out" 2>&1
want R12 "$(grep -c '^  [0-9]\.' "$WORK/two.out")" "2" "--top N names exactly N"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
