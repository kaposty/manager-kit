---
description: Hand the coordinating role in this repository to this session, without closing anything
---

Run the block below exactly as it stands, in one Bash call, and report its output to the
user in full. Do not summarise it, and do not soften a refusal: the point of this command
is that the person can read which session holds the role now, which one just lost it, and
what has not caught up yet.

```bash
MK=$(python3 -I - <<'PY'
import json, os
roots = []
# Set for a hook, and possibly for this. It is tried first and costs nothing when it is
# not there, so the block does not depend on whether it is substituted here.
if os.environ.get("CLAUDE_PLUGIN_ROOT"):
    roots.append(os.environ["CLAUDE_PLUGIN_ROOT"])
# Claude Code puts <install path>/bin of every enabled plugin on PATH, so this session's
# own PATH names the copy it started with [read out of the PATH of a Bash call on
# 2026-09-07: .../plugins/cache/manager-kit/manager-kit/0.3.0/bin].
roots += [os.path.dirname(p) for p in os.environ.get("PATH", "").split(os.pathsep) if p]
# The record the installer keeps, which names the exact install path per scope AND the
# project each entry was installed for.
#
# FILTERED BY THAT PROJECT, because the register holds one entry per project and they do
# not point at the same copy. Measured 2026-11-02 on the machine this was built on: 8
# entries for manager-kit, 5 distinct projectPath, 3 distinct versions, all 8 installPath
# present on disk with a claim script in them. Taking the first that carried one resolved
# every project to .../manager-kit/0.9.0, including the project whose own entry records
# .../manager-kit/0.13.0, so the role was moved by a copy the register does not name for
# it, chosen by the order of a JSON object.
#
# THE RULE IS A PREFIX TEST AND NOT mk_project_root, which is where this kit keeps that
# rule and the only place it is allowed to live. The exception is forced: this block is
# resolving WHERE THE KIT IS, so it cannot source a file it has not found yet, and a
# second copy of that climb inside a markdown block would be the drift that rule exists to
# prevent. So the narrower question is asked instead and written down: an entry answers
# for a directory that IS its recorded project or lies under it, and the most specific
# such entry wins. An entry with no projectPath is a user scope install, recorded for
# every project, so it answers for this one and answers least specifically.
cfg = os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")
try:
    reg = json.load(open(os.path.join(cfg, "plugins", "installed_plugins.json")))
except Exception:
    reg = {}
here = os.path.realpath(os.getcwd())
def covers(p):
    p = os.path.realpath(os.path.expanduser(p))
    if here == p or here.startswith(p.rstrip(os.sep) + os.sep):
        return len(p)
    return -1
hits = []
# NOT FILTERED BY NAME. The name of a copy is in its manifest, and this block is looking for that copy, so it cannot read
# it; a name typed here left a fork under another name without its own entry. What marks a copy of this kit is the
# script the loop at the end asks every candidate for, so that loop is the filter.
for entries in (reg.get("plugins") or {}).values():
    for e in entries or []:
        if not e.get("installPath"):
            continue
        rank = covers(e["projectPath"]) if e.get("projectPath") else 0
        if rank >= 0:
            hits.append((rank, e["installPath"]))
hits.sort(key=lambda h: -h[0])
roots += [p for _, p in hits]
# Standing in the kit's own checkout.
roots.append(os.getcwd())
for r in roots:
    p = os.path.join(r, "tools", "manager-claim.sh")
    if os.path.isfile(p):
        print(p)
        break
PY
)
if [ -n "$MK" ]; then bash "$MK"; else
  printf 'manager-kit: tools/manager-claim.sh is not reachable from this session.\n'
  printf 'None of CLAUDE_PLUGIN_ROOT, PATH, the installed_plugins.json entries recorded\n'
  printf 'for THIS project, or the working directory names a copy of it, so the role was\n'
  printf 'NOT moved. Check that the plugin is installed in this project and that this\n'
  printf 'session was started after it was.\n'
  false
fi
```

The block decides nothing. It resolves where `tools/manager-claim.sh` lives and runs it.
Every check, every refusal and every line of the output belongs to that script, so what
this command does can be tested without a model in the loop.

## What to say afterwards

Pass the script's output on, and add nothing to it. Three things in it matter and none of
them is yours to reword:

- **A refusal is a refusal.** If the script says it wrote nothing, the role did not move.
  Say so plainly and do not try again by writing `.claude/manager-kit.role` yourself: a
  record with a pid the script refused to name is the failure it exists to prevent.
- **The boundary moves with the next turn**, not with this one. The prompt hook and the
  role guard read the file fresh every time, so the session that held the role before is a
  carrier from its next turn on.
- **The long role text lags.** It is injected at `SessionStart`, and this session already
  had its start. Until a restart, a `/clear` or a compaction, this session gets the
  one-line stamp every turn and the guard names the role when it refuses, but not the full
  text. That is a limit, not a fault, and the user should hear it.

If the user ran this in the wrong session, the way back is the same command in the right
one. Nothing has to be closed.
