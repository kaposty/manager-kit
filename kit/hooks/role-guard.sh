#!/usr/bin/env bash
# PreToolUse: the role boundary.
#
# It refuses a write to a work path when the coordinating session performs it with its
# own hands. It says nothing at all in every other turn, which is most of them.
#
# Two channels, and they are not interchangeable [read out of the shipped binary,
# Claude Code 2.1.220, 2026-09-07]:
#   permissionDecisionReason  becomes the blocking error and reaches THE MODEL
#   systemMessage             becomes a hook_system_message and reaches THE USER
# Both are used on a refusal, because GOAL.md done-when 2 needs the person to notice.
# Neither is used when a declared exception passes, because the same GOAL requires that
# the terminal cannot tell the kit is installed except in the turns where it stopped you.

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_classify.sh"
. "$HERE/_sessions.sh"

input=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
  # A hook that silently does nothing is worse than no hook. Say so, out loud.
  printf '%s\n' '{"systemMessage":"manager-kit: the role guard is inert, python3 is not on PATH."}'
  exit 0
fi

# WHAT RAN IS ASKED, NOT ONLY WHAT IS THERE. `command -v` answers for a python3 that exists and
# says nothing for one that does not run: an xcrun stub, a Store stub, a broken install. The
# first real call is the probe, so it costs no process the hook did not already start, and a
# python3 that fails or prints nothing is answered the way the missing one is answered above.
parsed=$(printf '%s' "$input" | python3 -I -c "$MK_PY_INPUT"'
ti = d.get("tool_input") or {}
say("CWD", d.get("cwd"))
say("SESSION_ID", d.get("session_id"))
say("AGENT_ID", d.get("agent_id"))
say("TOOL", d.get("tool_name"))
say("FPATH", ti.get("file_path") or ti.get("notebook_path"))
say("CMD", ti.get("command"))
') && [ -n "$parsed" ] || {
  printf '%s\n' '{"systemMessage":"manager-kit: the role guard is inert, python3 is on PATH but does not run."}'
  exit 0
}
eval "$parsed"
# A relative path is the session's, and the measure asks the disk about it: see _mk_abs.
MK_CWD=${CWD:-}

# Which role this session holds, decided out of the same file and in the same order as
# manager-stamp.sh decides it, because hooks/hooks.json makes this guard the third
# carrier of one identity and three carriers that disagree is worse than one.
#
# Fail closed at every step: only a role file that positively names SOMEBODY ELSE, whose
# process is still there, makes this session a carrier. No file, an unreadable one, a
# malformed one, one naming me, or one naming an owner who is gone, are all the main
# session, and the main session is what this guard is for. Every branch that cannot
# establish a carrier answers manager, so a hole in the register costs a false stop and
# never a silent pass.
# <root> is a PROJECT root, derived below, and never the working directory this call
# happened to come from: a role file that only the sessions standing in one subdirectory
# can see is a role file that lets every other session call itself the manager.
mk_guard_role() {
  _root=${1-}; _sid=${2-}
  _rf=$_root/.claude/manager-kit.role
  [ -n "$_sid" ] || { printf 'manager\n'; return 0; }
  command -v mk_own_pid >/dev/null 2>&1 || { printf 'manager\n'; return 0; }
  mk_kit_usable "$_rf" || { printf 'manager\n'; return 0; }
  _ownerpid=$(awk 'NR==1 {print $1}' "$_rf" 2>/dev/null)
  _ownersid=$(awk 'NR==1 {print $2}' "$_rf" 2>/dev/null)
  [ -n "$_ownersid" ] || { printf 'manager\n'; return 0; }
  # A FIELD 1 THAT IS NO PID NAMES NO HOLDER, and mk_field1_is_pid in _sessions.sh is the
  # one place that decides it, with the measurement of why 0 is no pid. Answered manager,
  # because a carrier stands down at the return below, which sits ahead of the log.
  mk_field1_is_pid "$_ownerpid" || { printf 'manager\n'; return 0; }
  [ "$_ownersid" = "$_sid" ] && { printf 'manager\n'; return 0; }
  # The pid is asked second, and only when the session id did not settle it, because
  # mk_own_pid walks the parent chain and the manager should not pay for that every turn.
  _mypid=$(mk_own_pid)
  [ -n "$_mypid" ] && [ "$_ownerpid" = "$_mypid" ] && { printf 'manager\n'; return 0; }
  # The recorded manager is gone, so the role is vacant, and vacant counts as mine. A
  # guard that falls silent because the session it was watching died is the failure this
  # kit exists to catch, and _identity.sh hands the role over for the same reason.
  kill -0 "$_ownerpid" 2>/dev/null || { printf 'manager\n'; return 0; }
  printf 'carrier\n'
}

# A subagent is the hand the manager delegated to, and it is supposed to work. The main
# session carries no agent_id [measured against the hook input builder in Claude Code
# 2.1.220 on 2026-09-07: agent_id comes from the subagent context and is absent on the
# main thread]. Unknown counts as the main session, so the guard fails closed.
if [ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "$SESSION_ID" ]; then
  exit 0
fi

# WHERE THE RECORD IS KEPT, and it is the project rather than the directory this call was
# made from. Derived once, here, and used for all four files below. Measured 2026-09-07 in
# a live project: anchored at the working directory, a session standing in .claude/agents
# wrote a whole second record there, and the one tools/week-verdict.sh reads counted that
# day as a day the guard slept through. The role file and the marker split the same way,
# and those two fail silently: an unseen role file makes every session the manager, and a
# marker spent where nobody reads it buys a crossing that is on no record at all.
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name, and a project called
# tail<newline> would then be recorded in its sibling called tail [measured 2026-11-07 at a7dc5a9].
mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT

# A carrier is the other hand the manager hands work to, and it is supposed to work too.
# hooks/carrier-text.md tells that session in as many words that the guard does not stop
# it, and README.md says a second session in the directory is told it is a carrier. A
# guard that stops it anyway refuses the work on the ground that the session is "the
# coordinating session", which is the one thing the kit has already decided it is not,
# and it does so on every single work write, against the five false alarms GOAL.md allows
# for a whole week.
#
# It stands down HERE, next to the subagent and ahead of the log, because a turn the
# guard does not stop leaves no trace at all.
if [ "$(mk_guard_role "$ROOT" "$SESSION_ID")" = carrier ]; then
  exit 0
fi

MARKER=$ROOT/.claude/manager-exception
SEEN=$ROOT/.claude/manager-kit.seen
# NO RECORD HERE, and the guard goes on regardless: at home or above it, or behind a .claude that
# is no directory of this project, nothing is read as this project's record and nothing is
# written, and every work write below is refused all the same. mk_record_home has the reason.
NO_RECORD=1
if mk_kit_make_home "$ROOT"; then NO_RECORD=0; fi

# The log holds LINES, never a counter this process increments. Every number the kit
# reports is derived by counting them at read time, so a lost write shows up as a
# smaller number and never as a number that disagrees with its own history.
#
# THE SHAPE OF THE LINE MOVED TO mk_log_event IN _sessions.sh, and this is the local name
# for it rather than a second copy. The hooks have a second writer since 0.16.0:
# mk_record_role logs every write of the role file, because a role that moves without a
# line is a role nobody can audit. Typed out twice, those five keys would agree on the day
# they were typed and drift on the first rename, silently: json.loads goes on parsing and
# rec.get() goes on answering None. This name stays because it is used four times below
# and reads as what it does.
append() { mk_log_event "$ROOT" "$1" "$2" "${3-}" "${4-}"; }

# Liveness witness, one line on the first call of a day.
#
# Without it a quiet week is unreadable: a guard that stopped nothing because everything
# was handed out, and a guard that stopped nothing because it never ran, leave exactly
# the same trace. Those are two different wirings, and the second is the failure this
# kit is most likely to have. The file holds a DATE, which is a property, and the log
# gets a line, which is an event. Neither is a counter.
today=$(date -u +%Y-%m-%d)
seen=
mk_kit_usable "$SEEN" && seen=$(cat "$SEEN" 2>/dev/null)
if [ "$NO_RECORD" = 0 ] && [ "$seen" != "$today" ]; then
  printf '%s\n' "$today" | mk_kit_write "$ROOT" manager-kit.seen
  append guard-ran "$TOOL" "" ""
fi

case "$TOOL" in
  Bash) verdict=$(classify_bash "$CMD"); subject=$CMD ;;
  *)    verdict=$(classify_path "$FPATH"); subject=$FPATH ;;
esac
[ "$verdict" = work ] || exit 0

NOTE=
if [ "$NO_RECORD" = 0 ] && { [ -e "$MARKER" ] || [ -L "$MARKER" ]; }; then
  # Declared and spent. One declaration buys one crossing, so a standing exception
  # cannot quietly become a standing permission.
  #
  # It buys the NEXT crossing, not one an hour later. Measured 2026-09-07 in the probe: a
  # marker written for one call went unspent, because that call happened to be invisible
  # to the Bash half, and was then quietly spent by an unrelated command twenty minutes
  # on. The log carried a crossing with somebody elses reason on it. GOAL.md done-when 3
  # asks for the reason given AT THE TIME, so a stale marker is discarded rather than
  # honoured, and the call it was lying in wait for gets the ordinary refusal.
  #
  # SPENT FIRST, BOOKED SECOND, AND PASSED ONLY WHEN BOTH LANDED. mk_kit_spend has why a marker
  # that cannot be removed buys nothing. A crossing whose line cannot be written does not pass
  # either: the record is what a crossing is declared for, and without it this is a silent pass.
  reason=$(mk_kit_spend "$ROOT" manager-exception)
  case $? in
    0)
      if append exception "$TOOL" "$subject" "$reason"; then exit 0; fi
      NOTE="The declaration was spent and no line could be written to the record, so it bought nothing." ;;
    2|3) ;;
    *) NOTE="The marker is there and cannot be spent: it is no plain file, or .claude does not let it be removed. It buys nothing until that is cleared." ;;
  esac
fi
TROUBLE=$(mk_record_trouble "$ROOT")
NOTE="$TROUBLE${TROUBLE:+${NOTE:+ }}$NOTE"
DOOR_ROOT=$ROOT
[ "$NO_RECORD" = 0 ] || DOOR_ROOT=

# WHY IT STOPPED, in the words of the measure that decided, and ONLY HERE. Until 2026-11-02
# the stop went on the record with an empty reason, and mk_log_event cuts the subject at 400
# characters. Counted 2026-11-02 over the 122 stop lines of one week of a foreign project:
# 95 subjects cut at exactly 400, and 11 stops classed open by hand, because the word that
# stopped them lay behind the cut and was written nowhere. The reason is the LAST line of the trace _classify.sh prints under MK_EXPLAIN=1,
# which is the line that decided: the word, then the rule by which it is work. It is the
# same trace tools/mk-explain.sh prints, so the record and the recheck the refusal names
# cannot say two different things. Not the whole trace: a long script reads a run of paths
# before the one that decides, and that account would be cut before it reached the word.
#
# The measure is asked a SECOND time for it, with the trace on, and that is deliberate.
# Every call that is not a stop has left above, so the silent path, which is every tool
# call of the session, does not pay for the reason at all.
case "$TOOL" in
  Bash) why=$(export MK_EXPLAIN=1; classify_bash "$CMD" 2>&1 >/dev/null) ;;
  *)    why=$(export MK_EXPLAIN=1; classify_path "$FPATH" 2>&1 >/dev/null) ;;
esac
why=$(printf '%s\n' "$why" | sed -n '$s/^ *//p')
append stop "$TOOL" "$subject" "$why"
# WHAT THE MEASURE COULD NOT READ IT SAYS, in the refusal and not only in the record. The line that
# decided opens with this one word when that is why it is work. Cut here because it travels in the
# environment, and it goes through the same redactor as everything the refusal repeats.
UNREAD=
case $why in 'unreadable: '*) UNREAD=${why#unreadable: }; UNREAD=${UNREAD:0:1000} ;; esac

# WHERE A DOUBTED VERDICT IS RECHECKED, and it is named here because this is the text that
# arrives in the moment it is doubted. hooks/role-text.md promises this tool to the
# coordinating session at every session start; until 2026-11-02 the refusal itself did not
# name it, so the one text a stranger reads when the measure looks wrong was the one text
# that did not say how to ask the measure why. The alternative to naming it is arguing with
# a hook.
#
# NAMED ONLY IF IT IS THERE. A refusal that points at a file the installation does not
# carry is worse than one that points at nothing: it sends a session that is already
# blocked after a path that does not exist. Which tool it is is DERIVED in the assertion,
# out of the one file under tools/ that the explain switch is wired to, so a rename shows
# up as a red check here rather than as a dead path in a refusal.
EXPLAIN=tools/mk-explain.sh
[ -r "$HERE/../$EXPLAIN" ] || EXPLAIN=

# Both numbers are derived by reading the whole log, with no upper bound anywhere in the
# command, and both are printed: a count without its companion cannot be told apart from
# an empty base set.
# THE SUBJECT TRAVELS ON STDIN, NOT IN THE ENVIRONMENT. It is the whole command, and the
# system refuses to start a program whose environment is too large: measured 2026-11-06 on
# macOS, a 900000 byte heredoc was refused and a 1100000 byte one let through, because the
# exec of this very program failed and the failure was swallowed below. A pipe has no such
# limit. Only the first 300 characters are ever printed; the rest is read for the marker.
out=$(printf '%s' "$subject" 2>/dev/null |
  MK_MARKER=$MARKER MK_DOOR_ROOT=$DOOR_ROOT MK_NOTE=$NOTE MK_NO_RECORD=$NO_RECORD MK_EXPLAIN_TOOL=$EXPLAIN MK_UNREAD=$UNREAD MK_LOG_CAP=$MK_LOG_CAP python3 -I -c "$MK_PY_DOOR$MK_PY_REDACT"'
import sys, json
raw = sys.stdin.buffer.read().decode("utf-8", "replace")
# What the refusal repeats of the command is blacked out like the record is, and raw stays whole for
# the one question below that has to see the marker name in it.
subject = mk_safe(raw, 300)
stops = crossings = 0
since = ""
cap = int(os.environ.get("MK_LOG_CAP", "0"))
counted = True
try:
    with os.fdopen(mk_file(mk_home(os.environ.get("MK_DOOR_ROOT", "")), "manager-kit.log", os.O_RDONLY), "rb") as fh:
        data = fh.read(cap + 1)
    # A LOG PAST THE CAP IS NOT COUNTED, and the refusal says so. Counting the part of it that was read would
    # print a number nobody can tell from the whole, and reading all of it holds the hook as long as it is long.
    counted = len(data) <= cap
    if counted:
        for line in data.split(b"\n"):
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if not isinstance(rec, dict):
                continue
            if not since:
                since = str(rec.get("ts", ""))[:10]
            ev = rec.get("event")
            if ev == "stop":
                stops += 1
            elif ev == "exception":
                crossings += 1
except Exception:
    pass

# Which of the two refusals this is, read out of the refused text itself. A command that
# names the marker file AND crosses the line packed the declaration and the crossing into
# one call, and the guard is handed the whole of it before any of it runs: it refuses the
# declaration along with the crossing, so the marker the caller was just told to write
# never comes into being. Sending that caller the general lecture tells somebody who has
# already written a declaration to write one. Measured twice on 2026-09-07, in this
# project and in a foreign session, both times straight out of the sentence below.
# The name is taken from MARKER rather than typed, so a rename cannot split the two.
#
# AND THE ADDRESS IS THE ONE THE GUARD READS, whole. The record belongs to the project and a
# session can stand anywhere in it: told ".claude/manager-exception", a session in a
# subdirectory followed the text to the letter and wrote one the guard does not read. Measured
# 2026-11-06 at 9dc29df: with git it stayed refused, without git the same step grew a second
# .claude and split the record.
# A SECOND NAME FOR ONE OF THE KIT FILES, a hard link: a write to it changes the file at the other end, and a
# shell cannot see it without a process. This program runs anyway, so the refusal says it at no cost, and the
# start of a session, which has no such program, does not.
hard = ""
try:
    home = mk_home(os.environ.get("MK_DOOR_ROOT", ""))
    for name in ("manager-kit.log", "manager-kit.role", "manager-kit.seen", "manager-exception"):
        try:
            st = os.stat(name, dir_fd=home, follow_symlinks=False)
        except OSError:
            continue
        if stat.S_ISREG(st.st_mode) and st.st_nlink > 1:
            hard = name
            break
except Exception:
    pass
hard_sentence = (".claude/%s has a second name, it is a hard link, so a write to it would change the file at the other end "
                 "and the kit does not use it. Remove it to have it back." % hard) if hard else ""
marker_path = os.environ.get("MK_MARKER", "")
marker = os.path.basename(marker_path)
note = os.environ.get("MK_NOTE", "")
if hard_sentence:
    note = (note + " " if note else "") + hard_sentence
no_record = os.environ.get("MK_NO_RECORD", "") == "1"
packed = bool(marker) and marker in raw and not no_record

boundary = (
    "manager-kit: you are the coordinating session and this is a work path, not "
    "bookkeeping. Hand it out to a subagent instead of writing it yourself. Bookkeeping "
    "is anything under a .claude directory, every *.md file and the session "
    "scratchpad; everything else is work. "
)
if no_record:
    # No way out is offered that does not exist: no marker can be spent where no record is kept.
    lead = boundary + note + " "
    note = ""
    booked = ""
elif packed:
    lead = (
        "manager-kit: this call names .claude/manager-exception and crosses the line "
        "in one command, so both halves were refused together: the guard reads the "
        "whole command before any of it runs, and the marker is not there yet. Send the "
        "declaration to " + marker_path + " in a call of its own, then repeat this crossing "
        "as the next call: it passes, the marker is spent, and "
    )
    booked = "the crossing is on the record. "
else:
    lead = (
        boundary +
        "If this crossing is genuinely yours to make, write one line of reason into " +
        marker_path +
        " in a call of its own, and repeat this call right after. "
        "A declaration older than five minutes is discarded: it passes, the marker is "
        "spent, and "
    )
    booked = "the crossing is on the record. "
# THE TOOL THAT RECHECKS THIS VERDICT, dropped rather than guessed when the
# installation does not carry it. It rides on both leads: the packed caller has just
# been told to split the call, and a split that was never the problem is the first
# thing that caller will want to recheck.
tool = os.environ.get("MK_EXPLAIN_TOOL", "")
recheck = (" Recheck this verdict with %s, which names the word that caused it."
           % tool) if tool else ""
unread = os.environ.get("MK_UNREAD", "")
said = (" " + mk_safe(unread, 400)) if unread else ""
model_reason = lead + booked + "Refused: " + subject + said + recheck + ((" " + note) if note else "")
tail = (" since " + since) if since else ""
if counted:
    user_msg = (
        "manager-kit stopped a write to %s.%s Stops %d, declared crossings %d%s."
        % (subject, said, stops, crossings, tail)
    )
else:
    user_msg = (
        "manager-kit stopped a write to %s.%s Stops and declared crossings were not counted: the record is "
        "longer than %d bytes, which is more than the refusal reads. tools/week-verdict.sh counts all of it."
        % (subject, said, cap)
    )
told = os.environ.get("MK_NOTE", "")
if hard_sentence:
    told = (told + " " if told else "") + hard_sentence
if told:
    user_msg += " " + told
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": model_reason,
    },
    "systemMessage": user_msg,
}))
' 2>/dev/null) || out=

# THE REFUSAL GOES OUT WHATEVER HAPPENED TO THE PROGRAM ABOVE. The stop is on the record by
# now, so a pass here would be a pass the record contradicts. The text is fixed, written out
# in the shell, and carries the three things a refusal has to carry: the boundary, the way
# out and the tool. It is the short form, and it says so.
case $out in
  *'"permissionDecision": "deny"'*) ;;
  *)
    recheck=
    [ -z "$EXPLAIN" ] || recheck=" Recheck this verdict with $EXPLAIN, which names the word that caused it."
    # THE PATH IS MADE SAFE FOR JSON BY HAND, because no python is left at this point and a
    # broken answer here is a refusal that does not refuse. A control character falls back to
    # the short name; the two characters JSON would choke on otherwise are escaped.
    where=$MARKER
    case $where in *[[:cntrl:]]*) where=.claude/manager-exception ;; esac
    where=${where//\\/\\\\}
    where=${where//\"/\\\"}
    way="If this crossing is genuinely yours to make, write one line of reason into $where in a call of its own, then repeat this call."
    [ "$NO_RECORD" = 0 ] || way=
    # The sentence is fixed: what the measure read in the command has no way into this JSON by hand.
    said=
    [ -z "$UNREAD" ] || said="The target could not be read: spell the path out, or assign it in the same command. "
    out='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"manager-kit: you are the coordinating session and this is a work path, not bookkeeping (bookkeeping is anything under a .claude directory, every *.md file and the session scratchpad). Hand it out to a subagent instead of writing it yourself. '"$said$way${way:+ }$NOTE${NOTE:+ }"'This is the short form of the refusal: the full text could not be built.'"$recheck"'"},"systemMessage":"manager-kit stopped a write to a work path. '"$said"'The full message could not be built, and the refusal stands."}'
    ;;
esac
printf '%s\n' "$out"
exit 0
