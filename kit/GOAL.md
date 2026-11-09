# Goal

Keep the division of labour honest once more than one carrier works on the same thing.

**The measured failure, and it is the only one v1 addresses:** the coordinating role
loses to the work, every day, because each single act of working is useful on its own.
The rule is not disputed, it is walked around. Measured 2026-09-05: 39 commits out of
the manager line in one day, against that project's own written doctrine.

The reframing this kit stands on: **the role boundary is not a question of discipline,
it is a question of where a file sits.** A resolution cannot be checked. A path can, and
what can be checked can go red. Anything under a `.claude` directory, every `*.md`
file and the session scratchpad is bookkeeping and belongs to the coordinator. Everything
else is work, and work is handed out. The scratchpad axis was added on 2026-09-08 by the
owner's decision, after measurement put 37.8 percent of all stops in that one directory
and 26 of 27 hand-read cases there were false alarms; `/tmp` stayed work, because the
wider rule silences at least 202 stops that write real code. It was narrowed the same day,
after a full reading of the 2263 silenced stops found 141 of them writing production code
through a script, a heredoc or a git subcommand whose target was nowhere on the command
line: for those three shapes the scratchpad answer does not hold, which closes 140 of the
141 and buys back 25 false alarms.

Done when: somebody who did not build this coordinates a week of work with it installed,
and at the end of that week all three hold.

1. They can **read off**, rather than remember, how often the boundary stopped them and
   how many crossings they declared, without opening a file.
2. The guard **stopped them at least once**, and they either handed the work out or
   declared the crossing deliberately. Both count. Ignoring it does not.
3. Every crossing they made is on disk with the reason they gave at the time, and none
   of them happened silently.

And from their terminal it was not possible to tell all week that the kit was installed,
except in the turns where it stopped them.

## How it would be measured

**The falsification is the point, and it is one command:**

```
bash tools/week-verdict.sh <project> --since <the day the week started> --until <the day it ended>
```

It reads two witnesses that do not depend on each other, the project's git history and
the guard's own log, and classifies commits with the same function the guard uses rather
than a second copy of it.

It reads the commits of `HEAD` and says so on its `history:` line. A checkout that stands
behind its upstream, with the work on `origin/main` or on another branch, would read as an
empty week, so in that case one `behind:` line gives the number, from the tracking ref already
on disk: no fetch, nothing written. `--ref origin/main` (any ref git resolves to a commit)
reads that stand instead, and a ref that names none is refused with nothing read. The guard's
log is read only as a plain file inside the project, like every file of the kit under
`.claude`; a pipe, a link, a directory, or the `.claude` of the home directory is reported as
not read, and the week is then inconclusive.

**The refutation is not what it was first written as, and the correction is measured.**
It used to read: `git log` shows work coming out of the coordinator line while the guard
stayed silent. That cannot be read. In the project this kit was built for, all 1545
commits carry a single author, and no field in the history says which line a commit came
out of [measured 2026-09-07: `git log --format=%an | sort | uniq -c` gives one row]. The
same measurement takes away the other half of the old framing: 39 commits on the day that
prompted all this is unremarkable next to 177 on 2026-09-03 and 112 on 2026-08-24, so a
count of commits was never going to be the signal either.

What can be read, and what the command reads:

- **Was the guard alive on every day that carries commits?** If not, the week is
  inconclusive and the wiring is the finding. This is the likeliest way for this kit to
  fail, because a guard proven to work in the suite is not proven to run when it counts.
- **Did it stop the coordinator at least once?** That is done-when 2, and a week with no
  stops satisfies nothing, however clean it looks.
- **How many crossings were declared, and with what reason?** That is done-when 3.

With the guard alive, a coordinator write to a work path that the measure can read cannot
happen without a stop or a declared crossing. What it cannot read it says when it refuses, and
what it does not see at all is a third path, named hole by hole in README.md under "The Bash
gap". So silence with a live guard means the work was handed out or went through a named hole,
and silence with a dead guard means nothing at all. The command prints exactly that for a
live guard that stopped nothing, and calls the week QUIET and not held: git carries no field
that says which line a commit came out of, so it cannot tell a week of handed-out work from
one that went through a hole, and says so.
Telling a live guard from a dead one is the whole job, and it is why the guard writes one line on the
first call of each day.

The other direction is just as hard. If the guard stops the coordinator on turns where a
coordinator was doing exactly what a coordinator should do, those are false alarms, and
past **N = 5 of them in the week the kit gets switched off, not tuned.** Five is one per
working day, and the number is here rather than in a note because it has to be fixed
before the week and left alone afterwards: a boundary adjusted until it stops complaining
has stopped being a boundary. Change it before the week starts if five is wrong for your
project. Changing it after voids the test.

**STAND, 2026-11-02: the first run of this measure failed it.** Window
`2026-09-10T16:16:37Z` to `2026-10-08T22:09:15Z`, 28 days in one project, 277 log lines:
122 stops, and **73 of them false alarms** against the five above, the fifth of them on day
four. 38 stops were correct, and 11 are permanently undecidable because the transcripts
behind them were deleted, so the 73 is a lower bound. The number moved from 72 to 73 on
2026-11-02, when one stop was re-measured and turned out to have been transcribed rather
than measured: its reason field named a source path as if it were the destination. Every narrower reading stays over the
line too: 49 without the narrowing cases, 21 pure parse errors, 19 counting only targets
under `.claude`. Three classes carry 47 of the 72, and they are reader defects rather than
boundary disagreements.

This line is a record, not a repair of the number above it. **N stays 5**, because a
boundary adjusted after the week has stopped being a boundary, and the week stays failed.
What follows is the repair of those three classes and a second week against the same five.
`check.sh` reads this line as a recorded result and not as a violation, so a kit that
failed its own measure ships green while saying so, which is the only honest way to ship
one.

Note what this measure does not need. There is no threshold on a quantity, no retention
window and no calibration period, because the measure is a path and not a size. That was
the point of choosing it.

## The model routing, and what would switch it off

The routing refuses one combination on a subagent launch, haiku on the repair hand `xhigh` at
every effort, because that is where a measurement found a false report (one in n = 2 on one task of kit
code), and it writes one line per handout naming the model
the call or the definition on disk names, which is not always the one that ran; only the
hand's transcript proves that. `GUIDE.md` carries the rule. What belongs here is the stopping condition,
because this policy ships in a state the measurement does not cover.

**Its limits, in one place, because a stranger inherits them.** The policy is on by
default, everywhere on, by the owner's decision of 2026-11-01. Its gain is measured in two
parts and open in the third. The price is an estimate: `tools/mk-cost.sh --what-if` over the
UTC days 2026-11-06 and 2026-11-07 on the machine this kit was built on put the hand rounds
30.3 percent below the same tokens on the newest Opus, an upper bound at list price. Measured
are pair comparisons per kind of work on one task of kit code, the three decided ones with
n = 3 or fewer a side (`GUIDE.md`). What is unmeasured is whether real work keeps the same
quality at that price: no number anywhere in this repository says so. The official help promises only
a direction, "Opus costs several times more per turn than Sonnet, and Sonnet more than
Haiku", a direction and not a number, and no figure is published. That is why there is a
switch, and the switch is `MANAGER_KIT_NO_ROUTING`.

**The cost side cannot falsify it, and that is measured rather than conceded.** 269128
Opus tokens moved the weekly window by zero of a hundred points [measured 2026-11-01], so
one point costs more than that and the only instrument that shows spend cannot resolve a
week's worth of routing decisions. A policy whose benefit is below the resolution of its
own meter cannot be defended with that meter, and it cannot be refuted with it either.

**The trigger is therefore quality, and the threshold is N = 3.** Past three results
delivered on a cheap model that the gate called green and that turned out to be
incomplete, the routing gets switched off and not tuned: the variable for the refusal,
and the `model:` lines of the hands back to `inherit` for the table in `GUIDE.md`, which
the variable does not reach. The case of 2026-11-01 counts as
the first, so two remain. Against N = 1: the function would be dead on the day it
shipped. Against N = 5, which is the number the false-alarm threshold above carries: a
failure here happens SILENTLY and is never visible as a stop, so it has to be caught
earlier than one that announces itself. The number is fixed here rather than in a note for
the same reason the five above is: a threshold adjusted until it stops complaining has
stopped being a threshold.

**What the trigger needs in order to be readable, and both halves now exist.** A gate that
tells a complete fix from an incomplete one, which is what the suite does since `e149aa4`:
it calls the incomplete fix RED at 1 of 97 and the complete one GREEN at 97 of 97, where
the suite before it passed the same incomplete fix with `ALL GREEN: 96 checks`. And a
record of which model was written for which order, which is the `route`, `route-stop` and
`route-off` lines on `.claude/manager-kit.log`, with the hand's transcript as the proof of
the model that ran. Without the second there is nothing a
falsification could show up in; without the first every quality number is blind.

**What is not in the cheap set, named now so it is not reargued later.** `sonnet` is not, and the
effort lever is no reason to put it there: it costs 3.2x on sonnet and `sonnet max` buys nothing over
`sonnet low`, but that is a price and this section has just recorded the cost side as unable to falsify
anything. On the repair hand sonnet came complete and honestly reported, and it is that hand's
suggestion. Adding a model is one word in `hooks/_routing.sh`; it needs a false report behind it.

**What the policy does not reach, so the condition above is not read as wider than it is.**
The refusal sees a model named in the handout or in the hand's own definition, and a cheap
model inherited from the session, on a hand whose definition names none, is invisible to it. It sees
the name of a hand and not the work: a repair sent to another hand falls through. `README.md` carries both limits, the second being that the matcher keeps a
dead spelling on a reading of the shipped program rather than on a live measurement.

`bash check.sh` for the floor, `bash tests/run.sh` for the mechanics, and
`python3 tests/mutate.py` for the standing claim that every assertion in the suite was
seen red before it was kept. **None of the three settles the stopping condition above.**
The week settles it, read off `git log` and `.claude/manager-kit.log`.

## Not this project

- **Starting, naming or stopping sessions.** Only the person can. A kit that waits for
  that is waiting at the wrong post.
- **A role policy.** Who the coordinator is, and whether they may work, is a decision
  belonging to the project. This kit measures and stops. It does not decide.
- **Ownership, receipt and deadline on disk.** A real second failure, measured
  2026-09-01: five messages, each acknowledged `success: true`, none of them read,
  because the receiving session was not running. Delivery is not receipt. It is out of
  v1 on purpose and not because it stopped being true: with one carrier there is nothing
  to hand over, so the mechanism would have no case to prove itself against. It is the
  first candidate for v2.
- **A message bus.** The disk is the bus. A message is a wake-up call at best.
- **Whatever the runtime already does.** Session naming, worktree isolation,
  foreign-change detection on write: what ships with the host gets used, not rebuilt.

## Open questions

- **Does the guard fire on the right thing?** Entirely unmeasured, and it is the middle
  of the kit. No prior art was found anywhere that guards a role boundary, so there is
  nothing to copy and nothing to compare against.
- **The Bash half is a string check**, which is the class of check the house rules argue
  against. It is declared in the README rather than hidden, and it is the first place a
  false alarm or a silent pass will come from. **That stopped being a prediction on
  2026-09-07: both halves were seen, within an hour of each other.** The silent pass:
  `python3 -c "open('src/rates.py','w').write('x')"` rewrote a work file and the guard log
  did not move. The false alarm: a call writing nothing but bookkeeping was refused,
  because `classify_bash` reads the WHOLE command text, a heredoc carries prose, and a
  write verb occurring as an ordinary word with no punctuation after it turns every
  following word into a candidate target path. Pinned to one line out of twelve, with
  every real command still judged correctly. The rule is therefore not merely strict, it
  is unpredictable: the same verb with a comma or a full stop after it passes.
  **Repaired later the same day as M2.16**: a write verb now counts in command position
  only, measured against 30877 real commands, 15 false stops out and 19 real writes in
  with the rate unchanged. The string check itself stays, and so does this bullet, because
  the class of failure it names has not gone anywhere: the unterminated quote is still
  open, and it was left open deliberately after the repair for it was built and measured
  to trade a loud false alarm for a silent pass.
- **Unsolicited contradiction from outside an order disappears** the moment standing
  sessions are replaced by ending ones, and no clause in an order buys it back: a clause
  reaches only as far as the order does. Whether this kit merely names that, or keeps one
  standing session, is undecided.
- **The audit half is not built.** A guard catches events; statements in living files
  have no holder and go stale silently. Statements cannot be enumerated, so an audit has
  to manufacture its own base set before it can sample one. v1 builds the guard only.
  `tests/mutate.py` is the one place this kit already treats its own standing claim as
  something that can rot.
- **The transition has no endpoint.** Installing this into a workshop where several
  lines already run is the normal case, not the exception. The role is claimed by
  whoever starts alone in the directory, and taken over if the recorded holder's process
  is gone; neither branch has been watched under real load. Two mechanisms behind that
  were read off the code on 2026-09-07 and are named here rather than fixed, because the
  procedure carries them for now:
  - **Nobody claims when nobody is alone.** With two or more live sessions in the
    directory and no role file yet, `mk_decide_role` returns carrier and does not claim,
    so the role file is never written. That much still holds, and the way out is still
    procedural: exactly one live session in the directory at the moment the role is
    claimed. **What was repaired on 2026-09-07 as M2.12 and M2.15 is the contradiction
    that sat on top of it.** `manager-stamp.sh` used to fall back to manager whenever the
    role file was missing, so two of the three carriers told the same session two
    different roles on the same turn, and neither was wrong by its own lights. All three
    now read the same file in the same order, including the takeover from a recorded
    holder whose process is gone.
  - **A failed measurement is not solitude**, repaired the same day as M2.13. The census
    answers `0 0 0 0 1` when the register cannot be read, and `0 >= 2` is false, so an
    outage used to read as being alone and every session claimed the role at once,
    overwriting the record on the way past. An unmeasured directory now yields carrier
    and no claim. Note what that costs and what it does not: nobody claims, so no role
    file appears, and the guard goes on refusing all the same. The repair costs the
    claim, not the boundary.
  - **A dead holder is taken over by EVERY live session, not by one.** Measured
    2026-09-07 against the shipped copy: with two live sessions and a role file naming a
    process that is gone, `manager-prime.sh`, `manager-reinject.sh`, `manager-stamp.sh`
    and the guard's own `mk_guard_role` all answer manager, to both, on every call, and
    the record stays on the dead entry. It needs no race: two carriers whose manager dies
    are simply both told they are the manager from then on. The comment in the code
    argues against VACANCY, and that argument carries exactly one taker; it does not say
    why all of them take. The guard stopping both is the documented fail-closed side and
    not the defect. What is broken is the sentence the kit tells the sessions about
    themselves. Note where the suite stands on this: the assertion that covers the
    takeover rewrites the record before every call, so it asserts THAT a takeover happens
    and never that exactly one does.
  - **The session name and the role file are two registers with nothing between them.**
    A session can be called `manager` and not hold the role, and nothing shows it. The
    role is claimed only at `SessionStart` with `startup` or `clear`, so a session that
    was already running when the plugin arrived never writes the file, however it is
    named and however long it runs. Naming sessions is the person's, by the section
    above, but the kit currently cannot tell the person that the two disagree.
