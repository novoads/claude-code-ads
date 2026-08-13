#!/usr/bin/env bash
# scripts/release.sh — the ONE writer of a release.
#
# A release is four edits and a tag, and the whole point of this script is that
# they are never four separate decisions:
#
#   1. VERSION                       bumped
#   2. every SKILL.md                stamped with metadata.packVersion = VERSION
#   3. CHANGELOG.md                  the unreleased section dated
#   4. one commit                    carrying exactly those
#   5. one tag, ON THAT COMMIT       vX.Y.Z
#
# THE INVARIANT, and why it is the reason this file exists: **the tag commit IS
# the VERSION-bump commit.** gstack shipped the other arrangement — a VERSION
# file bumped by hand on its own schedule, and installs delivered from branch
# HEAD — and got two clocks (gstack#2378). Between bumps, a measured 29-day
# window, installs sat silently behind while reporting themselves up to date,
# and two clones holding different trees reported the same version. One writer,
# one commit, one tag is what keeps our solo channel's clock honest, and the
# script asserts it after tagging rather than trusting itself.
#
# WHAT IT DOES NOT DO: push. Not the branch, not the tag. Releases land through
# a PR like everything else, and `--apply` finishes by printing the checklist of
# steps nothing here automates — including two in the novoads.ai repo, which
# this script cannot see and which no CI will notice are missing.
#
# Usage:
#   ./scripts/release.sh                     dry run, minor bump (the default)
#   ./scripts/release.sh patch               dry run, patch bump
#   ./scripts/release.sh 2.0.0               dry run, explicit version
#   ./scripts/release.sh --apply minor       do it: write, commit, tag
#
# Dry run is the default and prints the complete plan. Nothing is written, no
# commit is made, no tag is created, and the exit code is 0 if the plan is
# sound.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_FILE="$ROOT/VERSION"
CHANGELOG="$ROOT/CHANGELOG.md"
# The platform truncates a description at 1024 and the tail is where the "NOT
# for X, use Y" disambiguation lives. 1000 is the warning line, deliberately
# under the cliff: a description that lands at 1023 is one edit from silently
# stealing its neighbour's sentences. check-skill-frontmatter.sh fails at 1024;
# this only ever warns, because a release must not be blocked by a description
# that is legal today.
DESC_WARN=1000

APPLY=0
STAMP_ONLY=0
BUMP="minor"

while (( $# > 0 )); do
  case "$1" in
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    # Re-stamp every SKILL.md to the CURRENT VERSION and stop. No bump, no
    # changelog, no commit, no tag. This exists because a skill added between
    # releases arrives with no packVersion at all, and nothing else would notice
    # until the next release stamped it — one release late, on a file that spent
    # the whole cycle unable to tell a customer it was behind.
    --stamp-only) STAMP_ONLY=1 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    major|minor|patch) BUMP="$1" ;;
    [0-9]*.[0-9]*.[0-9]*) BUMP="$1" ;;
    *) echo "release: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

die() { printf 'release: %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 is required (it edits the frontmatter)"

# ── Resolve the version ──────────────────────────────────────────────────────
# ANCHORED, and deliberately the same shape migrations/run.sh's _pack_is_semver
# accepts: a version release.sh is willing to write must be one the migration
# runner can order. A glob like [0-9]*.[0-9]*.[0-9]* is not a validator — it
# matched `1.0.0-rc1` and `0#dirt`, and the arithmetic below then failed with
# raw bash noise instead of a sentence anyone could act on.
is_semver() {
  case "${1:-}" in
    *[!0-9.]* | '' | *..* | .* | *.) return 1 ;;
  esac
  local a b c rest
  IFS=. read -r a b c rest <<EOF
$1
EOF
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -z "$rest" ]
}

[ -f "$VERSION_FILE" ] || die "no VERSION file at $VERSION_FILE"
CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
is_semver "$CURRENT" || die "VERSION holds '$CURRENT', which is not an X.Y.Z semver. Fix $VERSION_FILE before releasing."

case "$BUMP" in
  major|minor|patch)
    IFS=. read -r _MA _MI _PA <<EOF
$CURRENT
EOF
    # Normalized through 10# on every component, so a hand-written `01.2.3`
    # cannot bump to `01.3.0` — a string the migration runner would order as
    # 1.3.0 while VERSION and the tag spell it differently.
    _MA=$((10#$_MA)); _MI=$((10#$_MI)); _PA=$((10#$_PA))
    case "$BUMP" in
      major) NEXT="$((_MA + 1)).0.0" ;;
      minor) NEXT="$_MA.$((_MI + 1)).0" ;;
      patch) NEXT="$_MA.$_MI.$((_PA + 1))" ;;
    esac
    ;;
  *) NEXT="$BUMP" ;;
esac
is_semver "$NEXT" || die "'$NEXT' is not an X.Y.Z semver"

# --stamp-only never bumps: it reconciles the skills with the VERSION already on
# disk, which is the only version any of them may honestly claim.
((STAMP_ONLY)) && NEXT="$CURRENT"

TAG="v$NEXT"
DATE="${RELEASE_DATE:-$(date +%Y-%m-%d)}"
HEADING="## $TAG — $DATE"

# ── The frontmatter worker ───────────────────────────────────────────────────
# One implementation, two modes, so what the dry run reports is produced by the
# code that would do the writing rather than by a second description of it.
frontmatter() {
  python3 - "$1" "$NEXT" <<'PY'
import glob, re, sys

mode, version = sys.argv[1], sys.argv[2]
files = sorted(glob.glob("skills/*/SKILL.md") + glob.glob("shared/skills/*/SKILL.md"))

def split_front(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 3)
    if end < 0:
        return None
    return text[4:end + 1], text[end + 1:]

def description_len(front):
    m = re.search(r"description:\s*>-?\s*\n(.*?)(?=\n[a-zA-Z_]+:|\Z)", front, re.S)
    if m:
        return len(" ".join(l.strip() for l in m.group(1).strip().splitlines()))
    m = re.search(r"description:\s*(.+)", front)
    return len(m.group(1).strip()) if m else -1

def stamp(front, version):
    """Set metadata.packVersion without disturbing any other key."""
    # 1. metadata: as a block mapping that already carries packVersion.
    pat = re.compile(r"(^metadata:[ \t]*\n(?:[ \t]+\S.*\n|[ \t]*\n)*?)([ \t]+)packVersion:[ \t]*\S*[ \t]*$",
                     re.M)
    m = pat.search(front)
    if m:
        return pat.sub(lambda x: f"{x.group(1)}{x.group(2)}packVersion: {version}", front, count=1), "updated"
    # 2. metadata: as a block mapping without packVersion — insert as first child.
    m = re.search(r"^metadata:[ \t]*\n", front, re.M)
    if m:
        rest = front[m.end():]
        child = re.match(r"([ \t]+)\S", rest)
        indent = child.group(1) if child else "  "
        return front[:m.end()] + f"{indent}packVersion: {version}\n" + rest, "inserted"
    # 3. metadata: as a flow mapping on one line — the shape this pack ships.
    m = re.search(r"^metadata:[ \t]*\{(.*)\}[ \t]*$", front, re.M)
    if m:
        body = m.group(1)
        if re.search(r"\bpackVersion\s*:", body):
            body = re.sub(r"(\bpackVersion\s*:\s*)[^,}]*", lambda x: x.group(1) + version, body, count=1)
        else:
            body = (body.rstrip() + ", " if body.strip() else "") + f"packVersion: {version}"
        return front[:m.start()] + "metadata: {" + body + "}" + front[m.end():], "updated"
    # 4. No metadata at all — insert it immediately after `name:`.
    #
    # NOT at the end of the frontmatter, which is where this used to put it.
    # `description` is the last key and by far the highest-churn line in the
    # file, so a stamp sitting against its tail shares a diff hunk with every
    # description edit anyone makes: 2 of 16 skills conflicted within 5 commits
    # of main. `name:` is the one line in this frontmatter that never moves.
    m = re.search(r"^name:[ \t]*\S.*$", front, re.M)
    if m:
        return front[:m.end()] + f"\nmetadata: {{packVersion: {version}}}" + front[m.end():], "added"
    # No `name:` either — this is not a skill frontmatter we understand. Leave it.
    return front, "skipped"

stamped = warned = 0
for path in files:
    text = open(path, encoding="utf-8").read()
    parts = split_front(text)
    if parts is None:
        print(f"SKIP   {path}: no parsable frontmatter", file=sys.stderr)
        continue
    front, body = parts
    n = description_len(front)
    if n > 1000:
        print(f"WARN   {path}: description is {n} chars — over 1000, and the cap is 1024.")
        warned += 1
    new_front, _how = stamp(front, version)
    if new_front != front:
        stamped += 1
        if mode == "apply":
            open(path, "w", encoding="utf-8").write("---\n" + new_front + body)
print(f"COUNT  {len(files)} SKILL.md files · {stamped} need the stamp rewritten · {warned} description warning(s)")
PY
}

# ── The changelog worker ─────────────────────────────────────────────────────
# Dates the unreleased section in place and opens a fresh one above it. It never
# invents prose: if there is nothing under an unreleased heading, that is an
# author's job that has not been done and the release stops.
changelog() {
  python3 - "$1" "$HEADING" "$CHANGELOG" <<'PY'
import re, sys

mode, heading, path = sys.argv[1], sys.argv[2], sys.argv[3]
target = heading.split()[1].lstrip("v")
text = open(path, encoding="utf-8").read()

# `## Unreleased`, or `## v1.1.0 (unreleased)` — both are shapes this file has had.
m = re.search(r"^##[ \t]+(?:v?([0-9][0-9.]*)[ \t]+)?\(?[Uu]nreleased\)?[ \t]*$", text, re.M)
if m and m.group(1) and m.group(1) != target:
    # The section names the version its entries describe. Promoting it to a
    # different number would relabel somebody else's release notes, and the
    # relabelling is invisible afterwards — the heading looks deliberate.
    print(f"ERROR  the unreleased section is labelled v{m.group(1)}, but this release is v{target}.")
    print(f"       Release v{m.group(1)} first (./scripts/release.sh --apply {m.group(1)}),")
    print(f"       or retitle the section if its entries really belong to v{target}.")
    raise SystemExit(3)
if not m:
    print("ERROR  no `## Unreleased` section in CHANGELOG.md.")
    print("       Write the entry first — this script dates a release, it does not invent one.")
    print("       Group it as Added / Changed / Fixed, or as dated `###` subsections like the rest of the file.")
    raise SystemExit(3)

nxt = re.search(r"^##[ \t]+", text[m.end():], re.M)
body = text[m.end(): m.end() + nxt.start()] if nxt else text[m.end():]
if not body.strip():
    print("ERROR  the `## Unreleased` section is empty. A release with no changelog entry is not a release.")
    raise SystemExit(3)

new = text[:m.start()] + "## Unreleased\n\n" + heading + text[m.end():]
print(f"PLAN   {text[m.start():m.end()].strip()!r} becomes {heading!r}")
print(f"       {len([l for l in body.strip().splitlines() if l.strip()])} non-blank line(s) of entry carried into it")
print("       a fresh `## Unreleased` is opened above it for the next cycle")
if mode == "apply":
    open(path, "w", encoding="utf-8").write(new)
PY
}

# ── Stamp-only ───────────────────────────────────────────────────────────────
if ((STAMP_ONLY)); then
  printf '\nre-stamping every SKILL.md to the VERSION on disk (%s)\n' "$CURRENT"
  frontmatter "$( ((APPLY)) && echo apply || echo plan )" | sed 's/^/  /'
  rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] || die "the frontmatter pass failed"
  ((APPLY)) || printf '\nNothing was written. Re-run with --apply --stamp-only to execute.\n'
  printf '\n'
  exit 0
fi

# ── Report ───────────────────────────────────────────────────────────────────
printf '\n'
printf 'novoads pack release — %s\n' "$( ((APPLY)) && echo 'APPLY' || echo 'DRY RUN (nothing is written; pass --apply to execute)' )"
printf '%s\n' "────────────────────────────────────────────────────────────────────"
printf 'VERSION      %s -> %s   (%s)\n' "$CURRENT" "$NEXT" "$BUMP"
printf 'tag          %s, on the commit that bumps VERSION\n' "$TAG"
printf 'date         %s\n' "$DATE"
printf '\nskill stamps\n'
frontmatter plan | sed 's/^/  /'
FM_RC=${PIPESTATUS[0]}
printf '\nchangelog\n'
changelog plan | sed 's/^/  /'
CL_RC=${PIPESTATUS[0]}
[ "${FM_RC:-0}" -eq 0 ] || die "the frontmatter pass failed"
[ "${CL_RC:-0}" -eq 0 ] || die "the changelog is not ready"

# ── The checklist, printed in both modes ─────────────────────────────────────
# In the dry run it is the thing you read before deciding; on --apply it is the
# thing you do next. Steps 2 and 3 are in a DIFFERENT REPOSITORY, nothing
# automates them, and nothing fails when they are skipped — the well-known index
# just keeps serving the previous tag and the /v1 header keeps advertising the
# previous version, both of them quietly and indefinitely.
print_checklist() {
  cat <<CHECKLIST

after this release — nothing below is automated, and nothing fails if it is skipped
────────────────────────────────────────────────────────────────────
  1. Push the branch and the tag (this script never pushes):
       git push origin HEAD
       git push origin $TAG
     Open the PR; do not merge your own release.

  2. In the novoads.ai repo — refresh the well-known skill index:
       pnpm pack:refresh-wellknown && open a PR
     The index is pinned to the LATEST TAG. Release without this and it keeps
     serving $CURRENT's tree from a URL that claims to be current. Nothing
     notices: every digest still matches, because they are $CURRENT's digests.

  3. In the novoads.ai repo — bump the header constant:
       SKILL_PACK_LATEST_VERSION = "$NEXT"   in lib/config/skill-pack.ts
     Open a PR. This is what every /v1 response tells an installed pack, and it
     is how a clone learns it is behind. It is bumped AFTER the tag is pushed,
     never before: a header naming a tag that does not exist yet sends people to
     a 404, and under-reporting is the safe direction to be wrong in.
CHECKLIST
}

if ((!APPLY)); then
  print_checklist
  printf '\nNothing was written. Re-run with --apply to execute this plan.\n\n'
  exit 0
fi

# ── Apply ────────────────────────────────────────────────────────────────────
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
git symbolic-ref -q HEAD >/dev/null || die "HEAD is detached; check out a branch first"
[ -z "$(git status --porcelain)" ] || die "the working tree is dirty. Commit or stash first — a release commit carries the release and nothing else."
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"

printf '\napplying…\n'
printf '%s\n' "$NEXT" > "$VERSION_FILE"
frontmatter apply | sed 's/^/  /' || die "stamping failed"
changelog  apply | sed 's/^/  /' || die "changelog rewrite failed"

git add -- VERSION CHANGELOG.md skills shared/skills || die "git add failed"
git commit -q -m "release: $TAG" || die "commit failed"
git tag -a "$TAG" -m "$TAG" || die "tag failed"

# ── The invariant, asserted against the TAG'S OWN CONTENTS ───────────────────
# Not "does the tag point at HEAD" — this script just created the tag on HEAD,
# so that question answers itself and proves nothing. The claim worth checking
# is the one the solo channel depends on: **the commit this tag names is the
# commit that carries the version change.** Ask the tag, by name, what it
# contains, and require VERSION and the stamps to be in it.
TAGGED="$(git rev-parse -q --verify "$TAG^{commit}")"
[ -n "$TAGGED" ] || die "INVARIANT BROKEN: $TAG does not resolve to a commit"

# `$TAG^{commit}`, never a bare `$TAG`: `git show` on an ANNOTATED tag prints the
# tag header first, so the file list would carry the tag message with it and a
# message containing a line `VERSION` would satisfy the check below without a
# single file being in the commit.
TAG_FILES="$(git show --pretty=format: --name-only "$TAG^{commit}" | sed '/^$/d')"
printf '%s\n' "$TAG_FILES" | grep -qx 'VERSION' \
  || die "INVARIANT BROKEN: the commit tagged $TAG does not change VERSION. A tag whose commit does not carry the version is the two-clocks bug."
STAMPED_IN_TAG="$(printf '%s\n' "$TAG_FILES" | grep -c 'SKILL\.md$')"
[ "$STAMPED_IN_TAG" -gt 0 ] \
  || die "INVARIANT BROKEN: the commit tagged $TAG carries no SKILL.md stamps, so the skills claim a version their tag never shipped."

# And the bytes, not just the filename: VERSION inside the tagged tree must be
# the version the tag is named for.
IN_TAG="$(git show "$TAG:VERSION" 2>/dev/null | tr -d '[:space:]')"
[ "$IN_TAG" = "$NEXT" ] \
  || die "INVARIANT BROKEN: $TAG:VERSION reads '$IN_TAG', but the tag is named for $NEXT"

git show --stat --oneline "$TAGGED" | head -1 | sed 's/^/  commit  /'
printf '  tag     %s -> %s\n' "$TAG" "${TAGGED:0:12}"
printf '  proved  %s:VERSION == %s, and %s SKILL.md stamp(s) ride the same commit\n' \
  "$TAG" "$IN_TAG" "$STAMPED_IN_TAG"

print_checklist
printf '\n'
