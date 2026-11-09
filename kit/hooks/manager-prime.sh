#!/usr/bin/env bash
# SessionStart startup|clear: the session learns which role it holds, and the manager
# claims it. Silent to the terminal by construction.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_identity.sh"
input=$(cat)
command -v python3 >/dev/null 2>&1 || { printf '%s\n' '{"systemMessage":"manager-kit: no python3 on PATH, the session was not primed."}'; exit 0; }
# WHAT RAN IS ASKED, NOT ONLY WHAT IS THERE. `command -v` answers for a python3 that exists and
# says nothing for one that does not run: an xcrun stub, a Store stub, a broken install. The
# first real call is the probe, so it costs no process the hook did not already start, and a
# python3 that fails or prints nothing is answered the way the missing one is answered above.
parsed=$(printf '%s' "$input" | python3 -I -c "$MK_PY_INPUT"'
say("CWD", d.get("cwd") or "")
say("SESSION_ID", d.get("session_id") or "")
') && [ -n "$parsed" ] || {
  printf '%s\n' '{"systemMessage":"manager-kit: python3 is on PATH but does not run, the session was not primed."}'
  exit 0
}
eval "$parsed"
# The project this session is standing in, derived ONCE and handed to both calls. The
# working directory is what the hook is given; the record belongs to the project around
# it, or a session started in a subdirectory claims a role file nothing else reads.
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name, and a project called
# tail<newline> would then be recorded in its sibling called tail [measured 2026-11-07 at a7dc5a9].
mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT
role=$(mk_decide_role "$ROOT" "$SESSION_ID" claim)
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
