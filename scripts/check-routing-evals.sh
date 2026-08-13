#!/usr/bin/env bash
# Every routable skill carries a routing eval, and the fixtures have to be honest.
#
# The platform ROUTES but never VERIFIES. A description is the only thing loaded
# for every skill, the model matches a user's sentence against it, and nothing
# anywhere reports that the match still lands where it used to. So a description
# decays silently: a sibling ships next month with a broader tail, a clause gets
# trimmed to fit the 1024-char cap, and the skill that used to win a phrasing
# quietly stops winning it. Nothing goes red — the user just gets the wrong skill,
# or an answer written straight into the chat with no skill at all.
#
# routing-eval.jsonl is the regression gate for that. One intent per line:
#
#   {"intent": "...", "expected_skill": "<name>"}                     a positive
#   {"intent": "...", "expected_skill": "<name>",
#                     "ambiguous_with": ["<sibling>"]}   a phrasing two skills
#                                                        can legitimately claim
#   {"intent": "...", "expected_skill": null}            a near-miss negative:
#                                                        adjacent topic, and
#                                                        NOTHING here should fire
#
# `//` lines are comments and say WHY a fixture is tricky.
#
# ── What this script does and does not do ────────────────────────────────────
#
# It checks STRUCTURE, deterministically, with no model in the loop: valid JSONL,
# names that resolve against the tree, the counts, and one lint. Actually running
# the intents through a router is a live-session job that needs a model and a
# budget; it does not belong in a check that has to pass on a fork PR with no
# credentials. What this buys is that the fixtures are always loadable and always
# name real skills — so the day someone does run them, the file is not the thing
# that is broken.
#
# ── The lint, which is the part with teeth ───────────────────────────────────
#
# REJECT any fixture whose intent is verbatim-equal to a phrase in the target
# skill's own description.
#
# A description is a list of trigger phrases. A fixture that copies one measures
# string overlap, not intent: it will pass forever, including on the day the skill
# stops routing for every sentence a real user would write. That is exactly the
# overfitting Anthropic's own description-optimization guidance warns about
# ("avoid adding specific keywords from failed queries"), frozen into a test.
#
# So the fixtures have to be phrased the way somebody would actually ask —
# including the indirect asks that never name the skill's subject at all, which
# are the ones that catch decay first.
#
# Negatives are checked against EVERY skill's description, not just the owner's.
# A negative asserts that nothing in this pack fires; if it verbatim-quotes any
# skill's trigger, the assertion is false on its face and the fixture is wrong
# rather than hard.
#
# ── Ownership ────────────────────────────────────────────────────────────────
#
# A non-null expected_skill must be the skill the file sits beside. A file whose
# fixtures expect a sibling tests the sibling and leaves its own routing unproven,
# while its counts still read as covered. If the sibling should win a phrasing,
# that fixture belongs in the sibling's file — and the pair is what makes an
# ambiguity legible from both sides.
#
# ── Failure, not warning ─────────────────────────────────────────────────────
#
# check-evals-present.sh warns because it arrived with six skills already in debt,
# and a guard that arrives red gets deleted rather than satisfied. This one lands
# with all sixteen files present, so there is no debt to grandfather and nothing
# to walk past. A new skill without a routing eval is a new hole, and it fails.
#
# Usage: ./scripts/check-routing-evals.sh   (exit 0 clean, 1 on any problem)
set -uo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, os, re, sys

FIXTURE = "routing-eval.jsonl"
PARENTS = ("skills", "shared/skills")
MIN_POSITIVE, MIN_AMBIGUOUS, MIN_NEGATIVE = 5, 2, 2
ALLOWED_KEYS = {"intent", "expected_skill", "ambiguous_with"}

problems = []


def fail(where, msg):
    problems.append((where, msg))


# ── The tree ─────────────────────────────────────────────────────────────────
# Routable = carries a SKILL.md. shared/skills/ entries holding only a prompting/
# guide are libraries another skill reads, never invoked on their own, so there is
# no routing decision to test.
skills = {}
for parent in PARENTS:
    if not os.path.isdir(parent):
        continue
    for name in sorted(os.listdir(parent)):
        d = os.path.join(parent, name)
        if os.path.isfile(os.path.join(d, "SKILL.md")):
            skills[name] = d


def description(path):
    """The frontmatter description, unfolded to one line. Same parse as
    check-skill-frontmatter.sh, which is the file that owns this format."""
    parts = open(path).read().split("---")
    if len(parts) < 2:
        return ""
    fm = parts[1]
    m = re.search(r"description:\s*>-?\s*\n(.*?)(?=\n[a-z_]+:|\Z)", fm, re.S)
    if m:
        return " ".join(l.strip() for l in m.group(1).strip().splitlines())
    m = re.search(r"description:\s*(.+)", fm)
    return m.group(1).strip() if m else ""


def norm(s):
    """Compare on words alone: case, quotes and punctuation are not what makes a
    fixture a copy. Unicode-aware, because two of the image-to-motion triggers are
    Japanese and stripping them to nothing would exempt them from the lint."""
    s = s.replace("’", "'").replace("‘", "'")
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    return re.sub(r"\s+", " ", s).strip().lower()


# A description is one sentence of prose wrapped around a comma-separated list of
# trigger phrases, most of them quoted. Split on both: sentence punctuation and
# commas. Em dashes too — this pack writes asides with them, and an aside is a
# phrase. Runs of 2+ words only, so a fragment like "or" cannot reject anything.
SPLIT = re.compile(r"[.;:!?()\[\]{}]|,|—|--")
LEAD = re.compile(r"^(or|and|nor|also)\s+")


def phrases(desc):
    out = set()
    # Quoted spans first and whole: the trigger list lives inside quotes, and a
    # comma INSIDE one ("clone this ad, video attached") must not split it.
    for q in re.findall(r'"([^"]{3,})"', desc):
        n = norm(q)
        if n:
            out.add(n)
    for chunk in SPLIT.split(desc):
        n = LEAD.sub("", norm(chunk))
        if len(n.split()) >= 2:
            out.add(n)
    return out


own_phrases = {}      # skill -> set of normalized phrases from its description
phrase_owner = {}     # normalized phrase -> first skill that publishes it
for name, d in skills.items():
    p = phrases(description(os.path.join(d, "SKILL.md")))
    own_phrases[name] = p
    for ph in p:
        phrase_owner.setdefault(ph, name)

# ── Orphans: a fixture file beside something that is not routable ────────────
for parent in PARENTS:
    if not os.path.isdir(parent):
        continue
    for name in sorted(os.listdir(parent)):
        path = os.path.join(parent, name, FIXTURE)
        if os.path.isfile(path) and name not in skills:
            fail(path, "routing eval beside a directory with no SKILL.md — "
                       "nothing can route to it")

# ── Per skill ────────────────────────────────────────────────────────────────
rows = []
totals = [0, 0, 0]

for name in sorted(skills):
    path = os.path.join(skills[name], FIXTURE)
    if not os.path.isfile(path):
        fail(path, "missing — every routable skill needs a routing eval")
        rows.append((name, "-", "-", "-"))
        continue

    positive = ambiguous = negative = 0
    seen = {}

    for lineno, raw in enumerate(open(path), 1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        where = f"{path}:{lineno}"

        try:
            obj = json.loads(line)
        except ValueError as e:
            fail(where, f"not valid JSON: {e}")
            continue

        if not isinstance(obj, dict):
            fail(where, "each line must be a JSON object, one intent per line")
            continue

        unknown = set(obj) - ALLOWED_KEYS
        if unknown:
            fail(where, f"unknown key(s) {sorted(unknown)}; "
                        f"allowed: {sorted(ALLOWED_KEYS)}")
            continue
        if "intent" not in obj or "expected_skill" not in obj:
            fail(where, "needs both 'intent' and 'expected_skill' "
                        "(use null for a near-miss negative)")
            continue

        intent = obj["intent"]
        if not isinstance(intent, str) or not intent.strip():
            fail(where, "'intent' must be a non-empty string")
            continue

        key = norm(intent)
        if key in seen:
            fail(where, f"duplicate intent, already on line {seen[key]} — "
                        "a repeated fixture pads the count and tests nothing")
        else:
            seen[key] = lineno

        expected = obj["expected_skill"]
        if expected is not None:
            if not isinstance(expected, str):
                fail(where, "'expected_skill' must be a skill name or null")
                continue
            if expected not in skills:
                fail(where, f"expected_skill '{expected}' is not a skill in this "
                            "pack (a dangling name can never pass)")
                continue
            if expected != name:
                fail(where, f"expected_skill '{expected}' is not this skill. A file "
                            f"that expects a sibling leaves '{name}' unproven while "
                            "its counts read as covered; put that fixture in "
                            f"{expected}/{FIXTURE} instead")
                continue

        amb = obj.get("ambiguous_with")
        if amb is not None:
            if expected is None:
                fail(where, "a negative asserts nothing fires, so it cannot also "
                            "name a sibling it is ambiguous with")
                continue
            if not isinstance(amb, list) or not amb or \
                    not all(isinstance(x, str) for x in amb):
                fail(where, "'ambiguous_with' must be a non-empty list of skill names")
                continue
            if len(set(amb)) != len(amb):
                fail(where, "'ambiguous_with' repeats a name")
            for sib in amb:
                if sib not in skills:
                    fail(where, f"ambiguous_with '{sib}' is not a skill in this pack")
                elif sib == name:
                    fail(where, f"ambiguous_with names '{name}' itself — "
                                "an ambiguity needs a second skill")

        # ── The lint ─────────────────────────────────────────────────────────
        if expected is None:
            owner = phrase_owner.get(key)
            if owner:
                fail(where, f"this negative is verbatim a phrase in {owner}'s "
                            "description. It asserts nothing should fire while "
                            "quoting a trigger — rewrite it as a genuine near-miss")
        elif key in own_phrases[name]:
            fail(where, f"this intent is verbatim a phrase in {name}'s own "
                        "description. A fixture that quotes its trigger measures "
                        "string overlap, not routing: it passes forever, including "
                        "on the day the skill stops firing for real sentences")

        if expected is None:
            negative += 1
        else:
            positive += 1
            if amb:
                ambiguous += 1

    if positive < MIN_POSITIVE:
        fail(path, f"{positive} positive fixture(s), needs at least {MIN_POSITIVE} "
                   "— vary the phrasing and include asks that never name the subject")
    if ambiguous < MIN_AMBIGUOUS:
        fail(path, f"{ambiguous} ambiguous fixture(s), needs at least {MIN_AMBIGUOUS} "
                   "— every skill here has a sibling that can steal a phrasing")
    if negative < MIN_NEGATIVE:
        fail(path, f"{negative} negative fixture(s), needs at least {MIN_NEGATIVE} "
                   "— an eval with no near-misses cannot catch a description "
                   "that got greedy")

    rows.append((name, positive, ambiguous, negative))
    totals = [totals[0] + positive, totals[1] + ambiguous, totals[2] + negative]

# ── Report ───────────────────────────────────────────────────────────────────
width = max(len(r[0]) for r in rows) if rows else 10
print(f"{'skill'.ljust(width)}  pos  amb  neg")
for name, p, a, n in rows:
    print(f"{name.ljust(width)}  {str(p).rjust(3)}  {str(a).rjust(3)}  {str(n).rjust(3)}")
print()

if problems:
    print(f"{len(problems)} problem(s):", file=sys.stderr)
    print("", file=sys.stderr)
    for where, msg in problems:
        print(f"  {where}", file=sys.stderr)
        print(f"      {msg}", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

# AMBIGUOUS IS A SUBSET OF POSITIVE, not a third class — the loop above counts a
# fixture as positive and THEN, if it carries `ambiguous_with`, as ambiguous too.
# So the total is positives plus negatives; `sum(totals)` counted every ambiguous
# fixture twice and reported 234 for a file set holding 195. Nothing failed, which
# is why it survived: the number is only ever read as reassurance, and an inflated
# one reassures better. Said in the message as "incl." so the arithmetic is legible
# from the line itself and the next reader does not have to re-derive it.
total = totals[0] + totals[2]
print(f"OK: {len(rows)} routing evals, {total} fixtures "
      f"({totals[0]} positive incl. {totals[1]} ambiguous, {totals[2]} negative).")
PY
