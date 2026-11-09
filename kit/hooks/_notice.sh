#!/usr/bin/env bash
# THE CONTEXT LINE AND THE LOOP LINE, the two things the main session is told about its own cost.
#
# Measured on the machine this was built on, 2026-10-01 to 11-07 (tools/mk-cost.sh --context): the
# cost of the coordinating session lies in its context and in its own tool loops. A hook cannot
# compact, so all it can do is tell the session once that the time has come to ask the person, who
# can, at the next pause. Two triggers, each said ONCE:
#   the context of the last round is over the cap C, said again only after it fell back to C or
#   under it (a compaction) and crossed it anew;
#   the own loop since the last input has reached MK_LOOP_ROUNDS rounds while the context is over
#   MK_LOOP_CONTEXT, said again only in a loop after the next input.
# Each is one short line through additionalContext, which reaches the model and is no chat message:
# read out of Claude Code 2.1.318 on 2026-11-08, a PreToolUse hook's additionalContext becomes an
# attachment of type hook_additional_context and is handed to the model as "<hook> hook additional
# context: <text>", the same way the UserPromptSubmit stamp is.
#
# WHAT A ROUND AND AN INPUT ARE is the rule of tools/mk-cost.sh --context, so the line counts what the
# report counts: a round is one answer, keyed by message.id and requestId, <synthetic> left out; its
# context is input, read and written cache of its last line; an input is a user line that is no tool
# result, no isMeta and no isCompactSummary. The loop is counted in the transcript and not by a
# counter between the stamp and the guard: a task notification starts a loop for the report and fires
# no prompt hook, and the guard does not run on a round that only reads.
#
# WHAT IS READ: the last MK_NOTICE_REACH bytes of the transcript at most, backwards in steps of
# MK_NOTICE_STEP, and only as far as the answer needs: the last round for the context, back to the
# last input for the loop. A loop whose input lies further back is not counted, and says nothing.
#
# FAILURE IS SILENCE. A transcript that is missing, empty, no plain file or broken, a record that is a
# link, a directory, longer than MK_KIT_SMALL or not the kit's own, a record that cannot be written:
# no line, nothing written, and the refusal of the guard never passes through here. A line is only
# said after its record landed, so a record that cannot be kept cannot make a line come every call.
MK_CONTEXT_CAP_DEFAULT=300000
MK_LOOP_ROUNDS=8
MK_LOOP_CONTEXT=150000
MK_NOTICE_STEP=262144
MK_NOTICE_REACH=4194304
MK_NOTICE_NAME="manager-kit.notice"

MK_PY_NOTICE='
import sys, json, zlib

def mk_is_input(d):
    if d.get("type") != "user" or d.get("isMeta") is True or d.get("isCompactSummary") is True:
        return False
    m = d.get("message")
    c = m.get("content") if isinstance(m, dict) else None
    if isinstance(c, list):
        return not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)
    return isinstance(c, str)

def mk_tokens(u, k):
    v = u.get(k)
    return v if isinstance(v, int) and v >= 0 else 0

def mk_transcript(path, loop):
    # -> (context of the last round or None, rounds since the last input, the key of that input or None)
    ctx, keys, key = None, set(), None
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return None, 0, None
        end = pos = st.st_size
        step, reach = int(os.environ["MK_NOTICE_STEP"]), int(os.environ["MK_NOTICE_REACH"])
        carry = b""
        while pos > 0 and end - pos < reach:
            n = min(step, pos)
            pos -= n
            parts = (os.pread(fd, n, pos) + carry).split(b"\n")
            carry = parts.pop(0) if pos > 0 else b""
            # A LINE LONGER THAN THE REACH is no line this can judge, and whether it was an input nobody can say,
            # so the loop is not counted past it. Kept, it would be copied once a step, and a reader that went too
            # far would grow with the file instead of with the step.
            if len(carry) > reach:
                carry, loop = b"", False
            for line in reversed(parts):
                if b"\"usage\"" not in line and b"\"user\"" not in line:
                    continue
                try:
                    d = json.loads(line.decode("utf-8", "replace"))
                except ValueError:
                    continue
                if not isinstance(d, dict):
                    continue
                m = d.get("message")
                if isinstance(m, dict) and isinstance(m.get("usage"), dict) and m.get("model") != "<synthetic>":
                    u = m["usage"]
                    if ctx is None:
                        ctx = sum(mk_tokens(u, k) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
                    if loop and key is None:
                        keys.add((str(m.get("id")), str(d.get("requestId") or "")))
                elif loop and key is None and mk_is_input(d):
                    key = d.get("uuid") if isinstance(d.get("uuid"), str) and d.get("uuid") else "line %08x" % zlib.crc32(line)
                if ctx is not None and (not loop or key is not None):
                    return ctx, len(keys), key
    finally:
        os.close(fd)
    return ctx, len(keys), key

def mk_notice():
    env = os.environ
    sid, event, root = env.get("MK_NOTICE_SESSION", ""), env.get("MK_NOTICE_EVENT", ""), env.get("MK_DOOR_ROOT", "")
    if not sid or not root:
        return []
    loop = event == "PreToolUse"
    cap, why = int(env["MK_CONTEXT_CAP_DEFAULT"]), ""
    raw = env.get("MANAGER_KIT_CONTEXT_CAP", "").strip()
    if raw:
        if raw.isascii() and raw.isdigit():
            cap = int(raw)
        else:
            why = " (MANAGER_KIT_CONTEXT_CAP is no whole number of tokens, so the default is used)"
    ctx, rounds, key = mk_transcript(env.get("MK_NOTICE_TRANSCRIPT", ""), loop)
    if ctx is None:
        return []
    home = mk_home(root)
    name = env["MK_NOTICE_NAME"]
    try:
        fd = mk_file(home, name, os.O_RDONLY)
        try:
            data = os.read(fd, int(env["MK_KIT_SMALL"]) + 1)
        finally:
            os.close(fd)
        made = False
    except FileNotFoundError:
        data, made = b"", True
    if len(data) > int(env["MK_KIT_SMALL"]):
        return []
    was = {}
    if data.strip():
        was = json.loads(data.decode("utf-8"))
        if not isinstance(was, dict) or set(was) != {"session", "above", "loop"}:
            return []
    mine = was if was.get("session") == sid else {}
    above, said_loop = mine.get("above") is True, mine.get("loop")
    lines = []
    if cap > 0:
        if ctx > cap and not above:
            lines.append("manager-kit: the context is %d tokens, over the cap of %d%s. The person can compact at the next pause." % (ctx, cap, why))
            above = True
        elif ctx <= cap:
            above = False
    if loop and key is not None and key != said_loop and rounds >= int(env["MK_LOOP_ROUNDS"]) and ctx > int(env["MK_LOOP_CONTEXT"]):
        lines.append("manager-kit: your own tool loop has run %d rounds since the last input, at %d tokens of context. The person can compact at the next pause." % (rounds, ctx))
        said_loop = key
    # Written only when what was said moved, so a session that never crosses leaves no file behind.
    if (above, said_loop) != (mine.get("above") is True, mine.get("loop")):
        body = json.dumps({"session": sid, "above": above, "loop": said_loop}).encode("utf-8")
        if made:
            fd = mk_file(home, name, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        else:
            fd = mk_file(home, name, os.O_WRONLY)
        try:
            os.ftruncate(fd, 0)
            if os.write(fd, body) != len(body):
                return []
        finally:
            os.close(fd)
        if made:
            mk_exclude(root)
    return lines

try:
    said = mk_notice()
except Exception:
    said = []
if said:
    text = "\n".join(said)
    if os.environ.get("MK_NOTICE_EVENT") == "PreToolUse":
        print(json.dumps({"suppressOutput": True, "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}}))
    else:
        sys.stdout.write(text)
'

# mk_kit_notice <root> <session id> <transcript> <event> -> the lines that are due, and nothing else. For
# PreToolUse a whole hook answer in JSON, for UserPromptSubmit the bare text, which the stamp puts under its
# role line. The plain tests come first and cost no process, so a call with no transcript starts nothing. What the
# transcript is, is asked of the open file and not of its name: a pipe is opened without waiting and read as no file.
mk_kit_notice() {
  [ -n "${2-}" ] && [ -n "${3-}" ] || return 0
  mk_record_home "${1-}" || return 0
  [ -d "${1-}/.claude" ] || return 0
  MK_DOOR_ROOT=$1 MK_NOTICE_SESSION=$2 MK_NOTICE_TRANSCRIPT=$3 MK_NOTICE_EVENT=${4-} MK_NOTICE_NAME=$MK_NOTICE_NAME \
  MK_CONTEXT_CAP_DEFAULT=$MK_CONTEXT_CAP_DEFAULT MK_LOOP_ROUNDS=$MK_LOOP_ROUNDS MK_LOOP_CONTEXT=$MK_LOOP_CONTEXT \
  MK_NOTICE_STEP=$MK_NOTICE_STEP MK_NOTICE_REACH=$MK_NOTICE_REACH MK_KIT_SMALL=$MK_KIT_SMALL \
    python3 -I -c "$MK_PY_DOOR$MK_PY_NOTICE" 2>/dev/null
  return 0
}
