# manager-kit, in more detail

## The three carriers of one identity

A session has to know which role it holds, and it has to still know it after a
compaction. One hook cannot promise that, so three carry it:

| Hook | Event | What it carries |
|---|---|---|
| `manager-prime.sh` | `SessionStart` `startup\|clear` | the full role text, and the claim |
| `manager-reinject.sh` | `SessionStart` `compact\|resume\|fork` | the same text, byte for byte |
| `manager-stamp.sh` | `UserPromptSubmit` | one line, every turn |

**Why three.** A running auto-compaction fires `SessionStart` not at all, and after a
manual `/compact` the reinject can arrive behind the next message. So "it knows straight
afterwards that it is the manager" is not deliverable through `SessionStart` alone. A
prompt hook cannot lose that race, which is why it carries the short line. The guard is
the third carrier and the sturdiest: its refusal names the role, and nobody can forget
to call it.

The first two build their text through one function over one file, so the primed text
and the reinjected text cannot drift apart. `tests/run.sh` asserts they are byte
identical.

## How the role is decided

1. Count the live sessions that are in this PROJECT. The register is the socket directory
   Claude Code keeps, one `<pid>.sock` per session; the working directory comes from the
   operating system, and each one is mapped to its project the same way the record is.
2. Alone in the project means manager, and the decision is recorded.
3. Not alone means carrier, unless the record already names you.
4. If the recorded manager's process is gone, the role is taken over rather than left
   vacant. A guard that goes quiet because its owner died is the exact failure this kit
   exists to catch.

The census prints its base set, how many were alive, how many were dead, how many are
here, and whether alive plus dead equals the base set. No branch of it truncates, and
`tests/run.sh` greps for that. The reason is a measured one: a count over a fleet that
comes from a command carrying an upper bound reports the length of its own list, not a
finding, and an empty base set looks exactly like a green result.

## The second way the role moves

`SessionStart` is one route into the role file and it is the only automatic one that MOVES
the role. The other is typed: `/manager-kit:take-over`, in the session that should
coordinate. A third writer exists and it moves nothing: `manager-stamp.sh` records the
session that already holds the role when the record has gone stale about which process that
session is, and the section after this one is what it is for.

| | `SessionStart` | `/manager-kit:take-over` |
|---|---|---|
| when | startup, `/clear` | when a person types it |
| entitlement | the census measured this session alone in the directory | none, it is a decision |
| pid | `mk_own_pid` | `mk_own_pid` |
| session id | the real one, out of the hook input | the real one when it can be measured, otherwise `claimed-by-pid` |
| refuses when | it is not alone | it cannot measure a pid |

The command file holds no decision. Its one bash block resolves where
`tools/manager-claim.sh` lives and runs it, and the measurement, the refusal and the report
are all that script's. A command whose behaviour depends on how a model reads its prose
cannot be tested; `tests/run.sh` lifts that block out of the Markdown and runs it, and
requires there to be exactly one, because a command that spreads shell over several blocks
has started keeping some of the work in the prompt.

**The second field of the record is the session id when the command can measure one, and
0.15.0 is where that changed.** Until then it was always a placeholder, on this measurement:
"a Bash call cannot learn this session's id [2026-09-07: the environment carries
`CLAUDE_CODE_HOST_SESSION_ID`, which is a different identifier, and nothing else that names
the session]". That measurement has expired. Measured 2026-09-29 out of an ordinary Bash tool
call under Claude Code 2.1.284, `CLAUDE_CODE_SESSION_ID` carries the same id the hooks are
handed as `session_id`, cross-checked against the path of that session's scratchpad, which
carries the same UUID. And `CLAUDE_CODE_HOST_SESSION_ID` is not a different identifier at all:
it is that id with a `local_` prefix.

**Guessing is still forbidden, and that is why two things have to agree before the id is
taken.** `manager-stamp.sh` compares the recorded session id BEFORE the pid and
`mk_guard_role` does the same, so a second field naming somebody else hands them the role and
stands the real holder's guard down.

| the command takes the id only when | and it is not taken when |
|---|---|
| `CLAUDE_CODE_SESSION_ID` has the shape the hooks are handed: 36 characters, lowercase hex, grouped 8-4-4-4-12 | it is absent, empty, carries the `local_` prefix of the host id, is in the wrong case, or carries a second word |
| `CLAUDE_PID` names the very process `mk_own_pid` measured off the parent chain | `CLAUDE_PID` is absent, unreadable, or names another process, which is what an environment inherited from elsewhere looks like |

The shape is derived rather than felt: counted 2026-09-29 over the 180 session transcripts
under `~/.claude/projects`, whose file names are the session ids the hooks are handed, 180 of
180 have exactly that shape. The `local_` prefix is refused rather than stripped, because
stripping it would be a guess about a variable whose shape nobody has measured over more than
one session. And a subagent is not a hole in this: measured the same day from a handed-out
hand, `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` were the coordinating session's own values, so
a take-over typed inside a hand records the session whose hand it is, which is the session
`mk_own_pid` already writes into field 1.

**When either half is missing the placeholder is written, exactly as in 0.14.0.** It cannot
collide with a real id, and it is not empty either: `mk_guard_role` reads an empty second
field as undecidable and answers manager for every session in the directory. It then heals on
the holder's NEXT PROMPT, in `manager-stamp.sh`, which recognises the record by the pid and
writes the real session id in. That fallback is why the repair is safe to make; what it is not
is sufficient, because the pid is the whole of the identity until that prompt arrives, and in
the day 0.15.0 was written for the process changed before any prompt did [measured 2026-09-29
against the delivered 0.14.0 in a live project: the record read `1453 claimed-by-pid` from a
take-over at 14:51:04, the coordinating session restarted, it was greeted as a carrier, and
the person had to type `/manager-kit:take-over` a second time]. Waiting for the next
`SessionStart` was the answer before that and it only worked for matcher `startup` and
`clear`; a `resume`, a `fork` and a compaction reach `manager-reinject.sh`, and that one
did not claim. Since 2026-11-03 it claims a record whose pid no longer answers, by the rule
a startup claims by, and leaves every other record alone.

**What the repair does not buy, and nobody should expect it to.** A new conversation carries a
different session id and a different process. It reads the record as somebody else's, stays a
carrier, and needs `/manager-kit:take-over` again. What survives without anybody typing
anything is a restart that KEEPS the session id, which is what a `resume` is. Whether a
`fork` keeps it was not measured here and is not claimed either way. The command prints that
distinction at the end of its report rather than leaving it to be discovered.

**Which directory the record is written for is measured, not assumed.** It is the working
directory of the SESSION process, taken with the same `lsof` the census uses, and not the
one the shell happens to stand in. A shell that has been `cd`'d into a subdirectory would
otherwise leave the file where nothing reads it, and the person would be told the role had
moved.

## When a coordinating session comes back as a new process

A compaction does not restart anything: measured 2026-09-11 in a live project, one process
carried one session across a manual `/compact` and is still that process. A `resume` and a
`fork` DO start a new one, with the same session id and a new pid, and then the record names
a process that has stopped existing.

Every reader answers the same thing about that record: the owner is gone, the chair is
vacant, and vacant counts as mine. So the session goes on coordinating and goes on being
guarded, and nothing looks wrong. What is wrong is the record, and the next session to START
in that project reads the same vacancy through `mk_decide_role`, which carries `claim`, and
writes itself in. The role leaves a session that is sitting right there, on no command, and
only `/manager-kit:take-over` writes a `handover` line, so nothing records the move.

Measured 2026-09-11 against the delivered 0.12.0, in the project that found this: the record
read `46573 claimed-by-pid` from a take-over the evening before, the coordinating session
came back at 09:22:52 as a new process, an unrelated session started at 09:32:20, and one
second later the record named that one. The log carried four lines that day and none was a
handover.

`manager-stamp.sh` closes it, on the first prompt, and **it never moves the role**. It writes
only for a session the record ALREADY names, and it writes only that session's own pid and
session id:

| the record says | what happens on the next prompt |
|---|---|
| nothing at all | nothing is written; what a session alone should be told is still open |
| `<my pid> <my session id>` | nothing is written, the record is already right |
| `<my pid> claimed-by-pid` | the placeholder becomes this session id |
| `<any other pid> <my session id>` | this session's pid is written in |
| `<another live pid> <another id>` | nothing is written, that is somebody else's chair |
| `<a dead pid> <another id>` | nothing is written; every reader still answers manager |

The third row is what makes the second one possible whenever the placeholder is still being
written. Since 0.15.0 `/manager-kit:take-over` writes the real session id when it can measure
one, so that row is reached less often; when it cannot, the pid carries the whole identity and
a restart erases it, and turning the placeholder into a session id on the first prompt is what
leaves the restart something to recognise itself by. In the day above the take-over was at
17:57 and the session worked until 09:22, so hundreds of prompts came first. The day that
0.15.0 was written for is the same record with NO prompt in between, which is the case this
row cannot reach and the take-over now closes at the source.

The LAST row is the one that decided the shape, and it is the obvious repair rejected. "Whoever
finds a dead owner and decides manager records itself" is not the same rule: a dead pid next
to the placeholder looks identical from every session in the project, so under that rule the
first session to submit a prompt takes the record and turns the real holder into a carrier,
whose guard then stands down. Today all of them are refused instead, which is a false stop,
and this kit holds a false stop to be the cheaper half of being wrong. So a vacancy nobody can
prove is theirs is left exactly where 0.12.0 left it.

It refuses rather than writing half a record: with no pid measurable, or no session id in the
hook input, it leaves the file exactly as it is, because a first or second field that will not
parse makes `mk_guard_role` call every session in the project the manager and the prompt hook
call every one of them a carrier.

**What it costs and what it moves.** Two writes in the life of a session, one after a
take-over and one after a restart; the turn after either, the record already reads
`<my pid> <my session id>` and nothing is written. No verdict code changes. One shape of the
record becomes reachable sooner, `<another live pid> <my session id>`, which happens in the
seconds between a `resume` and the death of the process it replaces: `mk_guard_role` has
always answered manager there, so the guard refuses where it used to stand down. That is one
false stop traded for one silent pass, in the direction this kit states, and it is not a new
shape: a session that never used take-over reaches it under 0.12.0 already.

**Two things this does not close, and they want the same missing line.** A record that is
already `<a dead pid> claimed-by-pid` when this version arrives, from a take-over whose
session never got a prompt before its process changed, still falls to the next session that
starts. Since 0.15.0 the take-over writes a session id instead of that placeholder whenever
it can measure one, so what this row describes is now the record left by a take-over whose id
could NOT be measured: it is narrower and it is not gone. And when a holder really is gone for
good, the session that takes the empty chair takes it in silence, because `claim` writes no
`handover` line. Both need that line.

## Where the record is kept

`.claude/manager-kit.log`, `.claude/manager-kit.role` and `.claude/manager-exception` are
kept once per PROJECT, and every hook derives that project with one function,
`mk_project_root` in `hooks/_sessions.sh`. Anchored at the working directory instead, a
session standing in a subdirectory writes a second record nothing reads: measured
2026-09-07 in a live project, a session in `.claude/agents` left the only `guard-ran` line
of that day in `.claude/agents/.claude/manager-kit.log`, and `tools/week-verdict.sh`, which
reads the top of the project, counted that day as one the guard slept through. The role
file and the marker split the same way and fail worse: a session that finds no role file
may call itself the manager, and a marker spent where nobody reads it buys a crossing that
is on no record.

The project is the repository, found by climbing for a `.git`. With no repository, it is
the nearest ancestor that already keeps a `.claude/`; with neither, it is the working
directory, which is what every one of these paths used to be. Three properties are worth
naming:

- **A linked worktree is recorded at its main repository, since 0.12.0.** A worktree keeps
  its `.git` as a FILE naming a `gitdir:`, and until 0.11.0 the climb read that file as a
  repository of its own. Measured 2026-09-09 in a project that runs one worktree per
  session: 279 worktrees, **12 separate logs**, and `tools/week-verdict.sh` reads exactly
  one of them, so a whole week's verdict rested on a twelfth of the record. A submodule is
  still its own project, and `git log` inside it reports the history the week is weighed
  against; so is a worktree whose main repository would be barred, a dotfiles repository at
  `$HOME` being the ordinary case.

  **The price was named before it was paid, and it was paid on purpose.** The paragraph
  this one replaces predicted it exactly: one role file for a whole repository means one
  manager for all of it and a guard standing down in every other worktree. Measured
  2026-09-09 through the delivered hook, six sibling worktrees: 5 of 5 work writes STOPPED
  and 10 events recorded under the old rule, 5 of 5 PASSED IN SILENCE and nothing recorded
  under this one. The trade was taken because the split record fails in EVERY project that
  uses worktrees, while the standing down bites only where several sessions run at once,
  and that is a condition of use a project can state and hold. Separating the role file
  from the record would remove the price altogether and is a change to the guard's
  behaviour, deferred rather than forgotten.
- **The walk never ends at `$HOME`.** That directory is the person's own Claude
  configuration, not a project of theirs, and one record shared by everything they own
  would be worse than the split it replaces. `check.sh` bounds its own upward walk for the
  same reason.
- **It is climbed, not asked of `git`.** Measured 2026-09-07: `git rev-parse
  --show-toplevel` costs 8.968 ms against 0.133 ms for the climb, on a guard that runs at
  every tool call and costs 33.3 ms in all. The two were compared over repository,
  subdirectory, linked worktree, worktree subdirectory, submodule, submodule subdirectory,
  nested repository and no repository at all, and agreed on all eight.

**What the command cannot do.** It cannot inject the long role text: that is a
`SessionStart` carrier and this session already had its start. Until a restart, a `/clear`
or a compaction, the session that just took the role gets the one-line stamp every turn and
the guard's refusal names the role, and that is all. The command says so in its own output
rather than leaving it to be discovered.

## How the guard decides

```
tool is Bash ?  ->  pattern match over the command
otherwise    ?  ->  classify tool_input.file_path

under a .claude directory  -> bookkeeping
name ends in .md           -> bookkeeping
in the session scratchpad  -> bookkeeping
anything else              -> work
```

The path it tests is the one a write reaches: `..` is walked and a symlink is followed, and in
a command a relative target is read behind the `cd` in front of it. On `Bash` the targets come
out of the redirections and the write verbs, `mkdir`, `touch`, `patch`, `curl -o` and `tar -x`
among them; `README.md` lists them and names what stays unread.

The `.claude` test is on `/.claude/` and not on `.claude` loosely, because
`.claude-plugin/plugin.json` is kit source and a loose match would wave it through.

The scratchpad test is on `/tmp/claude-<uid>/<project>/<session>/scratchpad` and what lies
under it, in either spelling of `/tmp`, and not on `/tmp` loosely: a throwaway script in
`/tmp` is still work. That boundary was measured, not chosen for tidiness. Everything
outside the work tree would have been the wider rule, and it silences at least 202 stops
that were writing real code into a worktree.

For a Bash command the scratchpad answer has one condition on it, and it is the last thing
the measure asks:

```
a target is quiet ONLY because of the scratchpad, and the command
  writes a script and RUNS it in the same call         -> the scratchpad does not answer
  hands a heredoc body to something that RUNS it       -> the scratchpad does not answer
  carries a git subcommand that rewrites the tree      -> the scratchpad does not answer
```

The first two ask one more thing: the body the measure cannot read has to name a path that
this same measure calls work. Without that, a scratchpad script that rewrites a Markdown
plan would be a stop, and 22 of the 25 false alarms this rule costs are exactly that shape.
A target that is quiet for one of the OTHER two reasons, under `.claude` or ending in `.md`,
is never reached by this at all. Measured 2026-09-08 over the 2263 stops the scratchpad axis
had silenced: 165 become a stop again and 140 of the 141 silent passes are closed.

Then:

```
the call carries an agent_id that is not the session id  ->  a subagent, let it work
a fresh marker sits in .claude/manager-exception         ->  spend it, log it, let it pass
that marker is older than five minutes                  ->  discard it, then refuse
the verdict is bookkeeping                               ->  say nothing
otherwise                                                ->  refuse, on both channels
```

`agent_id` is absent on the main thread and set for a subagent [measured against the
hook input builder in Claude Code 2.1.220 on 2026-09-07]. Unknown counts as the main
session, so the guard fails closed: a future version that stops sending the field turns
the guard strict, not silent.

## The manager reading its own measure

The role above says which session may write what. It does not, on its own, let that session
find out WHY a particular command falls on one side of the line, and until 2026-09-08 the
manager could not find out at all.

Every route to `classify_bash` puts the example commands into a COMMAND LINE, and a command
line carrying an example is read by the very function under test. Measured 2026-09-08
against the shipped guard with real hook input: the seven examples of one probe, written
into a single line, came back a stop, and so did the one line
``classify_bash "bash -c \"cd /tmp && rm -rf src/x.py\""``. The coordinating session was
therefore blind to its own instrument and had to delegate every check of it, which is the
one thing delegating cannot settle: the report that comes back is about the function the
reader cannot run. It happened twice that day, and once the answer contradicted the
manager's diagnosis and was believed rather than checked.

```
bash tools/mk-explain.sh .claude/probe.txt
```

The examples live in the file, one per line; the call carries nothing but a bookkeeping
path, so it passes in silence. `--whole` reads the whole input as one command, which is the
only way to measure a heredoc or a line continued with a backslash, because both carry a
newline inside a single command.

It prints the reason and not only the verdict: which word was read as the write verb, which
word as the target, and why that target is work; and on a quiet verdict, why nothing was
found. **The reasons are printed by `hooks/_classify.sh` itself**, out of the branches that
decide, under `MK_EXPLAIN=1`. The tool lays them out and holds no rule of its own. A second
implementation would report on the second implementation, which is the mistake behind two
of the false-alarm classes this classifier has already had to unlearn. Measured over 450735
real Bash commands on 2026-09-08, turning the trace on leaves the verdict of every single
one unchanged.

**One thing about that switch is worth knowing.** `MK_EXPLAIN` is read out of the
environment, and `hooks/role-guard.sh` does not clear it. Exported at the shell that starts
your session it would make the guard write its reasons to the hook's standard error on
every tool call. That stream is discarded while the hook exits 0, so what it costs today is
nothing, and it is left alone rather than cleared because clearing it is a change to the
guard that nothing in `tests/run.sh` would hold. If you export it, export it for the one
command that wants it.

Two routes look equivalent and are not. A pipe carries the example straight back into the
command line and is refused whenever the example is one of the interesting ones. A heredoc
passes because the guard reads a heredoc body as data, which is the first hole `README.md`
lists, so that route lives exactly as long as that hole does. The file route depends on
neither. `README.md` gives the measurements for all three.

## Reading the log

```
python3 - <<'PY'
import json, collections
c = collections.Counter()
for line in open(".claude/manager-kit.log"):
    c[json.loads(line)["event"]] += 1
print(dict(c))
PY
```

The log holds lines and never a counter this kit increments. Every number it reports is
derived by counting them at read time, so a lost write shows up as a smaller number and
never as a number that disagrees with its own history.

Eight events appear: `guard-ran` once a day, `stop`, `exception` for a declared crossing,
`handover` when the role was moved by hand, `claim` whenever a hook wrote the role record,
and one of `route`, `route-stop` or `route-off` per subagent launch, for a handout that
passed, one refused for its model, and one that ran with the routing switched off.
`tools/week-verdict.sh` counts the first three and ignores the other five. Neither a
handover nor a claim stopped anybody, and the three route events record which model was
written for which order rather than a write at the boundary, so counting them would spend the
false-alarm budget in `GOAL.md` on something that never fired at it. The route events are
counted by `hooks/route-guard.sh` itself, for the line it shows on a refusal.

**A route line names the model that was written, not the one that ran.** It carries what
the call names, or else what the hand's definition holds on disk at that moment. The hook
reads the file on every call and the runtime keeps the definition from session start, so a
session started before a definition changed runs on the old one until it restarts, while
its log already names the new one. [Reported 2026-11-05 by a session of another project,
started before the delivery of the `model:` lines, and not measured here: the log said
`model=sonnet effort=xhigh` for `manager-kit:xhigh-readonly`, `message.model` in the hand's
transcript said `claude-opus-5-5`, on 83 of 83 lines.] With `MANAGER_KIT_NO_ROUTING` set no
definition is read at all, so a call that names no model writes `(inherit)` whatever the
definition says. Only the hand's transcript proves the model that ran.

**A route line also says where its model came from**, as its last word: `from=call` when the
call names it, `from=definition` when the hand's definition supplied it, and `from=none` when
neither did, which is every `(inherit)`. Counting `from=call` is how to see whether managers
choose. It says nothing about what ran either. Lines written before 2026-11-06 do not carry
the word; nothing in this kit parses the reason of a route line except `tests/run.sh` and
`tools/mk-cost.sh --hands`.

**A route line names the effort that applies, and where that came from**, in `effort=` and in
its last word `effort_from=`. The call wins when it names an effort: `effort_from=call`. Else the
definition does: `effort_from=definition`. When neither does, which is a hand this project
cannot see or a definition with no effort, the line says `effort=(none) effort_from=none`, and
so it does with the routing switched off and a call that names none, because no definition is
read then. The effort of the call is read out of the payload by the parse that runs already,
which is why a `route-off` line carries it and costs nothing: it is the one effort that no file
holds, so nothing later could recover it from `agents/*.md`. An `effort` in the call that is not
one of `low`, `medium`, `high`, `xhigh`, `max`, or is no word at all (an object, a number, a
line break, a very long text), is written as `(other)` and never as it was sent: it comes out of
the payload, and the line is cut at 400 characters. The four words keep their order, the first
three as they were, so a reader that took `model=`, `effort=` and `from=` reads on as before; for
a line written before 2026-11-07 `effort=` is the definition's even where the call named another,
and it carries no `effort_from=`. It is what was written, as the model is, and not what ran.

`claim` carries the same two facts the `handover` line carries, in the same words: the
subject names the pid the record now holds, and the reason names the previous pid and
whether its process was `none`, `unusable`, `alive` or `gone`. The two events are kept
apart because only one of them was typed by a person.

`stop` carries in its reason the line of the measure that decided: the word that stopped
the call, then the rule by which it is work, in the words the measure itself prints under
`MK_EXPLAIN=1` and `tools/mk-explain.sh` lays out. The subject is cut at 400 characters
and the reason is not built from it, so the word is on the record even where the
subject lost it.

## The role library

Roles live in `.claude/roles/`, not in `.claude/agents/`. That is deliberate: an agent
definition's `description` sits in the context on every single turn, which is precisely
the budget this kit is trying to protect. A role file is read when an order is written
and not before.

Each role carries `fassung:` and `stand:`. The manager quotes the `fassung` in the order
it gives. An order that does not name the version it was given under cannot be checked
afterwards, which is the same reason a verified fact carries the command that proved it.

`roles/example-implementer.md` in this repository is a starting point, not a catalogue.
A fixed catalogue of DOMAIN roles is still not shipped, for the reason it was dropped for:
the useful ones are what a project discovers, and a shipped list of them is a claim about
somebody else's work.

## What an order looks like

An order is all a hand knows about the work. It carries what follows, and each item is
there because leaving it out has a price somebody pays later:

1. **The role file and its `fassung:`.** The standing rules live there and are not typed
   into the order again; the hand quotes the version back, so the result can be traced to
   the rules it was produced under.
2. **One endpoint.** The one thing the hand finishes. What lies beside it comes back as a
   finding with its size, not as a second change nobody asked for.
3. **The evidence, with its command.** The command that shows the problem as it stands,
   so the hand sees it before it touches anything.
4. **The acceptance, with its command.** How "done" is recognised, written as something
   that runs rather than something that reads well.
5. **Where the work happens, and where it does not.** The tree and the branch to write in,
   and what is off limits even for reading.
6. **What comes back, and where to.** The path or the form of the report, and what it has
   to hold: the command behind every number, and what was NOT done, with its size.

**A statement of fact in an order that carries no command is an assumption**, whatever it
is called. A sentence with its command can be rerun by the hand before anything is built
on it; a sentence without one can only be believed, and an order that has to be believed
is the order nobody checked. Of the 9 finished orders in the order log kept by the
coordinating session that built this kit, 3 carried at least one false premise, 4 in all,
each found and reported by the hand that received it. [Counted 2026-11-03 over
`.claude/auftraege.md` with the first command below, which prints `4 3 9`. The log's own
summary line, which says that every false premise stood in a sentence without its
command, is the coordinator's reading and is not derived from the table, so it is not
repeated here as a count.] In all 9, the report also named something the hand had found
outside its endpoint [counted the same day with the second command, `9 9`].

**The role file is what keeps an order short.** In the 8 orders that did not yet point to
one, the standing rules took 13 to 36 percent of the text and were rewritten every time
[counted the same day with the third command, `13 36 8`].

```
awk -F'|' '/^\| MK-/ && $6 ~ /[A-Za-z]/ {f++; v=$5+0; s+=v; if (v>0) o++} END {print s, o, f}' .claude/auftraege.md
awk -F'|' '/^\| MK-/ && $6 ~ /[A-Za-z]/ {f++; if ($7 ~ /[A-Za-z]/) o++} END {print o, f}' .claude/auftraege.md
awk -F'|' '/^\| MK-/ && $4 ~ /%/ {v=$4+0; n++; if (min==""||v<min) min=v; if (v>max) max=v} END {print min, max, n}' .claude/auftraege.md
```

**Each hand under `agents/` carries what to do when an order falls short.** With no
acceptance or no evidence it writes its own acceptance first, works against it and names
it in its report as self-set, because asking back is a deadlock. A statement in the order
that the code contradicts comes back as a reported deviation, not as a quiet adjustment.
That is a floor under the order written in a hurry, not a licence to write one: a hand
that had to set its own acceptance did the coordinator's half of the work, and that half
is the first thing to read in its report.

## The team the kit does ship, and why that is not the same thing

`agents/` carries six definitions. They are not domain roles. They are the six SHAPES a
hand-out takes, and that is a claim this kit is already making everywhere else:

| | effort | for |
|---|---|---|
| `low-readonly` | low | locate, count, list. The answer is a fact, not a judgement |
| `medium` | medium | one named endpoint, finished, with the command that shows it works |
| `high` | high | several files, a few real choices, and no assertion is owed |
| `xhigh-readonly` | xhigh | settle whether something is true. Changes nothing |
| `xhigh` | xhigh | a named defect, red first, with a mutation that kills its own assertion |
| `max` | max | the design is the difficulty and typing it is the small half |

**They are named after depth and not after a job**, since 2026-09-08. A manager choosing a
hand does not yet know what the work IS, which is what `scout` and `architect` claimed to
say; what it does know is how much thinking the question is worth and whether the hand may
write. Both of those are in the name now, and nothing else is.

**The context objection above is real and it was measured rather than waved away.** The six
descriptions together are 3221 characters, roughly 805 tokens at four characters a token,
carried on every turn. [Counted 2026-11-08 as the sum of the `description:` fields of
`agents/*.md`, 2019 before each named its suggested model. On 2026-09-09 they were 1923, the
five they replaced were 1793, and the sixth rung is what that difference bought.] That
is the price. It is paid because a hand is how a manager picks depth by name, and the other
way to set it is not the kit's to use: the Agent tool also takes `effort` in the call, and the
call then wins over the definition in both directions, but the tool's own text allows that only
when the user, or an instruction file such as CLAUDE.md or a skill, asks for a specific effort,
and this kit asks for none: no text it hands a manager says to name an effort in a call.
[Measured 2026-11-06 on one Mac, one question, 14 runs: a `low` hand on haiku spent
7.6 times the output tokens with `effort: max` in the call (3 runs against 3), a `low` hand on
sonnet 13 times (2 against 2), and a `max` hand on sonnet spent 523 and 535 with `effort: low`,
like the `low` hand's 376 and 377 and not like its own 5625 and 3724. That shows the parameter
taking effect. It does not show an answer getting better: every answer was 1. Which Claude Code
version ran it was not written down. The binary of 2.1.318, installed since 2026-11-04, carries
the parameter in the schema of the tool, and the binaries of 2.1.278 and 2.1.220 carry none,
read as strings on 2026-11-07. Whether a condition in the program removes the parameter, and
under which, is not measured.] A project that does not want the price deletes the directory.

**The ladder is measured, not assumed.** Same prompt, same model, two definitions differing
only in `effort`: 3334 tokens in 17 seconds against 12322 in 129. The expensive one did not
merely restate the answer, it found that the answer was implementation-dependent and said
which part it had not checked. So depth is bought where a question HAS depth, and on a
specified lookup the cheap tier is not weaker, it is cheaper.

**Pick by the shape of the question, not by how much it matters.** A wrong tier costs twice:
depth on a lookup is waste, and a lookup's effort on a judgement produces a confident answer
that nobody checked.

## Which model drives a hand, and the one combination that is refused

The depth of a hand is set in its definition, and a call that names an effort overrides it
(below). The MODEL is a parameter of the handout, and it is the other half of what a handout
costs. The rule has one mechanical half and one
half that stays with the person, and they are not the same kind of thing.

**The half that stays with the person.** A cheap model is allowed wherever the coordinator
can write down the one command that recomputes the answer. Not "the task is easy", but "a
wrong result is cheap to catch". That is the same shape as the role boundary itself: a
path and not a judgement. Where the answer can only be recomputed by trusting the report,
the cheap model is the wrong place for it, and the clearest case of that is a proof
obligation: an assertion owed red first cannot be rechecked out of a summary that says it
was. Measured 2026-11-01: two hands on the same repair, one delivered a complete fix and
one delivered a broken one, and the gate called both green. A promise nobody can check
must not sit on the cheapest link.

**How to choose, per order.** The model is your judgement on the order in front of you,
and leaving the suggestion takes a reason: say it next to the model in the order. The choice is
not deterministic, and the same order can fairly go two ways. Ask in this sequence, because
that is the sequence in which the answers decide. Measured 2026-11-05 and 2026-11-08, small samples,
listed kind by kind under the table. The one refused combination below stands whatever the answers are.

1. **Does one command carry the answer?** Then haiku on `low-readonly`, with the command in
   the order. Haiku `low` held 4 of 4 lookups and 4 of 4 claims with a known answer, the
   same as opus, at about 2 percent of the weighted cost of opus `xhigh`.
2. **Does the result hang on something nobody stated, and would the gate stay green without
   it?** Then opus, even at `medium`. A wrong sentence of advice stood in a refusal text and
   no order named it; suite and hidden probe were 10 of 10 on every run. Of the finished
   runs only opus `medium` corrected it, 2 of 2; sonnet `medium` 0 of 2, sonnet `high` 0 of
   1, haiku `medium` 0 of 1. Sonnet `xhigh` corrected it 2 of 2 and was broken off unfinished
   both times, at 83 and 74 calls, so it was not the cheaper way there. On 2026-11-08 a third
   opus `medium` run left three sentences standing that its change had made false, so opus
   stays here unconfirmed; sonnet `xhigh` finished 1 of 2 and was still not cheaper. Opus
   `high` held it 3 of 3 that day, the only measured cell that did, and sonnet `high` 0 of 2.
3. **Will you rely on the report?** Then not a cheap model at `medium`. On a repair with
   proof, one run each, haiku `medium` and sonnet `medium` wrote outside their copy and
   reported the opposite, with the probe at 6 of 6 and the mutant killed. Weighted against
   opus `xhigh` at 100, honest were opus `medium` at 39 and sonnet `xhigh` at 42, on one
   probe; sonnet `medium` at 17 and haiku `medium` at 2 are the two with the false report.
   Sonnet `xhigh` came complete and honest on the same repair twice more on 2026-11-08, n = 3.
4. **Is a wrong result expensive or irreversible?** One model up. Unmeasured: no run stands
   behind this, it is a judgement.
5. **Did a cheap result turn out incomplete?** One model up instead of the same run again.
   Unmeasured as well. If the gate had called it green it counts toward `N = 3` in `GOAL.md`.

**What a suite can hold here.** `tests/run.sh` can hold the table against the hands, and
does, but not the choice: which model an order deserved stands in no file. The `from=` of a
route line counts how often a call named a model, and says nothing about whether it should
have.

**The suggestion, when the handout names no model.** Every hand names its model in its own
definition, and the runtime takes it whenever the handout names none [measured live
2026-11-05: two probe hands defined with `model: haiku` and `model: sonnet` ran on
`claude-haiku-5-5` and `claude-sonnet-5-5`]. A model named in the handout still wins.
The effort of each hand is unchanged. Where a hand's kind of work was measured, its model is
the cheapest one that held the quality of opus on that work, with cost weighted by the API
list price, opus : sonnet : haiku = 1 : 0.5 : 0.025; where it was not measured, the hand
stays on opus [2026-11-05 and 2026-11-08]. Opus is written out rather than left
at `inherit`, so a session running on another model does not take the quality with it.

| | effort | model | why |
|---|---|---|---|
| `low-readonly` | low | haiku | lookups and claims one command can recompute held on haiku `low`: 4 of 4 lookups and 4 of 4 claims with a known answer, the same as opus [2026-11-05] |
| `xhigh-readonly` | xhigh | sonnet | judging claims beyond what one command recomputes: sonnet `xhigh` scored 10, 8 and 8 of 12 points, opus `xhigh` 0, 8 and 10, at a median of $1.14 against $1.89 a run, n = 3 each [to 2026-11-08]. Only opus found a hidden defect, n = 1 |
| `medium` | medium | opus | building with a consequence nobody stated: opus `medium` 2 of 2 [2026-11-05] and 0 of 1 [2026-11-08], so unconfirmed; sonnet `xhigh` 1 of 2 and not cheaper, sonnet `medium` 0 of 2, haiku `medium` 0 of 1 |
| `high` | high | opus | the same building task: opus `high` 3 of 3, sonnet `high` 0 of 2, at a median of $1.069 against $0.32 a run, confirmed n = 3 [2026-11-08] |
| `xhigh` | xhigh | sonnet | a repair owed with proof: sonnet `xhigh` delivered it complete and reported it honestly, like opus `xhigh`, at half the list price per token, n = 3 [2026-11-05 and 2026-11-08] |
| `max` | max | opus | not measured, so it stays on the strongest model the ladder names |

**What stands behind the table, kind by kind.** Each kind of work past lookups was measured on
one task of kit code, the body of the hand fixed and only model and effort changed. On
2026-11-08 a pair was decided by a rule written down before the runs: the cheaper model becomes
the suggestion when all three of its runs are honest and none wrote outside its copy, its worst
run scores at least as much as the worst run of the suggestion, and the median of its cost in
list-price dollars lies below.

**lookup, on `low-readonly`: haiku `low`, the suggestion since 2026-11-05.** Four questions,
each on opus, sonnet and haiku `low`, and haiku answered 4 of 4 like opus. Four claims with a
known answer, on opus and sonnet `xhigh` and on opus, sonnet and haiku `low`, held as well.
Nothing about lookups was measured on 2026-11-08.

**verify, on `xhigh-readonly`: sonnet `xhigh`, the suggestion since 2026-11-08.** Claims about
what kit code does, settled by judgement, 12 points a run. Three runs each: sonnet `xhigh`
scored 10, 8 and 8, opus `xhigh` 0, 8 and 10, so the worst run is 8 against 0, at a median of
$1.14 against $1.89 a run [opus three times on 2026-11-08, sonnet twice then and once on
2026-11-06]. The 0 is a run whose final report a safety classifier stopped half way, so on this
work opus can lose its own report, n = 1 [2026-11-08]. Without that run the worst opus run is 8
as well, and the rule still holds. What the rule does not see: of 14 valid runs on these claims,
over every model and effort, only one found the defect hidden in one of them, and it ran on opus
`xhigh`, n = 1 [2026-11-08; the points above are those after every run was rescored for that
find]. That is no rule. Naming opus in the call where a missed defect would be expensive is your
judgement, and unmeasured. Before 2026-11-08 this hand stood on opus, because its work was not
measured.

**repair, on `xhigh`: sonnet `xhigh`, confirmed with n = 3 on 2026-11-08.** A repair of kit
code owed with proof. Sonnet `xhigh` came complete and honestly reported on 2026-11-05 and
twice on 2026-11-08, at $0.55 and $0.66. On 2026-11-05 one run each also stood on opus
`xhigh`, `medium` and `high` (which refused, as its role asks), on sonnet `medium` and on haiku
`medium`, and the two cheap ones at `medium` reported falsely. Haiku is refused on this hand,
below.

**change, on `medium`: opus `medium`, the suggestion and unconfirmed since 2026-11-08.**
Building with a consequence nobody stated. Opus `medium` held it 2 of 2 on 2026-11-05 and 0 of
1 on 2026-11-08, when it corrected the wrong advice and left three sentences of `GOAL.md`,
`README.md` and `GUIDE.md` standing that its change had made false. So it stays the suggestion
until the next measurement and is called unconfirmed. Sonnet `xhigh` held it 1 of 2 on
2026-11-08 and was not cheaper, at a median of at least $0.91 against $0.87 for opus `medium`;
on 2026-11-05 it caught the consequence 2 of 2 and was broken off unfinished both times. Sonnet
`medium` 0 of 2, sonnet `high` 0 of 1 and haiku `medium` 0 of 1, all 2026-11-05.

**change, on `high`: opus `high`, confirmed with n = 3 on 2026-11-08.** The same building task
at `high`, decided by the same rule. Opus `high` held it 3 of 3, honest and without a write
outside its copy, at a median of $1.069 a run. Sonnet `high` held it 0 of 2 at $0.32 a run, and
both of its runs missed the same consequence nobody stated, which opus `high` found every time.
A third sonnet run was not made, because it could no longer meet the rule. On this task opus
`high` is the only measured cell with 3 of 3, at about 23 percent above opus `medium`. The
limit: one task, n = 3 against n = 2. What that means for other work with judgement is an
inference and unmeasured, and the choice per order stays yours. The sonnet `high` run of
2026-11-05 stood on another setup and is not counted here.

`max` was not measured.

**The samples are small, and that is the honest size of this table.** It is a
measured starting point and not a settled one, and `GOAL.md` carries what turns it back:
past `N = 3` results delivered on a cheap model that the gate called green and that turned
out to be incomplete, the routing is switched off. For this table switching off means
setting the `model:` line of the hands back to `inherit`; the variable below stills the
refusal and does not touch a definition. `tests/run.sh` holds this table, and the hand
table of `README.md`, against the `model:` of every hand under `agents/`, the list of hands
derived and not typed.

**The half that is mechanical, and therefore a hook.** Haiku on the repair hand `xhigh` is refused
by `hooks/route-guard.sh` on the subagent launch, at every effort, whichever names it, and the text says
which one applied and where it came from. That is the one thing a measurement says does harm: haiku at
`high` held a repair of kit code twice and left one false report, n = 2 on one task, and haiku at
`medium` reported falsely on the same task [2026-11-06 and 2026-11-05]. On judging, `xhigh-readonly`,
there was no false report and no effort complete in two runs, which is a warning in that hand's
description and no refusal. On building, nothing. The rule before this one refused haiku on every hand
from `high` up. It rested on the effort lever, 4.5x on haiku, 3.2x on sonnet and 1.27x on opus, which is
a price and no harm, and the parameter `effort` went round it. Every other combination is your
judgement, and the section above says how to make it.

**What that rests on and what it cannot see.** n = 2 on one task, and that task is kit code: a start
and no law. A hook knows the name of a hand and not the kind of work, so a repair sent to `medium` falls
through, though one of the two false reports came from exactly there. So does the text of `xhigh` copied
into a project under another name, and the measurement itself ran on such copies. A project file of the
same name, `.claude/agents/xhigh.md`, called as a bare `xhigh`, is the project's hand and passes: the
runtime lists it beside `manager-kit:xhigh` as a hand of its own, and a stop there would only tell a name
from a rename. `manager-kit:xhigh` is refused in that project all the same and reads the plugin's file.
A hand in `~/.claude/agents` is not read at all, so a bare `xhigh` from there is refused as if it were ours.

It is a hook rather than a sentence because a sentence does not hold. **Measured in this
kit three separate times: a rule that existed only as prose ran green while forbidding
something.** `GOAL.md` carries the standing version of that finding, and `tests/mutate.py`
is what keeps this one from becoming the fourth.

What is refused and what is not, with the reason, because a stop nobody can predict is
worse than no stop:

| the call | answer | why |
|---|---|---|
| `model: haiku`, `manager-kit:xhigh` or a bare `xhigh` the project does not define | refused, at every effort | the one combination with a false report behind it |
| `model: sonnet` or any other that is not haiku, on `xhigh` | passes | sonnet is that hand's suggestion, complete and honestly reported |
| `model: haiku`, any other hand of the kit, at any effort | passes | no false report was measured there. On `xhigh-readonly` its description warns |
| a `model` that cannot be read, on the repair hand | refused | it cannot be told from haiku, and the schema sends none. On any other hand it passes and the line says `(other)` |
| an input that cannot be read: `tool_input` no object, `subagent_type` no plain name | refused, aloud | nothing in it can be judged |
| `model: opus` or `model: fable`, any hand | passes | neither is the cheap end. `fable` sits above opus in the shipped tier text, read 2026-11-02 |
| no `model` in the call | judged on the definition | the hand runs on the `model:` of its definition, and that is what is judged; every hand this kit ships passes. A definition at `inherit` names nothing and passes. 4290 of 4335 real calls, 99.0 percent |
| `subagent_type: fork` | passes | the runtime ignores `model` for a fork and the fork runs on the parent's model |
| another plugin's hand, even `anderes-plugin:xhigh` | passes | it is not ours and it was not measured. The line says `hand=other` |
| a project's hand, at any name and any effort | passes | see the limit above. The line says `hand=project` |
| a hand this project cannot see | passes | its definition is in somebody else's file, and a guess there is a false stop on every project role |
| no model in the call or the definition, on a session running haiku | passes | it cannot be seen: the payload of a tool hook carries no model. `model=(inherit) from=none` is what the line can say. A `SessionStart` hook is told one and the transcript names one, both read out of 2.1.318 on 2026-11-07 and neither read by this hook, which would be a stored state or a file read on every handout |

**What a line can count about the order.** `order=len:5k,cmd:1,accept:1` is the sixth word of every
route line, and only numbers and fixed marks reach it, not one word of the order. `len` is the upper edge of
a tier, 500, 2k, 5k or 10k characters, or 0 or more. `cmd` says a span in backticks or a fence opens with a
command word or `./`, and `accept` says a word of acceptance stands in the order, German or English:
Abnahme, abgenommen, fertig ist, fertig wenn, acceptance, done when, must pass, ALL GREEN and a few more. <!-- de-input -->
The lists come from the 205 distinct subagent calls of one project's transcripts: 141 carry a command, 109
a word, 98 both, 60 of the 61 repairs a command and 51 a word, and 0 of 11 lookups both. They are
kit-flavoured for that reason. A bare `` `pytest` `` is not counted, because a bare `` `grep` `` is
usually a mention. It judges nothing and no verdict reads it: it is the instrument for how many real
orders carry a model, an effort and an acceptance. `hand=` next to it says whose hand it was.

**What ties a line to what ran.** A call that carries a `tool_use_id` ends its line in
`tool_use_id=`, and the `meta.json` beside the transcript of the hand it starts names the same id
as `toolUseId`. A call without one writes the line as before, and so does every line written
before 2026-11-08. `bash tools/mk-cost.sh --hands` reads both and prints, per hand, the model and
effort of its route line beside `message.model` and the effort of each round of its transcript,
names every deviation and counts every hand it finds no line for as `without route`. An alias stands
for the newest model of its family in `tools/prices.tsv`, so a route `opus` that ran on
`claude-opus-4-8` is a deviation.

**The list of hands and their effort is derived from `agents/*.md` and from the project's
own `.claude/agents/*.md`, never typed.** That is not a style preference here. A typed list
of role carriers let an incomplete fix through green on 2026-11-01 because the fourth
carrier was missing from it, and `tests/mutate.py` carries the typed list as a mutation for
exactly that reason. The hand's name comes from the frontmatter `name:` and falls back to
the filename, and only the plugin prefix of this kit is taken off, read from the name in its
manifest `.claude-plugin/plugin.json`, because that is what the runtime prefixes with: a marketplace or
a marketplace entry of another name leaves it, a manifest of another name changes it [measured
2026-11-07 on 2.1.318]. A manifest that cannot be read leaves every prefix counting as ours, so nothing
falls out of the refusal. The `subagent_type` in a live handout is `manager-kit:xhigh`, not `xhigh` [measured 2026-11-02
over 4335 launches: 1505 of them name `manager-kit:xhigh` and not one names a bare
`xhigh`]. A comparison against the filename would have matched nothing at all, green, for
every hand this kit ships.

**The switch, and it is one variable.** `MANAGER_KIT_NO_ROUTING` in the environment stills
the routing: no handout is refused for its model. It does not reach a definition, so the
hands keep the model the table above gives them.
Empty and `0` count as unset, anything else counts as set, because a switch that only
answers to the string `1` is a switch that was not reached. Its state is REPORTED in the
role text on every session start and never written: a kit that quietly changes a project's
settings has stopped being an instrument and become a participant.

**What this policy does not know, and the number is the point.** It is on by default, by
the owner's decision of 2026-11-01, and its gain is known in two parts and open in the third,
each as far as the machine this kit was built on measured it. The price is an estimate:
`mk-cost.sh --what-if` below, over the UTC days 2026-11-06 and 2026-11-07, put the hand rounds at
$440.67 against $632.03 for the same tokens on the newest Opus, 30.3 percent less, an upper
bound at list price. Measured are the pair comparisons per kind of work in the table above,
each on one task of kit code, the three decided ones with n = 3 or fewer a side. What is
unmeasured is whether real work keeps the same quality at that price. The official help
promises only a direction, "Opus costs several times more per turn than Sonnet, and Sonnet
more than Haiku", and publishes no number. The one instrument that could have falsified
the cost side cannot: 269128 Opus tokens moved the weekly window by zero of a hundred
points, so a point costs more than that. `GOAL.md` carries the trigger that follows from
it and the threshold, which is on quality and not on cost.

**Your own number, at list price.** `/manager-kit:cost` (or `bash tools/mk-cost.sh`) reads
every transcript under `~/.claude/projects`, or under `CLAUDE_CONFIG_DIR`, and prints the
list price in dollars from `tools/prices.tsv` per role and model. It is a lower bound, since
a call that writes no transcript line, compaction first among them, is not in it, and it is
not limit points. A round counts once, on the last line that carries it. `--since` and
`--until` take a UTC day, both included; `--exclude TEXT` drops every project folder whose
name holds TEXT, compared in lower case, and may be given more than once. When fewer than 95
percent of the rounds carry all four token counts, or more than 1 percent of them name a model
with no price row, it prints one line of reason and no number. `--hands` prints instead what
each hand was planned on beside what it ran on, see the route line above; when more than 5
percent of the `meta.json` files carry no `toolUseId`, it prints one line of reason and no report.
`--what-if` prints instead what the hand rounds would have cost with every hand on the newest
Opus in `tools/prices.tsv`, on the same tokens; a round that ran on any Opus and every manager
round keep their price, and the saving it prints is an upper bound. `--compare A B` compares two
windows of UTC days, `YYYY-MM-DD..YYYY-MM-DD` each, in dollars per active day, only against an
A/A band: the largest change among pairs of the same shape cut from the 4 times as many active
days right before A. Inside the band it prints "not distinguishable"; with fewer days it gives
no verdict and says why. `--causes` prints instead what the cache writing comes from, one cause
per round that writes: Start, after-compaction, expired>5m or idle>1h when the gap to
the round before in the same file is past the TTL of its last write, Growth within it, and
Other for what no rule reads. It prints rounds, dollars, share of all costs and the tokens and
dollars of one event per cause, and the compactions, each counted once, with their trigger and
the median context before and after. The causes sum to the write of the table. `--context`
prints instead the manager's own tool loops, the rounds of the main session between two inputs,
by length, and the context cap `C* = S + g T*` of this machine, `T* = sqrt(2K / (r g))`, with
each input, its count and where it comes from; the compaction call in K is estimated and says
so, and a window without a compaction gives no C*, only the reason.

**The line that the cap was passed.** The manager hears of its own context once, when the last
round passes the cap, and again only after a fall under it and a new crossing; and of its own
tool loop once, when the loop since the last input reaches 8 rounds over 150000 tokens of
context. One line each, through `additionalContext`, saying that the person can compact at the
next pause. The guard says it on a call it lets through, the stamp at a prompt, never inside a
refusal, and both read the end of the transcript by the rule of the cost report. The cap is 300000
by default, the measured cap of the machine the kit was built on, rounded; set
`MANAGER_KIT_CONTEXT_CAP` to the `C*` that `/manager-kit:cost --context` prints for yours. A
value that is no whole number falls back to the default and the line names it; 0 turns the
context line off. What was said is kept in `.claude/manager-kit.notice`, and
`hooks/_notice.sh` has the rules.

## The stop on a handed out hand

A hand keeps working until it is told to stop, and its answers get worse on the way. That
is not a feeling. Measured 2026-09-29 over 1494 subagent runs of the machine this kit was
built on, read out of the `<usage>` blocks the finished reports leave in the transcripts:

| | runs | share |
|---|---|---|
| reached 600000 tokens of context | 93 | 6.2 percent |
| reached 900000 | 26 | 1.7 percent |

The 93 runs that crossed 600000 took a median of 263 tool calls to get there. **The fastest
took 26.** That one number is why a rule counting tool calls alone cannot work: a hand that
reads a handful of large files is over the line before any call budget notices.

**The figure to read is the largest context of ONE turn, not the sum over the run.** The
two differ by roughly fourteen times, and mixing them up makes the rule either silent or
absurd. Calibrated over 258 finished runs by pairing the `totalTokens` the parent
transcript records against the agent transcript beside it: what a report calls
`subagent_tokens` is the per turn maximum, at a median ratio of 0.956, with several pairs
exactly equal. Totald instead, an ordinary twenty call run clears 600000 and the rule fires
on everything.

### The watch belongs to the coordinator

**Only the coordinating session knows a hand's id**, because the id falls out at the moment
the work is handed over. The hand itself never learns it. So the watch sits where the
knowledge is:

1. **Hand out to the background** and keep the id. A hand run in the foreground blocks the
   session that spawned it, which can then neither look nor act.
2. **On each turn you take anyway, read three numbers** out of
   `~/.claude/projects/<slug>/<session id>/subagents/agent-<id>.jsonl`: the largest per
   turn context, the tool call count, and the file size. Nothing is interrupted by
   looking; it is a file on disk.
3. **At 600000, send the hand a message**: write the handover and stop. That is the clean
   seam, and it costs one message.
4. **A hand that does not answer gets stopped hard.** Last resort, because it loses
   whatever was in flight.
5. **The successor is briefed with the handover file, never with the old order text.** The
   old text describes work that is partly done, and handing it over again is how the same
   half gets built twice.

### What this rule does NOT promise

**The coordinator looks only when it takes a turn.** If a hand runs in the foreground the
coordinator is blocked and sees nothing at all. If it runs in the background while the
coordinator sits idle, nobody looks either. So this is a duty attached to turns, plus a
floor, and it is not a watchdog sampling on a timer. Saying otherwise would be the third
time in this repository that a rule promised more than its mechanism holds, and the two
earlier ones each cost a release to unwind.

**That is what the floor in every hand is for.** 150 tool calls or 300 KB of material
read, whichever comes first, written into all six files under `agents/`. It is a parachute
for the stretch when nobody is looking, not a measure of anything. Measured against the
same 1494 runs, the honest accounting of that floor is:

- 210 runs (14.1 percent) would reach it. The coordinator will interrupt about one run in
  seven, not one in twenty.
- 125 of those 210 never came close to 600000. Three stops in five are a hand put down for
  nothing, and that is the price of a proxy that cannot see the real number.
- 8 of the 93 dangerous runs never reach 150 calls, including one that hit 1603166 tokens
  in 56 calls. The 300 KB arm is aimed at those, and how many it actually catches has not
  been measured.

Both halves together are still strictly better than the state they replaced, which was no
rule at all and 93 runs crossing the line unnoticed.

**`maxTurns: 170` in every hand is a backstop above the floor, not a third rule.** The client
stops a hand at 170 turns and returns a partial result. It writes no handover file and
names no seam: a hand that reaches it has most likely passed its floor of 150 calls without
handing over, and the successor starts from the transcript and not from a handover. It lies above 150 on purpose: one turn
can carry several tool calls, and how the client counts a turn is not measured. Measured is
the stop itself, at `maxTurns: 3` in a project hand (client 2.1.317, 2026-11-08). Do not
lower it under the floor, or it can cut a hand before its floor would have handed over.

**The hour cache is a price decision per hand.** The hands that write a one hour cache are
`high`, `max` and `xhigh`. Each does it by `experimental:` with `cacheTtl: 1h` nested
under it. A one hour write costs 2 times the input price against 1.25 for five minutes
(`tools/prices.tsv`), and it only pays back where a hand is often idle between 5 and 60 minutes. On measured
shares of all cost (council pyramid, 2026-11-06, with the expired hand cache at 14.7
percent by `tools/mk-cost.sh --causes` over 2026-10-01 to 2026-11-07) the net is: `xhigh`
-1.94 percent, `high` -1.95, `max` -0.81, `medium` -0.04, `xhigh-readonly` +0.53. To move
a hand in or out, change `HOUR_CACHE_HANDS` in `tests/run.sh` and the block in the hand;
the suite names the hand or the document that still disagrees.

**For a plugin hand the hour cache is measured once and the turn limit is read, not measured.**
Both fields were first run in a project hand. On 2026-11-09 a plugin hand `manager-kit:high`
called without a model ran on Opus and wrote every cache token as one hour (7 answers), and a
plugin hand `xhigh-readonly` called without a model ran on Sonnet and wrote five minute cache,
as decided (4 of 4 answers). The size of each is one project, one hand. That a plugin hand
stops at `maxTurns` has not been run: treat a plugin hand as one that may not stop at 170 turns.

### The file the rule turns on

The transcript directory is undocumented internals of Claude Code, observed on 2.1.275 and
2.1.281, and present on this machine since 2026-06-17 across 1313 agent transcripts. If a
future version moves it, the coordinator's half goes quiet and the floor in the hands keeps
working: the rule degrades to the proxies rather than failing open.

A hand can in principle find its own transcript under
`~/.claude/projects/*/$CLAUDE_CODE_SESSION_ID/subagents/`, newest file first, since
`CLAUDE_CODE_SESSION_ID` names the session that handed the work out rather than the hand.
**That lookup can be wrong and the text says so**: with several hands running at once,
the newest file is not reliably the reader's own. It is a convenience, the floor is what
binds, and nothing in the kit depends on it.

### The handover file

One file in the session scratchpad, which a hand shares with whoever called it. It carries
the order as the hand understood it; what is DONE, each point with the command that shows
it; what is HALF done and exactly where it stands; the next concrete move, written so it
runs without a question back; what the successor must NOT do again, and why; and the
numbers already measured, so nobody pays for them twice. **The hand names its path in the
first line of its report**, because a handover nobody can find is a handover nobody made.

A half task with a clean seam is worth more than a whole one nobody trusts.
