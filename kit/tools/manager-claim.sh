#!/usr/bin/env bash
# Move the coordinating role to THIS session, now, without closing anything.
#
# Until this existed the role was handed out by order of arrival and nothing else:
# mk_decide_role in hooks/_identity.sh claims it at SessionStart, with matcher
# startup|clear, and only for a session the census measured alone in the directory. Moving
# it meant closing every session in the working directory and starting exactly one. This
# is a SECOND way in, next to that one. The SessionStart route is untouched.
#
# WHAT THIS CAN PROVE ABOUT ITSELF, AND WHAT IT CANNOT. The three facts are not equally
# knowable and they are not treated as if they were:
#
#   the pid  is MEASURED. mk_own_pid walks the parent chain to the first ancestor that
#            owns a socket in the register, so it answers out of an ordinary Bash call and
#            not only out of a hook [measured 2026-09-07 from a plain Bash tool call: 3861,
#            and lsof -a -p 3861 -d cwd put that process in the working directory].
#
#   the cwd  is MEASURED, with the same instrument the census uses, and off the SESSION
#            process rather than off this shell. A shell that has been cd'd into a
#            subdirectory would otherwise leave the file where nothing reads it, and the
#            person would be told the role had moved. That directory is then mapped to its
#            PROJECT with mk_project_root, the same function the readers map theirs with:
#            the record is one file per project, and a claim written per directory would
#            be a claim the guard and the prompt hook never see.
#
#   the session id is MEASURED SINCE 0.15.0, and it is still never guessed. It used to say
#            NOT KNOWABLE HERE, on this measurement: "nothing in the environment of a Bash
#            call carries it [2026-09-07: env holds CLAUDE_CODE_HOST_SESSION_ID, which is
#            a different identifier, and nothing else that names the session]". That has
#            expired. Measured 2026-09-29 out of an ordinary Bash tool call under Claude
#            Code 2.1.284, CLAUDE_CODE_SESSION_ID holds the id the hooks are handed as
#            session_id, cross-checked against the path of that session's scratchpad,
#            which carries the same UUID. Whether it was reachable in September and missed
#            or arrived since is not decided here and does not matter to the repair: what
#            decides is that the value is checked before it is used, and the conditions
#            are under mk_claim_session_id below.
#
#            WHAT DOES NOT CHANGE IS THE DANGER. manager-stamp.sh compares the recorded
#            session id BEFORE the pid, so a second field naming somebody else hands them
#            the role and stands the real holder's guard down. The id is therefore taken
#            only when its shape is the shape the hooks are handed AND the environment
#            names the very process this command measured. Anything else falls back to
#            the placeholder, and the placeholder is exactly what shipped in 0.14.0: both
#            readers fall back to the pid on their own, manager-stamp.sh on the elif after
#            the session id, mk_guard_role in role-guard.sh on the line after its own, and
#            manager-stamp.sh writes the real id in on this session's NEXT PROMPT.
#
#            WHY THE FALLBACK IS NOT GOOD ENOUGH ON ITS OWN, which is the defect 0.15.0
#            repairs: while the placeholder stands the pid is the WHOLE of the identity in
#            this record, so a restart of this session erases it, and the next session to
#            start reads a dead pid as an empty chair and takes the role with no command
#            and no line on the record [measured 2026-09-11 against the delivered 0.12.0,
#            and again 2026-09-29 against 0.14.0 in a live project: "1453 claimed-by-pid"
#            from a take-over at 14:51:04, and after the restart the person had to type
#            the command a second time]. The prompt hook cannot close that: it heals the
#            placeholder on the next PROMPT, and in that day the process changed before
#            one arrived. With the id in the record from the take-over itself, the restart
#            is the ordinary case the prompt hook already handles.
#
#            AND WHAT IT STILL DOES NOT DO: a NEW CONVERSATION carries a different session
#            id and a different process. It reads this record as somebody else's and stays
#            a carrier, so it needs the command again. That is correct and it is printed
#            at the end rather than left for somebody to discover.
#
# It refuses rather than writing something it could not measure. A role file with an
# unusable first field is worse than no change at all: mk_guard_role answers manager for
# every session in the directory when it cannot parse the pid, and manager-stamp.sh answers
# carrier for every one of them, which is the split identity this kit has had to repair
# twice already.

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../hooks/_sessions.sh"

# The second field of the role file when this command writes it. It is deliberately not
# shaped like a session id, because both readers compare it against one: anything that
# could collide with a real id would hand the role to a session that never asked for it.
# It must not be empty either. mk_guard_role reads an empty second field as undecidable and
# answers manager for everybody, which is the fail-closed side of the guard firing on every
# session in the directory at once.
PLACEHOLDER=claimed-by-pid

# Its own event name, and the reason is a measurement rather than taste. GOAL.md counts
# false alarms out of the stop lines, and tools/week-verdict.sh counts stops, declared
# crossings and the days the guard proved it ran. A handover is none of those three. Filed
# as stop it would spend the week's budget on something that never stopped anybody.
EVENT=handover

if [ "$#" -gt 0 ]; then
  printf 'manager-claim takes no arguments: it reads the session it is running in.\n' >&2
  printf 'usage: bash manager-claim.sh\n' >&2
  exit 2
fi

# The working directory of one process, or nothing. Exactly one answer counts: lsof can be
# missing, refused or cut short, and every one of those comes back looking like an empty
# directory. A count that is not one is not a measurement, and the caller is told which of
# the two it got rather than being handed a path it cannot tell apart from a guess.
#
# AND WHAT LSOF PRINTS IS NOT YET THE PATH: mk_lsof_path_set in _sessions.sh has why. Taken as it
# stood, a take-over under C in mit-\xc3\xa4 made a directory of that name beside the project, put
# the role and the log in there, and said the role was now yours [measured 2026-11-06, 0bc14fe]. A
# name with a backslash in it did the same [measured 2026-11-07, 0464e26].
#
# THE ANSWER IS IN MK_CLAIM_CWD AND NOT ON STDOUT, because a command substitution removes a newline
# at the end of a name, and that reads as the sibling directory. Returns 0 (MK_CLAIM_CWD is the
# directory, or empty when lsof did not give exactly one) or 3: lsof printed a name that cannot be
# read back, and MK_CLAIM_PRINTED is what it printed. A name that ends in a newline is one too, and it stays
# refused. The root below no longer goes through a command substitution (MK-R5), so from a subdirectory of such a
# project the role lands in the project; the refusal for the directory itself was not asked to go and is kept.
MK_CLAIM_CWD=""
MK_CLAIM_PRINTED=""
mk_claim_pid_cwd() {
  MK_CLAIM_CWD=""
  _cpc=$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null |
    awk '/^n/ { n++; last = substr($0, 2) } END { if (n == 1) print last }')
  MK_CLAIM_PRINTED=$_cpc
  mk_lsof_path_set "$_cpc" || return 3
  case $MK_LSOF_PATH in *"$MK_NL") return 3 ;; esac
  MK_CLAIM_CWD=$MK_LSOF_PATH
  return 0
}

# One field of a JSON line, built without a JSON library. A backslash and a double quote
# are removed rather than escaped, and so is every control character, so nothing that is
# left can end the string early. Bytes above 127 stay: they are UTF-8 and the readers open
# the log as UTF-8. tests/run.sh parses the whole log with json.loads afterwards, so this
# writer is proved by a reader and not by looking at it.
#
# THE CUT COUNTS BYTES UNDER C, so it can fall inside a character, and a line with half a character
# in it is no UTF-8: json.loads refuses it and every reader of the log steps over it [measured
# 2026-11-06, a path over 400 bytes under C]. What is left of a broken character goes. This writer
# is about to need python3 anyway, and a field in ASCII never asks for it.
mk_claim_field() {
  _cf=$(printf '%s' "${1-}" | tr -d '\\"' | tr -d '\000-\037\177' | cut -c1-400)
  case $_cf in
    *[![:ascii:]]*)
      _cf2=$(printf '%s' "$_cf" | python3 -I -c 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read().decode("utf-8", "ignore").encode("utf-8"))' 2>/dev/null) && _cf=$_cf2 ;;
  esac
  printf '%s' "$_cf"
}

# mk_claim_session_id <the pid this command is about to record> -> the session id of the
# session it runs in, or NOTHING. Nothing is not a failure here: it is the placeholder,
# which is where this command stood before 0.15.0 and is always safe.
#
# TWO INDEPENDENT FACTS HAVE TO AGREE, and the pid is handed in rather than measured a
# second time so that the agreement is with the number that is actually going into field 1.
#
#   THE SHAPE IS DERIVED, NOT FELT. Counted 2026-09-29 over the 180 session transcripts
#   under ~/.claude/projects, whose file names ARE the session ids the hooks are handed
#   and whose sessionId field repeats the name: 180 of 180 are 36 characters, lowercase
#   hex grouped 8-4-4-4-12, and 180 of 180 also carry the UUID version nibble 4. The glob
#   below stops at the grouping and does NOT ask for the 4. An id of some later UUID
#   version would then be turned away, and being turned away costs the placeholder, which
#   is the state this command shipped in; asking for it buys nothing against the wrong
#   values that actually exist, because another session's id carries a 4 as well.
#
#   The ranges are read as ASCII and not as collation, which is the one way a glob of this
#   shape goes quietly wrong: in a locale that collates aAbBcC, [0-9a-f] also matches A to
#   F and an uppercase id would pass. Measured 2026-09-29 under bash 3.2.57 in LC_ALL=C,
#   en_US.UTF-8 and de_DE.UTF-8: the uppercase id was rejected in all three, and so was g.
#   No locale is pinned here because none of the three needed one.
#
#   THE HOST ID IS NOT THIS FIELD AND IS NOT READ. CLAUDE_CODE_HOST_SESSION_ID is the same
#   UUID with a local_ prefix [measured 2026-09-29: local_abf16e4e-0c16-401a-b7e2-2406
#   95ea9c8e beside abf16e4e-0c16-401a-b7e2-240695ea9c8e], so the 2026-09-07 reading of it
#   as "a different identifier" was wrong. Stripping the prefix is still not done: that
#   would be a guess about the shape of a variable nobody here has measured over more than
#   one session, and the glob refuses the prefixed form outright.
#
#   THE SECOND FACT IS THAT THE ENVIRONMENT IS DESCRIBING THIS SESSION. CLAUDE_PID names
#   the session process [measured 2026-09-29: CLAUDE_PID 7875, mk_own_pid answered 7875
#   walking the parent chain out of the same Bash call, and CLAUDE_CODE_MESSAGING_SOCKET
#   was /tmp/cc-socks/7875.sock, the very file mk_own_pid looks for]. An environment
#   inherited from somewhere else carries an id that belongs to somewhere else, and that
#   is the one value that must never be written. Where CLAUDE_PID is missing, unreadable
#   or not the pid measured here, the id is not taken. That is stricter than the day it
#   was written requires, and the whole of what it costs is the placeholder.
#
#   A SUBAGENT SEES ITS PARENT'S ID, measured rather than assumed. Run from a handed-out
#   hand on 2026-09-29, CLAUDE_CODE_SESSION_ID was abf16e4e-0c16-401a-b7e2-240695ea9c8e
#   and CLAUDE_PID was 7875, both identical to what the coordinating session measured for
#   itself. So a take-over typed inside a hand records the session whose hand it is, which
#   is the same session mk_own_pid already writes into field 1 today, because the parent
#   chain of a subagent's Bash call leads to that same process. The two fields agree and
#   neither names a session that never asked. CLAUDE_CODE_CHILD_SESSION is NOT a way to
#   tell a hand apart: it was 1 in the subagent and 1 in the coordinating session of the
#   same desktop app, so it marks a CLI under a host and not a delegation. It is not read.
mk_claim_session_id() {
  case "${CLAUDE_PID-}" in
    ''|*[!0-9]*) return 0 ;;
    *) [ "$CLAUDE_PID" = "${1-}" ] || return 0 ;;
  esac
  case "${CLAUDE_CODE_SESSION_ID-}" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      printf '%s\n' "$CLAUDE_CODE_SESSION_ID" ;;
  esac
  return 0
}

MYPID=$(mk_own_pid)
case "$MYPID" in
  ''|*[!0-9]*)
    printf 'manager-kit: REFUSED, and nothing was written.\n\n'
    printf 'The role file has to name a pid and this command could not find one.\n'
    printf 'mk_own_pid walks the parent chain for a session that owns a socket in one of\n'
    printf 'the registers below, and no ancestor of this shell owns one, so this command\n'
    printf 'cannot say which session it is running in:\n'
    # EVERY REGISTER AND NOT THE FIRST ONE. The register is derived from the platform
    # since 0.18.0 and there is more than one candidate, so a refusal that named only one
    # of them would send a reader who is already stuck to a directory the runtime was
    # never going to use. Read out of the one derivation in _sessions.sh rather than
    # rebuilt here, and walked with the same cut, so this cannot drift from what
    # mk_own_pid actually looked in.
    _mc_rest=$MK_SOCKET_DIRS
    while [ -n "$_mc_rest" ]; do
      _mc_d=${_mc_rest%%"$MK_NL"*}
      case $_mc_rest in *"$MK_NL"*) _mc_rest=${_mc_rest#*"$MK_NL"} ;; *) _mc_rest="" ;; esac
      [ -n "$_mc_d" ] && printf '  %s\n' "$_mc_d"
    done
    printf '\n'
    printf 'A role file whose pid cannot be parsed is worse than no change: the guard\n'
    printf 'then answers manager for every session in this directory and the prompt hook\n'
    printf 'answers carrier for every one of them. The record was left exactly as it is.\n'
    exit 2
    ;;
esac

# Asked once, after the pid it is checked against is known to be a pid, and kept in one
# variable from here on. Two calls could answer differently if the environment changed
# under the command, and the report at the foot has to describe the record that was
# written and not a second reading of the world.
SID=$(mk_claim_session_id "$MYPID")
SID_MEASURED=1
if [ -z "$SID" ]; then
  SID_MEASURED=0
  SID=$PLACEHOLDER
fi

MEASURED_DIR=1
mk_claim_pid_cwd "$MYPID"
if [ "$?" = 3 ]; then
  printf 'manager-kit: REFUSED, and nothing was written.\n\n'
  printf 'lsof prints the working directory of this session as\n\n  %s\n\n' "$MK_CLAIM_PRINTED"
  printf 'and that name cannot be read back into the directory it is. lsof writes a control\n'
  printf 'character as ^ and a letter, the same as a ^ in a name, and a name that ends in a\n'
  printf 'newline does not pass through the shell. The role file would land in a directory\n'
  printf 'that is not this project, so none was written. Start the session in a directory\n'
  printf 'whose name holds no such character.\n'
  exit 2
fi
SESSION_DIR=$MK_CLAIM_CWD
if [ -z "$SESSION_DIR" ]; then
  MEASURED_DIR=0
  SESSION_DIR=$PWD
fi

# AND THE RECORD BELONGS TO THE PROJECT, not to the directory the session stands in. This
# is the sixth reader of that one file, next to the three carriers and the guard, and a
# reader that anchors it anywhere else hands the role to a session the others cannot see.
# Derived with the same function they use, so there is one answer to the question and not
# two.
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name.
mk_project_root_set "$SESSION_DIR"; ROOT=$MK_ROOT

RF=$ROOT/.claude/manager-kit.role
LOG=$ROOT/.claude/manager-kit.log

# Read exactly the way the two readers read it, with the same one-line awk, so this command
# and the hooks cannot come to different conclusions about the same file.
PREVPID=""
PREVSID=""
if mk_kit_usable "$RF"; then
  PREVPID=$(awk 'NR==1 {print $1}' "$RF" 2>/dev/null)
  PREVSID=$(awk 'NR==1 {print $2}' "$RF" 2>/dev/null)
fi

# WHETHER FIELD 1 IS A PID AT ALL is mk_field1_is_pid's to say, in _sessions.sh, the one
# place the hooks ask too, so this line and theirs cannot name one byte two ways. Until
# 2026-11-03 this command asked an arm of its own without 0*, kill -0 0 succeeded, and a
# record reading "0 <id>" was handed over as "previous 0 alive".
PREVSTATE=none
if [ -e "$RF" ]; then
  if ! mk_field1_is_pid "$PREVPID"; then PREVSTATE=unusable
  elif kill -0 "$PREVPID" 2>/dev/null; then PREVSTATE=alive
  else PREVSTATE=gone
  fi
fi

say_where() {
  if [ "$MEASURED_DIR" = 1 ] && [ "$SESSION_DIR" != "$PWD" ]; then
    printf '\nThis shell stands in %s. The session itself stands in\n' "$PWD"
    printf '%s, and the session is what the hooks are handed.\n' "$SESSION_DIR"
  elif [ "$MEASURED_DIR" = 0 ]; then
    printf '\nThe working directory could not be measured off the session process, so the\n'
    printf 'one this shell stands in was used: %s. If that is not where\n' "$SESSION_DIR"
    printf 'the session is, the record is in a directory nothing reads.\n'
  fi
  # Said out loud whenever the two differ, because a person who typed this in a
  # subdirectory would otherwise be told the role moved somewhere they cannot see.
  if [ "$ROOT" != "$SESSION_DIR" ]; then
    printf '\nThe record is kept for the PROJECT and not for a working directory:\n'
    printf '%s lies in %s, and\n' "$SESSION_DIR" "$ROOT"
    printf 'that is where the role file and the log are, so every session in this project\n'
    printf 'reads one record.\n'
  fi
}

# Already yours, and that is not a failure. Nothing is written and nothing is logged.
#
# Rewriting would replace whatever second field is recorded, which after a SessionStart is
# the real session id, with this command's placeholder. That trades a precise record for a
# coarser one and buys nothing, because a live session's pid does not change. The log stays
# out of it for the same reason the role file does: every number this kit reports is derived
# by counting lines at read time, so a line for a transition that did not happen makes the
# count of transitions wrong. And it exits 0, because a command that goes red when the world
# is already the way you asked for it teaches people to stop reading its red.
if [ -n "$PREVPID" ] && [ "$PREVPID" = "$MYPID" ]; then
  printf 'manager-kit: the coordinating role in %s is already yours.\n' "$ROOT"
  printf 'Nothing was written and nothing was logged.\n\n'
  printf '  recorded      pid %s, second field %s\n' "$PREVPID" "${PREVSID:-<empty>}"
  printf '  this session  pid %s\n' "$MYPID"
  say_where
  printf '\nThe boundary is already where you want it, and both readers take it off this\n'
  printf 'file fresh on every turn.\n'
  exit 0
fi

if ! mk_kit_make_home "$ROOT"; then
  printf 'manager-kit: REFUSED, and nothing was written.\n' >&2
  mk_record_trouble "$ROOT" >&2
  exit 2
fi
# The 2>/dev/null stands BEFORE the target, and the order is not decoration: redirections
# are opened left to right, so with it behind, the shell's own "cannot create" would still
# reach the terminal ahead of the sentence written for this case.
if ! printf '%s %s\n' "$MYPID" "$SID" 2>/dev/null | mk_kit_write "$ROOT" manager-kit.role; then
  printf 'manager-kit: REFUSED. %s could not be written.\n' "$RF" >&2
  printf 'The role is where it was. Check that the directory exists and is writable,\n' >&2
  printf 'that python3 runs, and that this name is a plain file:\n' >&2
  mk_record_trouble "$ROOT" >&2
  exit 2
fi

# Read back through the reader, not trusted from the writer. A record that did not land is
# the one failure that would otherwise be reported as a handover.
NOWPID=
mk_kit_usable "$RF" && NOWPID=$(awk 'NR==1 {print $1}' "$RF" 2>/dev/null)
if [ "$NOWPID" != "$MYPID" ]; then
  printf 'manager-kit: REFUSED. %s was written and does not read back\n' "$RF" >&2
  printf 'as this session: it names %s and this session is %s.\n' "${NOWPID:-<empty>}" "$MYPID" >&2
  exit 2
fi

LOGGED=1
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
subject=$(mk_claim_field "pid $MYPID holds the role in $ROOT")
reason=$(mk_claim_field "previous ${PREVPID:-none} $PREVSTATE")
printf '{"ts": "%s", "event": "%s", "tool": "", "subject": "%s", "reason": "%s"}\n' \
  "$ts" "$EVENT" "$subject" "$reason" 2>/dev/null | mk_kit_write "$ROOT" manager-kit.log append || LOGGED=0

printf 'manager-kit: the coordinating role in %s is now yours.\n\n' "$ROOT"
case "$PREVSTATE" in
  none)     printf '  before        nobody was recorded in this directory\n' ;;
  unusable) printf '  before        the record named no usable pid\n' ;;
  alive)    printf '  before        pid %s, and that process is still running\n' "$PREVPID" ;;
  gone)     printf '  before        pid %s, and that process is gone\n' "$PREVPID" ;;
esac
printf '  now           pid %s, this session\n' "$MYPID"
printf '  recorded as   %s %s\n' "$MYPID" "$SID"
say_where

if [ "$SID_MEASURED" = 1 ]; then
  printf '\nThe second field is this session'"'"'s own id, read from the environment and only\n'
  printf 'taken because the environment also names the pid above, so it cannot be another\n'
  printf 'session'"'"'s. That is what makes a RESTART of this session keep the role: the readers\n'
  printf 'recognise the id, and the first prompt afterwards writes the new pid in. Until\n'
  printf '0.15.0 this field was a placeholder, the pid was the whole of the identity, and a\n'
  printf 'restart erased it: the chair fell to whoever started next, with no command.\n'
  printf '\nWhat this does not buy: a new conversation carries a different id and a different\n'
  printf 'process, reads this record as somebody else'"'"'s and stays a carrier. Start one and\n'
  printf 'you run this command again.\n'
else
  printf '\nThe second field is not a session id. This session'"'"'s id could not be measured:\n'
  printf 'CLAUDE_CODE_SESSION_ID is absent, is not shaped like the id the hooks are handed,\n'
  printf 'or the environment names a process other than the pid above. So the pid is\n'
  printf 'recorded, which is what both readers fall back on anyway. Your NEXT PROMPT writes\n'
  printf 'the real id in, and that matters rather than tidies: while the placeholder stands,\n'
  printf 'the pid is the whole of the identity here, so a restart of this session before\n'
  printf 'that prompt would erase it and the chair would fall to whoever starts next.\n'
fi

printf '\nThe boundary moves with your NEXT turn. manager-stamp.sh reads this file on every\n'
printf 'prompt and the role guard reads it on every tool call, so the session that held\n'
printf 'the role before is a carrier from that same turn on.\n'

printf '\nWhat lags: the long role text is injected at SessionStart and this session already\n'
printf 'had its start. You get the one-line stamp every turn and the guard names the role\n'
printf 'when it refuses, but the full text arrives after a restart, a /clear or a\n'
printf 'compaction.\n'

if [ "$LOGGED" = 1 ]; then
  printf '\nOne line went into %s, event "%s". It is not a\n' "$LOG" "$EVENT"
  printf 'stop and not a declared crossing, so the week'"'"'s false-alarm count does not move.\n'
else
  printf '\nThe role moved, but the line for it could not be written to\n'
  printf '%s. The transition is not on the record.\n' "$LOG"
fi
exit 0
