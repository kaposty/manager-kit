#!/usr/bin/env bash
# check.sh: goes red when the structure is decorative.
#
# WHY THIS FILE IS THE POINT OF THE BLUEPRINT, and not the templates next to it. A rule
# written into an instruction file measurably cuts violations and never reaches zero, so a
# blueprint made of rules is guaranteed to leak, and it leaks silently: the folders are
# there, the headings are there, and nothing says the content underneath is hollow. That is
# not a hypothesis, it is the failure mode of every project-structure recipe, and it is the
# reason this file exists. The templates are seeds. This is what holds them.
#
# The bar it enforces is NOT "everything must be filled in". A checker that is red on day one
# for everybody teaches people to ignore it, which costs more than it buys. The bar is
# narrower and it never gets easier: NOTHING MAY BE DECORATIVE. A project that grew a heading
# and left it hollow is red. One check is red on an empty project ON PURPOSE, the stopping
# condition, because writing that down is the first move and takes two minutes.
#
# Portable to bash 3.2 and BSD userland, because that is what macOS ships.
set -u

# THIS FILE IS COPIED INTO OTHER PEOPLE'S PROJECTS AND THEN NEVER HEARS FROM HOME AGAIN. It
# used to travel without a version, without a source and without a digest, while reading the
# manifest of its own dependency to solve exactly that problem for somebody else. A copy that
# cannot name where it came from cannot be told that it is behind. Both files carry the
# version and the suite asserts they agree, which catches the half of the drift that is ours.
BLUEPRINT_VERSION="2.0.1"
BLUEPRINT_SOURCE="https://github.com/kaposty/blueprint"

# Argument handling sits ABOVE the completion sentinel on purpose: the sentinel treats any
# exit before the verdict as a death, so a clean `--version` would be reported as a crash.
case "${1:-}" in
  --version|-V) printf 'blueprint %s\n%s\n' "$BLUEPRINT_VERSION" "$BLUEPRINT_SOURCE"; exit 0 ;;
  --quiet|-q) QUIET=1 ;;
  "") ;;
  *) printf 'unknown argument: %s\nusage: bash check.sh [--quiet|--version]\n' "$1" >&2; exit 2 ;;
esac

# QUIET IS FOR THE COMMIT PATH, NOT FOR HIDING THINGS. Run by a person, this prints every line
# it has, because a person asked. Run from the pre-commit hook it must say NOTHING while
# everything is fine: seven ok lines on every single commit is exactly the noise that teaches
# people to stop reading, and this whole version exists to remove it. Findings are printed in
# both modes, and so is a crash.
QUIET="${QUIET:-0}"

FAIL=0
RED() { printf 'RED  %s\n       %s\n' "$1" "$2"; FAIL=1; }
OK()  { [ "$QUIET" -eq 1 ] || printf 'ok   %s\n' "$1"; }

# DAY ONE IS NOT A DEFECT. Two checks below are about answers a project has not had time to
# give yet: the blanks in the seeds, and the stopping condition. Until 2.0 they went red
# immediately and blocked the very first commit, which was the loudest thing this tool did and
# the reason it could not be installed quietly. They now hold until the repository has one
# commit, and they say so rather than going quiet. The other four bite from the start, because
# none of them is red on a fresh project anyway.
# ONLY INSIDE A REPOSITORY THAT HAS NOT COMMITTED YET. A directory that is not a git
# repository at all is not "day one": no first commit is ever coming, so holding the checks
# there would silence them permanently, in exactly the projects that have no other guard.
# The first version of this block missed that distinction and three existing assertions went
# red over a plain directory, which is how it was found.
DAY_ONE=0
if git rev-parse --git-dir >/dev/null 2>&1; then
  _COMMITS="$(git rev-list --count HEAD 2>/dev/null || printf 0)"
  case "$_COMMITS" in ''|*[!0-9]*) _COMMITS=0 ;; esac
  [ "$_COMMITS" -eq 0 ] && DAY_ONE=1
fi

# soft_red: a real finding that must not stop a project that has not started. Returns 1 when
# it held the finding back, so the caller knows to skip its detail list.
soft_red() {
  if [ "$DAY_ONE" -eq 1 ]; then
    SKIP "$1: held until this repository has its first commit"
    return 1
  fi
  RED "$1" "$2"
  return 0
}
# A CHECK THAT STANDS DOWN IS NOT A CHECK THAT PASSED, and printing nothing makes the two
# identical for every reader. Measured in the kit this composes: a check reported "not
# applicable" nowhere and was read as green for as long as nobody went to look at the source.
# The marker goes in as an ARGUMENT, not in the format string: `printf '--  ...'` reads the
# leading -- as end-of-options and prints a usage error instead of the line. Caught by the
# assertion above, on the first version of this very function.
# Suppressed under --quiet along with the ok lines, and ONLY there. The rule this obeys is
# that a stand-down must never be invisible to somebody who is looking, and under --quiet
# nobody is: that mode exists for the commit path, where the person asked git for something
# and not this. Run `bash check.sh` by hand and every stand-down is on the screen again.
SKIP() { [ "$QUIET" -eq 1 ] || printf '%s   %s\n' '--' "$1"; }

# A CHECKER THAT DIES MUST GO RED, never silently green, because "no output" reads as "no
# problems" to every human and every CI job that has ever looked at one.
#
# The first attempt at this was itself decorative, which is the joke this file cannot afford:
# it trapped ERR, and an ERR trap without `set -e` does not fire, so the guard against a
# silent death was a silent no-op. `set -e` is not the fix either, because the checks below
# lean on tests that legitimately return non-zero. What works is a completion sentinel: the
# verdict is only reachable after DONE is set, so any death before that point, a syntax
# error, an unset variable under `set -u`, a signal, lands here instead of looking clean.
DONE=0
_finish() {
  RC=$?
  [ "$DONE" -eq 1 ] && return
  printf 'RED  the checker stopped before finishing (exit %s)\n' "$RC"
  printf '       A check that cannot complete has not passed. Fix the checker, then re-run.\n'
  exit 1
}
trap _finish EXIT

# WHERE THE BOOKKEEPING IS, AND THE TWO CASES ARE NOT THE SAME SHAPE. BOOK is the prefix
# from here to the directory that holds this project's .claude/. It is derived once, so
# that the checks below go on writing .claude/ the way they always did.
#
#   THE INSTALLED CASE, and it is the one this file was written for: check.sh sits at the
#   top of somebody's project and .claude/ is right beside it. BOOK stays EMPTY and every
#   path below is byte for byte the one it was before this block existed.
#
#   THE KIT CASE: this file ships inside a package directory of its own repository, and
#   the bookkeeping stays at the repository root, because Claude Code dictates where
#   settings.json and the development hooks live and moving them would switch them off.
#   BOOK becomes ../ and the same paths reach back out of the package.
#
# Measured 2026-09-07, run from the package with no derivation at all: checks 3, 4, 5, 6
# and 7 all stood down over a project that still had everything they look for, and the
# run ended in "green: nothing here is decorative". Five checks looking at nothing is the
# silent half of the two ways to be wrong.
#
# THE WALK IS BOUNDED BY THE REPOSITORY and never leaves it. An unbounded walk upwards
# finds $HOME/.claude on almost every machine and would read the person's own Claude
# configuration as this project's bookkeeping. BOOK also stays empty outside a repository
# altogether, so the non-git branch of every derivation below is only ever reached with
# BOOK empty and is left exactly as it was.
# SELF_DIR is where this file itself stands, which is the top of its own delivery. Used
# by check 7 only, and never as the subject: the subject is always the working directory.
# Left exactly as spelled on the command line rather than resolved to an absolute path,
# because check 7 PRINTS it, and an absolute path puts this machine's home directory into
# the output of the one check that exists to keep that name out of what ships.
SELF_DIR="$(dirname -- "$0")"
BOOK=""
if [ ! -d .claude ] && git rev-parse --show-toplevel >/dev/null 2>&1; then
  _top="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
  _here="$(pwd -P)"
  _rest="${_here#"$_top"/}"
  # A strip that changed nothing means this directory is not spelled under that top, which
  # is what a symlinked checkout looks like. Counting components off it would climb out of
  # the repository, so it counts none.
  [ "$_rest" = "$_here" ] && _rest=""
  if [ -n "$_top" ] && [ -d "$_top/.claude" ] && [ -n "$_rest" ]; then
    while [ -n "$_rest" ]; do
      BOOK="../$BOOK"
      case "$_rest" in */*) _rest="${_rest#*/}" ;; *) _rest="" ;; esac
    done
  fi
fi

# THE FILE SET IS DERIVED, NOT TYPED. A typed list covers the files that existed when
# somebody typed it, and the one it misses is always the newest.
#
# --others IS NOT OPTIONAL, and leaving it out was the first defect this checker had. The
# first version asked git for the tracked files, which is a perfectly reasonable-looking way
# to derive the set and is wrong for exactly the case this tool exists for: a project on day
# one has committed nothing, so the set came back empty, every loop below ran over nothing,
# and the checker reported green over a repository that was pure placeholder. It went green
# on the state it was written to catch. --cached plus --others --exclude-standard is the
# world minus what you deliberately ignore, which is the set that was meant all along.
# AND IT IS THE PROJECT'S SET, NOT THE PACKAGE'S. What checks 1, 3 and 4 audit is what
# this project WROTE, and in the kit case the ledger carrying every verified claim sits in
# the bookkeeping, one level out of the package. Derived from the package instead, all
# three stood down over a repository whose stores were still exactly where they were.
if git rev-parse --git-dir >/dev/null 2>&1; then
  FILES="$(git -C "${BOOK:-.}" ls-files --cached --others --exclude-standard '*.md' 2>/dev/null \
             | sed "s|^|$BOOK|" | sort -u)"
else
  FILES="$(find . -name '*.md' -not -path './.git/*' 2>/dev/null | sed 's|^\./||')"
fi
# ONE EXCEPTION, SUBTRACTED WITH ITS REASON, which is how exceptions are supposed to enter a
# derived set. `seeds/` holds the templates this blueprint hands to other projects, and a
# template is placeholder BY DEFINITION. Without this line the blueprint could never pass its
# own checker, which would leave it in the position of shipping a rule it does not keep.
# THE EXCEPTION USED TO TRAVEL. This line is copied verbatim into every seeded project, and
# `seeds/` is an ordinary directory name out there (Rails, Laravel, Phoenix), where it silently
# stopped checking real work. It is now gated on the blueprint's own shape, an `init.sh` beside
# a `seeds/`, and it says so out loud, because a subtraction nobody sees is a check nobody has.
SEEDS_OWN=0
if [ -f init.sh ] && [ -d seeds ]; then
  FILES="$(printf '%s\n' "$FILES" | grep -v '^seeds/' || true)"
  SEEDS_OWN=1
fi

# A SECOND EXCEPTION, and this one is DERIVED rather than typed. A project that installs a
# dependency into .claude/ has that dependency's own documentation in the world, and auditing
# it produces a verdict the reader is NOT ALLOWED to clear: those files are installation
# copies, owned by the tool that wrote them, and editing them is what that tool forbids.
# Measured 2026-08-19 against context-kit 1.6.2, the first time the two ran on one project:
# its ledger template carries `- <fact> [<what proved it>]` under a VERIFIED heading and came
# back as an unproven claim. A red nobody may clear teaches people to mute the checker.
# The subtraction reads the manifest the dependency writes for itself, so anything it did not
# deliver stays yours and stays checked: your own skills, and above all the ledger beside them.
if [ -f "${BOOK}.claude/.kit-manifest" ]; then
  VENDORED="$(awk -v B="$BOOK" '/^[0-9a-f][0-9a-f]*[[:space:]]/ {
                     sub(/^[0-9a-f]+[[:space:]]+/, ""); print B ".claude/" $0 }' \
                   "${BOOK}.claude/.kit-manifest" 2>/dev/null)"
  # NEVER hand `grep -F` an empty pattern. It matches every line, the -v below would then
  # delete the entire file set, and this checker would go green by having nothing left to
  # check: silent, and in the direction that looks like success.
  [ -n "$VENDORED" ] && FILES="$(printf '%s\n' "$FILES" | grep -vxF "$VENDORED" || true)"
fi

# ---------------------------------------------------------------------------
# 1. No placeholder survives contact with the project.
#
# Every seed here carries <<FILL: ...>> where a decision belongs. The marker is deliberately
# ugly and unambiguous: it cannot be mistaken for prose, and it cannot be half-answered. A
# seeded file that still carries one is a file nobody has thought about, and it is worse than
# no file, because it looks like an answer.
#
# A MARKER INSIDE BACKTICKS IS BEING QUOTED, NOT USED, and missing that distinction was the
# fourth defect here. The README documents what the marker looks like, so the checker read
# its own documentation as an unfilled placeholder and went red on a file that was finished.
# A check that fires on correct work is not strict, it is broken: people silence it, and then
# it protects nothing. Inline code spans are removed before counting.
# A FILENAME WITH A SPACE IS STILL A FILE. `for f in $FILES` word-splits on every blank, so
# `Design Notes.md` arrived as two halves, `[ -f ]` dropped both, and the checker printed ok
# over a file it had never opened. Silent, and in the direction that looks like success.
# Measured by Council #4. Reading the list line by line is the only shape that cannot do that.
# AND IT REPORTS THE DECISIONS, NOT THEIR COUNT. `still placeholder: GOAL.md(5) CLAUDE.md(4)`
# tells the reader that nine things are open and nothing about what they are, while two other
# checks print file:line cleanly. The promise on the README is a LIST, so this prints one.
[ "$SEEDS_OWN" -eq 1 ] && SKIP "seeds/ holds the templates this blueprint hands out, and a template is placeholder by definition, so those files are not audited"
HOLLOW=""; HOLLOW_N=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Code spans are stripped for the DETECTION only. Stripping them for the DISPLAY too ate the
  # backticked command out of the question and printed a mangled sentence, so the line that was
  # supposed to tell you what to answer no longer did. One pass, two variables.
  HITS="$(awk -v F="$f" '
    {
      s = $0
      gsub(/`[^`]*`/, "", s)
      if (s !~ /<<FILL:/) next
      q = $0
      sub(/^.*<<FILL:[[:space:]]*/, "", q)
      sub(/>>.*$/, "", q)
      if (length(q) > 68) q = substr(q, 1, 65) "..."
      printf "         %s:%d  %s\n", F, NR, q
    }' "$f" 2>/dev/null)"
  [ -n "$HITS" ] || continue
  N="$(printf '%s\n' "$HITS" | grep -c . || true)"
  case "$N" in ''|*[!0-9]*) N=0 ;; esac
  HOLLOW_N=$((HOLLOW_N + N))
  HOLLOW="$HOLLOW$HITS
"
done <<FILELIST
$FILES
FILELIST
if [ -z "$HOLLOW" ]; then
  OK "no file is still carrying a placeholder"
else
  if soft_red "a seeded file was never filled in" "$HOLLOW_N decision(s) nobody has made yet:"; then
    printf '%s' "$HOLLOW"
  fi
fi

# ---------------------------------------------------------------------------
# 2. The goal states how you would know it is reached.
#
# A goal without a stopping condition is a direction, and a direction cannot be missed, so it
# cannot be met either. This is the one check that is red on an empty project ON PURPOSE:
# writing it down is the first move, it takes two minutes, and everything downstream is
# measured against it.
if [ ! -f GOAL.md ]; then
  RED "there is no GOAL.md" "the blueprint seeds one, run init.sh or write it by hand"
else
  DONE_LINE="$(grep -inE '^[[:space:]]*(done when|fertig, wenn|abbruch)' GOAL.md 2>/dev/null | head -1 || true)"  # de-input
  if [ -z "$DONE_LINE" ]; then
    soft_red "the goal has no stopping condition" "GOAL.md needs a line starting with 'Done when'" || true
  else
    # A PLACEHOLDER IS NOT AN ANSWER, and treating it as one was the second defect here. The
    # first version only asked whether anything followed "Done when", and a seed that reads
    # "Done when: <<FILL: ...>>" satisfies that perfectly while saying nothing at all. The
    # emptier a check is, the more confidently it passes.
    BODY="$(printf '%s' "$DONE_LINE" | sed -E 's/^[0-9]+:[[:space:]]*(done when|fertig, wenn|abbruch)[:,]?//I')"  # de-input
    case "$BODY" in
      *'<<FILL:'*) soft_red "the stopping condition is still the placeholder" "GOAL.md:${DONE_LINE%%:*}" || true ;;
      *) case "$(printf '%s' "$BODY" | tr -d '[:space:]')" in
           ''|'.'|'...'|'TODO'|'tbd'|'TBD') soft_red "the stopping condition is empty" "GOAL.md:${DONE_LINE%%:*}" || true ;;
           # This verifies that a stopping condition is THERE, not that it could turn out
           # false, and the wording used to claim the second. Falsifiability is not machine
           # checkable, and a check may only assert what it measured.
           *) OK "the goal names a stopping condition" ;;
         esac ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# 3. A verified claim carries what proved it.
#
# A claim without its provenance is a belief, and beliefs are what a later session re-derives
# from scratch or, worse, trusts. The rule is cheap at writing time and expensive to add back
# later, because by then nobody remembers which command produced the number.
#
# The stores are DERIVED: any markdown file that has a VERIFIED or BELEGT heading is one,
# wherever it lives. Evidence counts as a backticked command, a path, or a number.
# A BULLET IS NOT ITS FIRST LINE. This tested one line and the evidence lives on the wrap, so
# the better the proof the longer the entry, the more likely it wrapped and the more likely it
# was reported. Measured by Council #4 against the only store that grew honestly over weeks:
# 11 of its 26 entries were called unproven, most of them carrying a backticked command two
# characters past the fold. A check that fires on correct work gets silenced, and then it
# protects nothing. The bullet is now accumulated to its blank line and judged as one text.
UNPROVEN=""; STORES=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -qiE '^#+[[:space:]]*(VERIFIED|BELEGT)' "$f" 2>/dev/null || continue
  STORES=$((STORES + 1))
  UNPROVEN="$UNPROVEN$(awk '
    # THE SHAPE OF AN ENTRY IS NOT AN ENTRY. Found by the first real installation: a skill
    # file documenting what a ledger entry looks like carries `- <fact> [<the command that
    # proved it>]` under a VERIFIED heading, and that was reported as a claim with no proof.
    # Narrow on purpose: a bullet counts as a template only when NOTHING is left after every
    # <...> group is removed, so one placeholder inside a real sentence is still a real entry.
    function is_template(s) {
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", s)
      gsub(/<[^>]*>/, "", s)
      gsub(/[^A-Za-z0-9]/, "", s)
      return (s == "")
    }
    function flush() {
      if (ln > 0 && !is_template(buf) && buf !~ /`/ && buf !~ /[0-9]/) printf " %s:%d", FILENAME, ln
      buf = ""; ln = 0
    }
    /^#+[[:space:]]*([Vv][Ee][Rr][Ii][Ff][Ii][Ee][Dd]|[Bb][Ee][Ll][Ee][Gg][Tt])/ { flush(); inb=1; next }
    /^#+[[:space:]]/ { flush(); inb=0; next }
    inb && /^[[:space:]]*[-*][[:space:]]/ { flush(); buf=$0; ln=NR; next }
    inb && /^[[:space:]]*$/ { flush(); next }
    inb { if (ln > 0) buf = buf " " $0 }
    END { flush() }' "$f")"
done <<FILELIST
$FILES
FILELIST
# A STORE THAT DOES NOT EXIST IS NOT A CLEAN STORE. This printed ok over a project that had no
# VERIFIED heading anywhere, which is a green line for a check that looked at nothing.
if [ "$STORES" -eq 0 ]; then
  SKIP "no file records a verified claim, so there was nothing to check (this check stood down)"
elif [ -z "$UNPROVEN" ]; then
  OK "every verified claim carries its command or its number"
else
  RED "a claim is recorded as verified with nothing that proved it" "unproven:${UNPROVEN}"
fi

# ---------------------------------------------------------------------------
# 4. An abandoned path carries its reason.
#
# Without the reason it gets proposed again, by a later session or by the same person three
# months on, and the second refusal costs the same as the first. Measured in the kit this
# composes: an item filed as "postponed" rather than "dropped" came back the moment its
# condition was met, and had to be refused a second time.
#
# WHAT THIS ASKS, AND WHAT IT CANNOT. The first version looked for `because`, `weil` (de-input), a colon
# or a comma, and measured against 16 entries that grew over weeks in three real stores it was
# wrong BOTH ways: it reported 2, and both of those carried a plain reason that happened to
# contain no comma, while an entry packing eight dropped items into one bullet, five of them
# with no reason at all, passed because commas were everywhere. Punctuation is not a reason.
# This asks instead whether anything of substance follows the thing being dropped: 0 of the
# same 16 are reported and every bare entry is still caught. It CANNOT judge whether a
# sentence that is there is a good reason, and it will still miss several dropped things
# packed into one bullet where the first one carries the only explanation. Both limits are
# stated in GOAL.md rather than papered over.
UNREASONED=""; DSTORES=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -qiE '^#+[[:space:]]*(DROPPED|VERWORFEN)' "$f" 2>/dev/null || continue
  DSTORES=$((DSTORES + 1))
  UNREASONED="$UNREASONED$(awk '
    # THE SHAPE OF AN ENTRY IS NOT AN ENTRY. Found by the first real installation: a skill
    # file documenting what a ledger entry looks like carries `- <fact> [<the command that
    # proved it>]` under a VERIFIED heading, and that was reported as a claim with no proof.
    # Narrow on purpose: a bullet counts as a template only when NOTHING is left after every
    # <...> group is removed, so one placeholder inside a real sentence is still a real entry.
    function is_template(s) {
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", s)
      gsub(/<[^>]*>/, "", s)
      gsub(/[^A-Za-z0-9]/, "", s)
      return (s == "")
    }
    function words(s,   a) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return (s == "") ? 0 : split(s, a, /[[:space:]]+/)
    }
    function flush(   c, rest, i, a, n, j) {
      if (ln == 0) return
      c = buf
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", c)
      if (c ~ /^\*\*/) { i = index(substr(c, 3), "**"); rest = (i > 0) ? substr(c, i + 4) : "" }
      else if (match(c, /[,:;]/)) { rest = substr(c, RSTART + 1) }
      else { n = split(c, a, /[[:space:]]+/); rest = ""; for (j = 4; j <= n; j++) rest = rest " " a[j] }
      if (!is_template(buf) && words(rest) < 4) printf " %s:%d", FILENAME, ln
      buf = ""; ln = 0
    }
    /^#+[[:space:]]*([Dd][Rr][Oo][Pp][Pp][Ee][Dd]|[Vv][Ee][Rr][Ww][Oo][Rr][Ff][Ee][Nn])/ { flush(); inb=1; next }
    /^#+[[:space:]]/ { flush(); inb=0; next }
    inb && /^[[:space:]]*[-*][[:space:]]/ { flush(); buf=$0; ln=NR; next }
    inb && /^[[:space:]]*$/ { flush(); next }
    inb { if (ln > 0) buf = buf " " $0 }
    END { flush() }' "$f")"
done <<FILELIST
$FILES
FILELIST
if [ "$DSTORES" -eq 0 ]; then
  SKIP "no file records a dropped path, so there was nothing to check (this check stood down)"
elif [ -z "$UNREASONED" ]; then
  OK "every abandoned path carries its reason"
else
  RED "a path is recorded as dropped with no reason" "unreasoned:${UNREASONED}"
fi

# ---------------------------------------------------------------------------
# 5. If the reasoning carrier is installed, it is actually wired.
#
# Files without wiring are the most convincing kind of nothing: the directory listing looks
# complete and not one hook runs. Measured in a real project on 2026-08-17, which carried
# skills/ and tools/ and had not a single hook wired, for weeks, with nobody noticing.
HOOKS=0
if [ -d "${BOOK}.claude" ]; then
  HOOKS="$(ls "${BOOK}.claude/hooks/"*.sh 2>/dev/null | wc -l | tr -d ' ')"
fi
if [ "${HOOKS:-0}" -gt 0 ]; then
  WIRED=0
  for s in "${BOOK}.claude/settings.json" "${BOOK}.claude/settings.local.json"; do
    [ -f "$s" ] || continue
    # `grep -c` PRINTS 0 AND EXITS 1 when nothing matches, so a `|| echo 0` fallback fired in
    # addition to the zero already printed. The arithmetic then saw "0\n0", bash raised a
    # syntax error, and the whole branch was abandoned: no ok, no RED, no stand-down, and a
    # green run over the exact half install this check exists to catch. Council #4 found it on
    # the flagship case of the README, with a settings file present that wired something else.
    n="$(grep -c 'claude/hooks/' "$s" 2>/dev/null)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    WIRED=$((WIRED + n))
  done
  # A MANIFEST IS NOT WIRING. The file merely existing was accepted as proof that something
  # runs the hooks, which is the same convincing kind of nothing named above: a plugin.json
  # with no hook declaration at all cleared the check. It counts when it declares hooks.
  if [ -f .claude-plugin/plugin.json ]; then
    if grep -q '"hooks"' .claude-plugin/plugin.json 2>/dev/null; then
      WIRED=$((WIRED + 1))
    elif [ -f hooks/hooks.json ] || [ -f .claude-plugin/hooks/hooks.json ]; then
      WIRED=$((WIRED + 1))
    fi
  fi
  [ "$WIRED" -gt 0 ] && OK "the hooks on disk are wired to something" \
    || RED "hook files are installed but nothing runs them" \
           "$HOOKS script(s) under ${BOOK}.claude/hooks and no entry in any settings file"
else
  # A CARRIER CAN RUN WITHOUT PUTTING ANYTHING IN THE PROJECT. The plugin path, the one init.sh
  # itself recommends, installs into the user's Claude configuration and leaves .claude/hooks
  # empty, so this used to print "no carrier installed" on a machine where the carrier was
  # running. That is not an unhelpful line, it is a false one, and two reviewers found it
  # independently. The lookup is deliberately literal because there is no JSON parser here:
  # whitespace out, the enabledPlugins object out, entries that say true kept. When it finds
  # nothing the wording says what was SEARCHED and not what is true, because a check may only
  # claim what it measured.
  CARRIER=""
  for _s in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" \
            "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.local.json"; do
    [ -f "$_s" ] || continue
    CARRIER="$(tr -d ' \t\n' < "$_s" 2>/dev/null \
                 | sed -n 's/.*"enabledPlugins":{\([^}]*\)}.*/\1/p' \
                 | tr ',' '\n' | sed -n 's/^"\([^"]*context-kit[^"]*\)":true$/\1/p' | head -1)"
    [ -n "$CARRIER" ] && break
  done
  if [ -n "$CARRIER" ]; then
    SKIP "the carrier runs as a plugin (${CARRIER}), so there is nothing to wire in this project"
  else
    SKIP "no carrier in this project, and none was found among the enabled plugins (stood down)"
  fi
fi

# ---------------------------------------------------------------------------
# 6. A settings file that is not valid JSON.
#
# THE MOST EXPENSIVE FAILURE IN THIS WHOLE FAMILY, and the only one on this list that is
# total. A single stray comma does not disable one hook: the runtime discards the ENTIRE file,
# so every hook, every permission and every environment line in it stops existing, and nothing
# anywhere says so. Measured in the kit this composes: nineteen hours of a session running
# with no guardrails at all, green everywhere, because "no output" and "no config" look
# identical from the outside.
SETTINGS_FILES="$(find "${BOOK}.claude" -maxdepth 2 -name 'settings*.json' 2>/dev/null | sort)"
if [ -z "$SETTINGS_FILES" ]; then
  SKIP "no settings file in this project, so there was nothing to parse (this check stood down)"
elif ! command -v python3 >/dev/null 2>&1; then
  SKIP "python3 is not on PATH, so the settings files could not be parsed (this check stood down)"
else
  BROKEN=""
  while IFS= read -r sf; do
    [ -f "$sf" ] || continue
    ERR="$(python3 -I -c 'import io,json,sys
try:
    json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    sys.stdout.write(str(exc))' "$sf" 2>/dev/null)"
    [ -n "$ERR" ] && BROKEN="$BROKEN
         $sf  $ERR"
  done <<SETTINGSLIST
$SETTINGS_FILES
SETTINGSLIST
  if [ -n "$BROKEN" ]; then
    RED "a settings file is not valid JSON" "the runtime discards the whole file, silently:$BROKEN"
  else
    OK "every settings file parses"
  fi
fi

# ---------------------------------------------------------------------------
# 7. The delivered files are still the ones that arrived.
#
# A SEEDED PROJECT USED TO BE FROZEN AT THE DAY IT WAS SEEDED. init.sh copied once, there was
# no way home, and this file said so in its own header while reading somebody else's manifest
# to solve exactly that problem for them. The manifest below is the return path.
#
# A CHANGED FILE IS NOT A DEFECT. You are allowed to edit anything here; it just means the
# copy is yours now and a later run will never touch it. That is reported, not failed. A
# MISSING one is different: something is wired to a path with nothing behind it.
BP_MANIFEST="${BOOK}.claude/.blueprint-manifest"
if [ ! -f "$BP_MANIFEST" ]; then
  SKIP "no delivery manifest here, so nothing claims what these files should be (this check stood down)"
else
  bp_digest() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else cksum "$1" | awk '{print $1 "-" $2}'
    fi
  }
  GONE=""; MINE=""
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    want="${line%% *}"; file="${line##* }"
    # A DELIVERED FILE THAT MOVED INSIDE THE PROJECT IS NOT A FILE THAT IS GONE. The
    # manifest records the paths the delivery landed on, and it records them relative to
    # the bookkeeping. The blueprint's own rule is that a copy you touched is yours, and
    # relocating one is a kind of touching it. Looked for where the manifest says first,
    # and then beside this checker, which is where a file that travelled with it landed.
    # In the installed case those are the same directory and the second lookup does
    # nothing. It is anchored to $0 rather than to the working directory on purpose: the
    # working directory is what this run AUDITS and it moves, while the checker sits at
    # the top of its own delivery wherever it is run from.
    if   [ -f "${BOOK}$file" ];  then have="${BOOK}$file"
    elif [ -f "$SELF_DIR/$file" ]; then have="$SELF_DIR/$file"
    else GONE="$GONE $file"; continue
    fi
    [ "$(bp_digest "$have")" = "$want" ] || MINE="$MINE $have"
  done < "$BP_MANIFEST"
  if [ -n "$GONE" ]; then
    RED "a delivered file named in the manifest is gone" "something may still be wired to it:$GONE"
  elif [ -n "$MINE" ]; then
    SKIP "changed since delivery, so these are yours now and updates will leave them alone:$MINE"
  else
    OK "every delivered file is the one that arrived"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Nothing that ships names the project it was measured in.
#
# A comment that names the project a number came out of hands that name to everybody who
# installs this, and it tells none of them anything. THE NUMBERS CARRY THE EVIDENCE, THE
# NAME CARRIES NOTHING. The home directory of the machine it ran on is the same leak with
# the person's name on top of the project's. Check 1 above was standing in for this and
# measures something else entirely: a file with no placeholder in it is not a generic file,
# and three names were removed by hand on 2026-09-07 with nothing to stop the fourth.
#
# THE SET IS THE DELIVERED ONE, not the working directory. A plain `grep -r .` reads build
# output and everything git was told to ignore, none of which reaches an installer, and
# every hit in there is a false alarm somebody has to argue away. Same derivation as the
# file set at the top of this file, without its markdown filter, because a name in a hook
# comment travels exactly as far as one in a heading.
#
# ONE SUBTRACTION, WITH ITS REASON, said out loud below because a subtraction nobody sees
# is a check nobody has. `.claude/` is the project's own bookkeeping, and a foreign path in
# there is the PROVENANCE of a measurement, which the rules demand rather than forbid.
# Those files can still travel with a copy of the repository, and that is a packaging
# question this check cannot answer by going red on the evidence itself.
#
# AND THE LINE FOLLOWS THE MEASUREMENT RATHER THAN A DIRECTORY TEST. It used to print
# whenever a .claude/ existed anywhere, which in the kit case is one level ABOVE the
# package and was never in this set to begin with: the reader was told a subtraction had
# happened that had taken nothing out. It is announced when the set actually got shorter,
# and stays quiet when the bookkeeping is outside the package altogether.
#
# THE NAMES ARE TYPED, and this is the only typed list in this file, because every
# derivation from the directories around the repository fires on correct work: measured
# 2026-09-07, the repository's own name stands 115 times in the delivered files and
# `context-kit`, a sibling directory, twice inside this very file. The machine path IS
# derived, from HOME, because that one never goes stale and catches the whole class rather
# than one spelling of it.
#
# AND THE TYPED LIST IS A DEFECT IN ITS OWN RIGHT, written down here and deliberately NOT
# repaired, because deriving the list changes what this check MEANS and that belongs in an
# order of its own. What the ok line below actually claims is "none of these four names".
# What a reader takes from it is "no foreign project". Nothing in the output tells the two
# apart. Measured 2026-09-09: a fourth project's name stood in hooks/_sessions.sh, a file
# inside the very set this check reads, and this check printed its ok line over it on
# every run until the name was taken out by hand; adding that one name to the list above
# turned the same run red on the same file. Until the list is derived, read this green as
# the narrow claim it is and not as an absence of names. It happened a second time:
# measured 2026-11-04, the package of the project the frozen corpus came from stood on six
# lines of README.md, hooks/_classify.sh and tests/run.sh under this ok line, and the
# fourth name on the list turned the same run red on exactly those six.
#
# AN INSTRUMENT THAT CARRIES WHAT IT LOOKS FOR REPORTS ITSELF: the first version of this
# block went red on its own pattern line, in a fixture that named nobody. The names are
# joined from two halves here, so this file does not contain them.
if git rev-parse --git-dir >/dev/null 2>&1; then
  SHIPPED="$(git ls-files --cached --others --exclude-standard 2>/dev/null | sort -u)"
else
  SHIPPED="$(find . -type f -not -path './.git/*' 2>/dev/null | sed 's|^\./||' | sort -u)"
fi
_SHIPPED_ALL="$SHIPPED"
SHIPPED="$(printf '%s\n' "$SHIPPED" | grep -v '^\.claude/' || true)"
[ "$SHIPPED" = "$_SHIPPED_ALL" ] || SKIP ".claude/ is this project's own bookkeeping, where a foreign path is the provenance of a measurement, so those files are not audited"
NAMES="$(printf '%s\n' "tradin""g_analysis" "matskapost""y" "manager-prob""e" "quiquer""y")"
# A HOME OF ONE COMPONENT IS NOT A HOME PATH. `/` or `/root` as a pattern matches most of
# the tree, and a check that is red on everything is a check that gets muted. Two
# components at least, or the derived half stays out of the list.
case "${HOME:-}" in
  /*/?*) NAMES="$NAMES
${HOME%/}" ;;
esac
FOREIGN=""; FOREIGN_N=0; SCANNED=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  SCANNED=$((SCANNED + 1))
  # -F because a home path carries dots that would otherwise be wildcards, -I because a
  # binary that matches is not a comment anybody can rewrite. The list is read line by
  # line for the reason check 1 is: a filename with a space in it is still a file.
  HITS="$(grep -nIF "$NAMES" "$f" 2>/dev/null | awk -v F="$f" '{
            s = $0
            if (length(s) > 92) s = substr(s, 1, 89) "..."
            printf "         %s:%s\n", F, s }')"
  [ -n "$HITS" ] || continue
  N="$(printf '%s\n' "$HITS" | grep -c . || true)"
  case "$N" in ''|*[!0-9]*) N=0 ;; esac
  FOREIGN_N=$((FOREIGN_N + N))
  FOREIGN="$FOREIGN$HITS
"
done <<FILELIST
$SHIPPED
FILELIST
if [ "$SCANNED" -eq 0 ]; then
  # SCANNING NOTHING IS NOT FINDING NOTHING, and the ok line below cannot tell the two
  # apart. A derivation that comes back empty would otherwise report a clean result.
  SKIP "no delivered file was readable here, so nothing was searched (this check stood down)"
elif [ -n "$FOREIGN" ]; then
  RED "a file that ships names a foreign project" "$FOREIGN_N line(s) that travel to everybody who installs this:"
  printf '%s' "$FOREIGN"
else
  OK "nothing outside the bookkeeping names another project or this machine"
fi

# ---------------------------------------------------------------------------
# 9. Nothing that ships forbids its own delivery.
#
# A file that carries its own release condition and is released anyway has turned a
# decision into decoration. The sentence is still there, it still reads as binding, and
# nobody downstream can tell whether the condition was met, waived or forgotten. Neither
# can the person who wrote it, six weeks later.
#
# MEASURED 2026-09-09 ON THIS REPOSITORY, which is why this check exists rather than being
# a good idea. The version of hooks/_sessions.sh that stood here until today carried, in a
# comment, the demand that the role file stop sharing a directory with the record BEFORE
# ... , wrapped across two comment lines. tests/run.sh reported ALL GREEN at 87 checks and
# this checker reported green, over a text that said of itself it was not deliverable.
# Nothing here could see it. That is a silent pass, and it is the whole of the case.
#
# THIS IS NOT A TODO HUNT, and that distinction IS the word list. A note that names FUTURE
# work is a normal thing to ship: "TODO", "a later version should", "next step" all claim
# nothing about the present state, and a checker that reddened on them would be muted
# inside a week. A sentence that hangs a condition on the act of delivery claims the
# present state is not deliverable, and it was delivered anyway. Only the second shape is
# caught, and each of the three arms below demands a verb of delivery; none fires on such
# a verb standing alone.
#
#   1. a connective of precondition ("before", "until"), then a subject pointing back at
#      the text itself ("this", "it", "the kit", "the file"), then a verb of delivery
#      ("goes out", "ships", "is shipped", "is released"). ALL THREE PARTS ARE REQUIRED,
#      and a measurement says which of them is paying. Measured 2026-09-09 over the
#      delivered set of this package: dropping the subject on its own costs nothing, 0
#      hits either way, so the subject is not what is holding the line. Dropping the
#      whole precondition clause and matching a delivery verb wherever it stands gives 41
#      hits across 10 files, and every one of them is a false alarm. One of the 41 is the
#      paragraph now standing in hooks/_sessions.sh saying the price is named rather than
#      paid as the kit is handed over: that sentence makes the OPPOSITE claim, and going
#      red on it is exactly the false alarm that gets an instrument switched off. A verb
#      of delivery is ordinary vocabulary in a kit that talks about delivery; only the
#      clause in front of it turns a description into a condition.
#   2. a refusal aimed at delivery: a negated modal ("cannot", "must not", "may not") in
#      front of one of those same verbs.
#   3. a flat statement of unreadiness: "not", then "ready" or "fit", then one of those
#      verbs once more.
#
# LEFT OUT ON PURPOSE, AND NAMED RATHER THAN BUILT: a bare precondition with no subject at
# all. It reads as a deadline exactly as often as it reads as a date, and this very file
# carries sentences of the second kind (eight shapes compared, numbers measured, each tied
# to a version). An arm that cannot tell a deadline from a timestamp buys one more catch
# and pays for it with a class of false alarm somebody has to argue away every run.
#
# WRAPPED COMMENTS ARE THE NORMAL CASE HERE, so the text is read over a TWO-LINE window
# with punctuation, comment markers and case flattened away. The defect above broke
# between its next-to-last and last word, and a line-at-a-time grep sees neither half; the
# window is the difference between this check and a decorative one. A sentence is reported
# at the line it STARTS on and only there, so a wrapped hit and a single-line hit each
# count exactly once.
#
# THE SET IS THE ONE CHECK 8 ALREADY DERIVED, and deliberately not a second list: two
# lists disagree the day somebody edits one of them. That includes check 8's subtraction
# of the bookkeeping, which is right here for a reason of its own. A plan under .claude/
# is WHERE a condition before delivery belongs; writing one there is the work, not a
# defect, and this check would otherwise go red on a project for planning properly.
#
# AN INSTRUMENT THAT CARRIES WHAT IT LOOKS FOR REPORTS ITSELF, which check 8 learned the
# hard way and which this check hit again while it was being written: the obvious wording
# for its own red line matched arm 2, and splitting the individual words was not enough to
# stop it. The normaliser below flattens punctuation, so an alternation written out in one
# piece reads back as running prose: the closing bracket of the modal group and the
# opening bracket of the verb group vanish, the two groups touch, and the line is a hit
# against itself. That is why the example cannot be written out here either. Each arm is
# therefore assembled from a group of triggers and a group of verbs held on SEPARATE
# lines, which puts a variable name between them as a word of its own, and the single
# words are split across a string join on top of that. Verified the only way it can be:
# by running this checker over its own source, which is in the set it scans.
_SB_WHEN="(be""fore|un""til)"
_SB_SELF="(this|it|these|they|that|the kit|the file|the hook|the guard|the change|the version)"
# THE PASSIVE FORMS ARE IN HERE BECAUSE THEY WERE MEASURED OUT AND BACK IN. An earlier
# draft gave arm 2 a verb list of its own; folding the three arms onto ONE list dropped
# the three passive forms below, and a fixture built on a negated modal plus a passive
# stopped being caught while every run of this checker stayed green. Nothing in here
# would have said so; it was found by re-running the fixtures after the refactor and
# reading them one by one. A shared list is still the right shape, and this is its
# price: the list has to carry every form that all three arms need. The fixture itself
# cannot be quoted here, for the reason given in the paragraph above.
_SB_VERB="(go""es out|go out|shi""ps|ship|is shi""pped|are shi""pped|is rel""eased|is del""ivered|can ship|can go out|be shi""pped|be rel""eased|be del""ivered)"
_SB_NEVER="(can""not|must not|may not|can not|do not|does not|will not|shall not)"
_SB_UNFIT="not (rea""dy|fit) (to|for)"
SELFBLOCK=" ($_SB_WHEN $_SB_SELF $_SB_VERB|$_SB_NEVER $_SB_VERB|$_SB_UNFIT $_SB_VERB) "
BLOCKED=""; BLOCKED_N=0; BLOCKED_SCANNED=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # A BINARY THAT MATCHES IS NOT A SENTENCE ANYBODY WROTE. Same -I as check 8, asked once
  # per file, before awk reads the whole thing into memory for nothing.
  LC_ALL=C grep -qI . "$f" 2>/dev/null || continue
  BLOCKED_SCANNED=$((BLOCKED_SCANNED + 1))
  HITS="$(awk -v F="$f" -v RE="$SELFBLOCK" '
    {
      s = tolower($0)
      gsub(/[^a-z0-9]+/, " ", s)
      sub(/^ /, "", s); sub(/ $/, "", s)
      n[NR] = s
    }
    END {
      for (i = 1; i <= NR; i++) {
        win = " " n[i] " " n[i+1] " "
        # A match beginning past line i belongs to line i+1, and is printed when THAT line
        # is the first half of its own window. Without this test every wrapped sentence
        # would be counted twice and the number in the red line would be a lie.
        if (match(win, RE) && RSTART <= 1 + length(n[i])) {
          q = substr(win, RSTART, RLENGTH)
          gsub(/^ | $/, "", q)
          printf "         %s:%d  %s\n", F, i, q
        }
      }
    }' "$f" 2>/dev/null)"
  [ -n "$HITS" ] || continue
  N="$(printf '%s\n' "$HITS" | grep -c . || true)"
  case "$N" in ''|*[!0-9]*) N=0 ;; esac
  BLOCKED_N=$((BLOCKED_N + N))
  BLOCKED="$BLOCKED$HITS
"
done <<FILELIST
$SHIPPED
FILELIST
if [ "$BLOCKED_SCANNED" -eq 0 ]; then
  # SCANNING NOTHING IS NOT FINDING NOTHING, for the reason check 8 gives above.
  SKIP "no delivered file was readable here, so nothing was searched (this check stood down)"
elif [ -n "$BLOCKED" ]; then
  RED "a delivered file forbids its own delivery" "$BLOCKED_N sentence(s) naming a condition ahead of the handover, in a file that was handed over:"
  printf '%s' "$BLOCKED"
else
  OK "nothing that ships carries a condition on its own delivery"
fi

# ---------------------------------------------------------------------------
# 10. Every hand that ships carries the stop and the handover at it.
#
# A SUBAGENT DEFINITION IS A CONTRACT THAT NOBODY RUNS. Nothing executes these files; they
# are read into a hand's context and that is the whole of their effect. So a clause that
# is missing from one of them fails in the quietest way this repository has: the hand
# works exactly as before, is never told to stop, and the only evidence is a report that
# got worse somewhere nobody was looking. Measured 2026-09-29 over 1494 runs of the
# machine this was built on: 6.2 percent reached 600000 tokens of context and 1.7 percent
# reached 900000, and the fastest run to cross 600000 took 26 tool calls. That is the case
# for the clause, and this check is the case for it being in every file rather than most.
#
# THE LIST IS DERIVED AND THAT IS THE ENTIRE POINT OF THE CHECK. Check 8 above types its
# list and says in its own comment why that is a defect it did not repair. This one had
# the same choice and made it the other way, because the failure it guards against IS a
# new file: a seventh hand added next month, copied from a sixth that predates the rule,
# is exactly the thing a typed list cannot see. Every `*.md` under `agents/` is read,
# whatever it is called.
#
# THE SUBJECT IS THE AUDITED PROJECT, NOT THIS PACKAGE. `agents/` is resolved against the
# working directory, the way checks 1 to 4 resolve theirs, so running this from the
# package audits the package's own hands and running it in somebody else's project audits
# theirs. It is deliberately NOT anchored to $0: that would make the checker audit itself
# no matter where it was pointed, and report green about this delivery while standing in a
# project it had never looked at.
#
# AND `.claude/agents/` IS LEFT ALONE, said out loud because a subtraction nobody sees is
# a check nobody has. Those are a project's own hands, written by people who never asked
# for this kit's stop rule, and a checker that reddens on them is the false alarm that
# gets an instrument switched off inside a week.
#
# FOUR ARMS, AND EACH ONE IS A SEPARATE CLAIM, because "the file mentions the rule" is not
# the same as "the file carries the rule" and a single grep cannot tell them apart. The
# floor, the line the coordinator watches, the duty that follows, and the one thing that
# makes the handover findable at all. A file missing any one of them is named with the arm
# it is missing, not with a verdict the reader has to go and decode.
#
# SIX IDENTICAL COPIES ARE A COST THIS CHECK EXISTS TO CARRY. One rule in six files is the
# shape this kit warns against everywhere else, and it is forced here: a subagent
# definition cannot include another file, so there is no single copy to point at. What
# this check buys is that the six cannot drift apart quietly.
AGENTS_DIR="agents"
if [ ! -d "$AGENTS_DIR" ]; then
  SKIP "no agents/ here, so no hand of this project claims the stop rule (this check stood down)"
else
  HANDS="$(find "$AGENTS_DIR" -type f -name '*.md' 2>/dev/null | sort)"
  NOSTOP=""; HANDS_N=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    HANDS_N=$((HANDS_N + 1))
    MISS=""
    grep -qF '150 tool calls or 300 KB' "$f" 2>/dev/null || MISS="$MISS the floor of 150 calls or 300 KB;"
    grep -qF '600000' "$f"                  2>/dev/null || MISS="$MISS the 600000 token line;"
    grep -qF 'handover file' "$f"           2>/dev/null || MISS="$MISS the duty to write a handover file;"
    grep -qF 'first line of your report' "$f" 2>/dev/null || MISS="$MISS naming its path in the first line;"
    [ -n "$MISS" ] || continue
    NOSTOP="$NOSTOP         $f: missing$MISS
"
  done <<HANDLIST
$HANDS
HANDLIST
  if [ "$HANDS_N" -eq 0 ]; then
    # SCANNING NOTHING IS NOT FINDING NOTHING, for the reason check 8 gives above. An
    # agents/ directory holding no markdown at all would otherwise report every hand clean.
    SKIP "agents/ holds no markdown file, so no hand was read (this check stood down)"
  elif [ -n "$NOSTOP" ]; then
    RED "a hand that ships never has to stop" "a hand with no stop runs until its context is spent, and the only sign is a worse answer:"
    printf '%s' "$NOSTOP"
  else
    OK "every hand carries the stop, the handover and the path to it ($HANDS_N read)"
  fi
fi

# ---------------------------------------------------------------------------
[ "$QUIET" -eq 1 ] || printf '\n'
DONE=1
[ "$FAIL" -eq 0 ] && { [ "$QUIET" -eq 1 ] || printf 'green: nothing here is decorative.\n'; exit 0; }
printf 'red: the structure is ahead of the thinking. Fix the lines above, not the checker.\n'
exit 1
