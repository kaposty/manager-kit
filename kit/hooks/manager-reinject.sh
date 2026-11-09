#!/usr/bin/env bash
# SessionStart compact|resume|fork: the same text again, from the same source.
#
# IT CLAIMS IN ONE LAGE ONLY: the record names no living process [field 1 no pid, or a pid
# kill -0 cannot reach]. Then mk_decide_role is asked with claim, exactly as manager-prime.sh
# asks it, census and contested branch included, so a continued session claims by the rule
# a starting one claims by and never by a second one. Every other record is not handed to
# it, so a continuation takes strictly less than a startup in the same lage: no record at
# all, a living foreign pid [registered or not], and a compaction of the holder itself are
# all left exactly as they were.
#
# WHAT WAS BROKEN, observed 2026-11-03 in a live project through the process table, the
# socket directory and file names: a new session started in a process of its own, claimed,
# and ended; seven seconds later the old session went on by resume in another process. Two
# hours later the record still named the phantom. Every reader called the real session the
# manager, nothing wrote it in, and the next session to start found the chair contested,
# so both were stopped until somebody restarted.
#
# WHY HERE AND NOT IN manager-stamp.sh: the stamp runs for every session on every prompt and
# cannot tell a continued session from a started one, so the claim there would reach every
# session in the project and not the one continuing. compact and fork come along because
# the hook cannot tell them apart without reading source, and the proof [no living holder,
# nobody else counted] is the same in all three.
#
# A RESUME THAT ARRIVES BEFORE ITS OLD PROCESS IS GONE is not reached, and need not be:
# measured in a live project on 2026-09-11, this hook ran at 09:22:52 against a record naming
# the old process of the same session, which died ten seconds later. That pid answers here,
# so nothing is claimed, and manager-stamp.sh puts the record right on the first prompt.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_identity.sh"
input=$(cat)
command -v python3 >/dev/null 2>&1 || { printf '%s\n' '{"systemMessage":"manager-kit: no python3 on PATH, the role was not reinjected."}'; exit 0; }
# WHAT RAN IS ASKED, NOT ONLY WHAT IS THERE. `command -v` answers for a python3 that exists and
# says nothing for one that does not run: an xcrun stub, a Store stub, a broken install. The
# first real call is the probe, so it costs no process the hook did not already start, and a
# python3 that fails or prints nothing is answered the way the missing one is answered above.
parsed=$(printf '%s' "$input" | python3 -I -c "$MK_PY_INPUT"'
say("CWD", d.get("cwd") or "")
say("SESSION_ID", d.get("session_id") or "")
') && [ -n "$parsed" ] || {
  printf '%s\n' '{"systemMessage":"manager-kit: python3 is on PATH but does not run, the role was not reinjected."}'
  exit 0
}
eval "$parsed"
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name, and a project called
# tail<newline> would then be recorded in its sibling called tail [measured 2026-11-07 at a7dc5a9].
mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT
claim=
rf=$(mk_role_file "$ROOT")
if mk_kit_usable "$rf"; then
  ownerpid=$(awk 'NR==1 {print $1}' "$rf" 2>/dev/null)
  if ! mk_field1_is_pid "$ownerpid" || ! kill -0 "$ownerpid" 2>/dev/null; then claim=claim; fi
fi
role=$(mk_decide_role "$ROOT" "$SESSION_ID" "$claim")
# THE ONE THING THIS HOOK ADDS WHEN THE RECORD HAS NO HOME: a sentence, to the session and to the
# person, and in a plain project not a word of it, so the role text stays at its budget.
MK_TROUBLE=$(mk_record_trouble "$ROOT")
export MK_TROUBLE
mk_role_context "$role" "$ROOT" | python3 -I -c '
import os, sys, json
text = sys.stdin.buffer.read().decode("utf-8", "replace")
trouble = os.environ.get("MK_TROUBLE", "")
answer = {"suppressOutput": True, "hookSpecificOutput": {
    "hookEventName": "SessionStart", "additionalContext": text + ("\n" + trouble + "\n" if trouble else "")}}
if trouble:
    answer["systemMessage"] = trouble
print(json.dumps(answer))
'
