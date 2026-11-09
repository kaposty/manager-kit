#!/usr/bin/env bash
# The model routing rule, in one place, and the switch that stills it.
#
# WHAT THIS DECIDES AND WHAT IT DOES NOT. Which model and which effort an order gets is a
# judgement about the order and it lives with the manager: haiku, sonnet and opus are open at every
# effort. What is mechanical, and therefore here, is the one combination measured to do harm: haiku on
# the repair hand. Measured 2026-11-06 [the kit's own model and effort runs, l12 and l13]: haiku at
# high held a repair of kit code twice and reported falsely once, n = 2 on one task, and haiku at
# medium had reported falsely on the same task on 2026-11-05. So the refusal stands at every effort.
# On the hand that judges there was no false report and no rung complete in two runs, which is a
# warning in that hand's description; on the hand that builds, nothing. The rule before this one
# refused haiku on every hand from high upward. It rested on what the effort lever costs, which
# is no harm, and the parameter effort went round it.
#
# THE LIMIT, AND IT IS THE ONE THAT MATTERS. A hook knows the name of a hand and not the kind of work
# in the order: a repair handed to medium falls through this rule, and so does the same text as a
# project hand under another name, though the measurement says the same of both. That is named in
# GUIDE.md and in the refusal, because a refusal that seems to cover repairs would be a false promise.
#
# IT HAS TO BE A HOOK AND NOT A SENTENCE. Measured in this kit three times: a rule that
# only existed as prose ran green while forbidding something. GOAL.md carries the
# standing version of that finding.
#
# WHAT WAS READ OUT OF THE RUNTIME BEFORE ANY OF THIS WAS BUILT, against Claude Code
# 2.1.278 on 2026-11-02, because every line below rests on it:
#
#   the tool is called Agent, not Task.  4335 of 4335 real subagent launches in
#   ~/.claude/projects carry tool_use name "Agent"; "Task" appears in none of them. A
#   matcher entry spelled `Task` still selects it, because the matcher list is
#   canonicalised through a legacy alias table (`var i={Task:"Agent",...}`) before it is
#   compared, and the regex arm additionally tests the reverse aliases. So the WIRING
#   survives the old spelling and a hook that compares tool_name to "Task" does not: it
#   is handed "Agent". hooks/hooks.json names both for that reason.
#
#   model is optional and absent in 4290 of those 4335 calls (99.0 percent). Absent
#   means the hand runs on the model: of its own definition, which every hand this kit
#   ships names since 2026-11-05 and route-guard.sh reads; only a definition at inherit
#   or with no model: leaves the hand on the session's model, which is not visible in
#   the call at all. This rule therefore reaches a cheap model WRITTEN in the call or in
#   a definition and nothing else, which is named as a limit in GOAL.md rather than
#   papered over.
#
#   model is a closed set, read off the shipped input schema: sonnet, opus, haiku, fable, in
#   2.1.278 and in 2.1.318 alike. effort was not in that schema, in 2.1.278, and the rule of that day
#   was read out of the hand's definition for that reason. It is in the schema of 2.1.318 [strings in the
#   shipped binaries, 2026-11-07; 2.1.278 and 2.1.220 carry none]: optional, and its own text
#   allows it only when the user or an instruction file such as CLAUDE.md or a skill asks for a
#   specific effort. The call then wins over the definition in both directions [measured
#   2026-11-06, one question, 14 runs, one Mac: that the parameter takes effect, not that an
#   answer gets better]. The refusal does not depend on it, because the measurement does not, and
#   its text names the effort that applies: mk_route_effort_applied.
#
#   THE PREFIX IS THE NAME IN THE MANIFEST of the plugin, and nothing else [measured 2026-11-07 on
#   2.1.318, the system init line of a headless session under its own CLAUDE_CONFIG_DIR]: a
#   marketplace of another name, and a marketplace entry of another name, both left it manager-kit;
#   a manifest of another name changed it; with no manifest it is the name of the directory. So it
#   is read off the manifest next to this file. A project file of the same name is listed beside it,
#   xhigh and manager-kit:xhigh, as two hands, and a bare name no file gives is answered with "not
#   found" by the runtime [the string of that answer is read; no call was made].
#
#   model is ignored for subagent_type "fork": a fork always inherits the parent's model.
#   So a fork is never routed, however it is spelled. mk_route_verdict says so.

HERE_RT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
# WHERE THE KIT'S OWN HANDS ARE, derived from this file's own location and never from the
# working directory a hook happened to be called from. A plugin lives outside the project
# it serves, so the only thing that reliably knows where agents/ is, is the file next to
# it.
MK_ROUTE_AGENTS=${MK_ROUTE_AGENTS:-$HERE_RT/../agents}

# THE TWO CONSTANTS, AND THEY ARE THE ONLY TYPED THING IN THIS FILE.
#
# haiku, and not sonnet. It is the model the measurement caught reporting falsely, and it is in the
# closed set of the schema under this spelling. Sonnet at xhigh came complete and honestly reported on
# the same hand, 2026-11-05, and is that hand's suggested model. fable is not in this set: it sits
# above opus in the shipped tier text, read 2026-11-02.
MK_ROUTE_CHEAP="haiku"

# THE REPAIR HAND, by the name it ships under. Nothing in a handout says what kind of work it is, so
# the name is the whole of what can be read, and the description of the hand is what ties the name to
# the work: route_table_holds_row_by_row in tests/run.sh asks it. The owner decided the names stay.
MK_ROUTE_REPAIR_HAND="xhigh"

# THE MANIFEST THE PREFIX IS READ OFF, derived the way the agents are, and set here and not taken from
# the environment, because it decides which hands are ours. The parse in route-guard.sh reads it
# through mk_kit_name below, in the process that runs anyway.
MK_ROUTE_MANIFEST=$HERE_RT/../.claude-plugin/plugin.json

# WHAT THE PARSE OF route-guard.sh ADDS TO THE ONE READER, and it does not read the input a second
# time: these are functions over values MK_PY_INPUT already holds.
#
# mk_word IS THE GATE OF A WORD FROM THE PAYLOAD, and a value that is no word becomes a question mark.
# The characters are those of a model name, opus[1m] among them. Not a space and not an equals sign,
# because both forge a word of the line, and no NUL, which a command substitution drops, so that
# "ha\u0000iku" would arrive as haiku on the line without having been sent as that.
#
# mk_kit_name ANSWERS EMPTY FOR A MANIFEST IT CANNOT READ, and it cannot raise, because a parse that
# fails is a refusal that does not happen. Empty means every prefix counts as ours, which is the rule
# as it was until 2026-11-07 and the loud direction: a stranger's hand is refused rather than ours
# passed. A loaded plugin always has a name, so this is a state of a damaged install and not of a day.
# O_NONBLOCK for the reason mk_route_table gives: a pipe of that name must not hold the hook.
#
# mk_order_marks IS THE ONLY THING THAT LOOKS AT THE TEXT OF AN ORDER, AND NOTHING OF IT LEAVES: what
# it returns is built from fixed marks and the words it searches for, and the record cannot hold more
# than that. It judges nothing either. It is the instrument for how many real orders carry an
# acceptance and a command, read by counting lines. The tiers and both lists are derived from the
# 205 distinct calls in the transcripts of the project this was measured in: words of the
# narrower list hit 35 of 61 repairs and adding "all green" 51, while "gruen" or "test" also hit
# built-in lookups, 9 and 12 of 15. A command is a span in backticks that opens with a word of the list,
# or with ./, because any span at all hit 179 of 205 and a file name is no command.
MK_PY_ROUTE='
import os, stat
def mk_word(value):
    if value is None:
        return None
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9._\[\]-]{1,64}", value) else "?"
def mk_kit_name(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                return ""
            manifest = json.loads(os.read(fd, 65536))
        finally:
            os.close(fd)
        name = manifest.get("name")
        return name if isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,64}", name) else ""
    except Exception:
        return ""
def mk_order_marks(text):
    if text is None:
        return "(none)"
    if not isinstance(text, str):
        return "(other)"
    n = len(text)
    size = "0" if n == 0 else "500" if n < 500 else "2k" if n < 2000 else "5k" if n < 5000 else "10k" if n < 10000 else "more"
    cmd = re.search(r"(?:`[ \t]*|```[\w-]*\n[ \t]*)(?:(?:bash|sh|zsh|git|grep|rg|python[23]?|cd|sed|awk|find|printf|cat|perl"
                    r"|chmod|mktemp|claude|docker|kill|mv|ls|wc|jq|curl|diff|head|tail|npm|npx|yarn|pnpm|pytest|make|node|cargo|go"
                    r"|ruby|sort|uniq|stat|test|gh)[ \t]|\./\w)", text)
    accept = re.search(r"\b(?:abnahme\w*|abnehmen|abgenommen|fertig ist|fertig,? wenn|gilt als fertig|erledigt,? wenn"  # de-input: German words of acceptance
                       r"|fertig hei(?:ss|\u00df)t|acceptance|accepted when|done when|done means|definition of done|must pass"
                       r"|all green)\b", text, re.I)
    return "len:%s,cmd:%d,accept:%d" % (size, 1 if cmd else 0, 1 if accept else 0)
'

# mk_route_rank <effort> -> 1..5 on the product's scale, 0 for anything it does not name.
#
# 0 is not "shallow", it is "not on the scale", and every caller has to treat it as a
# thing it does not know rather than as a low number. An effort spelling this kit has
# never seen is somebody else's vocabulary and the kit does not rank it.
mk_route_rank() {
  case "${1-}" in
    low)    printf '1\n' ;;
    medium) printf '2\n' ;;
    high)   printf '3\n' ;;
    xhigh)  printf '4\n' ;;
    max)    printf '5\n' ;;
    *)      printf '0\n' ;;
  esac
}

# mk_routing_is_off -> true when the switch stills the routing.
#
# ONE VARIABLE AND ONE SPELLING. The name is derived and not invented: every variable
# under hooks/ that a PERSON is meant to set carries the MANAGER_KIT_ prefix, and
# MANAGER_KIT_SOCKET_DIR in _sessions.sh is the whole of that convention today. The MK_
# prefix is for names this code passes to itself, so a switch an owner reaches for cannot
# wear it.
#
# EMPTY AND 0 ARE NOT SET, anything else is. The one value-reading variable in this kit,
# MK_EXPLAIN, tests `= 1`, and that is right for a debug flag where a wrong value should
# be ignored and wrong for a switch whose whole job is to be reachable in a hurry: a
# person who writes `yes` or `true` on the way out of a bad week has to get the kill, not
# a silent no-op. 0 is excluded because a switch that fires when it is set to zero is a
# trap, and both arms are asserted.
#
# IT IS READ HERE AND SET NOWHERE. A kit that writes a project's environment has stopped
# being an instrument. mk_role_context reports its state into the role text instead.
mk_routing_is_off() {
  case "${MANAGER_KIT_NO_ROUTING:-}" in
    ''|0) return 1 ;;
    *)    return 0 ;;
  esac
}

# mk_route_table <root> [key] -> one "<name> TAB <kit|project> TAB <value>" line per hand this project can see.
#
# DERIVED FROM THE FILESYSTEM, NEVER TYPED, and in this kit that is not a style
# preference. A typed list of role carriers let an incomplete fix through green on
# 2026-11-01 because the fourth carrier was missing from it, and tests/mutate.py carries
# the typed list as a mutation for that reason. The file this has to catch is the seventh
# hand somebody adds next month.
#
# TWO DIRECTORIES, AND THEY ARE NOT MERGED, because they are two sets of hands to the runtime: a
# project's xhigh and the plugin's manager-kit:xhigh are listed side by side. The project's come first,
# so that a bare name finds them first; mk_route_lookup decides which of the two a call means.
#
# The name comes from the frontmatter `name:` and falls back to the filename stem, which
# is the same order the runtime resolves an agent by.
#
# THE SECOND ARGUMENT NAMES THE FRONTMATTER KEY, effort when it is left out. The model a
# definition asks for lives in the same block of the same files and resolves by the same
# precedence, so it is read by this one reader rather than by a second one that could
# drift from it on which directory wins.
#
# A VALUE IS ONE WORD FOR THE LINE OR IT IS (other). The file belongs to the project and it can still
# cut the line, at 400 characters, and whatever it says has to survive being a word of it. Rungs
# nobody has heard of stay what they are, so ludicrous still reads ludicrous.
mk_route_table() {
  _rt_root=${1-.}
  python3 -I - "${2:-effort}" "$_rt_root/.claude/agents" "$MK_ROUTE_AGENTS" <<'PY' 2>/dev/null || true
import glob, os, re, stat, sys

# A DEFINITION IS READ BY ITS HEAD. The frontmatter is the block at the top, so 64 KiB of it is the same
# read for every file that has one, and a project can ship a definition of any length: in lines of two
# bytes, 60 MB held the route hook 7.0 s [measured 2026-11-07 at 0464e26, 20 MB took 2.6 s].
DEF_HEAD = 65536
want_key = sys.argv[1]
for d, origin in zip(sys.argv[2:], ("project", "kit")):
    seen = {}
    order = []
    if not d:
        continue
    for path in sorted(glob.glob(os.path.join(d, "*.md"))):
        # A LINK IS FOLLOWED AND A PIPE IS NOT WAITED ON. A hand linked in from elsewhere is a hand
        # the runtime runs, so the routing has to read it; what is no plain file at the end of
        # that is no definition. O_NONBLOCK and not a test ahead of the open: measured 2026-11-06
        # at 9dc29df, a pipe named x.md held this hook past its budget on every handout.
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            # errors=: one byte that is no UTF-8 in ANY hand file raised past the except below,
            # the whole table came back empty, and a refusal fell out [measured
            # 2026-11-06 at 0bc14fe, under every locale].
            with os.fdopen(fd, encoding="utf-8", errors="replace") as fh:
                if not stat.S_ISREG(os.fstat(fd).st_mode):
                    continue
                text = fh.read(DEF_HEAD)
        except OSError:
            continue
        name = os.path.basename(path)[:-3]
        effort = ""
        lines = text.splitlines()
        # The frontmatter is the block between the first --- and the next one. A file
        # with no frontmatter still yields a hand, with an effort nobody named, because
        # "this hand exists and its depth is unknown" is a different answer from "no such
        # hand" and the verdict below has to be able to tell them apart.
        if lines and lines[0].strip() == "---":
            for line in lines[1:]:
                if line.strip() == "---":
                    break
                # AN INDENTED LINE IS NOT A KEY OF THE TOP. It belongs to the block above it, as in
                # experimental: with cacheTtl under it, and read as a key it can stand in for name:,
                # model: or effort: of the hand [MK-E2, 2026-11-08: a nested name: renamed the hand].
                if line[:1] in (" ", "\t"):
                    continue
                key, _, value = line.partition(":")
                key = key.strip()
                value = value.strip()
                if key == "name" and value:
                    name = value
                elif key == want_key and value:
                    effort = value if re.fullmatch(r"[A-Za-z0-9._\[\]-]{1,64}", value) else "(other)"
        if name not in seen:
            order.append(name)
        seen[name] = effort
    # Bytes as well: a hand with an umlaut in its name took the whole table down under US-ASCII.
    for name in order:
        sys.stdout.buffer.write(("%s\t%s\t%s\n" % (name, origin, seen[name])).encode("utf-8", "surrogateescape"))
PY
}

# mk_route_kind <subagent_type> <kit name> -> sets MK_RK to own, other or bare, from the strings alone.
#
# A PLUGIN HAND ARRIVES PREFIXED and this is the half that is easiest to get wrong. The
# subagent_type in a real call is "manager-kit:xhigh", not "xhigh": measured 2026-11-02
# over the same 4335 launches, 1505 of them name manager-kit:xhigh and not one names a
# bare xhigh. A comparison against the filename stem would have matched nothing at all,
# green, for every hand this kit ships. Built-in and project hands arrive bare
# (general-purpose, 80 calls), so the prefix has to be optional and not required.
#
# ONLY OUR OWN PREFIX IS OURS. Until 2026-11-07 any prefix was cut off, so another plugin's xhigh
# inherited this refusal and this table. An empty kit name is a manifest that cannot be read, and then
# every prefix counts as ours: see mk_kit_name. It sets a variable and prints nothing because it runs
# on every handout and the subshell of a $(...) is the one cost it would add.
mk_route_kind() {
  case "${1-}" in
    *:*)
      case "${2-}" in
        '') MK_RK=own ;;
        *)
          case "$1" in
            "$2":*) MK_RK=own ;;
            *)      MK_RK=other ;;
          esac ;;
      esac ;;
    *) MK_RK=bare ;;
  esac
}

# mk_route_lookup <root> <key> <subagent_type> <kit name> -> "<own|project|other> <value>"
#
# WHICH FILE A CALL MEANS. A prefixed hand of ours reads the kit's file and never the project's, a bare
# name reads the project's when the project gives one and else the kit's, and another plugin's hand
# reads nothing, because its definition is in a directory this hook does not know. With no such hand
# the value is empty, and the word says whose name it was. A hand that is not ours costs no python3.
mk_route_lookup() {
  mk_route_kind "${3-}" "${4-}"
  case "$MK_RK" in
    other) printf 'other \n'; return 0 ;;
    own)   _rl_want=${3#*:} ;;
    bare)  _rl_want=${3-} ;;
  esac
  [ -n "$_rl_want" ] || { printf 'other \n'; return 0; }
  mk_route_table "${1-.}" "${2-effort}" | awk -F '\t' -v want="$_rl_want" -v kind="$MK_RK" '
    $1 == want && (kind == "bare" || $2 == "kit") { print (($2 == "project") ? "project" : "own") " " $3; found = 1; exit }
    END { if (!found) print ((kind == "own") ? "own " : "other ") }'
}

# mk_route_model <root> <subagent_type> <kit name> -> the model that hand's definition names, or empty.
#
# EMPTY FOR inherit AND FOR NO KEY AT ALL, because both mean the same thing to the runtime:
# the hand runs on the parent's model, which is not visible here. A fork has no definition
# file and the runtime ignores model for it, so it never resolves to anything.
mk_route_model() {
  case "${2-}" in fork|*:fork) return 0 ;; esac
  _rm_found=$(mk_route_lookup "${1-.}" model "${2-}" "${3-}")
  _rm_model=${_rm_found#* }
  case "$_rm_model" in inherit) _rm_model= ;; esac
  printf '%s\n' "$_rm_model"
}

# mk_route_effort_applied <call effort> <definition effort> -> "<effort> <origin>"
#
# THE EFFORT THE LINE NAMES, AND WHERE IT CAME FROM. The call wins over the definition when it names
# one, which is the measured order [2026-11-06, see GUIDE.md]; the definition is what is left; and
# when neither names one the answer is (none) and none. The origin is a word of its own because
# effort=max reads the same whether a manager typed it or the file said it, which is the reason from=
# exists for the model.
#
# A CALL EFFORT IS WRITTEN ONLY IF IT IS A RUNG. The first argument comes out of the payload, cut down
# to one word of letters or a question mark by route-guard.sh, and what is not a rung of the scale
# mk_route_rank knows is written as (other), so the line is never built from what was sent. The scale
# is asked of mk_route_rank and not typed a second time here. A definition's effort has been made one
# word by mk_route_table and is not asked of the scale, because it is the project's vocabulary.
#
# IT JUDGES NOTHING. The refusal does not depend on the effort, whichever names it: the measurement
# does not vary with it. The text of the refusal says which effort applied, and this is where it reads it.
mk_route_effort_applied() {
  case "${1-}" in
    '')
      case "${2-}" in
        '') printf '(none) none\n' ;;
        *)  printf '%s definition\n' "$2" ;;
      esac ;;
    *)
      if [ "$(mk_route_rank "$1")" -gt 0 ]; then
        printf '%s call\n' "$1"
      else
        printf '(other) call\n'
      fi ;;
  esac
}

# mk_route_verdict <root> <model> <subagent_type> <kit name> -> "<pass|stop|off> <where> <effort>"
#
# <where> says whose hand it is, own, project, other or, with the switch set and no table read, bare.
# The effort is carried out so the log line and the refusal text both get it from the same read
# rather than asking twice, and it is last because it can be empty.
#
# WHAT IS REFUSED: haiku on the repair hand, at any effort, and a model that cannot be read there,
# because that cannot be told from haiku and the runtime sends no such value. It does not ask whether
# the definition could be read: the prefix and the name are enough, so an unreadable hand file takes
# no refusal down, and a bare xhigh no project file gives is still ours.
#
# WHAT IS NOT REFUSED, each with the reason, because a stop nobody can predict is worse
# than no stop:
#   every other hand of the kit, on any model at any effort. Measured harm stands on one.
#   no model in the call AND none in the definition. 99.0 percent of real calls carry no
#   model, measured, and route-guard.sh then hands this function the model of the
#   definition; only where that is inherit or missing is the model the session's, which
#   is in neither place and not in the payload of the hook either, so there is nothing to judge.
#   subagent_type fork. The runtime ignores model for a fork and the fork runs on the
#   parent's model, so refusing one would refuse a call that is not cheap.
#   another plugin's hand, even one named xhigh. It is not ours and it was not measured.
#   a project's hand, even one named xhigh. The runtime runs the project's file under that name, and
#   the same file under another name passes, so a stop here would hold a rename apart and protect
#   nothing. The measurement ran on project copies of the kit's text, so a project that copies that
#   text and drives it on haiku is exactly what was measured, and it passes: named in GUIDE.md.
mk_route_verdict() {
  _rv_root=${1-.}; _rv_model=${2-}; _rv_type=${3-}; _rv_kit=${4-}
  mk_route_kind "$_rv_type" "$_rv_kit"
  _rv_kind=$MK_RK
  if mk_routing_is_off; then printf 'off %s \n' "$_rv_kind"; return 0; fi
  _rv_found=$(mk_route_lookup "$_rv_root" effort "$_rv_type" "$_rv_kit")
  _rv_where=${_rv_found%% *}
  _rv_effort=${_rv_found#* }
  case "$_rv_type" in fork|*:fork) printf 'pass %s %s\n' "$_rv_where" "$_rv_effort"; return 0 ;; esac
  [ "$_rv_kind" != other ] || { printf 'pass %s %s\n' "$_rv_where" "$_rv_effort"; return 0; }
  [ "$_rv_where" != project ] || { printf 'pass %s %s\n' "$_rv_where" "$_rv_effort"; return 0; }
  [ "${_rv_type#*:}" = "$MK_ROUTE_REPAIR_HAND" ] || { printf 'pass %s %s\n' "$_rv_where" "$_rv_effort"; return 0; }
  case " $MK_ROUTE_CHEAP (other) " in
    *" $_rv_model "*) printf 'stop own %s\n' "$_rv_effort"; return 0 ;;
  esac
  # THE CHEAP END IN ANY SPELLING, because a definition may write a full model id or another case, and the word
  # haiku alone let claude-haiku-5-5 pass in silence [measured 2026-11-07 at a7dc5a9]. Written out letter by letter:
  # the pattern is the same under any collation, and bash 3.2 has no ${var,,}.
  case $_rv_model in
    *[Hh][Aa][Ii][Kk][Uu]*) printf 'stop own %s\n' "$_rv_effort"; return 0 ;;
  esac
  printf 'pass %s %s\n' "$_rv_where" "$_rv_effort"
}
