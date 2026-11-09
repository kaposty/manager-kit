#!/usr/bin/env bash
# UserPromptSubmit: one line, every turn, and the record caught up with it.
#
# This is the carrier that cannot lose a race. A running auto-compaction fires
# SessionStart not at all, and a reinject after a manual /compact can arrive behind the
# next message. A prompt hook runs before the prompt is answered, every time, so the
# role survives any compaction whether or not the other two carriers got their turn.
#
# Because it cannot lose that race, it is also where the record is repaired when a
# coordinating session comes back as a new process. The long comment further down is the
# measurement that put it here rather than in either SessionStart hook.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_identity.sh"
. "$HERE/_notice.sh"
input=$(cat)
command -v python3 >/dev/null 2>&1 || exit 0
# WHAT RAN IS ASKED, NOT ONLY WHAT IS THERE. `command -v` answers for a python3 that exists and
# says nothing for one that does not run: an xcrun stub, a Store stub, a broken install. The
# first real call is the probe, so it costs no process the hook did not already start, and a
# python3 that fails or prints nothing is answered the way the missing one is answered above.
parsed=$(printf '%s' "$input" | python3 -I -c "$MK_PY_INPUT"'
say("CWD", d.get("cwd") or "")
say("SESSION_ID", d.get("session_id") or "")
say("TRANSCRIPT", d.get("transcript_path") or "")
') && [ -n "$parsed" ] || exit 0
eval "$parsed"
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name, and a project called
# tail<newline> would then be recorded in its sibling called tail [measured 2026-11-07 at a7dc5a9].
mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT
rf=$(mk_role_file "$ROOT")
role=carrier
if mk_kit_usable "$rf"; then
  ownersid=$(awk 'NR==1 {print $2}' "$rf" 2>/dev/null)
  ownerpid=$(awk 'NR==1 {print $1}' "$rf" 2>/dev/null)
  mypid=$(mk_own_pid)
  # WHICH OF THE TWO OWNERSHIP TESTS ANSWERED, remembered rather than asked again further
  # down. The repair below writes only for a session the record ALREADY names, which is the
  # same question these two branches ask, and asking it a second time underneath would be a
  # second copy of the rule that drifts the first time either of them moves.
  mine=0
  if [ -n "$SESSION_ID" ] && [ "$ownersid" = "$SESSION_ID" ]; then role=manager; mine=1
  elif [ -n "$mypid" ] && [ "$ownerpid" = "$mypid" ]; then role=manager; mine=1
  else
    # The recorded manager is gone, so the role is vacant, and vacant counts as mine. The
    # other two carriers of this identity already say so: mk_decide_role in _identity.sh
    # and mk_guard_role in role-guard.sh both hand the role over here. Measured 2026-09-07
    # with two live sessions in the directory and a dead pid in the role file, this hook
    # was the only one still saying carrier, so one session was told two roles on the same
    # turn. Only the recorded pid is read, and the branch with no role file at all is left
    # untouched, because what a session alone in the directory should be told is a design
    # question the user has held back until after the operating week.
    # NOT A PID IS manager HERE TOO, by mk_field1_is_pid in _sessions.sh, the one place
    # that decides it for all four readers and carries why 0 is no pid. Left at the carrier
    # default, this answered carrier for the very record the guard answers manager for, and
    # a carrier leaves role-guard.sh at the stand-down that sits AHEAD of the log, so that
    # half was a silent pass with no trace. THE RECORD IS STILL NOT WRITTEN HERE: mine
    # stays 0 for a record that does not name this session, which is what WHAT IT LEAVES
    # ALONE ON PURPOSE below means by a first field that will not parse.
    if ! mk_field1_is_pid "$ownerpid"; then role=manager
    else kill -0 "$ownerpid" 2>/dev/null || role=manager
    fi
    # AND A FIELD 2 THAT NAMES NO SESSION IS NOT A HOLDER EITHER, by the same question
    # mk_guard_role asks one line ahead of its own question over field 1. Left out, this hook
    # answered carrier for a record reading "<living pid>" with nothing behind it, while
    # the guard answered manager and refused the same session on the same prompt: two roles
    # in one turn, which this kit names as its own worst failure. Measured 2026-11-02
    # against the delivered hooks: guard manager, prime carrier, reinject carrier, stamp
    # carrier. mine stays 0, so the record is not written: a session this record does not
    # name cannot prove the chair is free, and manager WITH a claim is the silent pass one
    # step on, because the second session to start would overwrite the first.
    [ -n "$ownersid" ] || role=manager
  fi

  # THE RECORD CATCHES UP WITH THE PROCESS, and this is the whole of the repair.
  #
  # It never moves the role. It writes only for a session the record ALREADY names, and it
  # writes only the pid and the session id of that same session. Every other shape is left
  # exactly as it was, so no turn that used to end in a refusal can end in silence because
  # of this block. That property is the point, not a side effect: see WHAT IT REFUSES TO DO.
  #
  # WHAT WAS BROKEN. The record names a pid. When the coordinating session comes back as a
  # NEW process, a resume or a fork, it goes on naming the old one. All three carriers of
  # this identity read a dead owner as a vacant chair and answer manager, so the session
  # keeps working and keeps being guarded and nothing looks wrong. None of them wrote that
  # answer down. The next session to START read the same vacancy through mk_decide_role,
  # which carries claim, and wrote ITSELF in. The role left a session that was sitting right
  # there, on no command, and only tools/manager-claim.sh writes a handover line.
  #
  # MEASURED IN A LIVE PROJECT, 2026-09-11, through the delivered 0.12.0:
  #   09:22:52  the coordinating session comes back as a new process, SessionStart:resume.
  #             The record still says "46573 claimed-by-pid" from the take-over of 17:57
  #             the day before, and 46573 is the process it used to be.
  #   09:23:03  this hook tells it "you are the manager here", and the guard agrees: one
  #             guard-ran line is in the log at 09:23:15. Both read the dead pid as vacancy.
  #   09:32:21  an unrelated session starts, reads the same dead pid, and claims. The log
  #             carries four lines that day and not one of them is a handover.
  #   09:35:49  this hook tells the coordinating session it is a carrier. Its guard has
  #             stood down since 09:32:21.
  #
  # HOW THIS BLOCK STOPS THAT DAY, and it is one step further up than where it was found.
  # The take-over writes "<pid> claimed-by-pid", because a Bash call cannot learn its own
  # session id, so the pid is the whole of the identity in that record and a restart erases
  # it. The FIRST branch of that erasure is closed here: the record names this process, so
  # the placeholder is replaced by this session id on the first prompt after the take-over.
  # From then on the record names a session and not only a process, and the restart is an
  # ordinary case: the recorded session id is mine, the recorded pid is not, and the pid is
  # written again. In the day above the take-over was at 17:57 and the session worked until
  # 09:22, so it had prompts by the hundred before the process changed.
  #
  # WHAT IT REFUSES TO DO, and this is where the obvious repair goes wrong. "Whoever finds a
  # dead owner and decides manager writes itself in" looks like the same rule and is not:
  # after a take-over the record carries no session id, so a dead pid and a placeholder
  # cannot tell the restarted holder apart from any other session in the project. Every one
  # of them reads vacancy, every one of them answers manager, and under that rule the first
  # one to submit a prompt would take the record and turn the real holder into a CARRIER,
  # whose guard then stands down. Today all of them are refused instead, which is a false
  # stop, and this kit has written down twice which of those two it holds to be worse: a
  # hole in the register costs a false stop and never a silent pass. So the record is only
  # ever brought up to date, never claimed, and a vacancy nobody can prove is theirs is left
  # where 0.12.0 left it.
  #
  # WHY THIS HOOK AND NOT manager-reinject.sh, which is the obvious place and was measured
  # first: at 09:22:52 the old process had not died yet. mk_decide_role answered CARRIER on
  # that call, and a carrier writes nothing even when it is handed claim, so a reinject that
  # claimed would not have touched the day above. The pid died in the ten seconds between
  # that hook and this one.
  #
  # WHY THIS HOOK AND NOT role-guard.sh: the guard returns on "the recorded session id is
  # mine" BEFORE it asks for a pid, and says why, mk_own_pid walks the parent chain and the
  # manager should not pay for that on every tool call. That early return is exactly the
  # branch this repair has to write in, so catching it there would mean measuring the pid on
  # every Bash, Edit and Write in the project. This hook has already paid for mypid on the
  # line above, runs once per prompt against roughly four guarded tool calls [measured in
  # the same project on the same day: 30 prompts, 113 guarded calls, 3.8 times], and cannot
  # lose a race, which is the reason hooks/hooks.json gives for it existing at all.
  #
  # WHAT IT COSTS: one write on the first prompt after a take-over, and one on the first
  # prompt after a restart. The turn after either, the record already reads "<mypid>
  # <SESSION_ID>", the comparison below is false, and nothing is written.
  #
  # AND IT CLOSES A PID 0 ON THE WAY PAST, which was not the defect it was written for.
  # mk_decide_role records "${_mypid:-0}", so a claim taken while the register could not be
  # read leaves a 0 in field 1. Until 2026-11-02 that was worse than a blank: kill -0 0
  # signals the caller's own process group and SUCCEEDS [measured 2026-09-11, bash 3.2.57],
  # so every other session in the project read that record as a LIVING owner and stood down.
  # Since then mk_field1_is_pid finds no pid in a 0, and every other session is called the
  # manager and refused instead: a false stop rather than a silent pass. The record names
  # that session, so this block still owns the repair and puts a real pid there on its next
  # prompt.
  #
  # WHAT IT LEAVES ALONE ON PURPOSE:
  #   an empty mypid. A record whose first field will not parse as a pid is worse than a
  #   stale one: mk_guard_role and this hook then both call every session in the project the
  #   manager, and the guard refuses every one of them. When the register cannot say which
  #   process this is, the record stays exactly as it is.
  #   an empty session id, for the same reason one field over: mk_guard_role reads an empty
  #   second field as undecidable and answers manager for everybody.
  #   a record naming somebody else, alive or dead. Neither is this session's to write.
  #   the branch below, where there is no record at all. What a session alone in a project
  #   should be told is a design question the user has held back until after the operating
  #   week, and writing a file here would answer it.
  #
  # THE ONE CASE IT DOES NOT REACH, named rather than hidden: a record that is ALREADY
  # "<dead pid> claimed-by-pid" when this version arrives, from a take-over whose session
  # never got a prompt before its process changed. Nothing on disk says whose chair that is,
  # so nothing here may take it, and the next session to start still claims it in silence.
  # Closing that needs the handover line that claim does not write, which is the next thing
  # to answer and is not this repair.
  if [ "$mine" = 1 ] && [ -n "$SESSION_ID" ] &&
     [ "$ownerpid $ownersid" != "$mypid $SESSION_ID" ]; then
    case "$mypid" in
      ''|*[!0-9]*) ;;
      *) mk_record_role "$ROOT" "$mypid" "$SESSION_ID" ;;
    esac
  fi
else
  # Nobody has claimed, and this hook does not get to answer that on its own. The session
  # start hook asks the register the same question, and two carriers that hand one session
  # two different roles are worse than either answer on its own. Measured 2026-09-07 with
  # two live sessions in the directory and no role file: the start hook said carrier and
  # claimed nothing, while this one said manager on every prompt.
  role=$(mk_decide_role "$ROOT" "$SESSION_ID")
fi
if [ "$role" = manager ]; then
  line='manager-kit: you are the manager here. Bookkeeping is .claude/ and *.md, everything else is handed out.'
  # The context line, on a line of its own under the role line and only when it is due: hooks/_notice.sh.
  note=$(mk_kit_notice "$ROOT" "$SESSION_ID" "${TRANSCRIPT-}" UserPromptSubmit)
  [ -z "$note" ] || line=$line$MK_NL$note
else
  line='manager-kit: you are a carrier here, not the manager. Do the work you were given.'
fi
printf '%s' "$line" | python3 -I -c '
import sys, json
print(json.dumps({"suppressOutput": True, "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit", "additionalContext": sys.stdin.buffer.read().decode("utf-8", "replace")}}))
'
