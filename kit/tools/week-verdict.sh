#!/usr/bin/env bash
# The one command GOAL.md promises: read the week off disk and say what it settled.
#
# Usage: bash week-verdict.sh [project-dir] [--since 'YYYY-MM-DD[ HH:MM[:SS]]']
#                                           [--until 'YYYY-MM-DD[ HH:MM[:SS]]']
#                                           [--ref <ref>]
#
# --ref names the stand the commits are read from, any ref git resolves to a commit
# (origin/main, a branch, a tag). Without it the commits of HEAD are read, as always, and
# the output names HEAD. A ref that names no commit is refused out loud with nothing read.
#
# Both bounds are UTC and both are included. A bound with a time is read to the second
# (HH:MM is HH:MM:00); a bare day stands for the whole day, so --since opens at 00:00:00
# and --until closes at 23:59:59. Without --until the window runs to the moment of
# reading, and the output says so and names the newest log line it read.
#
# It reads two sources that do not depend on each other: the project's git history, and
# the guard's own log. That separation is the point. The guard cannot testify about the
# turns in which it was not running, so the question "was it silent because nothing
# crossed the line, or silent because it was dead?" has to be answered from outside it.
# Git history is the outside.
#
# Commits are classified with the SAME function the guard uses, not a copy of it. A
# verdict computed from a second implementation of the measure would be a verdict about
# the second implementation.

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../hooks/_classify.sh"
# The reader has to look where the guard writes, and the guard writes at the project root.
# Pointed at a subdirectory of the project without this, it would report the log as
# MISSING and the week as INCONCLUSIVE: loud rather than silent, but wrong, and the person
# would be told a live guard left no trace.
. "$HERE/../hooks/_sessions.sh"

PROJECT=${1:-.}
case "$PROJECT" in --*) PROJECT=. ;; esac
SINCE=""
UNTIL=""
UNTIL_GIVEN=0
REF=""
REF_N=0
SINCE_N=0
UNTIL_N=0
BAD_OPT=""
# The first word is the project unless it is an option, and it is not read as one.
if [ $# -gt 0 ]; then case "$1" in --*) ;; *) shift ;; esac; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --since) shift; SINCE=${1-}; SINCE_N=$((SINCE_N + 1)) ;;
    --until) shift; UNTIL=${1-}; UNTIL_GIVEN=1; UNTIL_N=$((UNTIL_N + 1)) ;;
    --ref) shift; REF=${1-}; REF_N=$((REF_N + 1)) ;;
    # A word this command has no name for is not passed over: the window it HAS would be read, and the verdict
    # would answer a question nobody asked [measured 2026-11-07 at a7dc5a9: --rf, --sinc and --since=DAY all read
    # the default week]. The first one is named.
    -*) [ -n "$BAD_OPT" ] || BAD_OPT=$1 ;;
  esac
  shift || break
done
if [ -n "$BAD_OPT" ]; then
  printf 'week-verdict: %s is not an option of this command.\n' "$BAD_OPT" >&2
  printf 'It has --since, --until and --ref, each with its value as the next word. Nothing was read.\n' >&2
  exit 2
fi
for _o in since:"$SINCE_N" until:"$UNTIL_N"; do
  if [ "${_o#*:}" -gt 1 ]; then
    printf 'week-verdict: --%s was given %s times. It names one bound. Nothing was read.\n' "${_o%%:*}" "${_o#*:}" >&2
    exit 2
  fi
done
[ -n "$SINCE" ] || SINCE=$(date -u -v-7d +%Y-%m-%d 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%d)

# ---- $SINCE is normalized EXACTLY ONCE, here, and never read raw again ------------
# The two witnesses below want the window in two different shapes, and handing each of
# them the string the caller typed is what broke both halves of this command:
#
#   `git log --since=2026-09-07` does NOT start at midnight. Git fills the missing time
#   of day in from NOW, so the window silently starts at the hour the command was run.
#   Measured 2026-09-07 13:02 in a project with two commits that morning: the bare date
#   found 0 of them, `--since '2026-09-07 00:00'` found 2.
#
#   The log reader compares the ten character day out of `ts` against the window. Give
#   it the obvious repair for the line above and "2026-09-07" < "2026-09-07 00:00" is
#   true as a STRING, so every line falls out and a live guard is reported as blind.
#
# So neither shape read both halves, and the two are derived here from one parse rather
# than from two places that can drift: SINCE_GIT is the bound `git log` gets, SINCE_DAY
# is the day the log reader compares day against day with. Anything that is not a date
# is refused out loud, because filtering on a string git guesses at is the same defect
# in a new coat.
#
# THE UPPER BOUND GOES THROUGH THE SAME PARSE, and every trap above holds for it too. A
# bare `git log --until=2026-09-02` closes at the hour of NOW on that day, not at its end:
# measured 2026-11-03 at 09:57 UTC in a throwaway repository, it kept the commits at 00:00
# and 03:00 of that day and dropped the one at 22:09:15. So a bare day is filled in here,
# with the first second of the day for the lower bound and the LAST for the upper one, and
# git never sees a bare day at either end. `--until` filters the committer date, the field
# the day set is read from [measured the same hour: author 2027, committer 2026-09-01 is
# inside `--until '2026-09-01 23:59:59'`, the reverse is not], and it is resolved in the
# zone of the process, which is why it goes on the same `TZ=UTC` line as --since.
#
# The upper bound used not to exist, and that cost a real number: a closed week read nine
# days later silently counted the nine days as well. Without --until the window still runs
# to the moment of reading, but the output says so and names the newest line it read.
#
# norm_bound <flag> <as typed> <time a bare day stands for> sets _bday and _btime or refuses.
norm_bound() {
  _s=${2%Z}
  case "$_s" in *T*) _s=$(printf '%s' "$_s" | tr 'T' ' ') ;; esac
  _bday=${_s%% *}
  case "$_s" in *' '*) _btime=${_s#* } ;; *) _btime=$3 ;; esac
  case "$_btime" in
    [0-9][0-9]:[0-9][0-9])            _btime="$_btime:00" ;;
    [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) : ;;
    *) _btime='' ;;
  esac
  case "$_bday" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) _bday='' ;;
  esac
  if [ -z "$_bday" ] || [ -z "$_btime" ]; then
    printf 'week-verdict: %s %s is not a window this command can filter on.\n' "$1" "$2" >&2
    printf 'Give YYYY-MM-DD, or YYYY-MM-DD HH:MM, or YYYY-MM-DD HH:MM:SS.\n' >&2
    printf 'Relative forms git would accept are refused here on purpose: the guard log is\n' >&2
    printf 'read by day, and a window only git can resolve cannot be turned into one.\n' >&2
    exit 2
  fi
}
# All of it is read as UTC. The _GIT shapes are handed to a `git log` that runs under
# TZ=UTC, and the day and the _TS shapes are compared against a `ts` the guard wrote with
# gmtime. See the block over the git history below for why one day concept has to hold
# across both witnesses. An empty UNTIL_GIT and UNTIL_TS is the open end.
norm_bound --since "$SINCE" 00:00:00
SINCE_DAY=$_bday
SINCE_GIT="$_bday $_btime"
SINCE_TS="${_bday}T$_btime"
UNTIL_GIT=''
UNTIL_TS=''
if [ "$UNTIL_GIVEN" -eq 1 ]; then
  norm_bound --until "$UNTIL" 23:59:59
  UNTIL_GIT="$_bday $_btime"
  UNTIL_TS="${_bday}T$_btime"
  # Compared as digits, because a string order between two shapes is exactly what went
  # wrong above, and a window that closes before it opens would read as an empty week.
  _l=$(printf '%s' "$SINCE_TS" | tr -dc '0-9')
  _u=$(printf '%s' "$UNTIL_TS" | tr -dc '0-9')
  if [ "$_u" -lt "$_l" ]; then
    printf 'week-verdict: --until %s closes the window before --since %s opens it.\n' \
      "$UNTIL_GIT" "$SINCE_GIT" >&2
    printf 'Without --since the window opens seven days before today. Nothing was read.\n' >&2
    exit 2
  fi
fi

# The x and the cut after it keep a newline at the end of the name, which a bare $(...) removes.
GIVEN=$(CDPATH= cd -- "$PROJECT" && pwd -P && printf x) || exit 2
GIVEN=${GIVEN%x}; GIVEN=${GIVEN%?}
# The SAME derivation the hooks write against, out of the same function, so the two
# witnesses cannot come to different conclusions about which directory this project is.
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name.
mk_project_root_set "$GIVEN"; PROJECT=$MK_ROOT
LOG=$PROJECT/.claude/manager-kit.log

# ---- THE STAND THE COMMITS ARE READ FROM, resolved once, before anything is printed -------
# The window was always cut from HEAD. Where a checkout stands behind its upstream and the work
# lies on origin/main or on other branches, that reads as an empty week and the verdict says
# nobody coordinated anything: INCONCLUSIVE "No commits in the window", measured 2026-11-07 at
# 6018feb in a clone whose HEAD stood three commits behind origin/main, with the work on both.
#
# So the stand is named, and it is resolved to one commit here and read by that hash from then
# on: a ref that is also the name of a file cannot change what is read, and a value that starts
# with a dash cannot become an option of git. A ref that names no commit is an input error like
# the ones above it, loud and with nothing read. The default is HEAD, and a HEAD that names no
# commit (no repository, nothing committed yet) behaves as it always did: no commits.
HSHA=''
HNAME=HEAD
if [ "$REF_N" -gt 0 ]; then
  if [ "$REF_N" -gt 1 ]; then
    printf 'week-verdict: --ref was given %s times. It names one stand.\n' "$REF_N" >&2
    printf 'Nothing was read.\n' >&2
    exit 2
  fi
  case "$REF" in
    ''|-*)
      printf 'week-verdict: --ref %s is not a name this command can read a history from.\n' "'$REF'" >&2
      printf 'Give a branch, a tag or a remote branch such as origin/main. Nothing was read.\n' >&2
      exit 2 ;;
  esac
  HSHA=$(git -C "$PROJECT" rev-parse --verify --quiet "$REF^{commit}" 2>/dev/null) || HSHA=''
  if [ -z "$HSHA" ]; then
    printf 'week-verdict: --ref %s names no commit in %s.\n' "$REF" "$PROJECT" >&2
    printf 'Nothing was read.\n' >&2
    exit 2
  fi
  HNAME=$REF
else
  HSHA=$(git -C "$PROJECT" rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) || HSHA=''
fi

printf 'manager-kit week verdict\n'
printf 'project: %s\n' "$PROJECT"
# Printed only when the two differ, because a line that always prints is a line nobody
# reads, and this one is a finding: the reader was pointed somewhere else than it read.
[ "$PROJECT" = "$GIVEN" ] || printf 'asked at: %s, which is in that project\n' "$GIVEN"
# The stand is named on every run: a count of commits without the history it was counted in is
# the number this change exists to stop being read wrongly.
if [ -n "$HSHA" ]; then
  printf 'history: %s, at %s\n' "$HNAME" "$(printf '%s' "$HSHA" | cut -c1-12)"
else
  printf 'history: %s, which names no commit here\n' "$HNAME"
fi
# THE WINDOW IS NAMED AS IT WAS READ, both ends of it. An open end is said out loud rather
# than left to be assumed, because the reader of a verdict about a past week cannot see
# from a count how far the reading went.
if [ -n "$UNTIL_GIT" ]; then
  printf 'window:  since %s UTC until %s UTC, both included\n' "$SINCE_GIT" "$UNTIL_GIT"
else
  printf 'window:  since %s UTC, NO UPPER BOUND given: read to the end, newest line below\n' \
    "$SINCE_GIT"
fi
printf '         counted to the second; guard liveness and days by whole UTC day\n\n'

# ---- git history, the outside witness -------------------------------------------
# No branch here truncates. The base set is printed and the parts are proved to sum.
#
# ONE DAY CONCEPT HOLDS IN THIS COMMAND, AND IT IS THE UTC CALENDAR DAY. Everything
# below is `TZ=UTC` for that reason, and the reason is not taste: the two witnesses have
# to answer the SAME question, "which day was this", or the difference between their
# answers is reported as a blind day, which is the worst verdict this command can print.
#
# The guard side is not negotiable. hooks/role-guard.sh writes its `ts` with
# `time.gmtime()` and keeps its once-a-day marker from `date -u`, so every day the guard
# can testify about is a UTC day. That side is also under a live measuring week and is
# not being touched. So the reader moves.
#
# Two things had to move, and they are two different mistakes:
#
#   1. WHICH TIMESTAMP. This read `%ad`, the AUTHOR date. `git log --since` filters the
#      COMMITTER date, so the set of commits and the set of days came from two different
#      fields, and a rebased, amended or `--date` commit reported a day the window had
#      never selected. Measured in a throwaway repository with
#      `GIT_AUTHOR_DATE=2020-01-01 GIT_COMMITTER_DATE=2026-09-02`: `--since 2026-09-01`
#      finds the commit, `%ad --date=short` says 2020-01-01, `%cd` says 2026-09-02, and
#      the verdict named 2020-01-01 as a day the guard slept through.
#      The week asks on which days work was COMMITTED, per GOAL.md, "was the guard alive
#      on every day that carries commits". A commit lands when it is committed. The
#      author date is a field the committer can set to anything, and no guard could have
#      been running on it. So it is `%cd`.
#
#   2. WHICH ZONE. `--date=short` renders in the zone RECORDED IN THE COMMIT, not in UTC.
#      A commit made at 01:00 in a zone two hours ahead is 23:00 UTC the day before, so
#      the guard line written in the same second carries the previous day and the day
#      before that fell out as blind. Measured in a throwaway repository with
#      `GIT_COMMITTER_DATE='2026-09-03 01:00:00 +0200'` and one guard-ran line at
#      `2026-09-02T23:00:00Z`: the verdict named 2026-09-03 as a blind day.
#      `--date=short-local` under `TZ=UTC` renders the UTC day instead.
#
# And the bound has to move with them, or the repair is only displaced. `git log --since`
# resolves its bound in the ZONE OF THE PROCESS, so with days counted in UTC and the
# bound left in the machine's zone, a commit whose UTC day is the 2nd would sit inside a
# window opened on the 3rd, and a day outside the window would be demanded of the guard
# log, which is filtered by the UTC day. `TZ=UTC` on this line is what keeps the window
# and the day count speaking about the same days.
#
# What this costs, said plainly rather than left to be discovered: for a coordinator east
# or west of UTC the week is cut at UTC midnight and not at theirs, so late evening or
# early morning work is filed on the neighbouring day. That is a shift of the whole
# picture by one boundary; it is not a disagreement between the two witnesses, and it is
# the disagreement that produces the fatal verdict. The alternative, moving the guard to
# local days, would need hooks/, which a running week owns.
commits=$(TZ=UTC git -C "$PROJECT" log --since="$SINCE_GIT" ${UNTIL_GIT:+"--until=$UNTIL_GIT"} \
  --format=%H "${HSHA:-HEAD}" -- 2>/dev/null)
total=0; work=0; book=0; commit_days=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  total=$((total + 1))
  commit_days="$commit_days$(TZ=UTC git -C "$PROJECT" log -1 --format=%cd --date=short-local "$c")
"
  v=bookkeeping
  # git prints a name that is not ASCII as "docs/b\303\244r.md", in quotes, unless it is told not
  # to, and with the closing quote behind it no such name ever ended in .md: a commit of Markdown
  # counted as a commit touching a work path [measured 2026-11-06 at 0bc14fe]. core.quotePath
  # changes nothing for a name in ASCII.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$(classify_path "$f")" = work ]; then v=work; break; fi
  done <<EOF
$(git -C "$PROJECT" -c core.quotePath=false show --pretty=format: --name-only "$c" 2>/dev/null)
EOF
  if [ "$v" = work ]; then work=$((work + 1)); else book=$((book + 1)); fi
done <<EOF
$commits
EOF

# `grep -c` PRINTS its zero and exits 1 when nothing matched, so the `|| printf 0` that
# used to stand at the end of this line fired IN ADDITION to the zero already printed, and
# the field carried two lines instead of one. Nothing here runs under `set -e`, so the
# fallback bought nothing and cost a wrong verdict on the one window it is reachable in:
# the empty one, which is the first day of every week and never again. The same defect is
# named in check.sh, where it was found first.
days_with_commits=$(printf '%s' "$commit_days" | sort -u | grep -c .)
# WHEN HEAD IS READ AND ITS UPSTREAM IS AHEAD, one line says so, with the number. Asked of the
# tracking ref that is already on disk: no fetch, no network, nothing written, and what the
# line reports is the state as of the last fetch. With --ref the person chose the stand, and
# a branch with no upstream has nothing to be behind.
if [ "$REF_N" -eq 0 ] && [ -n "$HSHA" ]; then
  UP=$(git -C "$PROJECT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || UP=''
  if [ -n "$UP" ]; then
    BEHIND=$(git -C "$PROJECT" rev-list --count 'HEAD..@{upstream}' 2>/dev/null) || BEHIND=0
    case "$BEHIND" in ''|*[!0-9]*) BEHIND=0 ;; esac
    if [ "$BEHIND" -gt 0 ]; then
      BEHIND_WIN=$(TZ=UTC git -C "$PROJECT" rev-list --count 'HEAD..@{upstream}' --since="$SINCE_GIT" \
        ${UNTIL_GIT:+"--until=$UNTIL_GIT"} 2>/dev/null) || BEHIND_WIN=0
      case "$BEHIND_WIN" in ''|*[!0-9]*) BEHIND_WIN=0 ;; esac
      printf 'behind:  HEAD is %s commit(s) behind %s as last fetched, %s of them inside the window; they are NOT read. --ref %s reads them.\n' \
        "$BEHIND" "$UP" "$BEHIND_WIN" "$UP"
    fi
  fi
fi
printf 'commits in window:        %s\n' "$total"
printf '  touching a work path:   %s\n' "$work"
printf '  bookkeeping only:       %s\n' "$book"
if [ $((work + book)) -eq "$total" ]; then
  printf '  sum check:              ok, %s + %s = %s\n' "$work" "$book" "$total"
else
  printf '  SUM CHECK FAILED:       %s + %s is not %s\n' "$work" "$book" "$total"
fi
printf 'days with commits:        %s\n\n' "$days_with_commits"

# ---- the guard log, the inside witness ------------------------------------------
# THE LOG IS READ THROUGH THE DOOR OF THE KIT, like every other file of it under .claude: a plain
# file inside the project, opened without following a link and without waiting on a pipe, and
# judged on the open file. A log that is a pipe held this command past 12 s, a log that is a link
# counted the stops of a foreign file, and the .claude of the home directory or of a link that
# leaves the project was read as this project guard [measured 2026-11-06 at 0bc14fe and 2026-11-07
# at 6018feb]. The shell asks the same function the hooks ask, mk_record_trouble, which of those
# it is, so the reader and the writer cannot disagree about where the record lives.
TROUBLE=$(mk_record_trouble "$PROJECT")
MK_LOG=$LOG MK_SINCE_DAY=$SINCE_DAY MK_SINCE_TS=$SINCE_TS MK_UNTIL_TS=$UNTIL_TS \
  MK_DAYS=$commit_days MK_DOOR_ROOT=$PROJECT MK_TROUBLE=$TROUBLE MK_WORK=$work MK_TOTAL=$total \
  MK_HIST=$HNAME python3 -I -c "$MK_PY_DOOR"'
import os, json, sys
log = os.environ["MK_LOG"]
trouble = os.environ["MK_TROUBLE"]


def pathline(head, value, tail=""):
    # A path or a ref name goes out as the bytes it is. The environment is decoded with the file
    # system encoding, which on a Mac is UTF-8 whatever LC_ALL says, and print encodes with the
    # locale, so a name with an umlaut came out in two spellings in one output.
    sys.stdout.flush()
    sys.stdout.buffer.write(head.encode("ascii") + os.fsencode(value) + tail.encode("ascii") + b"\n")
    sys.stdout.buffer.flush()

# Day against day, both exactly ten characters. The comparison below is a string
# comparison and ISO days sort correctly as strings, but ONLY at equal length: a bound
# carrying an hour would sort after every day it is supposed to include and quietly
# empty the log. So the length is a precondition, and a broken one is said out loud
# rather than absorbed.
since_day = os.environ["MK_SINCE_DAY"]
if len(since_day) != 10:
    sys.exit("week-verdict: the log reader was handed %r, which is not a day. The\n"
             "window was not normalized before it got here." % since_day)
# THE WINDOW TO THE SECOND, in the shape `ts` carries it without the zone letter, nineteen
# characters, under the same length precondition for the same reason. An empty upper bound
# is the open end. Stops, crossings and the lines in the window are counted to the second
# at BOTH ends, so a window stated to the second is the window read. Liveness is NOT: the
# guard marks a day alive with one line at its first call that day, and a bound inside the
# day can fall after that line, so a day is alive on any line of it from the first day of
# the window to the last, as it always was.
since_ts = os.environ["MK_SINCE_TS"]
until_ts = os.environ["MK_UNTIL_TS"]
if len(since_ts) != 19 or (until_ts and len(until_ts) != 19):
    sys.exit("week-verdict: the log reader was handed %r to %r, which is not a window to\n"
             "the second. The window was not normalized before it got here."
             % (since_ts, until_ts))
until_day = until_ts[:10]
commit_days = {d for d in os.environ["MK_DAYS"].split() if d}
stops = crossings = 0
ran_days = set()
lines = in_window = unreadable = 0
newest = ""
try:
    if trouble:
        raise OSError(trouble)
    with os.fdopen(mk_file(mk_home(os.environ["MK_DOOR_ROOT"]), "manager-kit.log", os.O_RDONLY), "rb") as fh:
        for line in fh:
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except Exception:
                rec = None
            if not isinstance(rec, dict):
                unreadable += 1
                continue
            lines += 1
            ts = str(rec.get("ts", ""))
            day = ts[:10]
            if day < since_day:
                continue
            if until_day and day > until_day:
                continue
            stamp = ts[:19]
            counted = since_ts <= stamp and (not until_ts or stamp <= until_ts)
            if counted:
                in_window += 1
                newest = max(newest, ts)
            ev = rec.get("event")
            if ev == "guard-ran":
                ran_days.add(day)
            elif ev == "stop":
                if counted:
                    stops += 1
                ran_days.add(day)
            elif ev == "exception":
                if counted:
                    crossings += 1
                ran_days.add(day)
except FileNotFoundError:
    pathline("guard log:                MISSING at ", log)
    print()
    print("VERDICT: INCONCLUSIVE. The guard left no trace at all, so the quiet cannot be")
    print("read. There is no file at that path: the guard may never have been installed here")
    print("or never have run, or the file may have been removed or moved after it ran.")
    sys.exit(3)
except OSError as exc:
    # A log that is there and was not read is not a log that is missing, and the person is told
    # which, with the sentence the hooks use for the same place.
    pathline("guard log:                NOT READ at ", log)
    print(trouble or ("It is not a plain file inside this project, or it could not be opened (%s)."
                      % (exc.strerror or exc.args[0] if exc.args else exc)))
    print()
    print("VERDICT: INCONCLUSIVE. The guard record was not read, so the quiet cannot be read.")
    sys.exit(3)

print("guard log lines (all time): %d" % lines)
print("guard log lines in window:  %d, newest %s%s"
      % (in_window, newest or "none", "" if until_ts else ", where the open window ended"))
if unreadable:
    print("unreadable log lines:       %d (no event, and not counted above)" % unreadable)
print("days the guard ran:         %d" % len(ran_days))
print("stops:                      %d" % stops)
print("declared crossings:         %d" % crossings)
print()

blind = sorted(commit_days - ran_days)
if blind:
    print("VERDICT: INCONCLUSIVE, and this is the important failure.")
    print("On %d day(s) with commits the guard left no trace: %s"
          % (len(blind), ", ".join(blind)))
    print("A guard that is green in the suite is proven to WORK. It is not proven to RUN")
    print("when it counts, and those are two different wirings. This command cannot tell")
    print("from here which it is: a wiring that does not fire, a log that was removed or is")
    print("kept somewhere else, a guard installed after those days, and commits made outside")
    print("any session all read the same. Find out which before reading anything else here.")
    sys.exit(3)

if not commit_days:
    pathline("VERDICT: INCONCLUSIVE. No commits of ", os.environ["MK_HIST"],
             " in the window, so there is nothing to read the")
    print("guard log against.")
    sys.exit(3)

# WHAT THIS COMMAND KNOWS HERE, and nothing past it. It knows the days on which the guard left a
# line, the stop lines, the exception lines, and which commits touch a work path. It does not know
# who wrote a commit: git carries one author and no field that says which line a commit came out
# of. So a quiet week with a live guard is not a held week. It means the work was handed out or
# went through a hole the guard cannot see, and the two cannot be told apart from here. This used
# to print HELD and "the coordinator never reached for a work path with its own hands" [measured
# 2026-11-07 at 6018feb: a command the guard lets through, a commit carrying src/new.py].
if stops == 0 and crossings == 0:
    work = int(os.environ["MK_WORK"])
    total = int(os.environ["MK_TOTAL"])
    print("VERDICT: QUIET, and a quiet week settles nothing either way.")
    print("The guard left a line on every day that carries commits and recorded no stop and no")
    print("declared crossing. That is all this command read.")
    if work == 0:
        print("No commit in the window touches a work path, so there was nothing to stop in the")
        print("history this command can see.")
    else:
        print("%d of %d commit(s) touch a work path, and nothing in git says which session wrote them."
              % (work, total))
        print("Silence with a live guard means the work was handed out or went through a hole the")
        print("guard cannot see (README.md, \"The Bash gap\"). This command cannot tell which.")
    print("Done-when 2 is NOT satisfied: it wants the guard to have stopped you at least once.")
    sys.exit(1)

# A stop line is a stop and an exception line is a declared crossing. Neither says what became of
# the other: a crossing can be declared before any stop, and nothing in the log says that a stop
# ended in a handover. So the counts are stated as counts, and what came of a stop is said to be
# unread. This used to say "stopped the coordinator %d time(s), and %d of those became a declared
# crossing rather than a handover", which for no stop and two crossings read "0 times, and 2 of those".
print("VERDICT: the guard was live and it fired.")
if stops:
    print("It stopped the coordinator %d time(s) in the window and %d crossing(s) were declared."
          % (stops, crossings))
else:
    print("It recorded no stop in the window, and %d crossing(s) were declared." % crossings)
print("Done-when 2 wants more than a stop: that the work was then handed out, or the crossing")
print("declared on purpose. This command cannot read what came of a stop. It reads the declared")
print("crossings, and those are on the record with the reason given at the time.")
print()
print("What this command CANNOT settle, and you have to read yourself:")
print("  - whether those stops were right. Count the ones that stopped a coordinator")
print("    doing what a coordinator should do; past N in GOAL.md the kit gets switched")
print("    off, not tuned.")
print("  - the Bash gap (README.md, \"The Bash gap\"). A write performed inside a program is")
print("    invisible to the guard, so a work commit can exist that the guard never had a")
print("    chance to see.")
'
