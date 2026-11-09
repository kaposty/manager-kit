---
description: What the transcripts on this machine cost at list price, per role and model, as a lower bound
argument-hint: "[--since YYYY-MM-DD] [--until YYYY-MM-DD] [--exclude TEXT]... [--causes] [--context] [--hands] [--what-if] [--compare A B]"
---

Run the block below exactly as it stands, in one Bash call, and give the user its output in
full, the table included. Do not round it, sum it again or turn it into a percentage of a limit.

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
    p = os.path.join(r, "tools", "mk-cost.sh")
    if os.path.isfile(p):
        print(p)
        break
PY
)
if [ -n "$MK" ]; then bash "$MK" $ARGUMENTS; else
  printf 'manager-kit: tools/mk-cost.sh is not reachable from this session.\n'
  printf 'None of CLAUDE_PLUGIN_ROOT, PATH, the installed_plugins.json entries recorded\n'
  printf 'for THIS project, or the working directory names a copy of it, so nothing was read.\n'
  false
fi
```

The resolution of the kit is the one `/manager-kit:take-over` uses, line for line, with the
name of the tool changed; the suite holds the two together.

## What the number is

Say this in your own words after the table, briefly:

- It is **list price**, in dollars from `tools/prices.tsv`, with the day those
  prices were read in the head. It is **not limit points**: what a plan counts against its
  weekly limit is not this number and cannot be read off it.
- It is a **lower bound** (the head says LOWER BOUND). Calls that write no line into a transcript, the
  compaction call first among them, are not in it.
- If the command printed one line and no table, that line is the reason, and there is no
  number on purpose: the transcripts no longer look the way the meter reads them, or a model
  has no price row. Pass the line on as it stands.

With `--hands` the command prints each hand's plan beside what ran instead of the table: the
plan is the route line of the route guard that carries the same `tool_use_id` as the hand,
what ran is the model and effort in its transcript, and a difference is a line of its own;
give it to the user as it stands.

With `--what-if` it prints instead what the hand rounds would have cost had every hand run on
the newest Opus of `tools/prices.tsv`, with the same tokens, beside what they did cost, per
hand type and in sum. A round that ran on any Opus and every manager round keep their price.
The same tokens are an assumption, and the head says why the saving is an upper bound; say so
when you pass the number on.

With `--compare A B`, each window written `YYYY-MM-DD..YYYY-MM-DD` in UTC days and A ending
before B begins, it prints the dollars per active day of both windows and judges the difference
only against a band of how much such windows differ on this machine without a change, cut from
the days before A. **"not distinguishable"** means the difference lies inside that band: report
it as no measurable difference, never as a saving and never as a percentage. One line instead
of a report is the reason there is no verdict, most often too few days of history before A;
pass it on as it stands.

With `--causes` it prints instead what the cache writing of the window comes from: every round
that writes cache gets one cause (Start, Growth, expired>5m, idle>1h,
after-compaction, Other), judged by the gap to the round before it in the same file against
the TTL of the last write, with rounds, dollars, the share of all costs of the window, and
tokens and dollars per round. Other is what no rule reads, counted openly. A last line counts
the compactions once each, with their trigger and the median context before and after. Give
it as it stands.

With `--context` it prints instead the manager's own tool loops and the context cap `C*` of
this machine. A loop is the rounds of the main session between two inputs; a tool result does
not end it, and a hand is no loop of the manager. Per length (1, 2-3, 4-7, 8-15, 16-31, 32+) it
prints loops, rounds, dollars and the share of all costs, then the loops from 8 rounds with
dollars per loop and the median context. Then `C* = S + g T*` with `T* = sqrt(2K / (r g))`,
each input with its count and where it comes from. The first round after a compaction is
measured; the compaction call itself is in no transcript, so that part of K is **estimated**
from `preTokens` and `postTokens`, and the line says so: pass that on with the number. A last
line `no C*` is the reason there is no cap, most often no compaction in the window; the loops
above it still hold.
