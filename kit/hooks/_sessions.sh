#!/usr/bin/env bash
# Which project a working directory belongs to, who else is in that project, and which
# of those processes am I.
#
# The register is the socket directory Claude Code keeps, one <pid>.sock per session
# [measured 2026-09-07: 12 sockets, every one of them with a live process]. It maps pid
# to address and nothing else, so the working directory has to come from the operating
# system, one lsof call for the whole base set rather than one per entry.
#
# No branch in here carries an upper bound: no head, no tail, no -n. The base set is
# counted and the sum is proved, because a truncated list and an empty base set look
# exactly alike from the outside, and both look like a green result.
#
# THE PROJECT ROOT LIVES HERE, and here only, because this is the one file all five hooks
# already load: role-guard.sh sources it directly, the three SessionStart and prompt
# carriers reach it through _identity.sh, and tools/manager-claim.sh sources it too. Six
# readers deriving that directory six times is the defect this file exists to prevent one
# cell over.

# WHERE THE REGISTER IS, AND IT IS A DERIVATION RATHER THAN A PATH. Until now this line
# read /tmp/cc-socks, which is the answer on exactly one shape of machine. The runtime
# builds that path out of two environment variables and a uid, in two functions and
# nowhere else [read out of the shipped binary, Claude Code 2.1.278, on 2026-11-02]:
#
#   function Lro(){ let e=a.XDG_RUNTIME_DIR||jy(),
#                   n=ce(N(e,"cc-socks",`${process.pid}.sock`));
#                   if(Buffer.byteLength(n)<=103)return n; return QTr() }
#   function jy(){ let e=a.CLAUDE_CODE_TMPDIR; if(e)return e; return "/tmp" }
#   function QTr(e=process.getuid?.()??0){ let n=a.TERMUX_VERSION?a.PREFIX:void 0,
#                   i=n?N(n,"tmp"):"/tmp"; return N(i,`cc-socks-${e}`,`${process.pid}.sock`) }
#
# So there are exactly TWO places, not a list of plausible ones: the primary, cc-socks
# under XDG_RUNTIME_DIR or else CLAUDE_CODE_TMPDIR or else /tmp, and the fallback the
# runtime drops to when the socket path would pass 103 bytes, cc-socks-<uid> under the
# Termux PREFIX or else under /tmp. Both are produced here, in that order, because the
# length that decides between them is a property of a pid this process does not have.
#
# THE SAME BINARY CARRIES THE SET IT WILL ACCEPT A SOCKET FROM, which is a second and
# independent witness that /tmp was never the whole answer:
#   [/^\/tmp\/cc-socks(?:-(0|[1-9]\d*))?$/, /^\/private\/tmp\/cc-socks(?:-(0|[1-9]\d*))?$/,
#    /^\/run\/user\/(0|[1-9]\d*)\/cc-socks$/,
#    /^\/data\/data\/com\.termux\/files\/usr\/tmp\/cc-socks(?:-(0|[1-9]\d*))?$/]
# /run/user/<uid> is what XDG_RUNTIME_DIR holds on a machine running systemd, and no
# branch in this file could reach it.
#
# WHAT IT COST, measured 2026-11-02 against the delivered hook with the register under
# XDG_RUNTIME_DIR and two live sessions in one project: the census answered "5 5 0 0 1"
# and mk_here_is_measured passed that through as a finding. Not a missing count, a
# CONFIDENT ZERO, because /tmp/cc-socks existed on that machine with five foreign sockets
# in it. A session that reads solitude it does not have CLAIMS, and the session that
# really was coordinating then reads a record naming somebody alive, becomes a carrier,
# and its guard stands down at the return ahead of the log. That is the silent pass.
#
# THE EXPLICIT OVERRIDE STAYS THE ONLY ANSWER WHEN IT IS GIVEN. MANAGER_KIT_SOCKET_DIR is
# how every probe in tests/run.sh hands a register in, and a derivation that added its own
# candidates beside an explicit one would count sockets the caller did not name.
#
# A LIST AND NOT A STRING, held newline separated and walked by the same cut this file
# already uses for path segments: no word splitting [on in bash, off in zsh, and a helper
# that answers differently depending on who sourced it cannot be trusted], no heredoc per
# round in a loop that runs at every tool call, and no fork anywhere.
MK_NL='
'

# HOW MUCH OF A PROJECT FILE THE KIT READS. The role file holds "<pid> <session id>" and the seen file a
# date, so anything past 4096 bytes is no such file, and a repository can ship one of 200 MB that held every
# call for 6 to 10 s [measured 2026-11-07 at 95792cd]. The guard log is the one file that grows without an
# end, and the refusal counts it only up to MK_LOG_CAP bytes: 16 MiB is about 21 ms a MB, well under half a
# second, and tens of thousands of lines. Past that it says it did not count, and tools/week-verdict.sh,
# which is no hook, still reads the whole of it.
MK_KIT_SMALL=4096
MK_LOG_CAP=16777216
# A settings file is read for one word, up to this many bytes. Past it the word is not looked for beyond, and
# the report says it did not check: 200 MB in lines of two bytes held both SessionStart hooks 5.2 s.
MK_SETTINGS_CAP=1048576

# THE ONE WAY A HOOK READS ITS INPUT. The runtime hands over JSON in UTF-8, and what decodes it here
# is not the locale. json.load(sys.stdin) and print() follow the locale, and a hook is started with
# whatever the session has: in a session on this machine neither LANG nor any LC_ variable is set. Measured
# 2026-11-06 at 0bc14fe through the delivered hooks, one project, one write to a work path:
#   en_US.US-ASCII, any path that is not ASCII   UnicodeDecodeError, an Exception like any other, so
#                                                the input was empty and the write PASSED, no line.
#   en_US.UTF-8, one byte in a command that is   the same pass, and under C the same call was
#   no UTF-8                                     refused: the verdict hung on the locale.
#   every locale, a lone surrogate in a command  print() fell over, and the guard reported that
#                                                python3 does not run. No refusal.
# surrogateescape carries a byte that is no UTF-8 through to the shell unchanged, so the verdict is
# taken on what was sent. A lone surrogate has no bytes at all, so it arrives as U+FFFD: the word it
# stood in stays one word for the measure, and the record says something was there. A pair is one
# character by then and is not touched. On any other input d answers as before, so a line that is
# no JSON at all stays what it was.
# every_hook_reads_its_input_through_the_one_reader in tests/run.sh derives the places.
MK_PY_INPUT='
import io, sys, json, re, shlex
try:
    d = json.load(io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="surrogateescape"))
except Exception:
    d = {}
def say(name, value):
    text = re.sub("[\ud800-\udc7f\udd00-\udfff]", "\ufffd", "" if value is None else str(value))
    sys.stdout.buffer.write(("%s=%s\n" % (name, shlex.quote(text))).encode("utf-8", "surrogateescape"))
'

# The uid the runtime would put in that name. EUID rather than `id -u` because this file
# is loaded by every hook at every tool call and the whole reason the project root is
# climbed instead of asked of git is that one fork per call was too much. bash and zsh
# both set it [measured 2026-11-02: 501 from each]. A shell that does not gets the fork,
# once, and a shell with neither gets 0, which is what the runtime defaults to when
# getuid is unavailable.
case "${EUID:-}" in
  ''|*[!0-9]*) MK_UID=$(id -u 2>/dev/null) ;;
  *) MK_UID=$EUID ;;
esac
case "${MK_UID:-}" in ''|*[!0-9]*) MK_UID=0 ;; esac

if [ -n "${MANAGER_KIT_SOCKET_DIR:-}" ]; then
  MK_SOCKET_DIRS=${MANAGER_KIT_SOCKET_DIR%/}
else
  case "${XDG_RUNTIME_DIR:-}" in
    /?*) MK_SD_BASE=${XDG_RUNTIME_DIR%/} ;;
    *) case "${CLAUDE_CODE_TMPDIR:-}" in
         /?*) MK_SD_BASE=${CLAUDE_CODE_TMPDIR%/} ;;
         *) MK_SD_BASE=/tmp ;;
       esac ;;
  esac
  # The Termux branch of the fallback, and PREFIX is required to be an absolute path
  # before it is believed: QTr reads it only when TERMUX_VERSION is set, and a relative
  # PREFIX would name a directory that moves with whatever the hook was handed as a cwd.
  MK_SD_PX=/tmp
  if [ -n "${TERMUX_VERSION:-}" ]; then
    case "${PREFIX:-}" in /?*) MK_SD_PX=${PREFIX%/}/tmp ;; esac
  fi
  MK_SOCKET_DIRS="$MK_SD_BASE/cc-socks${MK_NL}$MK_SD_PX/cc-socks-$MK_UID"
fi

# mk_socket_dir_holds <pid> -> true when any register holds <pid>.sock.
mk_socket_dir_holds() {
  _sh_rest=$MK_SOCKET_DIRS
  while [ -n "$_sh_rest" ]; do
    _sh_d=${_sh_rest%%"$MK_NL"*}
    case $_sh_rest in *"$MK_NL"*) _sh_rest=${_sh_rest#*"$MK_NL"} ;; *) _sh_rest="" ;; esac
    [ -n "$_sh_d" ] || continue
    [ -e "$_sh_d/$1.sock" ] && return 0
  done
  return 1
}

# mk_root_is_barred <dir> -> true when <dir> is the user's home directory or lies above
# it. The walk below must never end there: $HOME/.claude is the person's own Claude
# configuration, and reading it as this project's bookkeeping would put one log, one role
# file and one exception marker across every project they own. check.sh bounds its own
# upward walk for the same reason and says so in as many words.
#
# A HOME that is not an absolute path with something under the slash is not a home path,
# and the bar stays off rather than guessing: with the bar off the walk simply behaves as
# it did before this rule existed, which is the harmless direction.
mk_root_is_barred() {
  case "${HOME:-}" in
    /?*) ;;
    *) return 1 ;;
  esac
  [ -n "${1-}" ] || return 1
  # <dir> barred when $HOME is <dir> itself or lies under it. The trailing slash on both
  # sides is what makes "is the same directory" and "is an ancestor" one test: * matches
  # the empty string, so "/u/me/" matches "/u/me/*" and "/u/mekong" does not. The % takes
  # the slash off a <dir> of "/", which lies above every home there is.
  case "${HOME%/}/" in
    "${1%/}"/*) return 0 ;;
  esac
  # THE SAME DIRECTORY UNDER ANOTHER SPELLING. The test above compares strings, the runtime
  # hands over a physical cwd, and HOME may run through a link: measured 2026-11-06 with HOME
  # a link and cwd its target, the record went into the home .claude anyway. -ef asks the
  # file system and is a builtin, so this costs two stats and no fork. A directory ABOVE a
  # linked home is caught by the walk below.
  [ "${1-}" -ef "$HOME" ] && return 0
  # THE DIRECTORIES ABOVE A HOME THAT RUNS THROUGH A LINK. HOME may be /a/link/me with /a/link a link to
  # /b/real, and /b is then above the home and no string-ancestor of it. $HOME/.. is resolved by the
  # file system, one physical step up each round, and -ef asks it the same question as above. Builtins
  # only, a handful of stats, bounded, and ended at "/".
  # Not for a directory under the home: that is no ancestor of it, and every project under a home, which is
  # nearly all of them, skips the loop.
  case "${1%/}/" in "${HOME%/}"/*) return 1 ;; esac
  [ -d "$HOME" ] || return 1
  _rb_d=$HOME; _rb_n=0
  while [ "$_rb_n" -lt 64 ]; do
    _rb_d=$_rb_d/..
    [ "${1-}" -ef "$_rb_d" ] && return 0
    [ "$_rb_d" -ef / ] && break
    _rb_n=$((_rb_n + 1))
  done
  return 1
}

# mk_project_root_set <dir> -> sets MK_ROOT to the directory whose .claude/ holds the
# bookkeeping for <dir>. THE RULE LIVES IN THIS FUNCTION AND NOWHERE ELSE.
#
# Measured 2026-09-07 in a live project: anchored at the working directory instead, a
# session standing in .claude/agents left a whole second record there, guard log, role
# file and exception marker, and the record the week is read from never heard about that
# day. Under-counting the week is the mildest of the three: a session that finds no role
# file may call itself the manager, and a marker spent where nobody reads it buys a
# crossing that is not on any record.
#
# 1. THE WORK TREE, found by climbing for a .git. It is climbed rather than asked of
#    `git rev-parse --show-toplevel`, and the reason is a measurement: 8.968 ms per call
#    against 0.133 ms for the climb, on a hook that runs at EVERY tool call and costs
#    33.3 ms in total, so the fork would have been 27 percent on top of every turn. The
#    two answers were compared over the eight shapes that matter [measured 2026-09-07:
#    repository, subdirectory, linked worktree, worktree subdirectory, submodule,
#    submodule subdirectory, nested repository, no repository at all] and agreed on all
#    eight. A linked worktree and a submodule each carry a .git FILE at their own top and
#    not a directory, which is why the test is -e and why the file is then READ: -d alone
#    walks past both. The climb also cannot be misdirected by a GIT_DIR or GIT_WORK_TREE
#    that happens to be exported into the session, and it answers on a machine with no
#    git at all.
#
#    A WORKTREE IS RECORDED AT ITS MAIN REPOSITORY, and this reverses what stood here
#    until 2026-09-09. A count overturned it: in a live project carrying 279 worktrees,
#    `find <the tree of projects> -maxdepth 4 -name manager-kit.log` came back with 12
#    separate records holding 30 events between them, the log at the top of the main
#    repository held 5 of those 30, and tools/week-verdict.sh reads exactly ONE of the 12.
#    The same find for manager-kit.role gave 0, so no session in any of those worktrees
#    ever read a role file at all.
#
#    IT IS NOT FREE, AND THE PRICE IS WHAT THIS PARAGRAPH USED TO ARGUE. One project root
#    means one role file for the whole repository, so a session in any other worktree
#    reads a role file naming somebody who is alive, calls itself a carrier, and its guard
#    stands down before it logs anything. Measured 2026-09-09 through the delivered hook,
#    six worktrees of one main repository, the manager claiming while alone and the others
#    opening after it: with the old rule 5 of 5 work writes in the other worktrees were
#    STOPPED and 10 events were recorded; with this one 5 of 5 PASSED IN SILENCE and
#    nothing was recorded anywhere. That is a silent pass bought with an under-count, and
#    the mk_session_census comment below is where this kit says which of the two it holds
#    to be worse.
#
#    THE PRICE IS CHARGED FOR A WAY OF WORKING AND NOT FOR A LINE OF CODE, which is why
#    this goes out with the price named rather than paid. It falls only where one project
#    runs SEVERAL sessions at the same time in sibling worktrees; the guard then keeps one
#    of them and loses the rest. One session at a time reads its role file and records its
#    events out of any worktree exactly as it did before. That makes it a condition on the
#    USE of this kit and not a property of its code, and a condition on the use is
#    something the reader is owed out loud, because nothing in here can discover it for
#    them. The project every number above was measured in runs with exactly ONE session
#    from 2026-09-09 by the decision of its user, so the case does not arise there.
#
#    TAKING THE ROLE FILE OUT OF THE RECORD'S DIRECTORY IS A CHANGE TO WHAT THE GUARD
#    DOES, not a tidying of where files sit: it moves where every session reads its role
#    from. A measuring week is running on another project right now against this hook as
#    delivered, and a measure that shifts in the middle of the week has stopped measuring.
#    Held until that week closes, and written down here so that it is held and not lost.
#
#    A SUBMODULE STAYS A PROJECT OF ITS OWN, and there both ways of asking still agree:
#    `git log` inside it reports the submodule's history, which is the history
#    tools/week-verdict.sh weighs the guard's own record against.
#
# 2. NO REPOSITORY: the nearest ancestor that already keeps a .claude/. A project without
#    git must not come off worse than it did before this rule existed, and it does not:
#    the walk either finds the bookkeeping it has been writing all along, or falls
#    through to 3, which is byte for byte the old behaviour.
#
# 3. THE WORKING DIRECTORY, which is what every one of these call sites used to use.
#
# A candidate that lies under a .claude/ is skipped in both walks. Bookkeeping inside
# bookkeeping is not a project, and without that line the repair would heal a fresh
# project while every project the defect already broke kept writing into the stray
# directory it created: that directory has a .claude/ in it now, so the walk would stop
# at it. The pattern is the one _classify.sh uses, "/.claude/" and never "*.claude*".
mk_project_root_set() {
  MK_ROOT=${1-}
  # Only an absolute path can be climbed. Anything else is not a directory this hook was
  # handed, and the working directory of this process is the honest stand-in.
  case "$MK_ROOT" in /?*) ;; *) MK_ROOT=$PWD ;; esac
  MK_ROOT=${MK_ROOT%/}
  [ -n "$MK_ROOT" ] || MK_ROOT=$PWD

  # The two walks strip one component per step, so the last candidate is a directory
  # directly under the root and "/" itself is never a candidate. A repository or a
  # project at "/" is not a case this kit is asked to serve, and reaching for it would
  # mean claiming the whole machine.
  _w=$MK_ROOT
  while [ -n "$_w" ]; do
    mk_root_is_barred "$_w" && break
    case "$_w/" in */.claude/*) _w=${_w%/*}; continue ;; esac
    # A .git IS A FILE (a worktree, a submodule) OR A DIRECTORY THAT HOLDS A HEAD, which is the first thing
    # git asks of one. An empty directory named .git is climbed past, as git does [measured 2026-11-07:
    # git rev-parse answers the repository around it], and a project does not start at it.
    if [ -f "$_w/.git" ] || [ -f "$_w/.git/HEAD" ]; then
      MK_ROOT=$_w
      # A .git that is a FILE and not a directory is a linked worktree or a submodule,
      # and it holds ONE line: "gitdir: <path>". Read with the read BUILTIN and a
      # redirection, never with a fork: this function runs at every tool call and again
      # in a loop inside mk_session_census, and the whole reason the climb exists rather
      # than a `git rev-parse` is that 8.968 ms per call was too much. An unreadable or
      # empty file leaves the line empty and the worktree stands, which is byte for byte
      # what this branch did before the rule existed.
      if [ -f "$_w/.git" ]; then
        _gl=""; _main=""; _wtn=""
        IFS= read -r -n "$MK_KIT_SMALL" _gl 2>/dev/null < "$_w/.git" || true
        case $_gl in
          'gitdir: '*)
            _gd=${_gl#gitdir: }
            # Against the WORKTREE and never against the working directory of this
            # process: a hook is handed a cwd, it is not standing in it, and the same
            # relative line would then name a different place on every call.
            case $_gd in /*) ;; *) _gd=$_w/$_gd ;; esac
            # THE COMPONENT DECIDES, and only worktrees. A linked worktree points into
            # <main>/.git/worktrees/<name> and its history is the main repository's. A
            # submodule points into <parent>/.git/modules/<name> and is a project of its
            # own: `git log` inside it reports the submodule's history, which is the
            # history tools/week-verdict.sh weighs the guard's record against. Cutting at
            # any /.git/ would swallow the submodule with it.
            case $_gd in */.git/worktrees/*) _main=${_gd%%/.git/worktrees/*}; _wtn=${_gd#*/.git/worktrees/} ;; esac
            # AND THE REPOSITORY HAS TO NAME THIS WORKTREE BACK. <gitdir>/gitdir holds the path of the .git
            # file of the worktree it belongs to, and git writes it when it makes the worktree. A .git file
            # that points into somebody else's repository, which a project can ship, is not named back by
            # that repository, and without this the record and the exclusion line went in there [measured
            # 2026-11-07 at 95792cd]. -ef asks the file system, so a link or a relative path in either
            # spelling is the same file, and it costs two stats. Not named back: the worktree stands.
            if [ -n "$_main" ]; then
              _bp=""
              IFS= read -r -n "$MK_KIT_SMALL" _bp 2>/dev/null < "$_gd/gitdir" || true
              case $_bp in /*) ;; *) _bp=$_gd/$_bp ;; esac
              [ "$_bp" -ef "$_w/.git" ] || _main=""
            fi
            ;;
        esac
        if [ -n "$_main" ]; then
          # Folded lexically, because this answer is COMPARED AS A STRING: mk_session_census
          # asks whether two sessions have the same root, and /a/wt/../a-main and /a/a-main
          # are one directory under two spellings and would count as two projects. cd and
          # pwd -P would fold it and cost the fork this climb is written to avoid.
          _n=""; _rest=$_main
          while [ -n "$_rest" ]; do
            _seg=${_rest%%/*}
            case $_rest in */*) _rest=${_rest#*/} ;; *) _rest="" ;; esac
            case $_seg in
              ""|.) ;;
              ..)   _n=${_n%/*} ;;
              *)    _n=$_n/$_seg ;;
            esac
          done
          _main=$_n
        fi
        # TAKEN ONLY AGAINST THE REPOSITORY THE FILE NAMES. Whatever the line said, the answer stands
        # only if the folded directory keeps the very administrative directory the line named, and
        # otherwise the worktree does. -ef asks the file system whether the two spellings are one
        # directory, because the fold is lexical and a link in front of a .. makes it name a place the
        # disk does not: a directory that is no repository, or ANOTHER REAL ONE [measured 2026-11-07
        # at a7dc5a9, a .git directory at the folded path was enough to be taken]. A name that is
        # only a directory is not an answer to "is this the repository", and a name that is the same
        # inode is. It costs two stats.
        #
        # That is what makes a worktree of a BARE repository, a main
        # repository that has been moved away, and a garbled line all fall back to the
        # behaviour this branch had before, instead of to a directory nobody keeps
        # bookkeeping in.
        #
        # AND NEVER PAST THE BAR. mk_root_is_barred is asked in every round of both walks
        # above, and this line is the one answer in the function that names a directory
        # neither walk ever stood on, so it is the one place the bar can be jumped. A
        # dotfiles repository keeps its .git at the home directory itself, which makes
        # every worktree of one resolve to $HOME: the log, the role file, the seen marker
        # and the exception marker would then be written into the person's own .claude
        # directory, which is read by every project they own. When the bar answers, the
        # worktree stands, which is what the walks themselves do when they run onto a
        # barred root [they break, and MK_ROOT keeps the candidate it already holds].
        if [ -n "$_main" ] && [ "$_main/.git/worktrees/$_wtn" -ef "$_gd" ] &&
           ! mk_root_is_barred "$_main"; then MK_ROOT=$_main; fi
      fi
      return 0
    fi
    _w=${_w%/*}
  done

  _w=$MK_ROOT
  while [ -n "$_w" ]; do
    if mk_root_is_barred "$_w"; then
      # The walk skips everything under a .claude and came up to the bar: this directory lies inside the
      # .claude of the person's home, which is their configuration. It is no project, and the record
      # would otherwise be made in there, a .claude inside a .claude [measured 2026-11-07 at 95792cd].
      case "$MK_ROOT/" in */.claude/*) MK_ROOT=$_w ;; esac
      break
    fi
    case "$_w/" in */.claude/*) _w=${_w%/*}; continue ;; esac
    [ -d "$_w/.claude" ] && { MK_ROOT=$_w; return 0; }
    _w=${_w%/*}
  done

  return 0
}

# mk_project_root <dir> -> the same answer on stdout, for the call sites that want one.
# A wrapper and never a second copy: two derivations of one directory is exactly the
# split this repair closes. NO HOOK AND NO TOOL TAKES ITS ROOT FROM THIS ONE: a command substitution
# removes a newline at the end of the answer, and a project called tail<newline> was then recorded in
# its sibling called tail [measured 2026-11-07 at a7dc5a9]. They call mk_project_root_set and read
# MK_ROOT, and a check lists the wiring to see that each of them does.
mk_project_root() { mk_project_root_set "${1-}"; printf '%s\n' "$MK_ROOT"; }

# mk_own_pid -> prints the pid of the Claude process this hook is running under, or
# nothing. Walks up the parent chain until it finds an ancestor that owns a socket, so
# it stays right no matter how many shells sit between the session and this script.
mk_own_pid() {
  _p=${PPID:-0}
  _guard=0
  while [ "$_p" -gt 1 ] && [ "$_guard" -lt 40 ]; do
    if mk_socket_dir_holds "$_p"; then printf '%s\n' "$_p"; return 0; fi
    _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')
    case "$_p" in ''|*[!0-9]*) return 0 ;; esac
    _guard=$((_guard + 1))
  done
  return 0
}

# mk_field1_is_pid <field 1 of the role record> -> true when it CAN name a living holder
#
# THE ONE PLACE THAT JUDGES FIELD 1, and every reader of the record asks it: mk_guard_role
# in role-guard.sh, mk_decide_role and the writer mk_record_role in _identity.sh,
# manager-stamp.sh, and the take-over in tools/manager-claim.sh, which sources this file.
# It answers only whether the field is a pid at all. Whether that process
# is still there is kill -0, asked by the caller afterwards, and never before: kill -0 is
# the wrong instrument until the field is known to be a pid.
#
# A PID IS A POSITIVE WHOLE NUMBER, AND NOTHING ELSE IS. kill -0 answers for a PROCESS
# GROUP as readily as for a process: `kill -0 -1` succeeds [measured 2026-11-01, bash
# 3.2.57 on darwin] and so does `kill -0 0`, because signal 0 goes to the caller's own
# process group [measured 2026-11-02, same shell]. Without the 0* arm a record reading
# "0 <foreign session id>" was a living foreign holder in all four carriers at once: they
# AGREED on carrier, the guard stood down at the return that sits ahead of its log, and a
# write past the role boundary went through with no refusal and no line (repaired in
# da1c515). The 0 is the kit's own: mk_decide_role records "${_mypid:-0}" when the register
# cannot name this process. 0* also takes a leading zero, which no writer of this record
# produces, and that is the fail closed direction: a hole in the register costs a false
# stop and never a silent pass. An EMPTY field comes in through the first arm: every reader
# takes both fields off one awk, and `printf ' S1\n' | awk 'NR==1 {print $1}'` answers S1,
# so an empty field 1 is an empty line and names nobody.
#
# ONE FUNCTION AND NOT A FOURTH COPY, because the copies drifted. Until 2026-11-03 this rule
# stood as three case arms with a paragraph each, and the writer carried a fourth arm
# without 0*: for a record reading "0 S1" the three readers found no holder and the claim
# line said "previous 0 alive" [measured through manager-stamp.sh in a fresh project]; the
# take-over carried a fifth arm of the same shape and wrote the same words into its handover
# line [measured through the tool, same day].
# field1_is_judged_in_one_place in tests/run.sh holds every reader to this function.
mk_field1_is_pid() {
  case "${1-}" in ''|*[!0-9]*|0*) return 1 ;; esac
  return 0
}

# mk_lsof_path_set <a name as lsof -Fn prints it> -> sets MK_LSOF_PATH to the directory it names, and
# fails, with MK_LSOF_PATH empty, for a name it cannot read back.
#
# WHAT LSOF PRINTS IS NOT THE PATH. Under C or with no locale set it prints mit-\xc3\xa4, four
# characters per byte, and under en_US.UTF-8 it prints the character, but \xe2\x80\x8b for one it
# calls unprintable, and under ISO8859-1 half of each. Measured 2026-11-06 at 0bc14fe, two live
# sessions in one project: the census read 2 2 0 0 1 under C and 2 2 0 2 1 under UTF-8. Under C the
# second session claimed, and the first one's guard stood down without a line. A take-over took the
# printed name for a directory, made it beside the project and put the role in there.
#
# AND IT ESCAPES A PLAIN ASCII NAME THE SAME WAY, which this function left as printed until MK-R2 on
# the order that no ASCII session may gain or lose a role. Measured 2026-11-07 at 0464e26, every byte
# from 1 to 31 and 127 under C and en_US.UTF-8: a backslash is printed doubled, and \b \t \n \f \r and
# DEL (as \x7f) are printed as their escape. printf %b is the exact inverse of all of them, because
# lsof doubles every backslash of its own, so what %b finds is an escape and never a piece of the
# name. A session in back\slash was counted into a project that does not exist, and a take-over made
# a directory of that name beside the project.
#
# printf -v AND NOT A COMMAND SUBSTITUTION, twice over: it forks nothing, and it keeps a newline at
# the end of the name, which $(...) removes, so that a project named tail<newline> was read as its
# sibling tail.
#
# A NAME THAT CANNOT BE READ BACK: every other control character is printed as ^ and the letter, and
# a literal ^A in a name is printed as ^A as well [measured, same day]. Nothing says which of the two
# a session stands in, so the name is not read, and the caller says it did not measure. The pattern is
# the bytes lsof prints that way (1 to 7, 11, 14 to 31), and tests/run.sh derives them again from
# lsof on every run.
mk_lsof_path_set() {
  MK_LSOF_PATH=${1-}
  case $MK_LSOF_PATH in
    *'^'[ABCDEFGKNOPQRSTUVWXYZ[\\\]^_]*) MK_LSOF_PATH=""; return 1 ;;
    *\\*) printf -v MK_LSOF_PATH '%b' "$MK_LSOF_PATH" ;;
  esac
  return 0
}

# mk_same_root <root> <root> -> true when the two are one project.
#
# TWO SPELLINGS OF ONE NAME. On APFS bash answers pwd -P with the spelling that was typed, and
# getcwd, node and lsof answer with the one on the disk [measured 2026-11-06]. So a cwd that comes
# out of a shell can be mit-\xc3\xa4 where the disk keeps mit-a\xcc\x88. Handed that, the census
# read 1 1 0 0 1 under C and under UTF-8. Whether the runtime ever passes such a cwd on was not
# measured; what is measured is that the answer is wrong when it does.
# The file system is asked and not a normal form computed, because this is its question to answer:
# APFS folds the two into one directory, and a disk that keeps them apart holds two projects.
#
# ONLY WHEN ONE OF THEM IS NOT ASCII. -ef also folds a spelling through a link, and an ASCII project
# reached that way counts 0 today. The order holds ASCII sessions to the role they have, so that
# stays, and two stats are paid only by a path that needs them.
mk_same_root() {
  [ "$1" = "$2" ] && return 0
  case "$1$2" in *[![:ascii:]]*) [ "$1" -ef "$2" ] ;; *) return 1 ;; esac
}

# mk_session_census <dir> -> prints "base alive dead here sumok"
#   base   every socket in the register
#   alive  those whose process still answers
#   dead   those whose process is gone
#   here   the live ones that are in the same PROJECT as <dir>, and 0 when that could not
#          be counted at all, which is a different fact: mk_here_is_measured tells them
#          apart. A session whose name lsof printed in a way that cannot be read back is not
#          counted here, and sumok says the count has a hole in it
#   sumok  1 when alive + dead == base AND every name lsof printed was read back, 0 when
#          either does not hold: a live session whose working directory lsof prints with a
#          control character cannot be told from one in a directory with a literal ^ in it
#
# THE COUNT MOVED WITH THE RECORD, and it had to. This census is what decides whether a
# session is alone and may claim the role, and the role file it claims is now one file per
# project. Left counting by working directory, two sessions in one project standing in two
# different subdirectories would each measure themselves alone, each claim, and the second
# claim would overwrite the first: the session that really was coordinating then reads a
# role file naming somebody else who is alive, becomes a carrier, and its guard stands
# down. That is a SILENT PASS, and it would have been strictly worse than the split record
# this repair removes. <dir> is read through mk_project_root_set, so a working directory
# and its project root are the same question asked twice.
mk_session_census() {
  _target=${1-}
  _base=0
  _pids=""
  # ONE PID IS ONE SESSION, however many registers name it, and the dedup is not tidying.
  # The register is two directories now, so a session whose socket lies in both arrives
  # twice. Measured 2026-11-02 without this line, one live session: the census answered
  # "2 2 0 1 1". Base and alive double; here does not, because lsof is asked ONCE for the
  # whole list and prints one line per process, so the repeat collapses there. The damage
  # is therefore to the BASE SET, which is the number every other one is proved against:
  # dead is base minus alive, so a duplicate reports a dead session that never existed,
  # and tools/week-verdict.sh and the guard's own refusal read those counts. The here
  # field being safe is a property of a tool this kit does not own, which is not a thing
  # to rest on.
  _seen=" "
  _cs_rest=$MK_SOCKET_DIRS
  while [ -n "$_cs_rest" ]; do
    _dir=${_cs_rest%%"$MK_NL"*}
    case $_cs_rest in *"$MK_NL"*) _cs_rest=${_cs_rest#*"$MK_NL"} ;; *) _cs_rest="" ;; esac
    [ -n "$_dir" ] || continue
    for _s in "$_dir"/*.sock; do
      [ -e "$_s" ] || continue
      _pid=${_s##*/}; _pid=${_pid%.sock}
      # A name that is not a pid still counts in the base set, exactly as it did when
      # there was one directory: the base set is what the sum is proved against, and
      # quietly dropping an entry from it is how a truncation starts looking green.
      case "$_pid" in ''|*[!0-9]*) _base=$((_base + 1)); continue ;; esac
      case $_seen in *" $_pid "*) continue ;; esac
      _seen="$_seen$_pid "
      _base=$((_base + 1))
      _pids="$_pids$_pid
"
    done
  done

  # Newline separated and read one per line, rather than an unquoted expansion: word
  # splitting on an unquoted variable is on in bash and OFF in zsh, and a helper that
  # answers differently depending on who sourced it is a helper that cannot be trusted.
  _alive=0
  _live_pids=""
  while IFS= read -r _pid; do
    [ -n "$_pid" ] || continue
    if kill -0 "$_pid" 2>/dev/null; then
      _alive=$((_alive + 1))
      _live_pids="$_live_pids$_pid,"
    fi
  done <<EOF
$_pids
EOF
  _dead=$((_base - _alive))

  _here=0
  _unread=0
  if [ -n "$_live_pids" ] && [ -n "$_target" ]; then
    _csv=${_live_pids%,}
    mk_project_root_set "$_target"
    _troot=$MK_ROOT
    # Still ONE lsof for the whole base set. What changed is the comparison: each answer
    # is mapped to its project with the same function the record is written against, and
    # never with a second rule written out here. The mapping runs in this shell, so a
    # register of any size costs no forks at all.
    #
    # lsof can be missing, refused or cut short, and what comes back is then no line at
    # all. That arrives as the same 0 every other failure produces, so no caller has to
    # guard against a word where it asked for a number, and mk_here_is_measured is what
    # tells that 0 apart from an empty project.
    while IFS= read -r _pcwd; do
      [ -n "$_pcwd" ] || continue
      mk_lsof_path_set "$_pcwd" || { _unread=1; continue; }
      mk_project_root_set "$MK_LSOF_PATH"
      mk_same_root "$MK_ROOT" "$_troot" && _here=$((_here + 1))
    done <<EOF
$(lsof -a -p "$_csv" -d cwd -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2) }')
EOF
    case "$_here" in ''|*[!0-9]*) _here=0 ;; esac
  fi

  _sumok=0
  [ $((_alive + _dead)) -eq "$_base" ] && [ "$_unread" != 1 ] && _sumok=1
  printf '%s %s %s %s %s\n' "$_base" "$_alive" "$_dead" "$_here" "$_sumok"
}

# mk_cwd_probe_answers -> true when the instrument that places a process in a directory
# answers at all. It is asked about this very shell, which is alive and has a working
# directory by construction, so an empty answer is the instrument and never the finding.
mk_cwd_probe_answers() {
  [ -n "$(lsof -a -p $$ -d cwd -Fn 2>/dev/null)" ]
}

# mk_here_is_measured <base> <alive> <dead> <here> <sumok>
#   True when the here field of a census is a count that was taken, false when it is the
#   absence of one. A register that is not there, a register nothing in answers, a sum
#   that does not add up, a name lsof printed that could not be read back, and an lsof
#   that is missing or refused all arrive as the same 0
#   that an empty directory arrives as. A caller that cannot tell those apart reads a
#   failed measurement as a fact about the world.
mk_here_is_measured() {
  [ "${5:-0}" = 1 ] || return 1
  [ "${1:-0}" -ge 1 ] 2>/dev/null || return 1
  [ "${2:-0}" -ge 1 ] 2>/dev/null || return 1
  # A zero is a finding only if the instrument answered, and the probe is asked only when
  # it has to be: any count above zero has already proved that it did.
  [ "${4:-0}" -ge 1 ] 2>/dev/null || mk_cwd_probe_answers || return 1
  return 0
}

# THE DOOR TO THE KIT'S OWN FILES. A file under .claude/ lies in the project and belongs to
# whoever ships the project, so a foreign repository can bring a link, a pipe or a directory
# under any of these names, and the hook runs as soon as its owner types `git status`.
# Measured 2026-11-06 at 9dc29df: a link overwrote its target at the first call of a day, a
# marker linked to a secret bought a crossing and put the secret on the record, a role file
# read through a link stood the guard down, a directory as marker bought three crossings
# because rm -f failed in silence, and a pipe held five hooks past their budget of 10 s.
#
# THE RULE: the kit reads and writes its own files only as plain files inside the project, and
# what fails that rule is treated as absent. The verdict is never taken from such a file, so
# the refusal stands whatever lies there. every_site_under_claude_goes_through_the_door in
# tests/run.sh derives the places and holds each of them to this block.
#
# TWO HALVES, AND THE LINE BETWEEN THEM IS THE PRICE OF A PROCESS.
#
# A WRITE, AND EVERY READ THAT DECIDES A CROSSING OR RUNS ON THE STOP PATH, GOES THROUGH PYTHON
# HERE, where O_NOFOLLOW and O_NONBLOCK are real: the open itself refuses a link and does not
# wait on a pipe, and fstat on the open file answers for what was opened. So nothing can be
# swapped in between a test and a use, which is what a shell test ahead of a redirection
# cannot promise. From the project root down, each directory is opened with O_NOFOLLOW from
# the one above it. It costs no process on the stop path and none on the silent path. It costs
# one on the first call of a day and on a declared crossing, measured below.
#
# THE READS ON THE SILENT PATH, the role file and the seen file, ARE ASKED OF THE SHELL:
# mk_kit_usable, builtins only. One more python on every tool call is the price of the first
# call of a day, which pays it now: 130 ms became 157 ms, against 76 ms for the silent path
# [measured 2026-11-06, median of 20 alternating runs, 9dc29df against this], so +27 ms on 76,
# a third on top of every turn, and this kit will not pay that. What it costs is named: a test
# and an open with a gap between them. Whoever swaps a pipe into that gap has a process running
# on this machine already, and can hold the hook for the budget and no further. What such a
# read can return is a date or a record it could as well have written as a plain file.
MK_PY_DOOR='
import os, stat

def mk_home(root):
    if not root:
        raise OSError("no record here")
    base = os.path.realpath(root)
    home = os.path.realpath(os.path.join(root, ".claude"))
    if not home.startswith(base + os.sep):
        raise OSError(".claude leaves the project")
    fd = os.open(base, os.O_RDONLY | os.O_DIRECTORY)
    for part in home[len(base) + 1:].split(os.sep):
        below = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        os.close(fd)
        fd = below
    return fd

MK_LOG_NAME = "manager-kit.log"
MK_KIT_IGNORE = (b"/.claude/manager-kit.log*", b"/.claude/manager-kit.seen", b"/.claude/manager-kit.role", b"/.claude/manager-exception")

def mk_exclude(root):
    # Called once, right after this process made the log, and it never raises. The line goes into
    # .git/info/exclude of the project, which is a file of the repository and not of the working
    # tree, so nothing shows in git status and nothing travels to a clone. Every step goes down from
    # the project with O_NOFOLLOW and O_NONBLOCK like the rest of this door: a .git that is a file
    # (a linked worktree, a submodule) or a link, an info that is a link, an exclude that is a link,
    # a pipe or a directory are not followed, not waited on and not written.
    try:
        base = os.open(os.path.realpath(root), os.O_RDONLY | os.O_DIRECTORY)
        git = os.open(".git", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=base)
        try:
            info = os.open("info", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=git)
        except FileNotFoundError:
            os.mkdir("info", 0o755, dir_fd=git)
            info = os.open("info", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=git)
        fd = os.open("exclude", os.O_RDWR | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o644, dir_fd=info)
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > (1 << 20):
            return
        have = os.read(fd, 1 << 20)
        missing = [line for line in MK_KIT_IGNORE if line not in have.split(b"\n")]
        if not missing:
            return
        lead = b"" if not have or have.endswith(b"\n") else b"\n"
        os.write(fd, lead + b"# manager-kit: its own files, and the log can hold part of a command\n" + b"\n".join(missing) + b"\n")
    except Exception:
        pass

def mk_file(home, name, flags):
    flags |= os.O_NOFOLLOW
    flags |= os.O_NONBLOCK
    if name == MK_LOG_NAME and flags & os.O_CREAT:
        # A LOG THAT THIS CALL MAKES is private, and only then is the exclusion written, with the lines of all
        # four files of the kit. A log that was there keeps its mode and its record, whatever an older version
        # made of it, and the lines are not put back.
        try:
            fd = os.open(name, flags | os.O_EXCL, 0o600, dir_fd=home)
            mk_exclude(os.environ.get("MK_DOOR_ROOT", ""))
        except FileExistsError:
            fd = os.open(name, flags, 0o600, dir_fd=home)
    else:
        fd = os.open(name, flags, 0o666, dir_fd=home)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_nlink > 1:
        # No plain file, or a plain file with a second name: a write to a hard link changes the file at
        # the other end, and O_NOFOLLOW does not see one.
        os.close(fd)
        raise OSError("no plain file with one name")
    return fd
'

# THE REDACTOR. The record is kept in the project and is meant to be committed with it, so a secret
# in a refused command must not reach it. Measured 2026-11-06 at f21aca6 in a fresh project:
# `export DB_PASSWORD=hunter2-FAKE; echo x > src/a.py` stood in manager-kit.log whole, in the
# refusal, and in the reason of a declared crossing, in a file of mode 0644 that git add -A staged.
#
# IT RUNS AFTER THE VERDICT AND AT THE PLACES WHERE TEXT IS WRITTEN OR PRINTED, never before:
# classify_bash reads the whole command as it was, because a value can be the very path that makes
# a write work. `API_KEY=src/a.py; echo x > $API_KEY` is work, and with the value blacked out first
# it reads bookkeeping, which is a silent pass. It runs BEFORE THE CUT to 400 or 300 characters, so
# a cut cannot leave half a value standing. It sees the first 64 KB, which is far more than any cut.
#
# WHAT IS BLACKED OUT, and only the value, so the verb, the path and the name stay readable:
#   NAME=value        a name that holds PASSWORD, PASSWD, SECRET, TOKEN, KEY or CREDENTIAL as a whole word
#                     (DB_PASSWORD, apiKey, KEYS) or ends in one (GITHUBTOKEN), bare, after export or -e, in
#                     quotes, lower case, and in a query string. KEY at the end of a glued name counts only
#                     behind API, ACCESS, SECRET, PRIVATE, AUTH, SSH, MASTER, LICENSE, SIGNING or ENCRYPTION
#                     (APIKEY, not MONKEY); a word glued to the start or the inside (KEYMAP, TOKENIZERS_PARALLELISM)
#                     is no secret. Not when the name ends in _FILE, _PATH, _DIR or _NAME (the value is a place or
#                     a label), and not when the value starts with $ (it is another name or a command)
#   "name": "value"   in JSON, and name: value in YAML at the start of a line or in a string. There only the LAST
#                     word of the name counts (token_type, key_id, business_key keep their value), a plural is a
#                     count (max_tokens), and a value without quotes must hold a digit and a letter or be 16
#                     characters long (str, required, 1024 are no secrets)
#   Authorization:    and Proxy-Authorization:, when -H or --header stands before it, a scheme word stands after it
#                     (Bearer, Basic, Digest, Token, Negotiate, NTLM, OAuth) or the name is a quoted key; the scheme
#                     word stays. Without quotes the value ends at the blank. The same word in prose or in a file
#                     name is no header. X-...-Key, -Token, -Secret headers are read as before
#   Bearer value      alone, when the value holds a digit and is 8 characters or more
#   --password value  --passwd, --token, --secret, --api-key, also with a prefix word (--db-password),
#                     with = or a blank, but not --password-stdin or --token-file
#   mysql -pvalue     only after mysql, mysqldump, mariadb and their kin, where -p glued to a value is
#                     the password and nothing else
#   curl -u user:pw   and --user, --proxy-user, -U, only after curl: the password, not the user
#   sshpass -p value  right behind sshpass, also glued (-pvalue)
#   user:password@    in a URL, the password only
#   sk-..., ghp_..., github_pat_..., AKIA..., ASIA..., xoxb-..., xapp-..., AIza..., a JWT (eyJ..eyJ..sig)  by the form
#   -----BEGIN ... PRIVATE KEY-----   the body up to the END line, when it is base64 text and nothing else
# A quote inside a value that has no quote around it (--password=ab"cd") belongs to the value when the value so
# far is a plain word, the quoted piece is plain too (letters, digits and . _ ~ + / @ % ! ^ * # -) and the word
# then ends clean. A quote that is left over was the closing quote of a string the name stands in, and ends the
# value as before.
# WHAT IT LEAVES, and README.md says so: a secret in a position with no name, a value that starts with $, a
# Bearer value without a digit, name = value with blanks around the =, a bare value that is a plain word or a
# number, key files with headers, anything this list does not name. A name with the word as a whole segment
# (KEY_ID, max_tokens) is blacked out, which is the wrong direction and the cheap one.
#
# IT CANNOT TAKE THE REFUSAL DOWN. mk_safe answers a short fixed text when the redaction fails, so a
# line that cannot be blacked out is shorter and never open, and the refusal that carries it still
# goes out. The one place that must not guess, the reason of a declared crossing, does not pass.
#
# NO SINGLE QUOTE IN THIS TEXT, comments included: it lives inside shell quotes.
MK_PY_REDACT='
import re

MK_REDACT_WORDS = ("PASSWORD", "PASSWD", "SECRET", "TOKEN", "KEY", "CREDENTIAL")
MK_REDACT_NOT = ("_FILE", "_PATH", "_DIR", "_NAME")
MK_REDACT_BEFORE_KEY = ("API", "ACCESS", "SECRET", "PRIVATE", "AUTH", "SSH", "MASTER", "LICENSE", "SIGNING", "ENCRYPTION")
MK_REDACT_FLAGS = ("password", "passwd", "token", "secret", "api-key", "apikey")
MK_REDACT_SCHEMES = ("Bearer", "Basic", "Digest", "Token", "Negotiate", "NTLM", "OAuth")
MK_REDACT_MARK = "[redacted]"
MK_REDACT_WINDOW = 65536

_NAME_EQ = re.compile(r"(?<![^\s;&|(){}`:?,\"\x27])([A-Za-z_][A-Za-z0-9_]*)=")
_SEGMENT = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+")
_FLAG = re.compile(r"(?<![A-Za-z0-9_-])--(?:[a-z0-9]+-)*(?:" + "|".join(MK_REDACT_FLAGS) + r")(?:=|[ \t]+(?=[^\s-]))", re.I)
_HEADER = re.compile(r"(?<![A-Za-z0-9_-])(?:(?:Proxy-)?(Authorization)([\"\x27]?)|X-[A-Za-z-]*(?:Key|Token|Secret)[\"\x27]?)[ \t]*:[ \t]*([\"\x27]?)", re.I)
_HEADER_FLAG = re.compile(r"(?:^|[\s;&|(=])(?:-[A-Za-z]*H|--header)(?:=|[ \t]+)?\$?[\"\x27]?$")
_HEADER_SCHEME = re.compile("(?:" + "|".join(MK_REDACT_SCHEMES) + r")[ \t]+(?=\S)", re.I)
_SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9-]*[ \t]+(?=\S)")
_BEARER = re.compile(r"(?<![A-Za-z0-9_-])(?i:Bearer)[ \t]+(?=[A-Za-z0-9._~+/=-]*\d)([A-Za-z0-9._~+/=-]{8,})")
_MYSQL = re.compile(r"(?<![A-Za-z0-9_.-])(?:mysql[a-z_]*|mariadb[a-z_-]*)(?=[ \t])")
_MYSQL_P = re.compile(r"(?<=[ \t])-p(?=\S)")
_CURL = re.compile(r"(?<![A-Za-z0-9_.-])curl(?=[ \t])")
_CURL_USER = re.compile(r"(?<=[ \t])(?:-[A-Za-z]*[uU][ \t]+|--(?:proxy-)?user(?:=|[ \t]+))(?=\S)")
_SSHPASS = re.compile(r"(?<![A-Za-z0-9_.-])sshpass[ \t]+(?:-[evV][ \t]+)*-p(?:[ \t]+(?=\S)|(?=\S))")
_URL = re.compile(r"(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]*://[^\s/@:\"\x27]*:([^\s/@\"\x27]+)@")
_KV_JSON = re.compile(r"(?<![A-Za-z0-9_])([\"\x27])(?P<name>[A-Za-z_][A-Za-z0-9_.-]*)\1[ \t]*:[ \t]*")
_KV_YAML = re.compile(r"(?:^[ \t]*(?:-[ \t]+)?|(?<=[\"\x27]))(?P<name>[A-Za-z_][A-Za-z0-9_.-]*)[ \t]*:[ \t]+", re.M)
_KV_WORD = re.compile(r"[A-Za-z0-9._~+/@%!-][A-Za-z0-9._~+/=:@%!-]*")
_PEM = re.compile(r"-----BEGIN [A-Z0-9 ]{0,30}PRIVATE KEY(?: BLOCK)?-----([A-Za-z0-9+/=:,.\s\\]+?)-----END [A-Z0-9 ]{0,30}PRIVATE KEY(?: BLOCK)?-----")
_KNOWN = (
    re.compile(r"(?<![A-Za-z0-9_./-])sk-(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{20,}"),
    re.compile(r"(?<![A-Za-z0-9_])gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"(?<![A-Za-z0-9_])github_pat_[A-Za-z0-9_]{22,}"),
    re.compile(r"(?<![A-Za-z0-9])(?:AKIA|ASIA)[0-9A-Z]{16}(?![A-Za-z0-9])"),
    re.compile(r"(?<![A-Za-z0-9_-])xox[abposr]-(?=[A-Za-z0-9-]*\d)[A-Za-z0-9-]{10,}"),
    re.compile(r"(?<![A-Za-z0-9_-])xapp-\d-[A-Za-z0-9-]{10,}"),
    re.compile(r"(?<![A-Za-z0-9_-])AIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_-])"),
    re.compile(r"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{6,}\.eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}"),
)
_SEGMENT_END = re.compile(r"[;&|\n]")
_HEADER_END = re.compile(r"[\"\x27\r\n]")
_HEADER_END_BARE = re.compile(r"[\s;&|<>()`\"\x27]")
_DQ = re.compile(r"[^\"\\]*(?:\\.[^\"\\]*)*\"", re.S)
_RUN = re.compile(r"[^\s;&|<>()`\"\x27\\]+")
_GLUE = re.compile(r"\"[A-Za-z0-9._~+/@%!^*#-]*\"|\x27[A-Za-z0-9._~+/@%!^*#-]*\x27")
_PLAIN = re.compile(r"[A-Za-z0-9._~+/@%!^*#-]+")

def mk_secret_name(name):
    # A name holds a secret word when a whole segment of it is the word (DB_PASSWORD, apiKey, KEYS), or the
    # word ends a segment (GITHUBTOKEN). KEY glued at the end counts only behind a word that says what it
    # opens (APIKEY, not MONKEY). A word glued at the start or inside (KEYMAP, TOKENIZERS) does not count.
    for seg in _SEGMENT.findall(name):
        seg = seg.upper()
        for s in ((seg, seg[:-1]) if seg.endswith("S") else (seg,)):
            for w in MK_REDACT_WORDS:
                if s == w or (s.endswith(w) and (w != "KEY" or s[:-3] in MK_REDACT_BEFORE_KEY)):
                    return True
    return False

def mk_kv_name(name):
    # The name of a key in JSON or YAML text. There only the LAST word of the name counts, so
    # token_type, key_id and business_key keep their values, and a plural (max_tokens) is a count.
    # KEY is a secret there only behind a word that says what it opens (api_key, not primary_key).
    segs = [s.upper() for s in _SEGMENT.findall(name)]
    while segs and segs[-1].isdigit():
        segs.pop()
    if not segs:
        return False
    last = segs[-1]
    for w in MK_REDACT_WORDS:
        if last == w:
            return w != "KEY" or (len(segs) > 1 and segs[-2] in MK_REDACT_BEFORE_KEY)
        if last.endswith(w) and (w != "KEY" or last[:-3] in MK_REDACT_BEFORE_KEY):
            return True
    return False

def mk_word_end(text, i, quote):
    # the end of the value that starts at i: a quoted string to its closing quote, and a quote that
    # never closes ends at the end of the line; anything else runs to a blank, a separator, a quote or
    # the end, so the closing quote of a string the name stands in is never part of the value. Outside
    # such a string a quoted piece of plain characters belongs to the value (ab"cd") when the value so far
    # is plain too and the word then ends clean; a quote left over means it was the closing quote of an
    # outer string.
    n = len(text)
    ch = text[i] if i < n else ""
    if ch in "\"\x27" and ch != quote:
        if ch == "\"":
            c = _DQ.match(text, i + 1)
            k = c.end() - 1 if c else -1
        else:
            k = text.find(ch, i + 1)
        if k >= 0:
            return k + 1
        e = text.find("\n", i)
        return n if e < 0 else e
    j = i
    glued = -1
    while j < n:
        c = _RUN.match(text, j)
        if c:
            j = c.end()
        elif text[j] == "\\":
            j += 2
        else:
            g = None if glued < 0 and not _PLAIN.fullmatch(text, i, j) else _GLUE.match(text, j)
            if not g:
                break
            if glued < 0:
                glued = j
            j = g.end()
    j = min(j, n)
    if glued >= 0 and j < n and text[j] in "\"\x27":
        return glued
    return j

def mk_kv_end(text, i):
    # the end of the value of a key: value line, or -1 when there is none to black out
    n = len(text)
    if i >= n:
        return -1
    ch = text[i]
    if ch in "\"\x27":
        end = mk_word_end(text, i, "")
        return -1 if end - i <= 2 or text[i + 1] == "$" else end
    c = _KV_WORD.match(text, i)
    if not c:
        return -1
    j = c.end()
    if j < n and text[j] not in " \t\r\n,;})]#\\\"\x27":
        return -1
    w = c.group()
    return j if len(w) >= 16 or (any(d.isdigit() for d in w) and not w.isdigit()) else -1

def mk_redact(text):
    text = text[:MK_REDACT_WINDOW]
    n = len(text)
    spans = []
    for m in _NAME_EQ.finditer(text):
        up = m.group(1).upper()
        if not any(w in up for w in MK_REDACT_WORDS) or up.endswith(MK_REDACT_NOT):
            continue
        if not mk_secret_name(m.group(1)):
            continue
        # A bare key= is a keyword argument, a sort key, a tag: four of 2126 real commands lost a word to it.
        # It is a secret only in a query string, where a service takes its key as ?key=.
        if m.group(1) in ("key", "Key") and (m.start() == 0 or text[m.start() - 1] not in "?&"):
            continue
        quote = text[m.start() - 1] if m.start() and text[m.start() - 1] in "\"\x27" else ""
        i = m.end()
        if i >= n:
            continue
        ch = text[i]
        if ch in "\"\x27":
            end = mk_word_end(text, i, quote)
            if end - i <= 2 or text[i + 1] == "$":
                continue
        else:
            if ch == "$":
                continue
            end = mk_word_end(text, i, quote)
        if end > i:
            spans.append((i, end))
    for pat in (_KV_JSON, _KV_YAML):
        for m in pat.finditer(text):
            if mk_kv_name(m.group("name")):
                end = mk_kv_end(text, m.end())
                if end > m.end():
                    spans.append((m.end(), end))
    for m in _FLAG.finditer(text):
        i = m.end()
        if i < n and text[i] != "$":
            end = mk_word_end(text, i, "")
            if end > i:
                spans.append((i, end))
    done = 0
    for m in _HEADER.finditer(text):
        if m.start() < done:
            continue
        i = m.end()
        bare = False
        if m.group(1):
            # Authorization is a header when a header flag, a scheme word or a quoted key says so; the same
            # word in prose or in a file name is not. A header with none of the quotes ends at the blank.
            lead = text[max(0, m.start() - 40):m.start()]
            if not (m.group(2) or _HEADER_FLAG.search(lead) or _HEADER_SCHEME.match(text, i)):
                continue
            bare = not (m.group(2) or m.group(3) or lead[-1:] in ("\"", "\x27"))
        if bare:
            s = _HEADER_SCHEME.match(text, i)
            if s:
                i = s.end()
            f = _HEADER_END_BARE.search(text, i)
            e = f.start() if f else n
        else:
            f = _HEADER_END.search(text, i)
            e = f.start() if f else n
            s = _SCHEME.match(text, i, e)
            if s:
                i = s.end()
        done = e
        if e > i and text[i:e].strip():
            spans.append((i, e))
    for m in _BEARER.finditer(text):
        spans.append((m.start(1), m.end(1)))
    done = 0
    for m in _MYSQL.finditer(text):
        if m.start() < done:
            continue
        f = _SEGMENT_END.search(text, m.end())
        e = f.start() if f else n
        done = e
        for p in _MYSQL_P.finditer(text, m.end(), e):
            end = mk_word_end(text, p.end(), "")
            if end > p.end():
                spans.append((p.end(), end))
    done = 0
    for m in _CURL.finditer(text):
        if m.start() < done:
            continue
        f = _SEGMENT_END.search(text, m.end())
        e = f.start() if f else n
        done = e
        for p in _CURL_USER.finditer(text, m.end(), e):
            end = mk_word_end(text, p.end(), "")
            k = text.find(":", p.end(), end)
            if k >= 0:
                k += 1
                if text[p.end()] in "\"\x27" and end - 1 > k and text[end - 1] == text[p.end()]:
                    end -= 1
                if end > k and text[k] != "$":
                    spans.append((k, end))
    for m in _SSHPASS.finditer(text):
        i = m.end()
        if i < n and text[i] != "$":
            end = mk_word_end(text, i, "")
            if end > i:
                spans.append((i, end))
    for m in _URL.finditer(text):
        spans.append((m.start(1), m.end(1)))
    for m in _PEM.finditer(text):
        if m.group(1).strip():
            spans.append((m.start(1), m.end(1)))
    for pat in _KNOWN:
        for m in pat.finditer(text):
            spans.append((m.start(), m.end()))
    if not spans:
        return text
    spans.sort()
    out = []
    pos = 0
    a, b = spans[0]
    merged = []
    for s, e in spans[1:]:
        if s <= b:
            b = max(b, e)
        else:
            merged.append((a, b))
            a, b = s, e
    merged.append((a, b))
    for s, e in merged:
        out.append(text[pos:s])
        out.append(MK_REDACT_MARK)
        pos = e
    out.append(text[pos:])
    return "".join(out)

def mk_safe(text, cut):
    try:
        return mk_redact(text)[:cut]
    except Exception:
        return "[withheld: the redaction failed]"
'

# mk_record_home <root> -> true when <root>/.claude may hold the kit's files: not the home
# directory or anything above it, and a .claude that is a directory of this project.
#
# A .claude THAT IS A LINK IS MEASURED AND NOT REFUSED OUT OF HAND. A link to a directory inside
# the project is a way of laying a project out, and it keeps everything it had. A link that
# leaves the project cannot be told apart from one a foreign repository brought along, so
# nothing is read or written through it, and mk_record_trouble says so out loud. The fork is
# only taken when the link is there; a plain .claude pays two builtin tests.
mk_record_home() {
  mk_root_is_barred "${1-}" && return 1
  if [ -L "${1-}/.claude" ]; then
    _rh_root=$(CDPATH= cd -- "${1-}" 2>/dev/null && pwd -P) || return 1
    _rh_home=$(CDPATH= cd -- "${1-}/.claude" 2>/dev/null && pwd -P) || return 1
    case "$_rh_home/" in "$_rh_root"/?*) return 0 ;; esac
    return 1
  fi
  [ ! -e "${1-}/.claude" ] || [ -d "${1-}/.claude" ]
}

# mk_record_trouble <root> -> one sentence for the person when the kit cannot keep its record
# here, and nothing at all when it can, so a plain project is told nothing and the role text
# stays at its budget. The refusal and both SessionStart hooks print it. Plain words only: the
# short form of the refusal puts this text into JSON as it stands.
mk_record_trouble() {
  if mk_root_is_barred "${1-}"; then
    printf '%s\n' "manager-kit keeps no record here: this is your home directory or lies above it, and its .claude is your Claude configuration, not a project. Nothing is logged, no role is recorded and no declaration can be spent. Start the session inside a project."
    return 0
  fi
  if ! mk_record_home "${1-}"; then
    printf '%s\n' "manager-kit keeps no record here: .claude is not a directory of this project, it is a link that leaves the project, a link to nothing, or a file, and the kit writes only inside the project. Nothing is logged, no role is recorded and no declaration can be spent. Make .claude a directory here, or a link to one inside the project."
    return 0
  fi
  for _rt_n in manager-kit.log manager-kit.role manager-kit.seen manager-exception; do
    if [ -L "${1-}/.claude/$_rt_n" ] || { [ -e "${1-}/.claude/$_rt_n" ] && [ ! -f "${1-}/.claude/$_rt_n" ]; }; then
      printf '%s\n' "manager-kit: .claude/$_rt_n is no plain file, it is a link, a pipe or a directory, so the kit does not use it. Remove it to have it back."
      return 0
    fi
  done
  for _rt_n in manager-kit.role manager-kit.seen; do
    if [ -f "${1-}/.claude/$_rt_n" ] && ! mk_kit_small "${1-}/.claude/$_rt_n"; then
      printf '%s\n' "manager-kit: .claude/$_rt_n is longer than $MK_KIT_SMALL bytes, so it is no such file and the kit does not use it. Remove it to have it back."
      return 0
    fi
  done
}

# mk_kit_usable <root>/.claude/<name> -> true when the shell may read that file: the record may
# live there, and the name is a plain file, not a link, a pipe or a directory. Asked ahead of
# every read the shell does itself. Builtins only, because the role file is read on every call.
mk_kit_usable() {
  mk_record_home "${1%/.claude/*}" || return 1
  [ ! -L "$1" ] || return 1
  [ -f "$1" ] || return 1
  [ -r "$1" ] || return 1
  mk_kit_small "$1"
}

# mk_kit_small <file> -> true when the file is no longer than MK_KIT_SMALL. Read with the shell's own read,
# which stops after that many characters whatever the file holds, so a 200 MB file costs what 4 KB cost and
# nothing is started. Characters and not bytes under a multibyte locale, which only makes it more generous.
mk_kit_small() {
  _ks_buf=""
  IFS= read -r -n $((MK_KIT_SMALL + 1)) -d '' _ks_buf 2>/dev/null < "$1"
  [ "${#_ks_buf}" -le "$MK_KIT_SMALL" ]
}

# mk_kit_make_home <root> -> makes .claude when the record may live there, and answers whether
# it may. A failed mkdir answers true, and the first write then finds out, as it always did.
mk_kit_make_home() {
  mk_record_home "${1-}" || return 1
  [ -d "${1-}/.claude" ] || mkdir -p "${1-}/.claude" 2>/dev/null
  return 0
}

# mk_kit_write <root> <name> [append] < text -> true when the text landed in that file. It
# replaces the file, or appends with append. A link, a pipe, a directory, a .claude out of the
# project and a barred root all come back false, and nothing was written anywhere.
mk_kit_write() {
  mk_root_is_barred "${1-}" && return 1
  MK_DOOR_ROOT=${1-} MK_DOOR_NAME=${2-} MK_DOOR_HOW=${3-replace} python3 -I -c "$MK_PY_DOOR"'
import sys
how = os.O_APPEND if os.environ["MK_DOOR_HOW"] == "append" else 0
fd = mk_file(mk_home(os.environ["MK_DOOR_ROOT"]), os.environ["MK_DOOR_NAME"], os.O_WRONLY | os.O_CREAT | how)
if not how:
    os.ftruncate(fd, 0)
os.write(fd, sys.stdin.buffer.read())
' 2>/dev/null
}

# mk_kit_spend <root> <name> -> the reason on stdout and status 0 when the marker was a plain
# file with something in it, young enough, AND IS GONE NOW. The status says what happened else:
#   2  older than five minutes, discarded, and it buys nothing
#   3  empty, left where it is, and it buys nothing
#   1  it cannot be spent: no plain file, or .claude does not let it be removed
#
# A MARKER THAT CANNOT BE SPENT BUYS NOTHING, and the order below is the whole of that: the
# removal comes first and the reason goes out only after it. Until 2026-11-06 the crossing was
# booked and rm -f asked afterwards, in silence. With a directory as marker, or a .claude
# without write permission, that was three crossings out of one marker [measured, 9dc29df],
# and with no log yet, three with no line anywhere.
#
# Only the first 64 KB are read: the record keeps 400 characters of a reason, and a marker of
# any size has to cost the same.
mk_kit_spend() {
  mk_root_is_barred "${1-}" && return 1
  MK_DOOR_ROOT=${1-} MK_DOOR_NAME=${2-} python3 -I -c "$MK_PY_DOOR"'
import sys, time
name = os.environ["MK_DOOR_NAME"]
home = mk_home(os.environ["MK_DOOR_ROOT"])
fd = mk_file(home, name, os.O_RDONLY)
st = os.fstat(fd)
if st.st_size == 0:
    sys.exit(3)
if time.time() - st.st_mtime > 300:
    try:
        os.unlink(name, dir_fd=home)
    except OSError:
        pass
    sys.exit(2)
# Not cut here. The writer blacks the reason out and THEN cuts it to 400, and a cut made in this
# program would come first and could leave half a value for the writer to miss. This program starts
# without the redactor on purpose: importing re costs a declared crossing 20 ms [measured].
reason = os.read(fd, 65536).decode("utf-8", "replace").translate({10: " ", 31: " "})
os.unlink(name, dir_fd=home)
sys.stdout.buffer.write(reason.encode("utf-8", "replace"))
' 2>/dev/null
}

# mk_kit_names_setting <word> <root> -> 0 when a settings file of the project names <word>, 1 when none does,
# and 2 when none does in the first MK_SETTINGS_CAP bytes of the ones it read and one of them is longer, which
# is a different fact from 1 and is not reported as it.
# These two are not the kit's: the runtime follows a link here and the report has to see what
# the runtime sees, so a link is read, and all that leaves this function is one bit. What does
# not pass [ -f ] is not read, because grep waits on a pipe: measured 2026-11-06 at 9dc29df, a
# pipe named settings.json held both SessionStart hooks past their budget. grep -r was also
# what this asked until then, and BSD grep -r does not follow a link named on its command line,
# so a linked settings.json was reported as unset on macOS and read on GNU.
mk_kit_names_setting() {
  _ns_big=0
  for _ns_f in "${2-}/.claude/settings.json" "${2-}/.claude/settings.local.json"; do
    [ -f "$_ns_f" ] || continue
    _ns_head=$(dd if="$_ns_f" bs=$((MK_SETTINGS_CAP + 1)) count=1 2>/dev/null)
    case $_ns_head in *"${1-}"*) return 0 ;; esac
    [ "${#_ns_head}" -gt "$MK_SETTINGS_CAP" ] && _ns_big=1
  done
  [ "$_ns_big" = 0 ] || return 2
  return 1
}

# mk_log_event <root> <event> <tool> <subject> <reason> -> one line on the guard log, and true
# when it landed there.
#
# THE ONE SHAPE OF A LOG LINE, and it lives here for the reason the header of this file
# gives for the project root: this is the one file every hook and tools/manager-claim.sh
# already load. Five keys are read by tools/week-verdict.sh, by the guard's own two counts
# and by tests/run.sh. A second writer that types that shape again agrees on the day it is
# typed and drifts on the first rename, and the drift is silent: json.loads goes on
# parsing and rec.get() goes on answering None, so every number derived from the log gets
# quietly smaller. It arrived here from the append() in role-guard.sh, which now calls it.
#
# The log holds LINES, never a counter this process increments, so every number the kit
# reports is derived by counting them at read time and a lost write shows up as a smaller
# number rather than as a number that disagrees with its own history.
#
# It does NOT create the directory. Both callers have already made it, and a writer that
# creates a .claude/ of its own would put a log where no reader looks the first time a
# root is derived wrongly.
#
# THE OPEN MOVED INTO THE PROGRAM, out of a redirection of the shell, and it costs no process:
# this python ran already. The redirection is the one thing that cannot say O_NOFOLLOW.
mk_log_event() {
  _le_root=${1-}; _le_ev=${2-}; _le_tool=${3-}; _le_subject=${4-}; _le_reason=${5-}
  mk_root_is_barred "$_le_root" && return 1
  printf '%s\0%s\0%s\0%s' "$_le_ev" "$_le_tool" "$_le_subject" "$_le_reason" |
    MK_DOOR_ROOT=$_le_root python3 -I -c "$MK_PY_DOOR$MK_PY_REDACT"'
import sys, json, time
# Bytes and UTF-8, not the locale: under ISO8859-1 the path went on the record as mit-\xc3\xa4 in
# characters, and under US-ASCII the line was lost and the call that wrote it never knew [measured
# 2026-11-06 at 0bc14fe]. A byte that is no UTF-8 goes on the record as the escape it always was
# under C, so the shape of a line is what it was and every older log reads the same.
# NUL separates the fields: a shell variable cannot hold one, so no field can carry the separator in. It was
# the unit separator, and a tool name with one in it moved the fields after it [measured 2026-11-07].
parts = sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\x00", 3)
ev, tool, subject, reason = (parts + ["", "", "", ""])[:4]
# Blacked out AFTER the verdict, which the caller took from the whole text, and BEFORE the cut, so
# the cut cannot leave half a value. A redaction that fails writes a short fixed text, never the text.
subject = mk_safe(subject, 400)
reason = mk_safe(reason, 400)
line = json.dumps({
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "event": ev, "tool": tool,
    "subject": subject, "reason": reason,
}) + "\n"
fd = mk_file(mk_home(os.environ["MK_DOOR_ROOT"]), "manager-kit.log", os.O_WRONLY | os.O_APPEND | os.O_CREAT)
os.write(fd, line.encode())
' 2>/dev/null
}
