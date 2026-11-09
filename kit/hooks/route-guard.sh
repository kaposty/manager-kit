#!/usr/bin/env bash
# PreToolUse on the subagent launch: the model routing.
#
# It refuses one combination, haiku on the repair hand at any effort, and it writes one line for every
# handout it sees. It says nothing else, ever, which is most of the calls. The rule and its reason are in
# _routing.sh.
#
# WHY A SECOND HOOK AND NOT A SIXTH TOOL ON role-guard.sh, which is the shorter diff. The
# guard stands down for a subagent and for a carrier BEFORE it looks at anything, and both
# of those stand-downs are correct for the role boundary and wrong here: a carrier that
# hands work out routes models too. Folding this in would have meant moving those
# stand-downs or branching around them, which is one script holding two unrelated verdicts
# and two reasons to be silent. The price of the split is one more process per subagent
# launch, measured against a hook budget of 10 seconds, and one more file to read.
#
# THE TWO CHANNELS, and they are not interchangeable [the same reading role-guard.sh
# records, Claude Code 2.1.220, re-checked against 2.1.278 on 2026-11-02]:
#   permissionDecisionReason  becomes the blocking error and reaches THE MODEL
#   systemMessage             becomes a hook_system_message and reaches THE USER
# Both are used on a refusal: the coordinator has to know which half of the call to
# change, and the person has to be able to see that a policy resting on n = 2 is costing
# them a handout.

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_sessions.sh"
. "$HERE/_routing.sh"

input=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
  # A hook that silently does nothing is worse than no hook. Say so, out loud, in the
  # same words role-guard.sh says it in.
  printf '%s\n' '{"systemMessage":"manager-kit: the route guard is inert, python3 is not on PATH."}'
  exit 0
fi

# WHAT RAN IS ASKED, NOT ONLY WHAT IS THERE. `command -v` answers for a python3 that exists and
# says nothing for one that does not run: an xcrun stub, a Store stub, a broken install. The
# first real call is the probe, so it costs no process the hook did not already start, and a
# python3 that fails or prints nothing is answered the way the missing one is answered above.
#
# WHAT CANNOT BE READ IS SAID, AND IT IS NOT A REASON TO FALL OVER. A tool_input that is no object felled
# this parse until 2026-11-07, and the answer was "inert" and no refusal; a falsy one read as an empty
# object and passed. Now both are UNREAD, and so is a subagent_type that is no plain name: a control
# character in it would split the record further down, or be dropped on its way to the shell and
# turn into a name nobody sent, and a name of megabytes holds the patterns of the shell past the budget
# of the hook [measured 2026-11-07 at e2559f7: 200 KB held it over 20 seconds, 20 KB took 0.40]. A
# missing or null input and a missing name are not unread: they name
# nothing, the line says so, and the guard has always let that pass.
parsed=$(printf '%s' "$input" | python3 -I -c "$MK_PY_INPUT""$MK_PY_ROUTE"'
ti = d.get("tool_input")
unread = ti is not None and not isinstance(ti, dict)
ti = ti if isinstance(ti, dict) else {}
sub = ti.get("subagent_type")
if sub is not None and not (isinstance(sub, str) and len(sub) <= 256 and not re.search("[\\x00-\\x1f\\x7f]", sub)):
    unread = True
    sub = None
say("CWD", d.get("cwd"))
say("TOOL", d.get("tool_name"))
say("UNREAD", "1" if unread else "")
say("MODEL", mk_word(ti.get("model")))
say("SUBAGENT", sub)
say("KIT_NAME", mk_kit_name(sys.argv[1]))
say("ORDER", mk_order_marks(ti.get("prompt")))
# THE EFFORT OF THE CALL, read by the parse that runs anyway and never by a second one. Only a WORD
# of letters goes through to the shell, and anything else becomes a question mark: a NUL is dropped
# by the command substitution that carries this text, so "ma\u0000x" would arrive as max, and an
# object, a number or 10000 characters have no business in a variable the line is built from. Whether
# the word is a rung is asked of _routing.sh below, where the scale is. This cannot raise, whatever
# the value is, because a parse that fails here is a refusal that does not happen.
ef = ti.get("effort")
say("EFFORT_CALL", ef if ef is None or (isinstance(ef, str) and re.fullmatch("[A-Za-z]{1,15}", ef)) else "?")
# THE tool_use_id OF THE CALL, the key that ties this line to the transcript of the hand: its meta.json carries the
# same id as toolUseId, and tools/mk-cost.sh --hands matches the two. Only the characters of such an id go through,
# anything else is a question mark, and a missing, null or empty one names nothing: the line is then the one it was.
tu = d.get("tool_use_id")
say("TOOL_USE_ID", tu if tu is None or (isinstance(tu, str) and re.fullmatch("[A-Za-z0-9_-]{0,128}", tu)) else "?")
' "$MK_ROUTE_MANIFEST") && [ -n "$parsed" ] || {
  printf '%s\n' '{"systemMessage":"manager-kit: the route guard is inert, python3 is on PATH but does not run."}'
  exit 0
}
eval "$parsed"

# WHICH TOOL THIS IS, AND BOTH SPELLINGS ARE HONOURED. The runtime hands over "Agent":
# measured 2026-11-02 over 4335 real subagent launches in this machine's transcripts,
# 4335 of them carry that name and none carries "Task". "Task" is the name the tool had
# before, and the runtime still accepts it IN A MATCHER by canonicalising the matcher list
# through a legacy alias table before comparing; it does not rewrite the payload. So a
# hook that only knew the old name would be selected and then do nothing, silently, which
# is the exact shape of failure this kit exists to catch. Anything else exits here, which
# is what makes this hook safe to wire more widely than it judges.
case "$TOOL" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

# WHERE THE RECORD IS KEPT, and it is the project rather than the directory the call was
# made from, derived with the same function the other four hooks derive it with. Measured
# 2026-09-07 in a live project: anchored at the working directory, a session standing in a
# subdirectory wrote a whole second record there and the one tools/week-verdict.sh reads
# counted the day as a day the hooks slept through.
# NOT $(mk_project_root ...): a command substitution removes a newline at the end of a name, and a project called
# tail<newline> would then be recorded in its sibling called tail [measured 2026-11-07 at a7dc5a9].
mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT
DOOR_ROOT=
if mk_kit_make_home "$ROOT"; then DOOR_ROOT=$ROOT; fi

# A MODEL THE CALL DOES NOT NAME CAN STILL BE NAMED BY THE HAND'S DEFINITION. A `model:`
# in agents/*.md or .claude/agents/*.md is what the runtime runs the hand on when the call
# leaves model out, so a haiku hand with high effort is the same combination whether the
# coordinator typed haiku or the definition did. The call wins when it names one, inherit
# and a missing key leave the line at (inherit) as before, and with the switch set nothing
# is read at all, so a stilled routing writes the line it always wrote.
MODEL_FROM=call
if [ -z "$MODEL" ] && ! mk_routing_is_off; then
  MODEL=$(mk_route_model "$ROOT" "$SUBAGENT" "$KIT_NAME")
  [ -z "$MODEL" ] || MODEL_FROM=definition
fi
# NEITHER THE CALL NOR THE FILE NAMED ONE, and the word for that is none rather than session:
# the session's model is what the runtime would then use, and this line claims nothing about
# what ran. A switched off routing reads no definition, so it lands here as well.
[ -n "$MODEL" ] || MODEL_FROM=none
# A MODEL THAT IS NO WORD IS (other), said in the shape the effort of the call says it. Until 2026-11-07
# it went onto the line raw: "haiku effort=max from=call" forged the front words of every reader, and
# 10000 characters cut off what stood behind them.
[ "$MODEL" != '?' ] || MODEL='(other)'

# THE RULE IS ASKED, NEVER RESTATED. Everything about which combination is forbidden lives
# in _routing.sh, so the refusal text below and the log line below read the same verdict
# off one call rather than two copies that agree today.
#
# TAKEN APART BY PATTERN, NOT BY `set -- $(...)`, which widened an effort of * against the directory of
# the hook and put a file name on the line [measured at 7bd221e and at e2559f7].
_verdict=$(mk_route_verdict "$ROOT" "$MODEL" "$SUBAGENT" "$KIT_NAME")
verdict=${_verdict%% *}
_verdict=${_verdict#* }
HAND_WORD=${_verdict%% *}
effort=${_verdict#* }
# WHAT THE PARSE COULD NOT READ IS REFUSED, unless the switch stands down on everything.
case "$UNREAD:$verdict" in 1:pass) verdict=stop ;; esac
# `effort` IS THE DEFINITION'S. The line and the refusal name the one that applies, which the call
# decides when it names one.
_applied=$(mk_route_effort_applied "$EFFORT_CALL" "$effort")
EFFORT_SHOWN=${_applied%% *}
EFFORT_FROM=${_applied#* }

# THE LINE, THROUGH THE ONE WRITER THE HOOKS ALREADY HAVE. Without this record there is
# nothing a falsification could ever show up in: GOAL.md puts the trigger of the switch on
# quality rather than cost, and quality is read off which model drove which order. One
# line per handout, and the numbers are derived by counting lines at read time, never by a
# counter this process increments.
#
# THE LINE NAMES WHAT IS WRITTEN, NOT WHAT RAN: the call, or else the definition on disk
# as this hook reads it now. The runtime keeps the definition from session start, so a
# session older than a change runs on the old model under a line naming the new one, and
# only the hand's transcript proves the model that ran. README.md carries the report.
#
# from= SAYS WHERE THE MODEL CAME FROM: call, definition or none. The model is the
# manager's judgement per order, and only this word can show whether managers use it,
# because model=sonnet reads the same typed or inherited from the file. It is appended and
# not put next to model=, so a reader that took the first two words reads them unchanged.
#
# THE FOURTH WORD, effort_from=, SAYS THE SAME FOR THE EFFORT, and effort= is the effort that
# applies: the call's when the call names one, else the definition's. Until 2026-11-07 it was
# the definition's whatever the call said, which was wrong in both directions [measured
# 2026-11-06: a low hand driven at max spent seven times the output tokens under a line that
# said low]. It is appended after from= for the reason from= was appended, and the three older
# words are read as they were. The verdict is not part of this and did not move.
#
# THREE EVENT NAMES AND NOT ONE WITH THE VERDICT IN THE TEXT, because every number this
# kit reports is a count of lines. A verdict buried in a field would have to be parsed,
# and a parse is a second reader that can drift from the writer.
#   route       a handout that passed
#   route-stop  a handout that was refused
#   route-off   a handout the switch stood down on
# The third is the one that is easy to leave out and the one that matters most: a week
# with the routing switched off and a week with no handouts leave the same trace without
# it, which is the distinction the guard writes a liveness line a day for.
#
# THE LAST TWO WORDS, hand= AND order=, were appended on 2026-11-07 for the reason the others were.
#   hand=  own, project or other, whose hand this is. The subject carries the name, and only this
#          word says whether that name counted as the kit's: a renamed kit prefixes differently, and
#          anderes-plugin:xhigh reads like a hand of ours to anybody counting by the end of the name.
#          With the switch set the table is not read, and a bare name says hand=bare.
#   order= what can be counted about the order, and nothing else: its length rounded to a tier (the
#          upper edge: 500, 2k, 5k, 10k, or 0 and more), whether a command stands in backticks, whether
#          a word of acceptance stands in it. mk_order_marks decides, the verdict does not read it, and
#          (none) or (other) stand for an order that is missing or no text. It costs no process: it
#          comes out of the parse that runs anyway, as the effort of the call does.
#
# THE SEVENTH WORD, tool_use_id=, was appended on 2026-11-08 for the reason the others were, and only when the call
# carries one. It names this call, and the meta.json of the hand the call starts names the same id as toolUseId, so a
# line and a transcript are one pair, which the time and the subject cannot make: two calls of one hand in one second
# share both. tools/mk-cost.sh --hands reads it. A call without one writes the line it wrote before.
#
# A route-off LINE CARRIES NO EFFORT OF THE DEFINITION, and that is a choice rather than an
# oversight. The verdict returns before the hand's definition is read, which is what keeps a
# switched off routing from paying for a python3 call on every handout, and the line says
# effort=(none) effort_from=none for a call that names no effort. It DOES carry the effort of
# the call. The reason this comment used to give, that the hand's effort is in agents/*.md and
# a later reading recovers it, holds for the definition and not for the call: nothing on disk
# holds what the call said, and reading it costs no process, because it comes out of the parse
# that ran already [4 python3 starts for a handout that passes, 2 for one the switch stood down
# on, the same with an effort in the call, counted 2026-11-07 against 7bd221e].
case "$verdict" in
  stop) event=route-stop ;;
  off)  event=route-off ;;
  *)    event=route ;;
esac
# The subject is the order, the reason is what drove it. Both are carried the way the
# guard carries them, so the five keys and their order come out of mk_log_event once.
mk_log_event "$ROOT" "$event" "$TOOL" "${SUBAGENT:-(none)}" \
             "model=${MODEL:-(inherit)} effort=$EFFORT_SHOWN from=$MODEL_FROM effort_from=$EFFORT_FROM hand=$HAND_WORD order=$ORDER${TOOL_USE_ID:+ tool_use_id=$TOOL_USE_ID}"

[ "$verdict" = stop ] || exit 0

out=$(MK_MODEL=$MODEL MK_MODEL_FROM=$MODEL_FROM MK_SUBAGENT=$SUBAGENT MK_EFFORT=$EFFORT_SHOWN MK_EFFORT_FROM=$EFFORT_FROM \
MK_DOOR_ROOT=$DOOR_ROOT MK_UNREAD=$UNREAD MK_LOG_CAP=$MK_LOG_CAP python3 -I -c "$MK_PY_DOOR$MK_PY_REDACT"'
import json

model = os.environ.get("MK_MODEL", "")
from_definition = os.environ.get("MK_MODEL_FROM", "") == "definition"
hand = mk_safe(os.environ.get("MK_SUBAGENT", ""), 400)
effort = os.environ.get("MK_EFFORT", "")

# Both numbers are derived by reading the log, and both are printed: a count without its companion
# cannot be told apart from an empty base set. THE LOG IS READ UP TO MK_LOG_CAP BYTES, the same cap the
# guard reads its own with, because this is the stop path and a log of 200 MB held it 4.3 s [measured
# 2026-11-07 at 0464e26]. A log past the cap is not counted and the refusal says so: a count taken from
# part of it would be a number nobody can tell from the whole.
handouts = refused = 0
cap = int(os.environ.get("MK_LOG_CAP", "0"))
counted = True
try:
    with os.fdopen(mk_file(mk_home(os.environ.get("MK_DOOR_ROOT", "")), "manager-kit.log", os.O_RDONLY), "rb") as fh:
        data = fh.read(cap + 1)
    counted = len(data) <= cap
    if counted:
        for line in data.split(b"\n"):
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if not isinstance(rec, dict):
                continue
            ev = rec.get("event")
            if ev in ("route", "route-stop", "route-off"):
                handouts += 1
            if ev == "route-stop":
                refused += 1
except Exception:
    pass
if counted:
    counts = "Handouts %d, refused %d." % (handouts, refused)
else:
    counts = ("Handouts and refusals were not counted: the record is longer than %d bytes, which is more than "
              "the refusal reads. tools/week-verdict.sh counts all of it." % cap)

# WHAT THE MODEL IS TOLD. Which half of the call is the problem, the effort that applied and where it
# came from, why, what goes instead, and where the lever is. The words of the measurement stand here
# once, and the limit with them, so that a refused manager does not read this as covering repairs.
origin = {"call": "named in the call", "definition": "from its definition", "none": "named nowhere"}.get(
    os.environ.get("MK_EFFORT_FROM", ""), "named nowhere")
if os.environ.get("MK_UNREAD") == "1":
    model_reason = (
        "manager-kit: this handout cannot be read: tool_input has to be an object and subagent_type a "
        "plain name, and here one is not. Nothing in it can be judged, and it cannot be told from "
        "haiku on the repair hand, so it is refused rather than passed unjudged. Send the call again in "
        "its normal shape. MANAGER_KIT_NO_ROUTING in the environment stills this."
    )
    user_msg = (
        "manager-kit refused a handout it cannot read. %s "
        "MANAGER_KIT_NO_ROUTING stills this." % counts
    )
else:
    model_reason = (
        "manager-kit: this handout puts %s on %s, the repair hand, at effort %s, %s. Measured: haiku held a "
        "repair of kit code twice and left one false report, n = 2 on one task, and haiku medium "
        "reported falsely on it too, so the refusal stands at every effort and naming another does not "
        "lift it. A report on a repair is what the rest of the work relies on. %sWhat goes instead: %s. If "
        "this is no repair, send it to another hand: haiku is open on all of them, at your judgement. A "
        "repair sent to another hand falls through this check, which knows the name of a hand and not "
        "the work, and the measurement says the same of it. MANAGER_KIT_NO_ROUTING in the environment "
        "stills this."
        % (model, hand or "a hand", effort, origin,
           ("The call names no model: %s comes from the model key in the definition "
            "of the hand itself. " % model) if from_definition else "",
           "pass another model in the call, which wins over the definition, or change the "
           "model key of the definition" if from_definition else
           "drop the model parameter, and the hand runs on the model of its definition, or name "
           "sonnet or opus")
    )
    user_msg = (
        "manager-kit refused a handout: model %s on %s (effort %s, %s). %s "
        "MANAGER_KIT_NO_ROUTING stills this."
        % (model, hand or "a hand", effort, origin, counts)
    )
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": model_reason,
    },
    "systemMessage": user_msg,
}))
' 2>/dev/null) || out=

# THE REFUSAL GOES OUT WHATEVER HAPPENED TO THE PROGRAM ABOVE. The route-stop line is on the
# record by now. The text is fixed and written in the shell, it names the ways on and
# the switch, and it says that it is the short form.
case $out in
  *'"permissionDecision": "deny"'*) ;;
  *)
    out='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"manager-kit: this handout puts haiku on the repair hand, or cannot be read. Measured: haiku left one false report on a repair, n = 2. Drop the model parameter, and the hand runs on the model of its definition, or name sonnet or opus. MANAGER_KIT_NO_ROUTING in the environment stills this policy. This is the short form of the refusal: the full text could not be built."},"systemMessage":"manager-kit refused a handout: haiku on the repair hand, or one it cannot read. The full message could not be built, and the refusal stands. MANAGER_KIT_NO_ROUTING stills this."}'
    ;;
esac
printf '%s\n' "$out"
exit 0
