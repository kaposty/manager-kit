#!/usr/bin/env bash
# The measure, and it is the whole of it: a path, not a judgement and not a budget.
#
# Bookkeeping is what a coordinator legitimately writes: anything under a .claude
# directory, every Markdown file, and the session scratchpad. Everything else is work, and
# work is handed out.
#
# This file is sourced by hooks/role-guard.sh and by tests/run.sh, so the thing under
# test and the thing that ships are the same function.

# THE TRACE, and it is the WORKING of the judgement rather than a report about it. Every
# line below is printed from the branch that decided, so a rule that moves and a trace
# that stays behind is not a state this file can be in. That is why it lives here and not
# in the tool that formats it: this kit has already paid once for a measurement run
# against a second copy of the measure instead of against the shipped function, and a
# second copy of the REASONS would be the same defect wearing a friendlier coat.
#
# It is silent unless MK_EXPLAIN=1, and it writes to STDERR, because the verdict is stdout
# and every caller reads that with a command substitution. hooks/role-guard.sh sets it
# only on a stop, to write the line that decided into the reason of the stop line, so
# every other call costs one test per path and one awk variable per command for it.
#
# Written for tools/mk-explain.sh, which exists because the coordinating session could not
# run this measure at all: the examples it wanted to classify had to be typed into a
# command line, and a command line carrying "rm -rf src/x.py" is refused by this very
# function. Measured 2026-09-08 against the shipped guard, the seven cases of that probe on
# one line came back work, so the manager had to hand its own instrument out to somebody
# else and believe what came back.
_mk_why() { if [ "${MK_EXPLAIN:-}" = 1 ]; then printf '%s\n' "$*" >&2; fi; return 0; }

# HOW MUCH COMMAND TEXT THE SCAN BELOW READS, in characters, counted AFTER the heredoc bodies
# are taken out: they are data, the first awk drops them in time that grows with their size
# alone, and a body of any size is judged by the command that carries it. What is left goes
# through an awk program whose time grows with the square of one long line. Measured
# 2026-11-06 through the whole hook, both passes of it, on one machine: a line of 100000
# characters took 2.3 s, 200000 took 7.1 s, 300000 took 15.0 s against a hook budget of 10 s,
# and 900000 was killed unfinished at 90 s. Over 222855 real Bash commands of 24 projects the
# longest text left after the heredoc bodies was 4860 characters [bodies cut by a regex of
# the same shape as the awk, not by the awk itself], so the limit stands 13 times above
# anything that was ever sent, and a line of exactly this length costs about 1.5 s
# [1.35, 1.44 and 1.63 s]. What the runtime does with a hook that runs past its budget has
# NOT been measured here, and nothing below relies on it: the point is that the answer comes
# before the budget does.
MK_READ_LIMIT=65536

# HOW MANY TARGETS THE LOOP BELOW READS, and it is the other half of the same promise. The characters are
# bounded above, and the awk program that reads them was made linear in what it is asked about, but every
# target the loop meets costs it a process of its own to judge: measured 2026-11-07 at 1b4da29, 0.94 to 1.4 ms
# each, so 7000 times `rm a.md;` (56 KB, well under MK_READ_LIMIT) took 14.6 s of a hook budget of 10, and
# the one work target that stood behind them in a hostile command was never reached. A hook the runtime ends
# has not refused, and the runtime does not hold it against the tool call: see README.md. Over 133542 distinct
# real commands of 27 projects the most targets one command named was 43, so the limit stands 5.9 times above
# anything that was ever sent. A command of exactly this many targets costs 0.27 s (`rm .claude/a1.txt; `
# times 256, five runs), and 256 targets of 174 characters with 79 path components each 1.5 s of CPU.
MK_TARGET_LIMIT=256

# WHERE A WRITE LANDS, and until 2026-11-07 the measure read the name instead. A kernel walks a
# path one component at a time and follows every link it meets, so .claude/../src/a.py is
# src/a.py, and docs/a.md with a link behind it writes where the link points. Measured at
# 7d695ce, both tools: both passed as bookkeeping, and /Users/u/proj/.claude/../../../.ssh/
# authorized_keys with them. l04 and l09 of the measurement series wrote through such a link.
#
# NO PROCESS UNLESS A LINK IS REALLY THERE. Everything below is a shell builtin but the one
# readlink per link, so the silent path pays one lstat per component it asks about and nothing
# else. A path relative to the session is asked against the cwd the hook was handed, MK_CWD:
# the hook's own working directory is not the session's.
#
# _mk_abs <path> -> _mk_a holds the spelling that can be asked of the disk.
_mk_abs() {
  case $1 in
    /*)    _mk_a=$1 ;;
    '~/'*) _mk_a=$HOME/${1#\~/} ;;
    *)     _mk_a=${MK_CWD:-.}/$1 ;;
  esac
}

# Does a link stand on the way from the anchor <upto> down the <rest>? Only below the anchor:
# a link above a .claude or above a scratchpad cannot take the path out of it, and on macOS /tmp
# itself is one. A write that replaces or removes the link itself does not go through its last
# component, which is _mk_nf: rm, mv and ln, and the scan says which.
_mk_link_below() {
  _lb=$1; _lr=$2
  while :; do
    if [ -n "$_lr" ] || [ -z "${_mk_nf:-}" ]; then
      _mk_abs "$_lb"
      [ -L "$_mk_a" ] && return 0
    fi
    [ -n "$_lr" ] || return 1
    case $_lr in
      */*) _lb=$_lb/${_lr%%/*}; _lr=${_lr#*/} ;;
      *)   _lb=$_lb/$_lr; _lr= ;;
    esac
  done
}

# _mk_walk <path> -> _mk_walked holds where it lands, the way the kernel walks it: "." is nothing,
# ".." takes back the last component that was walked, and a link is read and walked in its place.
# It stays relative as long as nothing makes it absolute, so a verdict on a relative path keeps
# resting on that path and not on the directory the session happens to stand in. Returns 1 when
# it cannot be read: a link that does not resolve, or more of them than the kernel follows.
_mk_walk() {
  _wr=$1; _wo=; _wn=0; _wt=
  case $_wr in */) _wt=/ ;; esac
  case $_wr in
    '~/'*) _wr=$HOME/${_wr#\~/} ;;
  esac
  case $_wr in /*) _wo=/; _wr=${_wr#/} ;; esac
  while [ -n "$_wr" ]; do
    case $_wr in
      */*) _ws=${_wr%%/*}; _wr=${_wr#*/} ;;
      *)   _ws=$_wr; _wr= ;;
    esac
    case $_ws in
      ''|.) continue ;;
      ..)
        case $_wo in
          ''|..|*/..) _wo=${_wo:+$_wo/}.. ;;
          /) ;;
          */*) _wo=${_wo%/*}; [ -n "$_wo" ] || _wo=/ ;;
          *) _wo= ;;
        esac
        continue ;;
    esac
    case $_wo in
      ''|*/) _wx=$_wo$_ws ;;
      *)     _wx=$_wo/$_ws ;;
    esac
    _mk_abs "$_wx"
    if [ -L "$_mk_a" ] && { [ -n "$_wr" ] || [ -z "${_mk_nf:-}" ]; }; then
      _wn=$((_wn + 1))
      [ "$_wn" -le 40 ] || return 1
      _wl=$(readlink "$_mk_a" 2>/dev/null) && [ -n "$_wl" ] || return 1
      case $_wl in
        /*) _wo=/; _wr=${_wl#/}${_wr:+/$_wr} ;;
        *)  _wr=$_wl${_wr:+/$_wr} ;;
      esac
      continue
    fi
    _wo=$_wx
  done
  _mk_walked=${_wo:-.}$_wt
  case $_mk_walked in //) _mk_walked=/ ;; esac
  return 0
}

# The path is read where it lands, and asked again under the same switch. What cannot be read is
# work, and it is said: unreadable is the word the refusal looks for.
_mk_landed() {
  if _mk_walk "$1"; then
    _mk_why "  $1 lands on $_mk_walked, which is what a write to it reaches"
    _mk_read=1; classify_path "$_mk_walked" "${2-}"; _mk_read=
  else
    _mk_why "unreadable: a path could not be read, $1: a symlink on its way does not resolve, and what the measure cannot read is not let through, so it is work"
    printf 'work\n'
  fi
}

# classify_path <path> -> prints "bookkeeping" or "work"
classify_path() {
  _p=${1-}
  # No path means the tool did not name one. Not our business.
  [ -z "$_p" ] && { _mk_why 'no path was named, so there is nothing to measure'
                    printf 'bookkeeping\n'; return 0; }
  # PAST ANY PATH THE KERNEL ACCEPTS it is not read: the walk below is a shell loop, and a path of
  # 100000 characters would cost it seconds for a write that cannot happen.
  if [ "${#_p}" -gt 4096 ]; then
    _mk_why "unreadable: a path could not be read: it is ${#_p} characters long, past what a kernel accepts, so it is work"
    printf 'work\n'; return 0
  fi
  # A ".." IS WALKED FIRST, on both ways in and in both directions: src/../.claude/a.md is
  # bookkeeping and .claude/../src/a.py is not. Everything below reads the path after it.
  case "/$_p/" in
    */../*) if [ -z "${_mk_read:-}" ]; then _mk_landed "$_p" "${2-}"; return 0; fi ;;
  esac
  # A leading slash is prepended so a repository-relative ".claude/x" matches the same
  # pattern as an absolute "/home/u/repo/.claude/x". The pattern is deliberately
  # "/.claude/" and not "*.claude*": ".claude-plugin/plugin.json" is kit source, which
  # is work, and a loose match would wave it through.
  case "/$_p" in
    */.claude/*)
      # THE .claude ITSELF AND EVERYTHING BELOW IT is asked for a link, from the first one on the
      # path: one above it cannot move the path out, one below it can.
      if [ -z "${_mk_read:-}" ]; then
        case $_p in
          .claude/*) _lr=${_p#.claude/}; _la=.claude ;;
          *)         _lr=${_p#*/.claude/}; _la=${_p%/.claude/"$_lr"}/.claude ;;
        esac
        if _mk_link_below "$_la" "$_lr"; then _mk_landed "$_p" "${2-}"; return 0; fi
      fi
      _mk_why "  $_p is bookkeeping: it lies under a .claude directory"
      printf 'bookkeeping\n'; return 0 ;;
  esac
  case "$_p" in
    *.md)
      # ONLY THE LAST COMPONENT, because that is the one that says .md: a link above it leaves the
      # write on a file of this name, and a link in that place writes somewhere else.
      if [ -z "${_mk_read:-}" ]; then
        if _mk_link_below "$_p" ""; then _mk_landed "$_p" "${2-}"; return 0; fi
      fi
      _mk_why "  $_p is bookkeeping: it ends in .md"
      printf 'bookkeeping\n'; return 0 ;;
  esac
  # THE SESSION SCRATCHPAD, the second axis of this measure since 2026-09-08, and it is
  # narrow on purpose. It is the throwaway directory a coordinating session is handed to
  # write its own measuring scripts into: no delegate, no commit, no reader. Measured over
  # 6919 stops of a foreign project, 2613 of them (37.8 percent) land in it, and 26 of the
  # 27 read by hand out of a sample of 50 were false alarms.
  #
  # /tmp IS NOT IN IT, and that boundary is the whole of the user's decision. A second hand
  # sample of 60 found 2 real writes of production code whose only catch was a path outside
  # the work tree, at least 202 over the corpus; a rule that took all of /tmp would silence
  # every one of them. So this asks for the shape Claude Code actually lays down, not for
  # "temporary": the per-user root claude-<uid>, then the project and the session, then a
  # directory called exactly scratchpad, and anything under it.
  #
  # THE TWO SPELLINGS ARE ONE DIRECTORY. On macOS /tmp is a symlink to /private/tmp and
  # both spellings reach the guard, so the leading /private comes off before the test
  # rather than the pattern being written twice and drifting.
  #
  # The * of a case pattern crosses a slash, so the two segments between the root and the
  # scratchpad are a MINIMUM DEPTH rather than exactly two names. That is deliberate and it
  # is the loose end of this rule: it holds /tmp/claude-501/<project>/<session>/scratchpad
  # and would hold a deeper one, and it does not hold /tmp/claude-501/scratchpad.
  #
  # IT SITS LAST, behind both older axes, so no verdict and no reason either of them
  # already gave can move. Only a path they both answered "work" reaches this.
  _sp=${_p#/private}
  # THE NARROWING, and the second argument is the whole of it. The scratchpad axis rests
  # on one belief about the directory: nothing that happens there reaches the work tree.
  # For a PATH handed over on its own that belief holds, because the path is all there is.
  # For a path named by a COMMAND it holds only as long as the command does nothing the
  # measure cannot read, and _mk_narrow below is the list of shapes where it does. Asked
  # strictly, this function measures the same path with the third axis switched off, and
  # classify_bash asks strictly exactly where a shape holds.
  #
  # It is an ARGUMENT and not a global, because the caller that knows about the shape is
  # the only caller that may switch the axis off. hooks/role-guard.sh classifies a Write
  # or an Edit through the one-argument form and cannot reach this branch at all.
  if [ "${2-}" = strict ]; then
    _mk_why "  $_p is measured strictly: the command naming it carries a shape that reaches the work tree, so the session scratchpad does not answer for it"
    _sp=
  fi
  case "$_sp" in
    /tmp/claude-[0-9]*/*/*/scratchpad|/tmp/claude-[0-9]*/*/*/scratchpad/*)
      if [ -z "${_mk_read:-}" ]; then
        case $_sp in
          */scratchpad/*) _lr=${_p#*/scratchpad/}; _la=${_p%/scratchpad/"$_lr"}/scratchpad ;;
          *)              _lr=; _la=$_p ;;
        esac
        if _mk_link_below "$_la" "$_lr"; then _mk_landed "$_p" "${2-}"; return 0; fi
      fi
      _mk_why "  $_p is bookkeeping: it lies in the session scratchpad"
      printf 'bookkeeping\n'; return 0 ;;
  esac
  _mk_why "  $_p is work: it lies under no .claude directory, does not end in .md and is not in the session scratchpad"
  printf 'work\n'
}

# _mk_narrow <command> -> prints 1 when this command carries a shape that reaches the
# work tree, 0 otherwise. It is asked by classify_bash and by nothing else. Under
# MK_EXPLAIN=1 the 1 is followed by the words that name the shape, for the line in
# classify_bash that says the scratchpad was cancelled; see benannt() below.
#
# WHY IT EXISTS. The session scratchpad axis of classify_path silences a call whenever the
# only path it names lies in the scratchpad. Measured 2026-09-08 over the 5099 stops of a
# foreign project [basis.nach.tsv of the frozen corpus, awk -F'\t' '$3=="work"'], 2263 of
# them go quiet that way, and a full reading of those 2263 found 141 SILENT PASSES in them:
# calls that write real production code into a work tree and that the guard would now let
# through without a word. Two independent hand samples of 40 each, no overlap, saw 6 of
# them and back the number.
#
# The build is always the same: THE TARGET IN THE TREE IS NOWHERE ON THE COMMAND LINE. It
# sits in a script the call writes and then runs, in a heredoc body the call hands to an
# interpreter, or in the working tree a git subcommand rewrites. Those calls were caught
# before only by ACCIDENT, at the scratchpad path of the script, and the scratchpad axis is
# exactly the removal of that accident.
#
# WHAT IT DOES NOT DO. It never makes a call quieter and it never speaks on its own. It is
# asked once per call, lazily, and only about a path that classify_path already answered
# bookkeeping FOR THE SCRATCHPAD REASON ALONE. A call that names no scratchpad path at all
# never reaches it, which is why "git rebase main" on its own is still silent: the shape
# holds and there is nothing for it to hold ON.
#
# THE THREE SHAPES, measured 2026-09-08 by running THIS FILE over the frozen 5099 stops of
# that project and crossing the result with the reading by hand: 165 of the 2263 are caught,
# 140 of the 141 silent passes are closed, and 25 calls that were false alarms before the
# scratchpad axis become false alarms again. Over the whole 5099, exactly 165 verdicts move
# and every one of them moves from bookkeeping to WORK; not one call went the other way
# [paste the two result tables, awk -F'\t' '$2!=$3']:
#
#   G1 a script written and run by the same call   114 of the 165
#   G2 a heredoc body handed to an interpreter      40 of the 165
#   G3 a git subcommand that rewrites the tree      11 of the 165
#
# The three add up because a call is counted once, under the FIRST shape that answers
# for it in the order G3, G1, G2, and a call can carry two: cat > x.py <<PY writes a
# script and opens a heredoc at once.
#
# THE 25 ARE READ AND NOT COUNTED. 22 of them are one shape: a Python script that rewrites
# a MARKDOWN plan file, which is bookkeeping, while the prose it inserts cites a source
# file, which is work. The measure cannot tell the cited path from the written one without
# reading the program, so it stops. Of the other three, one edits .claude/settings.json and
# cites a directory in a comment, one writes into a tempfile.mkdtemp(), and one hands its
# heredoc to ssh, which is the hole README.md names and which this shape reopens for the
# one call in the corpus that has it.
#
# THE ONE THAT IS NOT CLOSED is a python3 heredoc that writes to sys.argv[1], with the
# three work paths standing in the "for f in ..." list of the shell around it. No literal
# reaches this scan, so nothing here can see it.
#
# WHAT IT COSTS TO RUN. Measured 2026-09-08 over the first 800 real commands of that
# corpus, two runs each: 6.07 s before this rule and 8.20 s after, 2.7 ms more per call.
# The strict question is asked once per quiet target and the awk program at most once per
# call, and a call that names no scratchpad path pays only the question.
_mk_narrow() {
  _nrun=0
  # The awk program below prints "!git" for a shape that needs no further condition,
  # "!run" for the two that do, and then the path literals of the bodies it could not
  # read. The verdict on those literals is classify_path's and not this scan's, which is
  # what keeps the rule from carrying a second copy of the measure.
  #
  # LC_ALL=C ON THE THREE AWK PROGRAMS OF THIS FILE: they read bytes, whatever the session runs in.
  # macOS awk converts its input by the locale and stops at a byte it cannot convert, so the program
  # answers nothing and the verdict is bookkeeping. Measured 2026-11-06 at 0bc14fe: under
  # en_US.US-ASCII every command with one non-ASCII character, under en_US.UTF-8 every command with
  # one byte that is no UTF-8, passed in silence. For a command in ASCII the two read alike, and
  # with no locale set this is what ran already.
  for _nw in $(printf '%s' "${1-}" | LC_ALL=C awk -v explain="${MK_EXPLAIN:-0}" '
    function why(s) { if (explain == 1) { print s > "/dev/stderr"; zuletzt = s } }
    # THE LINE THAT NAMED THE SHAPE, handed up under the trace and only there. The line
    # in classify_bash that says the scratchpad was cancelled is the LAST line of the
    # trace, which is the reason a stop carries, and until 2026-11-03 it said "the shape
    # named above": the naming stood higher in the trace than any reason reaches, and 11
    # of the 66 stops of one measured week carried no more than that. why() keeps the
    # last line it printed, and by the order of this program that line is the shape: G2
    # is printed in the main pass, G3 and G1 in END just before the answer they give, and
    # nothing else prints in between. The spaces travel as \037 because the caller splits
    # this output into words. With the trace off nothing here prints, so the verdict
    # reads exactly the words it read before.
    function benannt(   s) { if (explain == 1) { s = zuletzt; gsub(/ /, "\037", s); print "!named=" s } }
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34)
            inh = 0; delim = ""; kopf = ""; nb = 0; g1 = 0; g2 = 0; g3 = 0
            # A heredoc consumer that STORES its body instead of running it. git is in
            # here for its own reason: git commit -F - takes a message, not commands.
            split("cat tee sponge sort grep diff patch psql sqlite3 jq column awk sed wc head tail git", a, " ")
            for (i in a) senke[a[i]] = 1
            split("python python3 bash sh zsh node ruby perl", a, " ")
            for (i in a) interp[a[i]] = 1
            # The git subcommands that rewrite the WORKING TREE and that git_sub() in the
            # scan below does not read as a write. clone is deliberately absent: its target
            # is the last operand on the line and the scan reads it there already.
            split("rebase merge revert cherry-pick am switch pull clean", a, " ")
            for (i in a) baum[a[i]] = 1
            split("push pop apply save drop clear branch", a, " ")
            for (i in a) stash[a[i]] = 1
            split("add remove move", a, " ")
            for (i in a) wtree[a[i]] = 1
            # \\200-\\377: a byte above ASCII is part of the path. Spelled in ASCII only, a path
            # literal stopped at the umlaut, and /x/d is a work path [measured 2026-11-06 at
            # 0bc14fe: 5 of 300 real commands refused in a tree spelled with one, silent in its
            # twin]. These programs read bytes, see the note in _mk_narrow, and a command in ASCII
            # has no such byte, so its verdict cannot move.
            pfad = "[\\200-\\377A-Za-z0-9_.$@{}~+-]*(/[\\200-\\377A-Za-z0-9_.$@{}~+-]+)+/?"
            skript = "\\.(py|sh|bash|zsh|js|mjs|cjs|ts|rb|pl)$"
    }
    function trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
    # The NAME of a file without the directory in front of it, and without the quotes
    # somebody wrote around it. The comparison is on the BASENAME and never on the whole
    # word, because "$SP/patch.py" and the spelled out path are the same file and a
    # comparison on the text makes them two.
    function base(t) { gsub(dq, "", t); gsub(sq, "", t); sub(/^.*\//, "", t); return t }
    # The last command SEGMENT of a string: everything behind the final list separator.
    function letztes(s,   i, c) {
      for (i = length(s); i >= 1; i--) {
        c = substr(s, i, 1)
        if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")") return substr(s, i + 1)
      }
      return s
    }
    # The first command segment, used to keep a git operand scan from eating past the &&
    # that ends the git.
    function erstes(s,   i, c) {
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "\n") return substr(s, 1, i - 1)
      }
      return s
    }
    # The COMMAND WORD of a segment. A leading VAR=value is an assignment and stands in
    # front of the command, so it is stepped over: PYTHONDONTWRITEBYTECODE=1 python3 -B
    # $S/x.py hands its script to python3 and not to the assignment.
    function kopfwort(s,   k, w, j) {
      k = split(s, w, /[ \t]+/)
      for (j = 1; j <= k; j++) {
        if (w[j] == "") continue
        if (w[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
        return base(w[j])
      }
      return ""
    }
    {
      # The heredoc pass, and it is the same reading the stripper at the head of
      # classify_bash does: <<< is not a heredoc, the delimiter may be quoted, and the body
      # ends at the line that reads exactly like it after trimming. What is different is
      # that the body is KEPT here instead of dropped, because the body is the only place
      # the target of these shapes is written down.
      if (inh) {
        if (trim($0) == delim) { inh = 0 } else { rumpf[nb] = rumpf[nb] $0 "\n" }
        next
      }
      kopf = kopf $0 "\n"
      probe = $0
      gsub(/<<</, "   ", probe)
      if (match(probe, /<<-?[ \t]*[^ \t;|&<>()]+/)) {
        d = substr(probe, RSTART, RLENGTH); pos = RSTART
        sub(/^<<-?[ \t]*/, "", d)
        gsub(/[^A-Za-z0-9_\200-\377]/, "", d)
        if (d != "") {
          delim = d; inh = 1; nb++; rumpf[nb] = ""
          # G2, the CONSUMER of the heredoc: the command of the segment to the left of the
          # <<. Only the last path segment of it is read, so /usr/bin/python3 counts as
          # python3, the same way shname() reads a program name in the scan below.
          k = kopfwort(letztes(substr(probe, 1, pos - 1)))
          if (k != "" && !(k in senke)) {
            g2 = 1
            why("the heredoc <<" d " is handed to " k ", which RUNS its body instead of storing it")
          }
        }
      }
    }
    END {
      # G3, and it is the only one of the three with no further condition. Measured
      # 2026-09-08 over the 2263, it costs nothing: all 11 calls it catches are silent
      # passes read by hand.
      s = kopf
      while (match(s, /(^|[ \t\n;|&()`])git[ \t]/)) {
        s = substr(s, RSTART + RLENGTH)
        rest = erstes(s)
        n = split(rest, w, /[ \t]+/)
        j = 1
        # git carries its own options in front of the subcommand and two of them take the
        # NEXT word, -C <path> and -c <name=value>. Stepped over the same way git_sub()
        # steps over them in the scan below.
        while (j <= n && (w[j] == "" || w[j] == "-C" || w[j] == "-c")) { if (w[j] == "-C" || w[j] == "-c") j++; j++ }
        while (j <= n && w[j] ~ /^-/) j++
        if (j > n) continue
        ub = w[j]
        o = ""
        for (m = j + 1; m <= n; m++) { if (w[m] != "" && w[m] !~ /^-/) { o = w[m]; break } }
        if (ub in baum) { g3 = 1; why("the git subcommand " ub " rewrites the working tree, and no operand of it is on the line"); break }
        # stash list and stash show only read. A stash with no operand at all is a push.
        if (ub == "stash" && (o == "" || (o in stash))) { g3 = 1; why("the git subcommand stash " o " rewrites the working tree, and no operand of it is on the line"); break }
        if (ub == "worktree" && (o in wtree)) { g3 = 1; why("the git subcommand worktree " o " rewrites the working tree, and no operand of it is on the line"); break }
        # git reset -q HEAD -- pfad moves the INDEX and leaves the tree alone. Only the
        # three modes that write files count.
        if (ub == "reset" && rest ~ /--(hard|merge|keep)([ \t]|$)/) { g3 = 1; why("the git subcommand reset rewrites the working tree with --hard, --merge or --keep"); break }
      }
      if (g3) { benannt(); print "!git"; exit }

      # G1, a script WRITTEN and RUN by the same call. Both halves have to be on the line:
      # the redirection that lays the file down, and an interpreter or a path that runs it.
      # cat >> counts like cat >, because a script appended to is a script written.
      s = kopf
      while (match(s, />>?[ \t]*[^ \t;|&<>()]+/)) {
        t = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        sub(/^>>?[ \t]*/, "", t)
        b = base(t)
        if (b ~ skript) geschrieben[b] = 1
      }
      tmp = kopf
      gsub(/&&|\|\|/, "\n", tmp)
      gsub(/[;|()]/, "\n", tmp)
      ns = split(tmp, segs, "\n")
      for (si = 1; si <= ns && !g1; si++) {
        nw = split(segs[si], w, /[ \t]+/)
        j = 1
        while (j <= nw && (w[j] == "" || w[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) j++
        if (j > nw) continue
        k = base(w[j])
        if (k in interp) {
          for (m = j + 1; m <= nw; m++)
            if (w[m] != "" && (base(w[m]) in geschrieben)) {
              g1 = 1
              why("the script " base(w[m]) " is written by this command and handed to " k " by the same one")
              break
            }
        }
        # The same shape with no interpreter word: chmod +x on a script and then the
        # script itself. It needs a slash in the word, so an ordinary program name can
        # never be mistaken for it. Measured 2026-09-08 over the 2263 this branch fires
        # NOT ONCE, so what it costs is unmeasured; it is kept because it errs loud.
        if (!g1 && (w[j] ~ /^\.\// || w[j] ~ /^\//) && (base(w[j]) in geschrieben)) {
          g1 = 1
          why("the script " base(w[j]) " is written by this command and run by the same one")
        }
      }
      if (!g1 && !g2) exit
      benannt(); print "!run"

      # THE CONDITION ON G1 AND G2, and it is the core of the narrowing. The shape alone
      # says the call runs something this measure cannot read; it does not say that what it
      # runs reaches the work tree. So the unreadable body is asked for a path literal, and
      # classify_path is asked whether that path is work. Measured 2026-09-08 over the
      # 2263: without this condition G1 and G2 together cost 182 false alarms instead of
      # 25, and they close one more silent pass for it.
      #
      # THREE THINGS ARE CUT AWAY BEFORE THE LITERALS ARE READ, and each one was measured:
      #   a body that writes NOTHING this scan can see is not read at all. Without that
      #     line the price is 85 instead of 25: a script that only READS the work tree is
      #     the commonest thing in the scratchpad;
      #   a triple quoted block is PROSE the script inserts, not program text;
      #   a Markdown code span in backticks is a CITATION, not a target. Without that line
      #     the price is 28 instead of 25 and not one silent pass more is closed.
      wre = "\\.write_text[ \t]*\\(|\\.write_bytes[ \t]*\\(|open[ \t]*\\([^;]*,[ \t]*[" dq sq "][wax]"
      for (bi = 1; bi <= nb; bi++) {
        b = without3(rumpf[bi])
        gsub(/`[^`\n]*`/, " ", b)
        if (b !~ wre) { why("the heredoc body " bi " writes nothing this scan can read, so the paths in it are not read either"); continue }
        nl = split(b, lines, "\n")
        for (li = 1; li <= nl; li++) litzeile(lines[li])
      }
    }
    # A body without its triple quoted blocks. An unterminated block takes the rest of the
    # body with it, which is the quiet direction and the right one: what cannot be read is
    # not evidence.
    function without3(b,   out, p1, p2, p, m, q) {
      out = ""
      while (1) {
        p1 = index(b, dq dq dq); p2 = index(b, sq sq sq)
        if (p1 == 0 && p2 == 0) return out b
        if (p1 == 0 || (p2 > 0 && p2 < p1)) { p = p2; m = sq sq sq } else { p = p1; m = dq dq dq }
        out = out substr(b, 1, p - 1)
        b = substr(b, p + 3)
        q = index(b, m)
        if (q == 0) return out
        b = substr(b, q + 3)
      }
    }
    # The path shaped literals of ONE line of a body. Only what stands inside quotes is
    # read, because a path in a program is written as a string; and only a token carrying a
    # slash, because a bare name is as likely to be a variable as a file. Each literal is
    # printed once: the caller runs classify_path over every one of them and the same path
    # twice is the same answer twice.
    # A WORD IN A BODY IS A PATH WHEN IT IS ANCHORED OR CARRIES AN ENDING, and these two
    # halves are the whole of the narrowing of 2026-11-02. Prose with a slash satisfies
    # neither: "10/10" and "Hoch/Tief" cost 16 of the 122 stops of the measured week.
    # Either half alone is measurably worse than the pair, both directions in
    # tests/run.sh under "prose in a heredoc body is not a path".
    function istanker(t) { return (t ~ /^\// || t ~ /^~\// || t ~ /^\.\.?\// || t ~ /^\$/) }
    function hatendung(t) { return (t ~ /\/[^\/]*\.[A-Za-z][A-Za-z0-9]*$/) }
    function litzeile(s,   c, p, e, body, t, q) {
      while (length(s) > 0) {
        p = 0
        for (c = 1; c <= length(s); c++)
          if (substr(s, c, 1) == dq || substr(s, c, 1) == sq) { p = c; break }
        if (p == 0) return
        q = substr(s, p, 1)
        e = index(substr(s, p + 1), q)
        if (e == 0) return
        body = substr(s, p + 1, e - 1)
        s = substr(s, p + e + 1)
        while (match(body, pfad)) {
          t = substr(body, RSTART, RLENGTH)
          body = substr(body, RSTART + RLENGTH)
          if (index(t, "/") > 0 && (istanker(t) || hatendung(t)) && !(t in gesehen)) { gesehen[t] = 1; print t }
        }
      }
    }'); do
    case "$_nw" in
      '!named='*) _nnamed=$(printf '%s' "${_nw#!named=}" | tr '\037' ' '); continue ;;
      '!git') printf '1%s\n' "${_nnamed:+ $_nnamed}"; return 0 ;;
      '!run') _nrun=1; continue ;;
    esac
    # Only reachable behind a "!run", because the two shapes that print literals are the
    # two that need one. A literal that is itself bookkeeping proves nothing: a script that
    # writes into the scratchpad, or over a Markdown file, is the ordinary case and stays
    # quiet.
    [ "$_nrun" = 1 ] || continue
    if [ "$(classify_path "$_nw")" = work ]; then
      _mk_why "  the body this command runs names $_nw, which is work, so the shape reaches the work tree"
      printf '1%s\n' "${_nnamed:+ $_nnamed, and the body this command runs names $_nw, which is work}"; return 0
    fi
  done
  printf '0\n'
}

# THE PARTS OF THE SCAN THAT MOST COMMANDS NEVER USE, kept out of the program a command that does
# not name them hands to awk. awk parses what it is given on every call, and the silent path is every
# tool call of a session: with all of this in one program a plain git status paid 3.6 ms more
# [median of 40 paired runs against 7d695ce, 80.6 to 84.2 ms]. A word in the command loads its part;
# the word is looked for by a shell case and costs no process. The stubs keep the program whole.
_MK_AWK_PROG='
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34)
            pm = sprintf("%c", 6); ss = sprintf("%c", 28); nl = 0; pq = ""
            q2 = "[" sq dq "]"
            opener = "(^|[ \t;|&(/`])(python[0-9.]*|nodejs|node|ruby|perl|gawk|awk)[ \t]"
            py = "(^|[^A-Za-z0-9_.])open[ \t]*\\(|(io|codecs)\\.open[ \t]*\\(|\\.(write_text|write_bytes|touch|mkdir|unlink|rmdir|rename)[ \t]*\\(|os\\.(remove|unlink|rmdir|removedirs|mkdir|makedirs|mkfifo|truncate|rename|renames|replace|link|symlink)[ \t]*\\(|shutil\\.(copy|copy2|copyfile|copytree|move|rmtree)[ \t]*\\("
            js = "\\.(writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|mkdir|mkdirSync|rm|rmSync|rmdir|rmdirSync|unlink|unlinkSync|truncate|truncateSync|rename|renameSync|copyFile|copyFileSync|cp|cpSync|symlink|symlinkSync)[ \t]*\\("
            rb = "(File|IO)\\.(write|binwrite|open|new|delete|unlink|rename)[ \t]*\\(|FileUtils\\.[a-z_]+[ \t]*\\(|Dir\\.(mkdir|rmdir)[ \t]*\\("
            pl = "(^|[^A-Za-z0-9_$])(open|unlink|rename|mkdir|rmdir)[ \t]*\\("
            ak = "printf?[^;}\n]*>>?[ \t]*" dq "[^" dq "]+" dq
    }
    function trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
    # ONE WORD MORE IN FRONT OF THE INTERPRETER, spaces carried as \034 because the scan splits
    # on them. A path that is "/dev/null" and the like is dropped where every target is dropped.
    function pw_add(t) { gsub(/ /, ss, t); if (!(t in pw_seen)) { pw_seen[t] = 1; pw = pw pm t " " } }
    # The arguments of the call whose opening parenthesis lies just in front of s, at their top
    # level: a[1..n], a quote and a nested parenthesis hold a comma back. Stops at 2000
    # characters: a call that long is not a call anybody typed.
    function args(s, a,   i, c, depth, q, cur, n, m) {
      split("", a); n = 0; depth = 0; q = ""; cur = ""; m = length(s)
      for (i = 1; i <= m; i++) {
        c = substr(s, i, 1)
        if (q != "") { cur = cur c; if (c == q) q = ""; continue }
        if (c == sq || c == dq) { q = c; cur = cur c; continue }
        if (c == "(" || c == "[" || c == "{") depth++
        if (c == ")" || c == "]" || c == "}") { if (depth == 0) break; depth-- }
        if (c == "," && depth == 0) { a[++n] = cur; cur = ""; continue }
        cur = cur c
      }
      a[++n] = cur
      return n
    }
    # A WHOLE ARGUMENT THAT IS A STRING LITERAL, and nothing else: r and b in front of it change
    # nothing about the path, an f in front of it does. Empty when it is anything else.
    function lit(t,   q, b) {
      t = trim(t)
      if (t ~ /^[rbuRBU][^A-Za-z0-9_]/) t = substr(t, 2)
      q = substr(t, 1, 1)
      if (q != sq && q != dq) return ""
      if (length(t) < 3 || substr(t, length(t), 1) != q) return ""
      b = substr(t, 2, length(t) - 2)
      if (index(b, q)) return ""
      return b
    }
    # A NAME THE SAME TEXT ASSIGNS A LITERAL, p = "x" or p = Path("x"). The first assignment on the
    # page, the same way a shell variable is read.
    function named(v,   re, l) {
      if (v !~ /^[A-Za-z_][A-Za-z0-9_]*$/) return ""
      re = "(^|[^A-Za-z0-9_.])" v "[ \t]*=[ \t]*([A-Za-z_.]*\\([ \t]*)?[rb]?" q2 "[^" sq dq "]*" q2
      if (!match(pbody, re)) return ""
      l = substr(pbody, RSTART, RLENGTH)
      sub(/^[^=]*=[ \t]*/, "", l)
      sub(/^[A-Za-z_.]*\([ \t]*/, "", l)
      return lit(l)
    }
    # THE TARGET, WHEN IT IS READABLE. One that is not is no stop: measured over the 136164 commands
    # of MK-A6 it would be 182 distinct stops, 687 weighted, 127 and 621 of them in a main session,
    # and those read by hand are bookkeeping edits through sys.argv. README.md names the limit.
    function tar(t,   l) {
      t = trim(t)
      l = lit(t)
      if (l == "") l = named(t)
      if (l != "") { pw_add(l); why("the program text writes " l); return }
      why("the program text writes to something that is no literal, and that is the limit README.md names")
    }
    # WHAT ONE PROGRAM TEXT WRITES. Language by language, and each hit looks at its own call.
    function prog(b, lang,   re, r, s, name, pre, a, n, i, l, hits, m) {
      re = (lang == "py" ? py : lang == "js" ? js : lang == "rb" ? rb : lang == "pl" ? pl : ak)
      r = b; pbody = b
      hits = 0
      while (match(r, re)) {
        if (++hits > 64) { if (!pu_quiet) pw_add("@@p@@"); why("the program text has more write calls than this scan reads"); return }
        pre = substr(r, 1, RSTART - 1); name = substr(r, RSTART, RLENGTH); s = substr(r, RSTART + RLENGTH)
        r = s
        if (lang == "ak") {
          l = name; sub(/^.*>>?[ \t]*/, "", l); gsub(dq, "", l)
          if (l != "") { pw_add(l); why("the program text prints into " l) }
          continue
        }
        sub(/^[^A-Za-z.]*/, "", name); sub(/[ \t]*\($/, "", name)
        n = args(substr(s, 1, 2000), a)
        if (lang == "py") {
          if (name ~ /open$/) {
            # The mode decides: it is the second argument, or mode= somewhere.
            m = ""
            for (i = 2; i <= n; i++) { l = a[i]; sub(/^[ \t]*mode[ \t]*=[ \t]*/, "", l); if (i == 2 || a[i] ~ /^[ \t]*mode[ \t]*=/) { m = lit(l); if (m != "") break } }
            if (m ~ /[wax+]/) tar(a[1])
          } else if (name ~ /^\./) {
            # A method: its target stands in front of the dot, Path("x").write_text(...).
            if (name == ".rename") tar(a[1])
            if (match(pre, "[A-Za-z_.]*\\([ \t]*[rb]?" q2 "[^" sq dq "]*" q2 "[ \t]*\\)$")) {
              l = substr(pre, RSTART, RLENGTH); sub(/^[^(]*\(/, "", l); sub(/\)$/, "", l); tar(l)
            } else if (match(pre, /[A-Za-z_][A-Za-z0-9_]*$/)) tar(substr(pre, RSTART))
          } else if (name ~ /\.(copy|copy2|copyfile|copytree|link|symlink)$/) tar(a[2])
          else if (name ~ /\.(move|rename|renames|replace)$/) { tar(a[1]); tar(a[2]) }
          else tar(a[1])
        } else if (lang == "js") {
          if (name ~ /(copyFile|copyFileSync|cp|cpSync|symlink|symlinkSync)$/) tar(a[2])
          else if (name ~ /(rename|renameSync)$/) { tar(a[1]); tar(a[2]) }
          else tar(a[1])
        } else if (lang == "rb") {
          if (name ~ /(open|new)$/) { m = lit(a[2]); if (m ~ /[wa+]/) tar(a[1]) }
          else if (name ~ /(rename|mv)$/) { tar(a[1]); tar(a[2]) }
          else if (name ~ /FileUtils\.(cp|cp_r|ln|ln_s)$/) tar(a[2])
          else if (name ~ /FileUtils\.(rm|rm_r|rm_rf|rm_f|mkdir|mkdir_p|touch|rmdir)$/ || name !~ /FileUtils/) tar(a[1])
        } else {
          if (name ~ /open$/) {
            l = lit(a[2])
            if (l ~ /^\+?>/) { sub(/^\+?>>?[ \t]*/, "", l); if (l != "") tar(sq l sq); else tar(a[3]) }
          } else if (name ~ /rename$/) { tar(a[1]); tar(a[2]) }
          else tar(a[1])
        }
      }
    }
    # Is the word at p the interpreter of a program text on this line? Sets p_lang, and p_at to
    # where the body opens with its quote behind the option. The words between are its flags.
    function opener_at(s,   k, w, i, name, opt, lang, pos, wn) {
      k = split(s, w, /[ \t]+/)
      name = w[1]; sub(/^.*\//, "", name)
      lang = (name ~ /^python/ ? "py" : name ~ /^node/ ? "js" : name == "ruby" ? "rb" : name == "perl" ? "pl" : "ak")
      if (lang == "py") opt = "^-[A-Za-z]*c$"
      else if (lang == "js") opt = "^(-e|--eval|-p|--print)$"
      else if (lang == "rb") opt = "^-[A-Za-z0-9]*e$"
      else if (lang == "pl") opt = "^-[0-9A-Za-z]*[eE]$"
      else opt = ""
      pos = length(w[1]) + 1
      for (i = 2; i <= k && i <= 12; i++) {
        wn = substr(s, pos)
        # Step over the gap, by the length it really has.
        match(wn, /^[ \t]*/); pos += RLENGTH
        if (w[i] == "") continue
        if (opt == "") {
          # awk: the first word that opens with a quote is its program. -F, and -v take a word.
          if ((substr(w[i], 1, 1) == sq || substr(w[i], 1, 1) == dq) && w[i - 1] !~ /^-[Fv]$/) { p_lang = lang; p_at = pos; return 1 }
          if (w[i] !~ /^-/ && i > 2 && w[i - 1] !~ /^-[Fv]$/) return 0
        } else {
          if (w[i] ~ opt) {
            wn = substr(s, pos + length(w[i]))
            match(wn, /^[ \t]+/)
            if (!RLENGTH || RLENGTH < 0) return 0
            pos += length(w[i]) + RLENGTH
            if (substr(s, pos, 1) != sq && substr(s, pos, 1) != dq) return 0
            p_lang = lang; p_at = pos
            return 1
          }
          if (w[i] !~ /^-/ && !(i > 2 && w[i - 1] ~ /^-[WXmMI]$/)) return 0
        }
        pos += length(w[i])
      }
      return 0
    }
    # Is this interpreter handed to another machine or into a container on its own segment?
    # Then what its program writes is not on this machine, the hole README.md keeps.
    function offsite(s,   i, c, seg) {
      seg = s
      for (i = length(s); i >= 1; i--) {
        c = substr(s, i, 1)
        if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")") { seg = substr(s, i + 1); break }
      }
      return (seg ~ /(^|[ \t\/])(ssh|docker|docker-compose|podman)[ \t]/)
    }
    # A word in front of column p of the line it belongs to.
    function insert(n, p, words) { out[n] = substr(out[n], 1, p - 1) words substr(out[n], p) }
    # Close the program text that was opened on line pline and hand its words to that line.
    function prog_end(   b) {
      b = pbuf; pq = ""
      if (pquote == dq) { gsub(/\\"/, dq, b); gsub(/\\\$/, "$", b) } else gsub(/\\"/, dq, b)
      pw = ""; split("", pw_seen); pu_quiet = 0
      prog(b, plang)
      if (pw != "") insert(pline, pcol, pw)
    }
    # An unescaped quote q in s, from i on; 0 if none. Only a double quote can be escaped.
    function qclose(s, q, i,   r, e) {
      r = substr(s, i)
      while ((e = index(r, q)) > 0) {
        if (q != dq || e == 1 || substr(r, e - 1, 1) != "\\") return i + e - 1
        i += e; r = substr(r, e + 1)
      }
      return 0
    }
    function prog_line(   e, from, added, nop_line, st, ln, next_from, w0, rest, r2, rest_off, body_at, before) {
      # A program text that opened on a line above runs on until its quote closes.
      if (pq != "") {
        e = qclose($0, pq, 1)
        if (e) { pbuf = pbuf substr($0, 1, e - 1); prog_end() } else pbuf = pbuf $0 "\n"
      } else if (!inh) {
        # Every interpreter on this line. The offset moves with what was inserted in front.
        # At most 16 to a line, and a line past the read limit is refused below anyway: what this
        # loop costs has to stay under the hook budget whatever is typed at it.
        from = 1; added = 0; nop_line = 0
        while (pq == "" && length($0) <= 65536 && nop_line++ < 16 && match(substr($0, from), opener)) {
          st = from + RSTART - 1; ln = RLENGTH; next_from = st + ln
          # The interpreter word starts behind the character the pattern opened on, and a path in
          # front of it belongs to it: /usr/bin/python3 and .venv/bin/python are one word.
          w0 = substr($0, st, ln)
          if (w0 ~ /^[ \t;|&(\/`]/) st++
          while (st > 1 && substr($0, st - 1, 1) ~ /[A-Za-z0-9_.\/~$-]/) st--
          rest = substr($0, st)
          from = next_from
          if (rest ~ /^[A-Za-z0-9_.\/~$-]*\//) { r2 = rest; sub(/^[A-Za-z0-9_.\/~$-]*\//, "", r2); rest_off = length(rest) - length(r2) } else { r2 = rest; rest_off = 0 }
          if (r2 !~ /^(python[0-9.]*|nodejs|node|ruby|perl|gawk|awk)[ \t]/) continue
          if (offsite(st > 2000 ? substr($0, st - 2000, 2000) : substr($0, 1, st - 1))) continue
          if (!opener_at(substr(r2, 1, 4096))) continue
          body_at = st + rest_off + p_at - 1
          e = qclose($0, substr($0, body_at, 1), body_at + 1)
          pquote = substr($0, body_at, 1); plang = p_lang; pline = nl; pcol = st + added
          if (e) {
            pbuf = substr($0, body_at + 1, e - body_at - 1)
            before = length(out[nl]); prog_end(); added += length(out[nl]) - before
            from = e + 1
          } else { pbuf = substr($0, body_at + 1) "\n"; pq = pquote }
        }
      }
    }
    # WHO RUNS THE HEREDOC. An interpreter with nothing but flags and a - in front of it, with or
    # without arguments behind the -: that is a program text. python3 run.py <<EOF hands a script
    # data, and that body is data.
    function hd_open(head,   i, c, hlo, seg, h0) {
      hlang = ""; hbuf = ""; hline = nl; hcol = 1; hlo = length(head) - 2000
      if (hlo < 1) hlo = 1
      for (i = length(head); i >= hlo; i--) {
        c = substr(head, i, 1)
        if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")") { hcol = i + 1; break }
      }
      seg = substr(head, hcol)
      if (seg !~ /(^|[ \t\/])(ssh|docker|docker-compose|podman)[ \t]/ &&
          match(seg, /(^|[ \t\/])(python[0-9.]*|nodejs|node|ruby|perl)([ \t]+-[^ \t]+)*([ \t]+-([ \t]|$)|[ \t]*$)/)) {
        h0 = substr(seg, RSTART, RLENGTH); sub(/^[ \t\/]/, "", h0); sub(/[ \t].*$/, "", h0)
        hlang = (h0 ~ /^python/ ? "py" : h0 ~ /^node/ ? "js" : h0 == "ruby" ? "rb" : "pl")
      }
    }
    function hd_line() { if (hlang != "" && length(hbuf) < 262144) hbuf = hbuf $0 "\n" }
    function hd_close(   b) {
      if (hlang == "") return
      b = hbuf; hbuf = ""
      pw = ""; split("", pw_seen); pu_quiet = 1
      prog(b, hlang)
      if (pw != "") insert(hline, hcol, pw)
      hlang = ""
    }
    function hd_end() {
      if (pq != "") prog_end()
      if (inh) hd_close()
    }
'
_MK_AWK_NOPROG='
    function prog_line() { }
    function hd_open(h) { }
    function hd_line() { }
    function hd_close() { }
    function hd_end() { }
'
_MK_AWK_OPT='
    # A word of its own in a word list: does s, space framed, hold the word w?
    function inlist(s, w) { return index(" " s " ", " " w " ") > 0 }
    # The value of an option, out of its own word or the next. Sets opend.
    function nextval(j) { if (j < NF && $(j + 1) !~ /^[;&|]+$/) return opnd(j + 1); opend = j; return "" }
    function wr(c, opt, v) {
      if (v == "" || v == "-") return
      why("the option " opt " of " c " names what it writes, " v)
      tgt(resolve(unclose(v)))
    }
    function optwrite(start, c,   j, t, k, ch, v, vals, wv, lo, lcwd, cwd, nm, hit, nw, mode, f, dirs, nop, old, ndirs) {
      if (c == "curl") { vals = "AbcCdDeEFhHKmoPQrtTuUwxXyYz"; wv = "oDc"; lo = "output dump-header cookie-jar trace trace-ascii stderr output-dir etag-save"; lcwd = "remote-name remote-name-all"; cwd = 0 }
      else if (c == "wget") { vals = "aABDeiIlOoPQRtTUwXY"; wv = "aoOP"; lo = "output-document output-file append-output directory-prefix"; lcwd = ""; cwd = 1 }
      else if (c == "sort") { vals = "koStT"; wv = "o"; lo = "output"; lcwd = ""; cwd = 0 }
      else if (c == "unzip") { vals = "dx"; wv = "d"; lo = ""; lcwd = ""; cwd = 1; nw = "lptZcfvz" }
      else if (c == "zip") { nop = 0
        for (j = start; j <= NF; j++) {
          if ($j ~ /^[;&|]+$/ || $j == ")" || $j == "(" || $j == uq) return
          if ($j ~ /[<>]/) { if ($j ~ /[<>]$/) j++; continue }
          if ($j ~ /^-/) continue
          wr(c, "operand", opnd(j)); return
        }
        return }
      else { # tar, and its first word may be its options with no dash: tar xzf a.tgz
        mode = ""; f = ""; ndirs = 0; old = 0
        for (j = start; j <= NF; j++) {
          if ($j ~ /^[;&|]+$/ || $j == ")" || $j == "(" || $j == uq) break
          if ($j ~ /[<>]/) { if ($j ~ /[<>]$/) j++; continue }
          t = opnd(j); j = opend
          if (t ~ /^--/) {
            nm = substr(t, 3); k = index(nm, "="); v = ""
            if (k) { v = substr(nm, k + 1); nm = substr(nm, 1, k - 1) }
            if (nm == "extract" || nm == "get") mode = mode "x"
            else if (nm == "create" || nm == "append" || nm == "update" || nm == "delete") mode = mode "c"
            else if (nm == "list") mode = mode "t"
            else if (nm == "to-stdout") mode = mode "O"
            else if (nm == "file") { if (!k) { v = nextval(j); j = opend } f = v }
            else if (nm == "directory") { if (!k) { v = nextval(j); j = opend } dirs[++ndirs] = v }
            continue
          }
          if (t ~ /^-./ || (j == start && t ~ /^[A-Za-z]+$/ && !old)) {
            old = (t !~ /^-/)
            for (k = (old ? 1 : 2); k <= length(t); k++) {
              ch = substr(t, k, 1)
              if (index("xcrutO", ch)) mode = mode (ch == "r" || ch == "u" ? "c" : ch)
              else if (index("fCTXbHKLNVg", ch)) {
                # With a dash the rest of the word is the value; without one, the next word is.
                if (!old && k < length(t)) { v = substr(t, k + 1); k = length(t) }
                else { v = nextval(j); j = opend }
                if (ch == "f") f = v; else if (ch == "C") dirs[++ndirs] = v
              }
            }
            continue
          }
        }
        if (mode ~ /x/ && mode !~ /O/) {
          if (ndirs) for (k = 1; k <= ndirs; k++) wr(c, "-C", dirs[k])
          else { why(c " extracts into the directory it stands in, so . is read"); tgt(".") }
        } else if (mode ~ /c/) {
          if (f != "") wr(c, "-f", f); else why(c " writes its archive to stdout")
        }
        return
      }
      hit = 0; nop = 0
      for (j = start; j <= NF; j++) {
        if ($j ~ /^[;&|]+$/ || $j == ")" || $j == "(" || $j == uq) break
        if ($j ~ /[;&|]$/ && $j !~ /^-/) break
        if ($j ~ /[<>]/) { if ($j ~ /[<>]$/) j++; continue }
        t = opnd(j); j = opend
        if (t ~ /^--/) {
          nm = substr(t, 3); k = index(nm, "="); v = ""
          if (k) { v = substr(nm, k + 1); nm = substr(nm, 1, k - 1) }
          if (lo != "" && inlist(lo, nm)) { if (!k) { v = nextval(j); j = opend } wr(c, t, v); hit = 1; cwd = 0 }
          else if (lcwd != "" && inlist(lcwd, nm)) cwd = 2
          else if (nm == "spider" || nm == "help" || nm == "version") cwd = 0
          continue
        }
        if (t ~ /^-./) {
          for (k = 2; k <= length(t); k++) {
            ch = substr(t, k, 1)
            if (c == "curl" && ch == "O") { cwd = 2; continue }
            if (c == "unzip" && index(nw, ch)) { cwd = 0; continue }
            if (index(vals, ch)) {
              if (k < length(t)) { v = substr(t, k + 1); k = length(t) } else { v = nextval(j); j = opend }
              if (index(wv, ch)) {
                wr(c, "-" ch, v); hit = 1
                # wget -O - and unzip -d are the place, so nothing lands where the command stands.
                if (c == "wget" && (ch == "O" || ch == "P")) cwd = 0
                if (c == "unzip") cwd = 0
              }
            }
          }
          continue
        }
        nop++
      }
      if (c == "curl" && cwd == 2 && !hit) { why(c " -O writes into the directory it stands in, so . is read"); tgt(".") }
      else if (c == "wget" && cwd == 1 && nop) { why(c " writes into the directory it stands in, so . is read"); tgt(".") }
      else if (c == "unzip" && cwd == 1 && nop) { why(c " extracts into the directory it stands in, so . is read"); tgt(".") }
    }
'
_MK_AWK_GITW='
    # git clone <url> <where>, or into the directory it stands in. The options that take a word are
    # git-clone(1)s, and an operand counted wrong would read the url as the target.
    function clone_read(start,   j, n, last) {
      n = 0
      for (j = start; j <= NF; j++) {
        if ($j ~ /^[;&|]+$/ || $j == ")" || $j == "(" || $j == uq) break
        if ($j ~ /[<>]/) { if ($j ~ /[<>]$/) j++; continue }
        if ($j ~ /^(-b|-o|-c|-j|-u|--branch|--origin|--config|--jobs|--depth|--reference|--separate-git-dir|--template|--upload-pack|--shallow-since|--shallow-exclude|--filter)$/) { j++; continue }
        if ($j ~ /^-/) continue
        last = opnd(j); j = opend; n++
      }
      if (n >= 2) { why("git clone writes into " last); tgt(resolve(unclose(last))) }
      else if (n == 1) { why("git clone writes into the directory it stands in, so . is read"); tgt(".") }
    }
'
_MK_AWK_NOOPT='
    function optwrite(s, c) { }
'
_MK_AWK_NOGITW='
    function clone_read(s) { }
'

# classify_bash <command> -> prints "bookkeeping" or "work"
#
# Deliberately crude, and the README says so in as many words. It reads a shell command
# as text, and a shell command is not text. Two holes are known and named: a write a
# program performs internally ("python build.py") is invisible here, and a construction
# this stripper does not understand can hide a redirection. It catches the common hand
# movements and nothing more.
#
# A third hole was closed on 2026-09-07: a write verb used to count at any word position,
# so "claude plugin install manager-kit" read as work. It now counts in COMMAND position
# only, and the whole risk of that rule is that command position is not the first word of
# the line. See the comment on the target scan below for the shapes that put a word back
# into command position, and tests/run.sh for the assertion that holds every one of them.
#
# A fourth was closed on 2026-09-08, and it sat at the centre of the promise: the body a
# shell is handed with -c is a COMMAND, and it was being blanked as text the moment it
# carried a metacharacter. See the quoting loop in the scan below. The line above stands as
# written for everything else, and the two holes that stay are the two named in README.md
# next to it: a command handed to another machine or another container is not read, and a
# write verb written with a path in front of it is not read as a verb.
#
# A fifth was closed on 2026-09-08 as well, and it is the only hole on that list the guard
# was ever measured to have FIRED on: a path that arrives in a shell variable was read as
# the literal word "$L". A coordinating session was refused its own session ledger with
# it. Assignments made by the same command are now resolved before the target is judged;
# see record() and resolve() in the scan below for what is resolvable and what is left
# loud. Measured over 95490 distinct real commands, 466001 weighted: 65 distinct and 216
# weighted changed verdict, all of them stop to silence, and with the path written out in
# full the measure already answered bookkeeping for every one of them. Nothing went the
# other way. The rate moved from 10.2304 to 10.1623 percent distinct, 9.6238 to 9.5774
# weighted.
#
# WITH MK_EXPLAIN=1 it also writes its reasons to STDERR, one line per decision, out of the
# branches that make them. The verdict on stdout is not touched by that switch: measured
# 2026-09-08 over 450735 real Bash commands, the verdict of every single one is the same
# character before and after this trace was added. tools/mk-explain.sh is what turns it on.
classify_bash() {
  _c=${1-}
  [ -z "$_c" ] && { _mk_why 'the command is empty, so there is nothing to read'
                    printf 'bookkeeping\n'; return 0; }

  # A heredoc body is DATA, not command text. It goes first, before quoted segments are
  # stripped, because stripping would eat the delimiter in << 'PY' and leave the body
  # looking like a run of commands. Measured 2026-09-07 against 30877 real commands: prose
  # and program text inside heredocs was one of two sources of false stops.
  #
  # IT ALSO READS WHAT A PROGRAM TEXT WRITES, and this pass is the only one that can: the body of
  # python3 -c may run over several lines, the scan below reads one line at a time, and the body
  # of a heredoc is gone behind this pass. What a program writes comes out as a word of its own,
  # \006 and the path, in front of the interpreter on its line, so the scan reads it in order and
  # a cd in front of it counts. No process: it is the same awk, and a line that names no
  # interpreter pays one regular expression.
  #
  # WHAT IS READ AND WHAT IS NOT, because the great majority of these programs only read: 5797
  # distinct real python -c in the corpus of MK-A6, 434 with a write word in them. A call that
  # writes is recognised by its name and, for open(), by its mode. A literal as its target is
  # read as that path, and so is a name the same text assigns a literal. Anything else passes and
  # README.md names it: see tar() for what stopping it would cost. A program that hides its write
  # behind an import or a helper is not read at all.
  case $_c in
    *python*|*node*|*ruby*|*perl*|*awk*) _mk_p=$_MK_AWK_PROG ;;
    *) _mk_p=$_MK_AWK_NOPROG ;;
  esac
  _s=$(printf '%s' "$_c" | LC_ALL=C awk -v explain="${MK_EXPLAIN:-0}" "$_mk_p"'
    # See _mk_why above. The trace goes to stderr because stdout is the stripped text.
    function why(s) { if (explain == 1) print s > "/dev/stderr" }
    {
      nl++; out[nl] = $0
      prog_line()
      if (inh) {
        t = $0
        sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        nl--
        if (t == delim) { inh = 0; hd_close() } else hd_line()
        next
      }
      probe = $0
      gsub(/<<</, " ", probe)
      if (match(probe, /<<-?[ \t]*[^ \t;|&<>()]+/)) {
        d = substr(probe, RSTART, RLENGTH); dpos = RSTART
        sub(/^<<-?[ \t]*/, "", d)
        gsub(/[^A-Za-z0-9_\200-\377]/, "", d)
        if (d != "") { delim = d; inh = 1
                       why("the body of the heredoc <<" d " is dropped: it is data, not command text")
                       hd_open(substr(probe, 1, dpos - 1)) }
      }
    }
    END {
      hd_end()
      for (i = 1; i <= nl; i++) print out[i]
    }')

  # WHAT THE MEASURE CANNOT READ IN THE TIME IT HAS IS NOT LET THROUGH. A command this long
  # is handed to a program that would run past the hook budget, and a guard that has not
  # answered by then has not refused, which for a guard whose one promise is the refusal is
  # the silent pass this file exists to prevent. It is work, with the reason in the trace, so
  # the stop line says what happened and the declared way out stays open to a command that
  # has to be this long.
  if [ "${#_s}" -gt "$MK_READ_LIMIT" ]; then
    _mk_why "unreadable: the command could not be read: it is ${#_s} characters long once its heredoc bodies are taken out, past the $MK_READ_LIMIT this measure reads: too long to read, and what it cannot read is not let through, so it is work"
    printf 'work\n'; return 0
  fi

  # Quoting and the scan are ONE program, and they used to be two. They were joined on
  # 2026-09-08 because the quoting pass turned out to need a decision it could not make
  # alone: whether a quoted body is TEXT or the COMMAND of a shell. Deciding that is
  # feeds_cmd(), the rule the scan below reads its own -c with, and a second program would
  # have needed a second copy of it. Two copies of one rule drift apart, and this kit has
  # already paid for a measurement that was not run against the shipped function.
  case $_c in
    *curl*|*wget*|*tar*|*unzip*|*sort*|*zip*) _mk_o=$_MK_AWK_OPT ;;
    *) _mk_o=$_MK_AWK_NOOPT ;;
  esac
  case $_c in
    *clone*) _mk_g=$_MK_AWK_GITW ;;
    *) _mk_g=$_MK_AWK_NOGITW ;;
  esac
  _targets=$(printf '%s' "$_s" | LC_ALL=C awk -v explain="${MK_EXPLAIN:-0}" "$_mk_o$_mk_g"'
    # THE TRACE. See _mk_why above for why it lives in here. It goes to STDERR and never
    # to stdout, because stdout is the target list this whole program exists to produce,
    # and a trace line landing in it would be classified as a path. Every call sits next
    # to the branch that decided, and every target printed below is named by exactly one
    # of them, so a target the reader cannot account for is a defect in this file.
    function why(s) { if (explain == 1) print s > "/dev/stderr" }
    # The quote characters, and the two markers laid around a quoted operand below. The
    # markers are words of their own in the scan, and never a target.
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34)
            oq = sprintf("%c", 2);  cq = sprintf("%c", 3)
            # Four more marks of the same kind, each a byte no command is typed with. qd closes
            # the number of a blanked quoted body; gl says two pieces of one word were kept apart
            # by the markers; pm opens a target a program text writes, out of the pass above; uq
            # ends the body of a shell that was unwrapped; ss is a space inside one word.
            qd = sprintf("%c", 4);  gl = sprintf("%c", 5); pm = sprintf("%c", 6)
            uq = sprintf("%c", 7);  ss = sprintf("%c", 28); fs_sep = ss
            qre = "Q" qd "[0-9]+" qd; qnum = 0; cmdwin = 1024; cdx = 0; cdmade = 0; nmade = 0; mlq = ""; glue_ok = 1
            cdir = ""; cdsoft = 0; depth = 0; tnf = 0 }
    # THE WHOLE OPERAND THAT BEGINS AT WORD j, THE WAY THE SHELL READS IT, and the last word of it in
    # opend. A quoted segment is one word however many it was split into, pieces with nothing
    # between them are one word, an escaped space is a space, and a body that was blanked for a
    # metacharacter comes back. Until 2026-11-07 a target was the FIRST WORD of its quote: measured
    # at 7d695ce, echo x > "/x/mein projekt/.claude/a.txt" was refused for /x/mein, and for a
    # stranger with a space in the path, iCloud is one, that is every such redirection. And
    # echo x > "src/a&b.py" was blanked to nothing at all and passed in silence.
    function opnd(j,   s, m, w2, k) {
      s = ""; opend = j
      while (j <= NF) {
        if ($j == oq) {
          m = qend(j)
          for (k = j + 1; k < m; k++) s = s (k > j + 1 ? " " : "") $k
          opend = m
          if (m < NF && substr($(m + 1), 1, 1) == gl) { j = m + 1; w2 = substr($j, 2); opend = j }
          else break
        } else { w2 = $j; opend = j }
        if (substr(w2, length(w2)) == gl && opend < NF && $(opend + 1) == oq) {
          s = s substr(w2, 1, length(w2) - 1); j = opend + 1; continue
        }
        s = s w2
        break
      }
      gsub(gl, "", s); gsub(ss, " ", s)
      while (match(s, qre)) {
        k = substr(s, RSTART + 2, RLENGTH - 3)
        s = substr(s, 1, RSTART - 1) qtab[k] substr(s, RSTART + RLENGTH)
      }
      return s
    }
    # WHERE THE REDIRECTION BEHIND A CLOSED ARITHMETIC BEGINS, for a word that begins with ((, 0 when there is none.
    # The ) that closes it is found by counting parentheses, ((x>(a+1))) has a pair of its own. What is glued straight
    # behind it is the shell own when it is a > with a descriptor or an & in front, or none: ((x))>f, ((x))>>f, ((x))2>f,
    # ((x))&>f. Anything else behind it, && and the like, is not read here, and an unclosed one is left alone.
    function arith_tail(w,   n, d, i, ch) {
      n = length(w); d = 0
      for (i = 1; i <= n; i++) {
        ch = substr(w, i, 1)
        if (ch == "(") d++
        else if (ch == ")" && --d == 0) break
      }
      if (i >= n) return 0
      return (substr(w, i + 1) ~ /^([0-9]*|&)>/ ? i + 1 : 0)
    }
    # WHERE A REDIRECTION GLUED TO THE END OF A WORD BEGINS, 0 when the word has none. echo x>src/a.py is the
    # command echo x and the redirection >src/a.py, and until 2026-11-07 the scan took the whole of it for one
    # word, because a > inside a word is also what a comparison in program text looks like. What is left of a >
    # after the quoted text and the heredoc bodies are gone is the shell own, with these exceptions, each of them
    # a shape that is no redirection to the shell either or that this scan has always read as it stands:
    #   a word that begins with (( is arithmetic, ((a>b)), and $((1>2)) begins with a $. What stands behind the ) that
    #   closes it is read: ((a>b))>src/a.py writes [MK-R6: until then the whole word was left alone, a silent pass,
    #   measured 2026-11-08 at 2ac5cbb]. A word that begins with ONE ( is
    #   a subshell, and what follows it is read: (>src/a.py), (a>b) and (cat<in.txt>src/a.py) write [MK-R5: until then
    #   they read as bookkeeping, a silent pass, measured 2026-11-07 at a7dc5a9 and counted on the corpus];
    #   a descriptor alone in front, 2>file, is read as the word that begins with it, as before;
    #   an equals sign, a minus, a < or a | in front, =>, ->, <> and |>, and an equals sign behind, >=;
    #   a < in front that has no letter, digit or _ before it: <name>, <noreply@anthropic.com>, -<suffix>.md and
    #   /<id>/logs are a placeholder in text, the last 6 of the 446 commands this scan stopped that had passed.
    #   cat<in.txt>out, whose < stands behind a letter, is a redirection and is read;
    #   a > inside ${...}, which is part of the expansion.
    # The & in front of the > is the operator, x&>f, and goes with it. Inside [[ ]] and (( )) it is the caller.
    function glued_at(w,   p, pre, c, r) {
      p = index(w, ">")
      if (p < 2) return 0
      c = substr(w, 1, 1)
      if (c == "(" && substr(w, 2, 1) == "(" && (r = arith_tail(w))) return r
      # oq, cq and uq are not asked here: the scan lays each of them with a space on both sides, so they are words of
      # their own and a > never stands behind one (MK-R1b: 0 of the 63410 real commands with a > reached one).
      if ((c == "(" && substr(w, 2, 1) == "(") || c == pm) return 0
      pre = substr(w, 1, p - 1)
      if (pre ~ /^[0-9]+$/) return 0
      if (index(pre, "${") && !index(pre, "}")) return 0
      if (pre ~ /(^|[^A-Za-z0-9_])</) return 0
      c = substr(pre, length(pre))
      if (c == "\\") return 0
      if (c == "&") return (length(pre) > 1 ? p - 1 : 0)
      if (c == "=" || c == "-" || c == "<" || c == "|") return 0
      r = substr(w, p + 1, 1); if (r == ">") r = substr(w, p + 2, 1)
      if (r == "=") return 0
      return p
    }
    # Gives every such redirection a word of its own. The line is rebuilt only when one was found.
    function glue_split(stopq,   i, w, p, out, db, did) {
      out = ""; db = 0; did = 0
      for (i = 1; i <= NF; i++) {
        w = $i
        if (stopq != "" && index(w, stopq)) { for (; i <= NF; i++) out = out (i > 1 ? " " : "") $i; break }
        if (w == "[[" || w == "((" || (w == "(" && i > 1 && $(i - 1) == "(")) db = 1
        if (db && (w ~ /^\]\]/ || w ~ /^\)\)/)) db = 0
        p = (db ? 0 : glued_at(w))
        if (db && w ~ /\)\)$/) db = 0
        if (p) { w = substr(w, 1, p - 1) " " substr(w, p); did = 1 }
        out = out (i > 1 ? " " : "") w
      }
      if (did) $0 = out
    }
    # A word glued to the ) of a subshell this line opened: that parenthesis is not in the name.
    function unclose(t) {
      if (depth > 0 && t ~ /\)$/) sub(/\)$/, "", t)
      return t
    }
    # WHERE A RELATIVE TARGET LANDS, and it is the one place every target goes through. A target
    # with a head of its own is left alone. Behind a cd that a separator has passed, whether the
    # target moved depends on whether that cd worked, and only the disk can say: see the shell
    # loop below. tnf is a verb that takes the link itself, see _mk_nf. tns is a writer that came
    # with MK-A6: its target is measured, and it does not open the narrowing, because mkdir -p
    # <scratchpad> in front of a script that only reads the tree was silent and stays so.
    # Measured over the corpus: 79 distinct commands, 23 in a main session, stopped without this.
    function tgt(t,   out) {
      # A word the shell loop below drops as no path stays that word. Joined to the directory it
      # would have a slash, and x > 1 in a program text behind a cd would be a stop on src/1.
      if (cdir != "" && t !~ /^[\/~$]/ && t !~ /^[0-9.:,)]*[0-9][0-9.:,)]*$/ && t !~ /^[=,#]$/ && (t ~ /\// || t !~ /[)\];:,]$/)) {
        if (cdsoft) out = "@@c@@" cdir fs_sep t
        else out = cdir "/" t
      } else out = t
      print (tnf ? "@@n@@" : "") (tns ? "@@x@@" : "") out
    }
    # A PATH COLLAPSED THE WAY cd COLLAPSES IT: by the letters, because a shell cd is logical. It is
    # the kernel that reads a target, and classify_path walks that, so nothing else in this file
    # reads a ".." without a look at the disk.
    function cdpath(d,   n, a, i, out, head, k) {
      head = ""
      if (d ~ /^\//) head = "/"
      n = split(d, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == ".." && k > 0 && st[k] != "..") { k--; continue }
        if (a[i] == ".." && head == "/") continue
        st[++k] = a[i]
      }
      out = head
      for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") st[i]
      return out
    }
    # THE cd OF THIS COMMAND, and until 2026-11-07 there was none: cd <scratchpad> && cat > datei
    # was a stop on the word datei, which is the false alarm, and cd .claude && echo x > ../a.py is
    # the write it must still see. It only holds where it really moved the shell. A wrapper that
    # starts a program of its own, env or sudo or nohup, leaves the shell where it stood, and the
    # separators that break the chain are read at the scan.
    function cdread(ii, hw,   j, d, t) {
      if (hw != "" && hw != "command" && hw != "builtin" && hw != "eval" && hw != "time" && hw != "sh" && hw != "bash" && hw != "zsh") {
        why("the cd behind " hw " moves nothing in this shell")
        return
      }
      d = ""
      for (j = ii + 1; j <= NF; j++) {
        if ($j ~ /^[;&|]+$/ || $j == ")" || $j == uq) break
        if ($j ~ /[<>]/) { if ($j ~ /[<>]$/) j++; continue }
        if ($j == "--" || $j ~ /^-[LPe@]+$/) continue
        if ($j == "-") { d = "$OLDPWD"; break }
        if ($j == "(") { d = "$(...)"; break }
        d = unclose(opnd(j)); break
      }
      if (d == "") d = "$HOME"
      d = resolve(d)
      # A command with more of them than anybody types is not walked: this is awk, and the sum over
      # thousands of cd is what would outrun the hook budget.
      if (++cdn > 64 || length(cdir) + length(d) > 4096) { cdir = "$(a directory too long to read)"; cdsoft = 0 }
      else if (d ~ /^[\/~$]/) { cdir = cdpath(d); cdsoft = 0 }
      else cdir = cdpath(cdir == "" ? d : cdir "/" d)
      if (cdir == "") cdsoft = 0
      # A NEW cd IS NOT THE ONE AN EARLIER || exit GUARDED, and it is read afresh: a directory this command
      # made in front of it is one the cd gets into, so it holds behind a plain ; as it does behind &&.
      cdx = 0; cdmade = (cdir != "" && cdcovered(cdir))
      why("this command moves to " (cdir == "" ? "where it started" : cdir) (cdmade ? ", a directory it made itself" : ""))
    }
    # THE DIRECTORIES THIS COMMAND MADE, in the order it made them and as far as the cd after them can read:
    # mkdir -p a/b; cd a; cd b; echo x > f writes a/b/f, and it is read so, because the directory is there when
    # the cd runs. Not the one an mkdir BEHIND the cd makes, which is why cdmade is asked when the cd is read.
    # 64 of them at most, like the cd: past that the cd is soft, which is the loud half.
    function made_add(p) {
      if (nmade >= 64) return
      if (p !~ /^[\/~$]/ && cdir != "") p = cdir "/" p
      madelist[++nmade] = cdpath(p)
    }
    # Is d one of the directories that were made, or one that lies above one of them?
    function cdcovered(d,   k) {
      for (k = 1; k <= nmade; k++)
        if (madelist[k] == d || index(madelist[k], d "/") == 1) return 1
      return 0
    }
    # Is the word after a || a command that ends the shell? Then the cd in front of it either worked or nothing
    # behind it ran, and it holds as it does behind &&. Only exit and return: || true and || echo go on.
    function cdexit(j) { return (j <= NF && ($j == "exit" || $j == "return")) }
    # Which option of a program takes the next word as its value, so that word is no target.
    function takesval(t, c,   a, k, ch) {
      if (t !~ /^-[^-]/) return 0
      if (c == "touch") a = "Adrt"; else if (c == "mkdir" || c == "mkfifo") a = "m"
      else if (c == "truncate") a = "rs"; else if (c == "shred") a = "ns"
      else if (c == "patch") a = "bBdDFioprVxYz"
      else return 0
      for (k = 2; k <= length(t); k++) {
        ch = substr(t, k, 1)
        if (index(a, ch)) return (k == length(t))
      }
      return 0
    }
    # THE PROGRAMS THAT NAME WHAT THEY WRITE IN AN OPTION. The list and the options are derived:
    # out of the words in command position over 136164 real commands, against each man page, and
    # kept where the shape stands in a real command [MK-A6]. Reading the operands of these is
    # what would be wrong: curl -d src/a.py sends a file and writes none.
    function isoptwriter(t) { return (t == "curl" || t == "wget" || t == "tar" || t == "gtar" || t == "bsdtar" || t == "unzip" || t == "sort" || t == "zip") }
    # Where a quoted operand ends: at its closing marker. There is no nesting to worry
    # about, a quote cannot open inside a quote.
    function qend(j) { while (j <= NF && $j != cq) j++; return j }
    # Does this one command carry pat among its OWN arguments? The scan stops at a shell
    # separator, because a flag that belongs to the next command does not belong to this
    # one. pat arrives as a STRING: a regex constant passed to an awk function is matched
    # against $0 at the call site and arrives as 0 or 1.
    function owns(start, pat,   j) {
      for (j = start; j <= NF; j++) {
        if ($j ~ /[;|&]/) return 0
        if ($j ~ pat) return 1
      }
      return 0
    }
    # A word made of nothing but list punctuation ends the command before it.
    function sep(t) { return (t ~ /^[;&|()`{}!]+$/) }
    # The NAME of a program, without the directory somebody wrote in front of it. A
    # program is its name: /bin/bash is bash, and the shell itself reads it that way after
    # the PATH lookup. hands_on() compared whole words, so /bin/bash handed command
    # position to nobody and the write behind its -c was never read at all: measured
    # 2026-09-08 against the shipped function, /bin/bash -c "rm -rf src/x.py" was a SILENT
    # PASS, and so was /usr/bin/env rm -f src/x.py, which is the very wrapper hands_on()
    # was written for. It is the last SEGMENT that is read and never a suffix of the word,
    # which is what keeps ssh from being read as sh.
    #
    # The shape is rare where it was measured, 4 of 93614 distinct real commands and 9 of
    # 463039 weighted, and that is not why it is closed. It is closed because what it cost
    # was silence, and a guard that is quiet on /bin/bash is quiet on the one spelling
    # somebody reaches for when the plain name did not work.
    function shname(t) { sub(/^.*\//, "", t); return t }
    # A word after which a command begins again.
    function opens(t) {
      return (t == "if" || t == "then" || t == "elif" || t == "else" ||
              t == "while" || t == "until" || t == "do" ||
              t == "-exec" || t == "-execdir" || t == "-ok" || t == "-okdir")
    }
    # A command whose job is to run the command after it. It stands in command position
    # itself AND hands command position on, so a write verb behind it still counts.
    # git is in this list because it carries its write verbs as subcommands: measured
    # 2026-09-07, git rm -r --cached Kulik/nqleg went from a stop to silence without it,
    # having been caught before only by the accident that rm was read at any position.
    # The subcommands git does NOT hand on this way, apply and restore and checkout, are
    # read off the git word itself; git_sub() says which word that subcommand is.
    function hands_on(t) {
      return (t == "sudo" || t == "doas" || t == "env" || t == "xargs" || t == "eval" ||
              t == "nohup" || t == "time" || t == "timeout" || t == "nice" ||
              t == "ionice" || t == "stdbuf" || t == "setsid" ||
              t == "command" || t == "builtin" || t == "exec" ||
              t == "sh" || t == "bash" || t == "zsh" || t == "git")
    }
    # Does this option hand a SHELL its command text in the NEXT operand? Read off sh(1):
    # -c is the one option whose operand is a COMMAND rather than an argument, and the
    # one-letter switches cluster, so the same option arrives as -c and as -lc. 408 of the
    # 4280 weighted occurrences of this shape in the measured corpus are written -lc, so
    # anchoring at ^-c$ would have caught five sixths of it and called that done.
    #
    # It matters because of the wrapper skip below. That skip is there for sudo -u root rm,
    # where the operand of -u is a name to be stepped over. Applied to -c it steps over the
    # first word of the COMMAND instead, and the second word lands in command position.
    # Measured 2026-09-08 against the shipped function, bash -c "npm install typescript"
    # came back work: npm was eaten as the operand of -c and install was read as the verb.
    # That is the same defect as claude plugin install manager-kit, one layer in, and 226 of
    # 80359 distinct real commands carry the shape, 1444 weighted.
    #
    # Scoped to the three shells by name, the way feeds() is scoped to sed and perl, because
    # -c means something else to the other wrappers that hand command position on: git -c
    # takes name=value and sudo -c takes a login class, and both of those ARE opaque
    # operands that the skip must go on eating.
    #
    # The Gegenprobe is the point of the rule: the operand of -c stays command TEXT, so
    # bash -c "rm -rf src/x.py" is still a write.
    function feeds_cmd(t, c) {
      return ((c == "sh" || c == "bash" || c == "zsh") && t ~ /^-[A-Za-z]*c$/)
    }
    # Is the quoted body that begins right here the COMMAND TEXT of a shell, or an operand
    # to be read as text? Read off the words the quoting loop has already emitted: the last
    # of them is the option, and the word in front of it, past whatever flags the shell
    # took for itself, is the program. Both go into feeds_cmd(), so nothing about which
    # option feeds which program is written down twice, and a -c that belongs to something
    # other than a shell stays the opaque operand it is: python3 -c and psql -c keep their
    # bodies as text.
    #
    # It reads the WORDS rather than the state of the scan below, because the scan runs
    # after this and on the result of it. The cost of that is named: a shell word that is
    # nobody command, echo bash -c "a > b", is unwrapped here as well. What it can cost is
    # bounded by the scan, which reads a write verb in COMMAND POSITION only, so a verb in
    # such a body is still nobody command either; what is left is a redirection, which is
    # read wherever it stands. Measured 2026-09-08 by running the whole of this file
    # before and after over 93614 distinct real commands, 463039 weighted: 3 commands
    # changed verdict, all three of them silence to stop, and every one of them redirects
    # into a path that is not bookkeeping. Nothing went the other way.
    #
    # IT READS THE END OF WHAT CAME BEFORE AND NOT ALL OF IT. It is asked once per quote, and it used to split the
    # whole text in front of the quote: a command of 48 KB with 8000 quotes in it split 8000 times, and ran past 40 s
    # against a hook budget of 10 [MK-R1, a"b c" times 8000]. What it is asked is the last word, the word in front of
    # the options, and whether a carrier stands between that word and the last separator, so a window of cmdwin
    # characters answers it. A first word the window cut is not read, and when the walk back runs out of the window
    # the answer is the loud one, the body is read as command text: a body read that is no command costs a stop,
    # a body blanked that is a command costs a silent pass. The test of the option comes first and walks back from the
    # end over the blanks and the letters of the last word, nothing more, so a quote with no -c in front of it, which is
    # nearly every quote, pays no split at all, and a -c behind any number of blanks or letters is found as it was
    # [the first version looked at the last 64 characters, and bash -c with 70 blanks in front of the body read it as
    # text: a silent pass, found by hand 2026-11-07]. What it lets through is exactly what feeds_cmd() takes.
    function cmdtext(pre,   a, k, m, f, n, j) {
      n = length(pre)
      while (n > 0 && (substr(pre, n, 1) == " " || substr(pre, n, 1) == "\t")) n--
      if (n < 2 || substr(pre, n, 1) != "c") return 0
      j = n - 1
      while (j > 0 && substr(pre, j, 1) ~ /[A-Za-z]/) j--
      if (j < 1 || substr(pre, j, 1) != "-" || (j > 1 && substr(pre, j - 1, 1) !~ /[ \t]/)) return 0
      n = length(pre)
      f = 1
      if (n > cmdwin) { pre = substr(pre, n - cmdwin + 1); f = 2 }
      k = split(pre, a, /[ \t]+/)
      while (k >= f && a[k] == "") k--
      if (k < f + 1) return (f > 1)
      if (!feeds_cmd(a[k], "sh")) return 0
      m = k - 1
      while (m >= f && a[m] ~ /^-/) m--
      if (m < f) return (f > 1)
      if (!feeds_cmd(a[k], shname(a[m]))) return 0
      if (offsite(a, m, f)) {
        why("the command in front of this shell hands it to another machine or another container, so its body is not read as command text of this one")
        return 0
      }
      return 1
    }
    # A program that hands its command SOMEWHERE ELSE: to another machine, or into a
    # container. README.md names that as a hole this kit keeps on purpose, and the whole of
    # the decision is that it stays ONE hole. Closing it means classifying paths on a
    # machine this kit has never measured, and a rule guessed rather than measured is how
    # two false-alarm classes got built into this classifier before.
    #
    # It was one and a HALF hole between the -c repair of 2026-09-08 and this line. That
    # repair reads the body behind the -c of a shell as command text, correctly, and it did
    # so wherever the shell stood, the surrounding ssh or docker included. So a container
    # body carrying a metacharacter was read and one without was not: measured 2026-09-08
    # against the shipped function, docker exec api sh -c "rm -f src/x.py" came back
    # bookkeeping while docker run img sh -c "echo hi > /data/x.py" and docker exec api
    # sh -c "cd /srv && rm -rf src/x.py" came back work, on paths that do not exist on this
    # machine. Half a remote command read is the worst of both halves: it does not catch
    # what it would have to catch to be worth anything, and it stops on paths nobody here
    # knows.
    #
    # THE LIST IS MEASURED AND NOT GUESSED, because every name in it makes the guard
    # QUIETER, and quiet is the half this kit pays for. Counted 2026-09-08 over 81089
    # distinct real commands, 451159 weighted: ssh stands in 5123 distinct and 43280
    # weighted, docker in 2028 and 17213, docker-compose in 287 and 2449, podman in 1 and 1.
    # kubectl, nerdctl, lxc and their neighbours are NOT here: not one of them stands in
    # that corpus even once, so a command handed to them stays loud, which is the half of
    # being wrong this kit chooses.
    #
    # scp and rsync stand next to ssh in README.md and are deliberately not here either.
    # Neither carries a command, so neither can ever be the word in front of the -c this
    # test is asked about, and a name in this list with nothing it can match is a rule
    # nobody can measure.
    function elsewhere(t) {
      return (t == "ssh" || t == "docker" || t == "docker-compose" || t == "podman")
    }
    # Does the command this shell stands in hand its work somewhere ELSE? Walked BACK from
    # the shell word to the nearest list separator, because a carrier that has already
    # finished is not the wrapper of this one: in docker ps; sh -c "rm -rf src/x.py" the
    # shell belongs to this machine and its body is read. The words arrive unsplit here, so
    # a separator is looked for INSIDE a word the way owns() does it: the pass that gives
    # punctuation words of its own runs after this one.
    function offsite(a, m, f,   n) {
      for (n = m; n >= f; n--) {
        if (a[n] ~ /[;|&()]/) return 0
        if (elsewhere(shname(a[n]))) return 1
      }
      return 0
    }
    function isverb(t) {
      return (t == "rm" || t == "mv" || t == "cp" || t == "tee" || t == "truncate" ||
              t == "patch" || t == "dd" || t == "install" || t == "ln" || t == "shred" ||
              t == "chmod" || t == "chown" || t == "rmdir" || t == "touch" || t == "mkdir" ||
              t == "mkfifo" || t == "unlink" || t == "rsync" || t == "scp" || t == "ditto" ||
              t == "split")
    }
    # A chmod mode written with a LEADING MINUS, chmod -x tool.py, is a mode and not a
    # flag. Read as a flag it is skipped, the first bare operand is eaten as the mode in
    # its place, and the file goes silent, which is the worse of the two ways to be
    # wrong. chmod(1) has no option of that shape: its options are -f -h -H -L -P -R -v
    # -N -E -C -I, and not one of them spells out of [rwxXstugo].
    function ismode(t, c) { return (c == "chmod" && t ~ /^-[rwxXstugo]+$/) }
    # THE TARGET OPTION OF cp, mv, install AND ln, IN EVERY SPELLING getopt_long TAKES.
    # Answers 0 when the word is not that option, 1 when it is and its value is the NEXT
    # word, which the operand loop reads as a candidate anyway, and 2 when the value is
    # glued on, handed back in tdv. Until 2026-11-02 the target in front was known as two
    # exact words, -t and --target-directory, and every other spelling went SILENT: the
    # word starts with a minus, the operand loop stepped over it with its value, and
    # "cp -tsrc/ .claude/a.md" wrote the work tree as bookkeeping. The rules, and each one
    # is a spelling that was silent:
    #   a short option takes the REST of its word as its value, -tsrc/, and the next word
    #     only when that rest is empty;
    #   options without a value bundle in front of it, -vt src/ and -vtsrc/, and the FIRST
    #     letter of a bundle that takes a value ends it: in install -gstaff the t belongs
    #     to the group. So the letters that take a value are listed per program, out of
    #     the option tables of GNU coreutils: S for all four, and g m o for install;
    #   a long option takes its value after "=" or in the next word, and every prefix that
    #     names one long option alone is that option. target-directory is the only long
    #     option of the four that begins with t, so --t is already enough. A prefix that
    #     getopt would refuse as ambiguous is read as the option here, which is loud;
    #   "--" ends the options. That one is kept by the caller, which sees the words in
    #     order.
    # Options after the operands count too, because getopt_long permutes. The four are the
    # verbs of isverb() whose option table has a target directory; the -t of patch is
    # --batch and takes nothing, and the -t of chmod is a mode.
    function tdopt(t, c,   a, k, ch, nm) {
      if (c == "cp" || c == "mv" || c == "ln") a = "St"
      else if (c == "install") a = "Sgmot"
      else return 0
      if (t ~ /^--./) {
        nm = substr(t, 3); k = index(nm, "=")
        tdv = (k ? substr(nm, k + 1) : ""); if (k) nm = substr(nm, 1, k - 1)
        if (nm == "" || index("target-directory", nm) != 1) return 0
        return (tdv == "" ? 1 : 2)
      }
      if (t !~ /^-./) return 0
      for (k = 2; k <= length(t); k++) {
        ch = substr(t, k, 1)
        if (!index(a, ch)) continue
        if (ch != "t") return 0
        tdv = substr(t, k + 1)
        return (tdv == "" ? 1 : 2)
      }
      return 0
    }
    # WHICH word is the subcommand of this git. git takes its own options in front of it
    # and two of them carry their operand in the NEXT word, -C <path> and -c <name=value>,
    # so the operand has to be stepped over or it is read as the subcommand. Measured
    # 2026-09-07, git -C /pfad/zum/worktree checkout -B docs/x origin/main stopped on the
    # worktree path alone. 0 when this git names no subcommand at all.
    function git_sub(start,   j) {
      for (j = start; j <= NF; j++) {
        if ($j ~ /[;|&]/) return 0
        if ($j == "(" || $j == ")") return 0
        if ($j == "-C" || $j == "-c") { j++; continue }
        if ($j ~ /^-/) continue
        return j
      }
      return 0
    }
    # Does this git checkout name a BRANCH rather than files? -b and -B create one, -t
    # and --track follow one, --orphan and --detach move HEAD. Not one operand of those
    # is a path, so there is nothing on the line for the measure to read. A "--" ends the
    # search, because behind it every word is a path by definition.
    function co_branch(start,   j) {
      for (j = start; j <= NF; j++) {
        if ($j ~ /[;|&]/) return 0
        if ($j == "--") return 0
        if ($j == "-b" || $j == "-B" || $j == "-t" || $j == "--track" ||
            $j == "--orphan" || $j == "--detach" || $j == "-d") return 1
      }
      return 0
    }
    # Where the PATHSPEC of a git checkout begins: behind the "--" that separates it, or
    # at the first operand when the line carries none.
    function co_from(start,   j) {
      for (j = start; j <= NF; j++) {
        if ($j ~ /[;|&]/) break
        if ($j == "--") return j + 1
      }
      return start
    }
    # Is this operand of a bare git checkout a PATH or a REF? git decides by looking: a
    # name that resolves to a ref switches branch, a name that resolves to a file is
    # restored over. The measure cannot look, so it reads the shape, and the shape that
    # separates them is the file name at the end. Measured 2026-09-07 against 46715 real
    # commands: the refs there are main, HEAD, origin/main, feat/..., docs/..., every one
    # of them without a dot in its last segment, and the paths are .github/workflows/ci.yml
    # and PROJECT_STATUS.md and tools/eval/abgleich.py, every one of them with one.
    function pathish(t,   b) {
      if (t ~ /\/$/) return 1
      b = t; sub(/^.*\//, "", b)
      return (b ~ /\./)
    }
    # Is the interpreter c editing in place, somewhere among its own arguments? Read off
    # sed(1), "sed [-EHalnru] command [-I extension] [-i extension] [file ...]", and off
    # perl(1), whose one-letter switches cluster. So the same flag arrives as -i, -i.bak,
    # -pi and -0pi. Anchored at ^-i it caught only the first two: measured 2026-09-07,
    # perl -0pi -e ... src/anker.py was a SILENT PASS, 111 occurrences weighted in the
    # loaded case and every one of them writing under src/.
    function inplace(start, c) {
      if (c == "sed")  return owns(start, "^-[iI]")
      if (c == "perl") return owns(start, "^-[0-9lnpsaw]*i")
      if (c == "ruby") return owns(start, "^-[0-9lnpsaw]*i")
      return 0
    }
    # Does this word hand the interpreter c its PROGRAM in the NEXT word? sed -e command
    # and sed -f command_file; perl -e and -E, clustered as -pe, -ne, -0pe.
    function feeds(t, c) {
      if (c == "sed")  return (t == "-e" || t == "-f")
      if (c == "perl" || c == "ruby") return (t ~ /^-[0-9lnpsaw]*[eE]$/)
      return 0
    }
    # The same option carrying its operand glued on, as in sed -eEXPR or perl -peEXPR.
    function feeds_glued(t, c) {
      if (c == "sed")  return (t ~ /^-[ef]./)
      if (c == "perl" || c == "ruby") return (t ~ /^-[0-9lnpsaw]*[eE]./)
      return 0
    }
    # The PATH OPERANDS of find, RETURNED as one space separated string rather than
    # printed, because two rules read them now and only one of them reads them where it
    # finds them: -delete prints them on the spot, and a -exec that turns out to name no
    # path of its own prints them at the end of its own operand scan, by which time the
    # path operands are long behind the scan. find(1) draws the line itself:
    # "find [-H|-L|-P] [-EXdsx] [-f path] path ... [expression]". The paths come first,
    # the expression starts at the first primary, and a path operand starts with a
    # path-shaped character rather than with -, ( , ! or a comma.
    #
    # No path operand at all: find(1) walks the working directory. Without that the shape
    # "find -name x -delete" would be a write with nothing to read, which is the silent
    # pass this rule exists to close.
    function findpaths(start,   j, n, out) {
      n = 0; out = ""
      for (j = start; j <= NF; j++) {
        if ($j ~ /[;|&]/) break
        if ($j ~ /^-[HLPEXdsx]+$/) continue
        if ($j == "-f") { if (j < NF) { out = out " " resolve($(j + 1)); n++; j++ } ; continue }
        if ($j == oq) { fq = resolve(opnd(j)); j = opend; gsub(/ /, ss, fq); out = out " " fq; n++; continue }
        if ($j !~ /^[A-Za-z0-9_.~$\/\200-\377]/) break
        out = out " " resolve($j); n++
      }
      if (n == 0) return "."
      return substr(out, 2)
    }
    # THE SEARCH PATH OF A FIND, READ AS THE TARGET of whatever that find does to what it
    # matched. The set is never on the line: -delete removes what the primaries matched,
    # and -exec rm {} + removes the same set through a placeholder. What IS on the line is
    # the search path, the upper bound of that set and the only real path the command
    # carries. Reading the -name pattern instead would mean trusting a filter the
    # coordinator wrote, and it would leave "find . -delete", which carries no pattern at
    # all, with nothing to read.
    function findtarget(paths, trig,   fa, fk, fi) {
      if (paths == "") return 0
      fk = split(paths, fa, / /)
      for (fi = 1; fi <= fk; fi++) {
        gsub(ss, " ", fa[fi])
        why(trig " names its search path " fa[fi])
        tgt(fa[fi])
      }
      return fk
    }
    # Is the newline at the END of this line masked by a backslash? In the shell a
    # newline separates two commands only when it is not, and a backslash masks the
    # newline only when it is not itself masked. So a DOUBLED backslash at the end of a
    # line is one escaped backslash and the line ends there. Parity is what decides,
    # never presence: a test for "ends in a backslash" gets the doubled case wrong, and
    # it gets it wrong in the silent direction.
    function masked(t,   n) {
      n = 0
      while (substr(t, length(t), 1) == "\\") { n++; t = substr(t, 1, length(t) - 1) }
      return (n % 2)
    }
    # WHAT THIS COMMAND ASSIGNED TO WHICH NAME, and it is the fifth hole of README.md
    # closing. A path that only exists in a shell variable was read as the literal word
    # "$L", which lies under no .claude directory and does not end in .md, so it was
    # stopped. That is the ONE stop this guard has really produced in a live project: on
    # 2026-09-07T23:46:12Z it refused a coordinating session its own
    # .claude/session-ledger.<id>.md, bookkeeping under both halves of the measure at
    # once, and the very file the kit tells that session to keep.
    #
    # asgn is keyed by name and holds the value ALREADY RESOLVED against the assignments
    # in front of it, so A=.claude; B="$A/probe" leaves B holding .claude/probe and
    # nothing is resolved twice. Chains go as deep as they are written, and there is no
    # recursion to run away with: each value is resolved once, at the moment it is
    # recorded, out of names that were recorded before it.
    #
    # It is filled and read in TEXTUAL order, which is what a straight run of commands
    # does. What that misses is named rather than hidden: a value assigned in one branch
    # of an if and read outside it is resolved against the last assignment ON THE PAGE,
    # not against the one the shell would have taken.
    #
    # THREE VALUES ARE REFUSED, and every refusal leaves the target LOUD, which is the
    # direction this rule must fail in:
    #   an EMPTY value, which is what is left of D=$(mktemp -d) after "$(" has been split
    #     into a word of its own: the value is not on the line, so it is not resolvable.
    # Two more were refused until 2026-11-07 and are read now: a quoted value with a space or a
    # metacharacter in it, and one glued to a word. opnd() reads them whole, which is what the
    # refusal was protecting: D="/x/mein projekt/.claude" is a value, and L=notes.md" and more.txt"
    # no longer ends in .md, because the whole of it is read and not the first half.
    function record(ii,   t, name, val) {
      t = opnd(ii)
      name = t; sub(/=.*$/, "", name)
      val  = t; sub(/^[^=]*=/, "", val)
      if (val == "") {
        why("the assignment to " name " does not put a readable value on the line, so $" name " stays unresolved")
        return
      }
      asgn[name] = resolve(val)
      why("this command assigns " name "=" asgn[name] ", so $" name " is read as that path")
    }
    # A TARGET READ THROUGH THE VARIABLE IT ARRIVED IN. $VAR and ${VAR}, and "$VAR" as
    # well, because the quoting pass has already taken the quotes off; standing alone, or
    # as the HEAD of a longer path, which is the shape "$W/tools/x.py" arrives in.
    #
    # A variable this command does not assign comes out of the ENVIRONMENT and is not
    # resolvable, so it is left standing and its target stays work. That is the whole
    # weight of this rule and not a corner of it: of 727 hand-resolved stops of this
    # shape in a foreign corpus, 636 resolve to a WORK path and 28 to bookkeeping. A
    # resolution that read a variable as bookkeeping BECAUSE it is a variable would be a
    # silent pass 636 times over, which is worse than the stop it replaces.
    #
    # Only the HEAD is replaced, and WHATEVER STANDS BEHIND IT IS CARRIED ALONG. Until
    # 2026-11-02 a literal behind the name refused the substitution outright, so "$F.log"
    # was read as the WORD "$F.log": under no .claude directory, no .md ending, work,
    # stopped. 5 of the 122 stops of the measured week are that one shape and all 5 are
    # false alarms [MK-PREIS.md, class 3, stops 70 to 74]. The substituted value stands on
    # the line, so this makes the measure MORE exact and not softer: P=plans/x.md with
    # $P.vor_sync_20260923 behind it resolves and stays LOUD, because the dated backup does
    # not end in .md any more. dir/$V is still left as it stands: the name is not at the
    # head there, and the directory in front of it is one this command never assigned.
    # The price is in tests/run.sh under "a variable with a literal behind it".
    function resolve(t,   name, rest) {
      rest = t
      if (substr(t, 1, 2) == "${") {
        if (!sub(/^\$\{[A-Za-z_][A-Za-z0-9_]*\}/, "", rest)) return t
        name = substr(t, 3, length(t) - length(rest) - 3)
      } else if (substr(t, 1, 1) == "$") {
        if (!sub(/^\$[A-Za-z_][A-Za-z0-9_]*/, "", rest)) return t
        name = substr(t, 2, length(t) - length(rest) - 1)
      } else return t
      if (!(name in asgn)) {
        why("this command assigns nothing to " name ", so " t " is read as it stands")
        return t
      }
      why("the assignment " name "=" asgn[name] " in this command resolves " t " to " asgn[name] rest)
      return asgn[name] rest
    }
    {
      # QUOTED SEGMENTS, and they are resolved before a single word is read, because a
      # quote is what decides where the words are. The CONTENT is kept and only a segment
      # carrying a shell metacharacter is blanked out. The wholesale replacement this used
      # to do had the right reason and the wrong reach. It kept grep -rn "a > b" src/ from
      # reading as a redirection into a file named b, and it also made EVERY quoted path
      # invisible. Measured 2026-09-07: rm -rf "src/x.py" came back bookkeeping, and
      # quoting a path is the ordinary way to write one, so that was the guard failing at
      # the one thing it is for.
      #
      # The body behind the -c of a SHELL is the exception, and closing it is why this
      # loop moved in here. That body is not text, it is a command, and blanking it took
      # the guard blind at the centre of what it promises: measured 2026-09-08 against the
      # shipped function, sh -c "cd /tmp && rm -rf src/x.py" and bash -c "echo hi >
      # src/x.py" both came back bookkeeping. 728 of 93614 distinct real commands carry a
      # shell body with a metacharacter in it, 2993 of 463039 weighted.
      #
      # Such a body is UNWRAPPED and pushed back in front of the text still to be read, so
      # the same loop reads it again and the same scan below reads the words out of it.
      # There is no second reading of the rules anywhere, and a body carrying a -c of its
      # own is simply unwrapped once more: bash -c "sh -c ..." goes as deep as it is
      # written. What ends it is not a depth counter but the buffer. Every unwrap drops
      # the two quote characters off a line of finite length, so what is left to read is
      # strictly shorter each time, and the loop cannot go round for ever.
      qs = $0; qout = ""; qi = 1; qn = length(qs); qopen = ""; qorig = $0
      while (qi <= qn) {
        qc = substr(qs, qi, 1)
        # An escaped space outside a quote does not end the word.
        if (qc == "\\" && substr(qs, qi + 1, 1) == " ") { qout = qout ss; qi += 2; continue }
        if (qc == sq || qc == dq) {
          qj = qi + 1; qbody = ""
          while (qj <= qn && substr(qs, qj, 1) != qc) { qbody = qbody substr(qs, qj, 1); qj++ }
          # A quote that never closes: the rest of the line is taken as it stands.
          if (qj > qn) { qout = qout substr(qs, qi); qopen = qc; break }
          if (cmdtext(qout)) {
            why("the quoted body " qc qbody qc " is the command text of a shell, so it is unwrapped and read")
            qout = qout " "
            # uq closes the body: a cd in a shell of its own is over when that shell is.
            qs = qbody " " uq " " substr(qs, qj + 1); qn = length(qs); qi = 1
            continue
          }
          # A quoted string is ONE operand of its command, however many words awk goes on
          # to split it into, and the scan below has to be able to skip it whole. So two
          # markers of its own are laid around it, saying where it begins and where it
          # ends. The rule that skips the EXPRESSION of an in-place sed skipped exactly
          # one word, and an expression carries a space as often as not: measured
          # 2026-09-07 against 46715 real commands, "s/alt und mehr/neu/" (de-input) was read as the
          # expression s/alt plus two files called und and mehr/neu/ (de-input). A body without a
          # space is already one word and gets no markers. They go on BEFORE the test
          # below, so a body carrying a metacharacter is still blanked whole and takes
          # them with it.
          # qraw is the body WITHOUT the markers, and it exists for the trace alone: the
          # markers are two control characters and a reader cannot see them.
          qraw = qbody
          # gl says the words the markers keep apart are still one word in the shell.
          qnx = substr(qs, qj + 1, 1)
          if (qbody ~ /[ \t]/) qbody = (qout != "" && qout !~ /[ \t]$/ ? gl : "") " " oq " " qbody " " cq " " (qnx != "" && qnx !~ /[ \t;|&()<>]/ ? gl : "")
          if (qbody ~ /[<>|;&]/) { why("the quoted segment " qc qraw qc " carries a shell metacharacter, so it is blanked: it is text, not syntax")
                                   # The mark carries a number, so a reader that needs the text back as
                                   # a target has it, and every other word goes on seeing no syntax.
                                   qtab[++qnum] = qraw
                                   qout = qout "Q" qd qnum qd } else qout = qout qbody
          qi = qj + 1
        } else { qout = qout qc; qi++ }
      }
      $0 = qout
      # WHETHER A > IN THIS LINE CAN BE A REDIRECTION AT ALL. The loop above reads one line at a time, and a quoted
      # string that runs over several lines, a commit message with its trailer or a program text in -c "...", is
      # not one the loop can pair: its lines are read as if they were commands. Until 2026-11-07 that did no harm
      # to a > glued to a word, which was never read. Read, it stopped 446 of the 133542 distinct commands of a
      # corpus that had passed, 237 of them for the Co-Authored-By trailer: <noreply@anthropic.com>" is a > glued
      # to a quote. So the state is kept from line to line, and a > is read only on a line that begins outside
      # a quote and carries no escaped quote, which the pairing above does not know. On the line that opens a
      # quote it is read up to the word that holds the quote. mlq is the character of the quote that is open.
      # Doubt is not a stop here: a line like that passes as it always passed, and README.md says so.
      glue_ok = 1
      if (index(qorig, "\\" dq) || index(qorig, "\\" sq)) glue_ok = 0
      if (mlq != "") {
        glue_ok = 0
        qtmp = qorig; qk = gsub(mlq, "", qtmp)
        if (qk % 2 == 1) mlq = ""
        why("this line is inside a quoted string that began on an earlier line, so a > in it is text, not a redirection")
      } else if (qopen != "") mlq = qopen

      # Command position is reset at the start of a line only when the newline BEFORE it
      # was a real separator. A line continued with a backslash is the same command, so a
      # write verb at the head of a continued ARGUMENT line is an argument and not a
      # command. Run against the shipped function on 2026-09-07, grep -rn \ /
      # "rm -rf src/x.py" / docs/ was read as three commands and stopped, and so were the
      # same shape behind echo and behind git commit -m. 730 of the 37753 real commands
      # from a production corpus carry a masked newline, 3265 weighted.
      #
      # The Gegenprobe is the point of the rule and tests/run.sh holds it: an unmasked
      # newline still separates, so echo hello / rm -rf src/x.py is still a write, and so
      # is a continuation followed by a real separator.
      if (!cont) { expect = 1; skip = 0; hw = ""; xf = 0; fpaths = ""; if (cdir != "" && !cdx) cdsoft = (cdmade ? 0 : 1); cdx = 0 }
      cont = masked($0)
      if (cont) why("this line ends in a masked newline, so the line after it continues the same command instead of starting a new one")
      if (rs_pend && !cont) {
        rs_pend = 0; rt = ""
        for (k = 1; k <= NF; k++) {
          if ($k ~ /^[;&|]+$/ || $k == ")") break
          if ($k ~ /[<>]/) { if ($k ~ /[<>]$/) k++; continue }
          if ($k == oq) { rt = opnd(k); k = opend; continue }
          if ($k != cq && $k !~ /^-/) rt = opnd(k)
        }
        if (rt != "" && rt !~ /^[^\/]*:/) { why("the last line of this continued command names what it writes, " rt); tgt(resolve(unclose(rt))) }
      }
      # Punctuation glued to its neighbours hid real writes. Measured 2026-09-07 against
      # the shipped function, "rm src/x.py; ls" and "echo $(rm src/x.py)" both came back
      # bookkeeping: the target carried the semicolon into the separator test, and the
      # verb carried the "$(" so it never equalled "rm". Giving the punctuation words of
      # its own is also what makes command position readable at all.
      #
      # ONLY these two, and the narrowness is measured rather than chosen. | & ` { } and
      # the bare parenthesis were each in this list for one run over the 30877 commands
      # and taken back out, because splitting them invents commands and redirections out
      # of ordinary program text: ${ln} became the ln command, a perl class [\s|>] became
      # a redirection into a file named ]$/, a backtick around a word in prose put that
      # word in command position, and a Python comparison len(x)>110 became a redirection
      # into a file named 110. They buy nothing either: && || | are written with spaces
      # around them and are already words of their own.
      gsub(/;/, " ; ")
      gsub(/\$\(/, " ( ")
      if (glue_ok && index($0, ">")) glue_split(qopen)
      for (i = 1; i <= NF; i++) {
        w = $i
        # WHAT ENDS THE cd OF THIS COMMAND. A word that closed a parenthesis or a backtick closed
        # the shell the cd may have stood in. The separators are read below, with the others.
        if (i > 1 && $(i - 1) ~ /[)`]$/) { cdir = ""; cdsoft = 0 }
        # The backslash that MASKS the newline is syntax, not a word. Left standing as
        # one it takes command position whenever the line before it ended in && or | or
        # ;, and then the command on the continued line is never read at all. Measured
        # 2026-09-07 against the loaded case, V=out && mkdir -p $V && \ / cp a.png
        # $V/b.png went SILENT that way, four occurrences weighted and every one of them
        # a real write.
        #
        # It is deliberately NOT skipped in the argument scan further down, where it is
        # read as a candidate target and comes back work. That is what keeps a write
        # whose operands all sit on the continued line loud rather than silent, and loud
        # is the better of the two ways to be wrong. The cost is named, and it is not new:
        # a cp of one bookkeeping path to another, split over a continued line, is a false
        # alarm here and was one before this repair as well.
        if (cont && i == NF && w == "\\") continue
        # The markers around a quoted operand are syntax, not words. They are stepped
        # over WITHOUT touching command position, which is what keeps the operand of
        # sh -c command text: bash -c "rm -rf src/x.py" is still a write.
        if (w == oq || w == cq) continue
        if (w == uq) { cdir = ""; cdsoft = 0; continue }
        # WHAT A PROGRAM TEXT ON THIS LINE WRITES, out of the pass above, in the place of the
        # interpreter, so a cd in front of it counts and one behind it does not.
        if (substr(w, 1, 1) == pm) { rt = substr(w, 2); gsub(ss, " ", rt); why("the program text of the interpreter behind this word writes " rt)
                                     # A heredoc with no quote on its word and a -c in double quotes let the shell
                                     # fill the text in first, so a variable this command assigns is read,
                                     # and S=<scratchpad>; python3 - <<PY writing $S/x is bookkeeping. One it
                                     # does not assign is the limit README.md names, like a name in the program.
                                     if (rt == "@@p@@") { print rt; continue }
                                     rt = resolve(rt)
                                     if (rt ~ /[$]/) { why("the program text writes " rt ", which is no literal, and that is the limit README.md names"); continue }
                                     tns = 1; tgt(rt); tns = 0
                                     continue }
        # redirection: > file, >> file, >file, >>file, and the descriptor in front of it, 2> file and
        # &> file, and the >| that overrides noclobber. A redirection is a write wherever it stands,
        # argument position included, so it is read before anything else. 2> src/a.py and
        # &> src/a.py passed in silence until 2026-11-07. A duplication names a descriptor and no
        # file: >&2 was a stop on the word "&2".
        if (w ~ /^([0-9]+|&)?>>?[|&]?/ && w !~ /^[0-9]+>=/) {
          match(w, /^([0-9]+|&)?>>?[|&]?/); ro = substr(w, 1, RLENGTH); v = substr(w, RLENGTH + 1)
          if (ro ~ /&$/ && (v ~ /^[0-9-]+([^A-Za-z0-9_.\/].*)?$/ || (v == "" && i < NF && $(i + 1) ~ /^[0-9-]+$/))) continue
          if (v == "") {
            if (i >= NF) continue
            if ($(i + 1) == "(") rt = "$(...)"
            else { rt = unclose(resolve(opnd(i + 1))); if (depth > 0 && $opend ~ /\)$/) depth--; i = opend }
          } else {
            # Glued to the operator, and a pipe glued behind it ends the word: >f|tail names f.
            rt = opnd(i)
            sub(/^([0-9]+|&)?>>?[|&]?/, "", rt)
            if (v !~ qre && v ~ /[|&]/) sub(/[|&].*$/, "", rt)
            rt = unclose(resolve(rt))
            if (depth > 0 && $opend ~ /\)$/) depth--
            i = opend
          }
          why("the redirection \"" ro "\" names " rt)
          tgt(rt)
          continue
        }
        # xf is WHETHER THE COMMAND NOW OPENING IS THE -exec OF A FIND, and it is the
        # only reason sep() and opens() are read apart here. A separator ends the find
        # outright; an if or a do opens a command that is the -exec of nobody; the four
        # primaries below open one. Nothing else about either branch moves.
        # A cd holds across && and into a subshell or a group it opens. Behind a plain ; it holds
        # if it worked, which tgt() leaves to the disk. Behind anything else it does not: a pipe
        # and a & run it in a shell of their own, and || runs what follows only if it failed.
        if (sep(w)) { if (w == "(") depth++; else if (w == ")") { if (depth > 0) depth-- }
                      if (w == ";") { if (cdir != "" && !cdx) cdsoft = (cdmade ? 0 : 1); cdx = 0 }
                      else if (w == "||" && cdir != "" && cdexit(i + 1)) cdx = 1
                      else if (w != "&&" && w != "(" && w != "{" && w != "!") { cdir = ""; cdsoft = 0; cdx = 0 }
                      expect = 1; skip = 0; hw = ""; xf = 0; continue }
        if (opens(w)) { cdir = ""; cdsoft = 0
                        expect = 1; skip = 0; hw = ""
                        xf = (w == "-exec" || w == "-execdir" || w == "-ok" || w == "-okdir")
                        continue }
        # Is this word the COMMAND of its own command, or somebody elses argument? Read
        # at any word position, a write verb turned every following word into a candidate
        # target, which is why "claude plugin install manager-kit" read as work. The risk
        # in narrowing it is blindness, and command position is NOT the first word of the
        # line: &&, |, ;, a subshell, sudo, env VAR=x, a bare VAR=x, nohup, time, xargs,
        # then, do, find -exec and sh -c all put the next word back into it.
        cmd = 0
        if (expect) {
          # A wrapper option and its operand sit in front of the command: sudo -u root rm.
          # An operand that is itself a write verb is NOT skipped, because that is exactly
          # the shape "sh -c rm" has.
          if (skip && !isverb(w)) { skip = 0; continue }
          skip = 0
          # A bare VAR=x in front of a command is an ASSIGNMENT, and it used to be
          # stepped over and forgotten. See record(). The whole of the value is stepped over with
          # it: D="rm x" names no command.
          if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { record(i); i = opend; continue }
          if (w ~ /^-/) { if (!feeds_cmd(w, hw)) skip = 1; continue }
          if (w ~ /^[0-9]+$/) continue
          # A PARENTHESIS GLUED TO THE COMMAND. (rm a.py) and (cd src && echo x > a.py) passed in
          # silence, because the command word read "(rm". Only here, in command position: program
          # text has parentheses everywhere, a command word does not. ((i++)) is no subshell.
          while (substr(w, 1, 1) == "(" && length(w) > 1 && substr(w, 2, 1) != "(") { w = substr(w, 2); depth++ }
          if (w == "fi" || w == "done" || w == "esac") { cdir = ""; cdsoft = 0 }
          cmd = 1
          if (w == "cd" || w == "pushd") cdread(i, hw)
          if (w == "popd") { cdir = ""; cdsoft = 0 }
          # The other spellings of an assignment. export A=.claude; echo x > $A/a.txt read $A as
          # unknown, and API_KEY in MK-A5 line 81 stays as loud as its value.
          if (w == "export" || w == "declare" || w == "typeset" || w == "readonly" || w == "local") {
            for (z = i + 1; z <= NF; z++) {
              if ($z ~ /^[;&|()]+$/) break
              if ($z ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { record(z); z = opend }
            }
          }
          # hw is WHICH wrapper is in force, and it is what feeds_cmd() reads above. A -c
          # is only command text when the word handing command position on was a shell.
          # The NAME is what is asked, never the whole word: see shname().
          if (hands_on(shname(w))) hw = shname(w); else { expect = 0; hw = "" }
        }
        # find -delete is a write and it was SILENT, which is the worse of the two ways
        # to be wrong. -exec rm and -execdir rm were caught already, by opens() putting
        # rm back into command position; -delete has no rm on the line to find.
        #
        # What is the target here. The deletion SET is not on the line: -delete removes
        # whatever the primaries matched. What IS on the line is the search path, and the
        # search path is the upper bound of that set, so it is the widest thing the
        # command can reach and the only operand on the line that is a real path.
        # Reading the -name pattern instead would mean trusting a filter the coordinator
        # wrote itself, and it would leave "find . -delete", which carries no pattern at
        # all, with nothing to read.
        # WHERE THIS find CAN REACH, remembered as the word is read. The write it
        # performs may stand behind a -exec further along the same line, and by the time
        # that write is scanned its own operand list is all this scan can still see.
        if (cmd && w == "find") fpaths = findpaths(i + 1)
        if (cmd && w == "find" && owns(i + 1, "^-delete$")) { findtarget(fpaths, "the -delete of a find"); continue }

        # The EXPRESSION of an in-place sed or perl is program text, not a path. The scan
        # knew only "flag" and "path", so s/a/b/ was read as the target, did not end in
        # .md, and every in-place edit of a Markdown file came back as a stop. Measured
        # 2026-09-07 against the 30877 real commands, that was a class of false alarms
        # introduced by the quoting repair before it: while quoted segments were replaced
        # wholesale the expression was invisible, and keeping their content made it
        # visible as the wrong kind of thing.
        #
        # Which argument is the expression follows sed(1) and perl(1): the first bare
        # operand is the program UNLESS -e or -f already supplied one. The backup suffix
        # never competes for that slot, because it is either glued to the flag, -i.bak,
        # or written as the empty word "" which the quoting pass above removes entirely.
        # The Gegenprobe is the point of the rule: the file BEHIND the expression is
        # still a target, so an in-place sed over src/x.py stays work.
        prog = ""
        if (cmd && (w == "sed" || w == "perl" || w == "ruby") && inplace(i + 1, w)) prog = w

        # WHICH arguments of a git name the files it writes, and from where on. The test
        # this replaces asked whether apply, restore or checkout stood ANYWHERE among the
        # arguments of a git and then read every word behind the git word as a candidate
        # target, the subcommand itself included. So the word "checkout" was a target,
        # and so was every branch name behind it. Measured 2026-09-07 against 46715 real
        # commands of a foreign project: 613 stops of 3715, 16.5 percent of everything
        # the measure stopped and the largest single class of false alarms it had. Of the
        # 613, only the 54 in the pathspec form wrote a file at all.
        gfrom = 0; gref = 0
        if (cmd && w == "git") {
          gs = git_sub(i + 1)
          if (gs && ($gs == "apply" || $gs == "restore")) gfrom = gs + 1
          else if (gs && $gs == "checkout" && !co_branch(gs + 1)) {
            gfrom = co_from(gs + 1)
            # No "--" on the line: git decides between a branch and a file by looking and
            # the measure cannot, so the operands are read by shape. See pathish().
            gref = (gfrom == gs + 1)
          }
          else if (gs && $gs == "checkout")
            why("the git subcommand \"checkout\" creates or follows a branch here, so not one of its operands is a path")
        }
        if (cmd && w == "git" && gs && $gs == "clone") { tns = 1; clone_read(gs + 1); tns = 0; continue }
        if (cmd && isoptwriter(w)) { tns = 1; optwrite(i + 1, w); tns = 0; continue }
        # write verbs: every remaining argument is a candidate target
        if (cmd && (isverb(w) || prog != "" || gfrom)) {
          # WHICH of the three opened this block, said once and read off the same three
          # tests the line above makes. gfrom is asked first because a git carries its
          # write in a subcommand and the word in command position is only "git".
          if (gfrom)          trig = "the git subcommand \"" $gs "\""
          else if (prog != "") trig = "the in-place edit of \"" w "\""
          else                 trig = "the write verb \"" w "\" in command position"
          # The MODE of a chmod and the OWNER of a chown stand where a path would, and
          # they are owed in exactly the way the expression of an in-place sed is. 35 of
          # the 3715 stops were a chmod stopped on its own mode word, +x in 92 of the 215
          # chmod calls in the measured corpus.
          owed = (prog != "" || w == "chmod" || w == "chown"); pending = 0; np = 0
          # DOES A FLAG PUT THE TARGET IN FRONT. Asked before the operands are
          # collected, because the arm below has to know it for the whole list and the
          # list is built one word at a time. Both spellings, and --target-directory
          # matches with its = value glued on.
          zielvorn = 0; tdend = 0
          # rm, rmdir and unlink take the link itself, and so does mv of what it moves. See _mk_nf.
          # Not ln and not the target of a mv: both go into a directory a link points at.
          tnf = (w == "rm" || w == "rmdir" || w == "unlink" || w == "mv")
          # mkdir names a directory, so what it names is read as one: mkdir -p .claude is bookkeeping,
          # and the measure holds a path UNDER .claude, not the bare word.
          tdir = (w == "mkdir")
          tns = (w == "mkdir" || w == "touch" || w == "mkfifo" || w == "unlink" || w == "rsync" || w == "scp" || w == "ditto" || w == "split")
          # IN THIS COMMAND ONLY: the loop stopped at the end of the line and not at the end of the command, so a line
          # of 7000 `rm a.md;` read the rest of the line 7000 times [MK-R1: 14.6 s]. A -t behind a separator is the
          # option of another command, and read as part of this one it turned the first operand into a directory.
          for (z = i + 1; z <= NF; z++) {
            if ($z ~ /[;|&]/ || $z == "(" || $z == ")") break
            if ($z == "-t" || $z ~ /^--target-directory/) { zielvorn = 1; break }
          }
          for (j = (gfrom ? gfrom : i + 1); j <= NF; j++) {
            if ($j ~ /[;|&]/) break
            # A command substitution ends the argument list of this command. The word is
            # punctuation this pass put there, never a path: read as one, it turned
            # cp .claude/x.md .claude/y-$(date +%F).md into a stop.
            if ($j == "(" || $j == ")") break
            # An owed operand that arrived quoted is skipped WHOLE, marker to marker.
            # That is the one thing the single-word skip further down cannot do.
            if ($j == oq && (owed || pending)) { j = qend(j); owed = 0; pending = 0; continue }
            # Anywhere else the markers are simply not there, and the words between them
            # are read one by one as before: rm -f "a b" still names two candidates.
            if ($j == cq || $j == uq || substr($j, 1, 1) == pm) continue
            # THE PLACEHOLDER OF A find -exec IS SYNTAX, NOT A PATH. {} is where find
            # substitutes what it matched, + and \; are what end the -exec, and not one of
            # the three is a name on disk. Read as paths they made every cleanup a stop on
            # a word that is not a file: measured 2026-09-08 against the shipped function,
            # find apps/api/src -name __pycache__ -type d -exec rm -rf {} + came back work
            # naming "{}" and "+", 27 distinct stops of 8234 and 189 of 43160 weighted. The
            # backslash arrives as a word of its own because the pass above gives the ";"
            # one, so \; is read down here as two words and both are stepped over.
            #
            # Scoped to the -exec the way the mode of a chmod is scoped to chmod, and for
            # the same reason: a file that really is called {} is a path, and rm -rf "{}"
            # standing on its own is still a write.
            if (xf && ($j == "{}" || $j == "+" || $j == "\\")) continue
            # A REDIRECTION IS NOT AN OPERAND OF THE COMMAND IT STANDS BEHIND. "2>/dev/null"
            # arrives here as one word, because the pass above gives a word of its own to
            # ";" and to "$(" and to nothing else, and a bare ">" arrives as one too. While
            # every operand was a candidate that cost ONE FALSE ALARM on a word that is not
            # a path. It costs SILENCE the moment the LAST operand decides, which is what
            # the block below the loop makes it do: cp /tmp/x src/y.py 2>/dev/null would
            # name 2>/dev/null as its target and a real write of src/y.py would go quiet.
            #
            # The redirection ITSELF is not lost with it. The outer scan visits every word
            # of the line again and reads ">" and ">file" wherever they stand; what is
            # dropped here is only the reading of a redirection as an OPERAND. Measured
            # 2026-09-08 over 46587 distinct payloads of a frozen foreign corpus, all 66
            # operands of this shape among the 4249 targets its 3001 stops name are
            # /dev/null, so no real path is dropped with them.
            #
            # A REDIRECTION WRITTEN APART IS TWO WORDS, and the second of them belongs to
            # the redirection and not to this command. Dropping the first and keeping the
            # second makes that file the LAST operand, and then "cp .claude/a.md src/y.py
            # > /dev/null" goes SILENT on a write it really performs. So the operand is
            # stepped over with the operator, marker to marker when it arrived quoted, and
            # exactly the way the outer scan reads the same pair.
            if ($j ~ /[<>]/) {
              if ($j ~ /[<>]$/) { if (j < NF && $(j + 1) == oq) j = qend(j + 1); else j++ }
              continue
            }
            # THE BACKSLASH THAT MASKS A NEWLINE IS NOT DROPPED HERE, and that is a
            # decision and not an omission. It was dropped for one build, next to the
            # redirection above and with the same sentence about syntax, and the sentence
            # is not true of this word. A redirection is stepped over TOGETHER WITH the
            # file it names, so nothing the command writes leaves the scan with it. The
            # operands a masked newline hands on stand on the NEXT LINE, where this loop
            # no longer reads them; drop the backslash and the operand list of the first
            # line is EMPTY, and an empty operand list says nothing at all.
            #
            # Measured 2026-09-09 against the half built repair over 46587 distinct
            # payloads of a frozen foreign corpus [sha256
            # e99cb3d14b918b0b89e759abfe3bfdd74fd5a2be07bf77c0802c44aa4a436dde], the drop
            # cost exactly one stop of 2877 and that one was a REAL WRITE: a "git checkout
            # HEAD --" continued over six production files of a worktree, id
            # aa6eee4710ae99e6, went from work to bookkeeping and nothing came back the
            # other way.
            #
            # So the backslash stays a candidate target and comes back work, which is what
            # this file has said about it since the continuation repair of 2026-09-07: see
            # the skip in the OUTER scan, which is deliberately not mirrored here, and the
            # paragraph next to it. The cost is named and it is not new: a write whose
            # operands are all bookkeeping and which is split over a continued line is a
            # false alarm on the backslash, here and before this repair alike. Loud is the
            # better of the two ways to be wrong.
            #
            # It IS dropped inside a find -exec, three lines up, and that is a different
            # word: there it is the backslash of the "\;" that ENDS the -exec, punctuation
            # the semicolon pass split off, and no operand of that command stands behind
            # it. tests/run.sh holds the two apart in one assertion.
            if (prog != "" && feeds($j, prog))       { pending = 1; owed = 0; continue }
            if (prog != "" && feeds_glued($j, prog)) { pending = 0; owed = 0; continue }
            # A mode with a leading minus is a mode and not a flag. See ismode().
            if (owed && ismode($j, w)) { owed = 0; continue }
            # THE TARGET IN FRONT, IN EVERY SPELLING, read here because the word is about
            # to be stepped over as a flag. See tdopt(). Behind a "--" no word is an
            # option, so cp -- -tsrc/ a.md copies a file called -tsrc/ and is not read so.
            #
            # A GLUED TARGET IS PRINTED HERE AND NOT COLLECTED, and that is deliberate: a
            # collected operand counts as a path this command names, and a find -exec
            # whose sources are all placeholders reads its search path only when it names
            # none. Collected, "find src -exec mv -t.claude/x/ {} +" goes quiet on a move
            # out of the work tree. The spelling with the value apart is quiet there, and
            # it was before this; that is named in the hand-over and not repaired here.
            if ($j == "--") tdend = 1
            if (!tdend && (tk = tdopt($j, w))) {
              zielvorn = 1
              if (tk == 2) { why(trig " takes its target directory out of the option word " $j)
                             tgt(resolve(tdv)) }
              continue
            }
            if ($j ~ /^-/ && $j != "-") { if (takesval($j, w)) { if (w == "patch" && $j ~ /o$/ && j < NF) { why(trig " writes the file its -o names, " $(j + 1)); tgt(resolve($(j + 1))); pr_o = 1 } j++ } continue }
            # The operand of -e or -f: a program, or a file of programs. Read, not written.
            if (pending) { pending = 0; continue }
            if (owed) { owed = 0; continue }
            # A ref is not a file. Only reachable for a checkout without a "--".
            rt = unclose(resolve(opnd(j))); j = opend
            if (gref && !pathish(rt)) { why(trig " names " rt ", whose last segment carries no dot, so it is read as a ref and not as a path")
                                        continue }
            # COLLECTED, NOT PRINTED. For four call forms the operand list carries words
            # this command READS, and which of them is written is decided by the FORM.
            # See the block below the loop.
            cand[++np] = rt
          }
          # WHICH OF THE COLLECTED OPERANDS IS WRITTEN, and it is the CALL FORM that says
          # so rather than the word. Every operand used to be printed the moment it was
          # read, so the FIRST of them decided, and for four forms the first of them is a
          # file this command only reads. Measured 2026-09-08 by running this file over
          # 46587 distinct payloads of a frozen foreign corpus, 354 of its 3001 stops
          # decide on an operand of that kind: 340 a cp, 3 an ln, and one each of dd,
          # install and git apply.
          #
          # mv IS DELIBERATELY NOT IN IT. "mv a b" REMOVES a, and removing a work file is a
          # write however many copies of it exist somewhere else. Measured over the same
          # corpus, leaving it out costs nothing.
          pr = 0
          if (gfrom && $gs == "apply") {
            # git apply READS its patch and WRITES the working tree, and the measure read
            # it the other way round: the operand was the target, so a patch file that is
            # bookkeeping made the whole call bookkeeping. That is the silent pass a
            # coordinator reaches by the shortest route, because the patch it just wrote
            # lies in its own session scratchpad. The tree is read the way find -delete is
            # read on its search path: the set of files is not on the line, and "." is the
            # widest thing the call can reach. This also answers the form that carries no
            # operand at all, where the patch comes in on stdin.
            for (z = 1; z <= np; z++) why(trig " names " cand[z] ", which it reads as a patch and does not write")
            why(trig " reads its patch and writes the working tree, so . is read instead")
            print "."; pr = 1
          } else if (w == "patch") {
            # patch(1): patch [options] [originalfile [patchfile]]. The first operand is written, and
            # with none the tree it stands in is, the way git apply is read.
            if (pr_o) { pr++; pr_o = 0 }
            else if (np) { why(trig " writes its first operand, " cand[1]); tgt(cand[1]); pr++ }
            else { why(trig " names no file, so it writes the tree it stands in, and . is read"); tgt("."); pr++ }
          } else if (w == "rsync" || w == "scp" || w == "ditto" || w == "split") {
            # THE LAST OPERAND, and only when it is on this machine: host:path is the hole README.md
            # keeps. split writes pieces named by its last operand when it has two, else where it stands.
            # A CONTINUED LINE IS FOLLOWED, because this is what kept rsync off this list since
            # 2026-09-09: its calls are long, the destination stands on the last line, and the scan
            # would stop on the backslash. rs_pend reads that last line when it comes.
            if (cand[np] == "\\") { rs_pend = 1; pr++ }
            else if (np >= 2 && cand[np] !~ /^[^\/]*:/) { why(trig " writes its last operand, " cand[np]); tnf = 0; tgt(cand[np]); pr++ }
            else if (w == "split" && np == 1) { why(trig " names no prefix, so it writes where it stands"); tgt("."); pr++ }
            else if (np >= 2) why(trig " writes to another machine, " cand[np] ", which this measure does not read")
          } else if (w == "dd") {
            # dd(1) names its files in name=value operands and writes exactly one of them,
            # of=. if= is the file it READS, and bs=, count=, status= and conv= are numbers
            # and words. All of them were printed as candidates, so if= decided. The VALUE
            # is what is read and never the operand word, because a file called
            # "of=/tmp/x" would be loud by accident rather than by measurement.
            for (z = 1; z <= np; z++) {
              dv = cand[z]
              if (dv !~ /^of=/) { why(trig " names " dv ", which dd reads as a parameter and never writes"); continue }
              sub(/^of=/, "", dv)
              why(trig " writes the file its of= operand names, " dv)
              tgt(dv); pr++
            }
          # THE SOURCE OF A COPY IS READ AND NOT WRITTEN, AND IT IS DROPPED, WITH TWO
          # EXCEPTIONS; without both of them this arm is not a narrowing but a silent
          # pass. cp(1), install(1) and ln(1) all put the thing they write LAST, so the
          # last operand is the target and every earlier one is a source. That sentence is
          # true about the COMMAND; what used to make it false about the CALL is exactly
          # the two exceptions below, so until 2026-11-02 there was no arm here at all.
          #
          # EXCEPTION ONE, -t AND --target-directory PUT THE TARGET IN FRONT. Then the last
          # operand is a SOURCE, and dropping it would take the only loud word off the
          # line. zielvorn is asked above, over the operand words of this command alone.
          #
          # EXCEPTION TWO, AN OPERAND NAMED A SECOND TIME ON THE LINE STAYS A CANDIDATE.
          # This is the shape the arm died on when it was first built on 2026-09-08 and
          # taken out again on 2026-09-09. Over 46587 distinct payloads of a frozen foreign
          # corpus [sha256 e99cb3d14b918b0b89e759abfe3bfdd74fd5a2be07bf77c0802c44aa4a436dde],
          # of which this file stopped 2921 without the arm and 2877 with it, the arm
          # silenced 44 stops and TEN OF THE 44 WERE SILENT PASSES on production code. Read
          # by hand, one by one, they are all one shape:
          #
          #   cp apps/api/src/example_api/llm/service.py <scratchpad>/service.orig.py &&
          #   <venv>/python -c "... p = Path('apps/api/src/example_api/llm/service.py');
          #                         p.write_text(t.replace(alt, neu)) ..."
          #
          # Back up the file, then rewrite it in place through an interpreter. The file the
          # cp READS is the very file the call WRITES, and the write is inside a -c body or
          # a heredoc, where neither this scan nor _mk_narrow can see it: _mk_narrow knows
          # the heredoc and the written-then-run script, and it is asked only about a path
          # that is bookkeeping for the scratchpad reason alone. In every one of the ten the
          # source stands a SECOND time on the line, inside that body, which is what the
          # second-mention test is for: whoever names the source again is touching it. The
          # ten, by id in that corpus: 8620f85ceb27fdf5, 94e920c0eaf9a1ff, 48eea116167ec1c8,
          # b999134282437477, 34f159ccbd2b6d8b, 37946429c36f9112, be04d312c804f8e8,
          # dd15abb04d832e1a, 589011d2631babfa, ae60379f726acd3a.
          #
          # THE SECOND MENTION IS A TEXT COMPARISON AND NOT A PATH COMPARISON, and that is
          # the open edge of this arm: a source spelled differently the second time, once
          # relative and once absolute, or through a variable, falls through it. Named here
          # because it is not measured.
          #
          # WHAT THIS BUYS, measured: 13 of the 122 stops of one week of a live project are
          # this family and all 13 are false alarms, at 0 silenced right stops of the 36
          # measurable [MK-PREIS.md, class 2]. What it gives up is named too: four stops of
          # the shape "cp src/x.py .claude/kopie.txt" that the assertion of 2026-09-09 held
          # loud on a reason that was wrong about which operand was written.
          #
          # THE DROPPED OPERAND IS STILL REPORTED, as "which it only reads", so a hand can
          # tell this arm from a measure that never saw the word. The two counter-probes are
          # in tests/run.sh: "a copy is read by the operand it writes" for the drop, and
          # "a copy keeps the operand its call still writes" for both exceptions.
          } else if (prog == "" && !gfrom && np >= 2 && !zielvorn &&
                     (w == "cp" || w == "install" || w == "ln")) {
            for (z = 1; z < np; z++) print "@@q@@" cand[z] fs_sep (cdir != "" && !cdsoft && cand[z] !~ /^[\/~$]/ ? cdir "/" cand[z] : cand[z])
            why(trig " writes its last operand, " cand[np])
            tgt(cand[np]); pr++
          } else {
            for (z = 1; z <= np; z++) { if (w == "mv") tnf = (z < np); why(trig " names " cand[z]); if (tdir) made_add(cand[z]); tgt(tdir && cand[z] !~ /\/$/ ? cand[z] "/" : cand[z]); pr++ }
          }
          if (xf && pr == 0) {
            # A find -exec whose operands are all placeholders names no path either, and
            # what it can reach is the search path of the find it runs under. Read exactly
            # the way -delete is read, because find(1) makes the two spellings ONE command:
            # a measure that stopped find . -name "*.py" -delete and waved
            # find . -name "*.py" -exec rm {} + through would ship its own way around
            # itself, in one line, in the README that documents it.
            why(trig " names no path of its own, so the search path of the find it runs under is read instead")
            findtarget(fpaths, trig)
          } else if (pr == 0) why(trig " names nothing this scan reads as a path")
          tnf = 0; tns = 0
          continue
        }
        # Only reachable when the word IS a write verb and is NOT in command position,
        # because the block above ends in a continue. It is the other half of the account
        # and the one a reader asks for next: a verb that was seen and deliberately not
        # counted leaves no trace of itself otherwise, and "claude plugin install
        # manager-kit" is exactly that shape. Silence here reads as "the measure did not
        # notice", which is the wrong thing to believe about the rule that fixed it.
        if (isverb(w)) why("the word \"" w "\" stands in argument position and not in command position, so it is not read as a write verb")
      }
    }')

  # How many words the scan handed down here, which is what separates the two shapes of a
  # quiet verdict: nothing on the line was read as a write at all, or something was and no
  # path it named came back work. Counted BEFORE the two words that are not paths are
  # dropped, because a command that reached a write verb and then had nothing to measure
  # is the first shape by accident and the second one in truth. Only the trace reads it.
  _ntargets=0
  # WHETHER THIS COMMAND CARRIES ONE OF THE THREE SHAPES, asked at most once and only when
  # it can change an answer. Empty means not asked yet. See _mk_narrow above.
  _mk_shape=
  #
  # ONE TARGET A LINE, and only a newline separates them: a target may carry a space now.
  # THE COUNT IS TAKEN IN THE LOOP, by the target, and not before it. It was taken before it, as the newlines
  # of the whole list taken out with ${_targets//$'\n'/}, and bash 3.2 does that cubically: 5.3 s at 4000 targets
  # and 39 s at 8000, so the guard that was to keep the budget used it up [MK-R1, nl-zeit.sh]. A counter costs
  # nothing, and the price is that the targets up to the limit are judged before the one past it is refused.
  _mk_nt=0
  _mk_ifs=$IFS
  IFS='
'
  for _t in $_targets; do
    IFS=$_mk_ifs
    _mk_nt=$((_mk_nt + 1))
    if [ "$_mk_nt" -gt "$MK_TARGET_LIMIT" ]; then
      # Past the limit the answer is the one a command too long to read gets: work, and the reason in the trace,
      # so the stop line says what happened and the declared way out stays open.
      _mk_why "unreadable: the command could not be read: it names more than $MK_TARGET_LIMIT targets, past what this measure reads in the time it has: too many to read, and what it cannot read is not let through, so it is work"
      printf 'work\n'; return 0
    fi
    _mk_nf=
    case "$_t" in
      # A slash behind the link goes through it, whatever the verb.
      '@@n@@'*/) _t=${_t#@@n@@} ;;
      '@@n@@'*) _mk_nf=1; _t=${_t#@@n@@} ;;
    esac
    _mk_nn=
    case "$_t" in '@@x@@'*) _mk_nn=1; _t=${_t#@@x@@} ;; esac
    case "$_t" in
      '@@p@@')
        _mk_why 'unreadable: the target of a write in the program text could not be read: it is no literal. Write the path as a literal in the program text, or in the same command'
        printf 'work\n'; return 0 ;;
      # BEHIND A cd AND A PLAIN SEPARATOR. Whether the target moved depends on whether that cd
      # worked, and a directory that is there is one it can get to. One that is not leaves the
      # command where it stood, so the word is read as it stands.
      '@@c@@'*)
        _cd=${_t#@@c@@}; _cr=${_cd#*$'\034'}; _cd=${_cd%%$'\034'*}
        _mk_abs "$_cd"
        if [ -d "$_mk_a" ]; then _t=$_cd/$_cr; else _mk_why "  $_cd is no directory here, so the cd in front of $_cr may not have worked, and $_cr is read as it stands"; _t=$_cr; fi ;;
    esac
    # AN OPERAND THE COPY ONLY READS, marked @@q@@ by the scan above. The test it needs is
    # whether the same word stands a SECOND time on the line, and the scan reads one
    # command at a time while the line can carry several, so the test is here, against the
    # whole command text. Named once it is dropped WITH A REASON; named twice it goes on as
    # a candidate like any other.
    case "$_t" in
      '@@q@@'*)
        _q=${_t#@@q@@}; _qj=${_q#*$'\034'}; _q=${_q%%$'\034'*}
        _rest=$_c; _nq=0
        while :; do
          case "$_rest" in *"$_q"*) _rest=${_rest#*"$_q"}; _nq=$((_nq + 1)); [ "$_nq" -lt 2 ] || break ;; *) break ;; esac
        done
        if [ "$_nq" -le 1 ]; then
          _mk_why "  $_q is only read by this copy and is named nowhere else on the line"
          continue
        fi
        _t=$_qj ;;
    esac
    _ntargets=$((_ntargets + 1))
    # A redirection into /dev/null or a here-document word is not a file we own.
    case "$_t" in
      /dev/*) _mk_why "  $_t is not a file we own" ; continue ;;
      Q)      _mk_why '  a blanked quoted segment is not a path'; continue ;;
      "")     _ntargets=$((_ntargets - 1)); continue ;;
    esac
    # THE SHAPE OF THE WORD, and it stands here rather than in classify_path because it is
    # about a word this SCAN produced and not about a path. classify_path answers for a
    # file_path a tool handed over whole, and it is asked a second question about the same
    # string by the narrowing below, so it has to go on being a truthful measure of a path.
    #
    # WHY IT EXISTS. A ">" is read as a redirection wherever it stands, which is what keeps
    # "echo hi > src/x.py" loud, and it is also what makes every ">" inside SQL, Python or
    # shell syntax name the word behind it as a file. Measured 2026-09-08 by running this
    # file over 46587 distinct payloads of a frozen foreign corpus [snapshot of 2026-09-08,
    # sha256 e99cb3d14b918b0b89e759abfe3bfdd74fd5a2be07bf77c0802c44aa4a436dde], of which it
    # stops 3001: 115 of those stops decide on a word of this shape, the largest of them
    # "now()" at 24, "=" at 25 and "0" at 10.
    #
    # TWO WIDER RULES WERE MEASURED AND REJECTED, and both of them are held open by the
    # counter-probe in tests/run.sh:
    #   "the word carries a parenthesis" loses 84 real targets in that corpus, because
    #     Next.js lays its routes down in bracketed directories and every file under
    #     apps/web/app/(app)/ carries one;
    #   "the word begins with a digit" silences a real file, Gegenprobe
    #     "echo hi > 2ndbrain.txt", which is why the third branch asks for the WHOLE word.
    case "$_t" in
      =|,|'#') _mk_why "  $_t is not a path: the whole word is punctuation"
               continue ;;
    esac
    # A NAME THAT ENDS IN PUNCTUATION AND NAMES NO DIRECTORY. "now()" and "c[bester_ce])"
    # are program text; the slash is what separates them from a real path that arrived with
    # the stray closing parenthesis of a $( ) glued to it. 8 real writes into /tmp reach
    # this branch that way in the measured corpus and every one of them keeps its stop,
    # and so does the Next.js route group directory, which ends in ")" and carries three.
    case "$_t" in
      */*|'$('*) : ;;
      *')'|*']'|*';'|*':'|*',')
        _mk_why "  $_t is not a path: it ends in punctuation and names no directory"
        continue ;;
    esac
    # A WORD MADE OF DIGITS AND PUNCTUATION ALONE. The digit is REQUIRED, and that is not
    # tidiness: without it "." matches, and "." is the WORKING TREE, which is what a git
    # checkout of a pathspec and a git apply with no operand both name. Measured over the
    # same corpus, dropping the digit would silence five real writes of a working tree.
    case "$_t" in
      *[!0-9.:,\)]*) : ;;
      *[0-9]*) _mk_why "  $_t is not a path: it is made of digits and punctuation alone"
               continue ;;
    esac
    if [ "$(classify_path "$_t")" = work ]; then
      # THE TARGET THIS COMMAND DOES NOT SPELL OUT. It stays work, and it is said, with what makes
      # it readable. The hook runs BEFORE the command, so nothing the command sources or assigns
      # exists yet anywhere, and a variable of an earlier Bash call does not survive that call
      # [measured 2026-11-07 in a live session: set in one call, unset in the next, and neither
      # TMP nor QQ_Q stands in the environment of the claude process above it]. So there is no
      # variable to read, and a sourced file is not read: it can compute what it sets.
      case "$_t" in
        *'$('*|*'`'*) _mk_why "unreadable: a target could not be read, $_t: it comes out of a command substitution. Spell the path out, or assign it in the same command" ;;
        *'$'*) _v=${_t#*\$}; _v=${_v#\{}; _v=${_v%%[!A-Za-z0-9_]*}
               _mk_why "unreadable: a target could not be read, $_t: this command assigns no value to \$$_v, and a hook does not see the variables of the shell that runs it. Spell the path out, or assign it in the same command: $_v=<path>; ..." ;;
      esac
      printf 'work\n'; return 0
    fi
    # THE NARROWING, and it is asked LAST and about ONE thing. The strict reading differs
    # from the plain one on exactly the paths whose only reason to be quiet is the session
    # scratchpad, so this test is the gate: a path that is bookkeeping because it lies
    # under .claude or ends in .md answers the same way strictly, never reaches _mk_narrow,
    # and cannot be turned loud by any shape. That is what keeps the shapes from being a
    # rule about commands: they only ever cancel the third axis, and only where it fired.
    #
    # THE STRICT READING IS ASKED WITH THE TRACE OFF, and that is not tidiness. It is a
    # QUESTION about this path and not a verdict on it, and classify_path answers every
    # question with the sentence it would print for a verdict. Left loud it printed
    # "<scratchpad path> is work" into the trace of a command that had just decided the
    # opposite about the same path: measured 2026-09-08 against the suite, that one line
    # turned "a copy out of the scratchpad follows its target" red, because that assertion
    # reads the trace to check the verdict rests on the TARGET and not on the source.
    if [ -z "$_mk_nn" ] && [ "$(MK_EXPLAIN=0; classify_path "$_t" strict)" = work ]; then
      [ -n "$_mk_shape" ] || _mk_shape=$(_mk_narrow "$_c")
      # The answer is 1, and under the trace 1 and the words that name the shape, so the
      # line that decides says WHICH shape cancelled the scratchpad and not only that one
      # did. See benannt() in _mk_narrow.
      if [ "${_mk_shape%% *}" = 1 ]; then
        _mk_why "  $_t lies in the session scratchpad, but ${_mk_shape#1 }, so it is read as work"
        printf 'work\n'; return 0
      fi
      _mk_why "  $_t is in the session scratchpad and this command carries no shape that reaches the work tree, so it stays bookkeeping"
    fi
  done
  IFS=$_mk_ifs
  if [ "$_ntargets" -eq 0 ]; then
    _mk_why 'no path reached the measure: this command carries no redirection, no write verb in command position, no in-place edit of sed or perl, no git write on a path and no find -delete'
  else
    _mk_why 'no path this command names is work'
  fi
  printf 'bookkeeping\n'
}
