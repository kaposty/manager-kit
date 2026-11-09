# manager-kit

A kit for the case where more than one carrier works on the same thing. The role boundary is
held as a path rather than a resolution: the coordinating session writes bookkeeping and hands
work out, and a write past that line is refused by a hook.

Repository, kit and plugin all carry the same name, `manager-kit`.

**It is not a way to run sessions.** Starting, naming and stopping them belongs to the person,
and so does deciding who the coordinator is. This kit measures, and it stops. It never chooses.

**v1 is the role boundary and nothing else.** Ownership, receipt and deadline on disk are a
real second failure and a real candidate for v2; they are named in `GOAL.md` under "Not this
project" with the reason they are out.

## Rules that do not bend

These are not preferences. Each one is here because breaking it cost something measurable,
and the cost is named so the rule can be argued with rather than obeyed.

- **Every verified fact carries the command that proved it.** A claim without provenance is a
  belief, and a later session either re-derives it or, worse, trusts it.
- **Every abandoned path carries its reason.** Without the reason it gets proposed again, and
  the second refusal costs the same as the first. "Postponed" is not a reason: an item filed
  that way comes back the moment its condition is met.
- **A check that has never failed proves nothing.** Write it, run it against the broken state,
  see it RED, and only then keep it. An assertion written after the fix pins the defect in
  place instead of catching it.
- **Test the shipped shape, not a string inside it.** Grepping for a substring passes on code
  that cannot run. Execute the thing, in the layout it will actually be used in.
- **Test the limit against a loaded case.** A budget verified against a small fixture is
  untested. Real input has run five times over a limit that stayed green all week.
- **Test the transition, not only the end state.** A behaviour change lands on everyone who
  started before it existed. Ask, in one sentence, what it does to them, and answer it with an
  assertion rather than a hope.
- **Derive lists, do not type them.** A typed list is a claim about the world at the moment it
  was typed, and the entry it misses is always the newest one. Let the filesystem, the schema
  or the manifest decide, and subtract exceptions one at a time with a reason.
- **The instrument must not sit inside what it measures.** A probe the subject can read hands
  it the answers; one that lives in the layer under test disappears with the failure.
- **A durable file records properties, never counters the process increments itself.**
- **Claims about somebody else's software rot without you touching a line.** Date them, or
  re-check them before repeating them.
- **Maintenance is done, not reported.** Filling in a blank, adding the command behind a
  claim, amending a message that froze a number nobody measured: that is part of the work, not
  a status update about the work. Say what changed in the project. Do not narrate the
  correction, and do not name whatever asked for it.
- **Structure is not progress.** A heading, a folder or a template with nothing behind it
  looks like an answer and is worse than an empty file. `bash check.sh` is what holds this,
  because a rule in a file like this one measurably cuts violations and never reaches zero.

## Before claiming that anything works

`bash check.sh` is the floor and only says that nothing here has gone decorative.
`bash tests/run.sh` is the mechanics, and every assertion in it was seen RED against the broken
state before it was kept. `python3 tests/mutate.py` is what makes that last sentence checkable
instead of believed: it turns each assertion's subject back, one at a time, and requires that
assertion to die. A claim in a living file has no holder and goes stale without anybody
touching it, so the claim ships with the command that re-proves it.

**Neither settles the thing this kit is for.** That is settled by a week of real coordination,
read off `git log`, the hook log and the ownership files, against the stopping condition in
`GOAL.md`. A guard that is green in the suite is proven to WORK. It is not proven to RUN when
it counts, and those are two different wirings: measured 2026-09-06 elsewhere, a counter that
was green across 35 probes appeared at 0 of 4 of the places where the decision was actually
made.

## Where things live

- `GOAL.md` is what "done" means and how you would know. Read it before proposing work.
- `README.md` and `GUIDE.md` are what a reader who did not build this gets.
- `check.sh` goes red when any of the above became decorative.
- The build plan, with its endpoints, their one acceptance each and the decision log, and the
  evidence the plan rests on stay in the author's source repository and are not shipped.

## Style

English, project neutral, and free of em and en dashes, because this is read and run by people
who did not build it. Only the plain hyphen, in every file, and full words rather than
abbreviations. Checkable: `grep -rn $'\u2014\|\u2013' -- . | grep -v '^\./\.git/'` must come back empty.

One rule with teeth beyond style: **a count over a fleet never comes from a command that
carries an upper bound.** Print the base set next to the number and prove the sum, because
without the sum a truncation is indistinguishable from an empty base set, and an empty
denominator looks exactly like a green result.
