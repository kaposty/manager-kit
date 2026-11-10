#!/usr/bin/env python3
"""The mutation probe behind the claim in CLAUDE.md.

CLAUDE.md says every assertion in tests/run.sh was seen RED before it was kept. That is
a statement in a living file, and a statement in a living file goes stale without
anybody touching it. This script is what makes it checkable rather than believed.

One mutation per assertion. Each turns exactly one thing back, runs the whole suite in a
copy of the repository, and requires the assertion aimed at that thing to die. The kills
have to spread: if one mutation kills everything, the suite is one check wearing many
names.
"""

import argparse
import concurrent.futures
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

# TWO ROOTS, DERIVED ONCE EACH, the same pair tests/run.sh derives. PKG is the package:
# everything that ships, and what every anchor path below is written against. REPO is the
# repository around it, which additionally carries the marketplace manifest that decides
# what the package even is. The copy has to be of REPO and not of PKG, because one of the
# mutations turns that manifest back and because the suite reads it to validate the pair.
PKG = os.path.dirname(os.path.abspath(os.path.dirname(__file__) + "/."))
REPO = os.path.dirname(PKG)
PKG_NAME = os.path.basename(PKG)


# THE KIT'S NAME, read once out of the manifest of the package, the way tests/run.sh reads it for KITP. An entry that needs
# the name derives its anchor from this and does not type it, so the register applies in a fork under another name. A
# package copied without its manifest has no name here, and the entries that use it say so as anchors that are not found.
try:
    import json
    with open(os.path.join(PKG, ".claude-plugin", "plugin.json"), encoding="utf-8") as _fh:
        NAME = json.load(_fh)["name"]
except (OSError, ValueError, KeyError):
    NAME = ""

PAD = "padding " * 260
EMDASH = "a " + chr(0x2014) + " b\n"

# (assertion name in tests/run.sh, file, anchor, replacement)
MUTATIONS = [
    ("the harness reports a crashing checker as red", "tests/run.sh",
     '  if _out=$("$@" 2>&1); then', '  if _out=$("$@" 2>&1) || true; then'),
    ("both manifests validate", ".claude-plugin/plugin.json",
     '"name": "%s"' % NAME, '"name": "Manager Kit!!"'),
    # The half raise, verbatim: the package is raised and the marketplace is left where it
    # was. The anchor is the KEY, and the replacement swallows the old value as a prerelease
    # suffix, so nothing here carries the current number and this entry does not go stale on
    # the next release. The fabricated version is semver-valid on purpose, so the assertion
    # has to die on the disagreement rather than on the shape. Anchor counted the way this
    # file counts, as a Python substring, against .claude-plugin/plugin.json: 1.
    #
    # IT KILLS TWO NAMES SINCE THE MANIFEST CHECK WENT STRICT, and that is the repair
    # showing rather than a mutation gone wide. The validator answers the half raise with a
    # WARNING and exits 0 on "Validation passed with warnings"; "both manifests validate"
    # used to grep for a prefix of that line and survived. It asks --strict now, so it dies
    # here too. Measured 2026-09-07 through this loop with MUTATIONS cut to these two
    # entries: the name mutation above killed 1, its own; this one killed 2, both names.
    #
    # The count at the foot of this file does not move for it. `killed` is a UNION over the
    # runs, and "both manifests validate" is already in it from the entry above, which kills
    # it on its own. A collateral hit only lifts "distinct killed" when it lands on a name
    # that has no entry of its own, and this one does. Same run: "Mutations run: 2. Distinct
    # assertions killed across all of them: 2."
    #
    # AND THE ENTRY STAYS THE HALF RAISE. A version broken in BOTH manifests would kill one
    # name and nothing else [measured: with "nonsense", "0.7" and "v0.7.0" in both halves
    # the validator answers "Validation passed" and exits 0 even under --strict], but then
    # nothing here would turn the DISAGREEMENT back on, which is the undelivered-release
    # defect this whole pair of assertions exists for. Buying a tidier number with a probe
    # that stops probing it is the wrong trade.
    ("both manifests carry one version", ".claude-plugin/plugin.json",
     '  "version": "', '  "version": "9.9.9-raised-past-'),
    ("every wired hook exists and is executable", ".claude-plugin/plugin.json",
     '"license": "MIT",', '"license": "MIT",\n  "hooks": "./hooks/hooks.json",'),
    # The anchor moved with the trace: the branch now says why before it answers. The
    # defect it turns back is unchanged, the .claude test going loose. Counted the way this
    # file counts, as a Python substring, against hooks/_classify.sh: 1.
    ("the path measure, eight paths", "hooks/_classify.sh",
     '    */.claude/*)\n      # THE .claude ITSELF', '    *.claude*)\n      # THE .claude ITSELF'),
    # The quoting loop moved INTO the scan with the M3.4 repair, because deciding whether a
    # quoted body is text or the command of a shell needs feeds_cmd(), and its variables
    # were renamed on the way in to keep them apart from the ones the scan already had. The
    # two anchors below moved with it, and they moved a second time on 2026-09-08 when the
    # blanking rule grew a line saying WHICH segment it is blanking. Neither defect changed
    # across either move: never blank, and always blank.
    #
    # Both anchors span the whole if, and that is not tidiness. An anchor on the tail alone
    # would leave the opening brace dangling, awk would refuse the program, and this probe
    # would answer ERROR where it is supposed to answer RED. Counted the way this file
    # counts, as a Python substring, against hooks/_classify.sh: 1 each, and the two are the
    # same string.
    ("the bash measure, six writes and three reads", "hooks/_classify.sh",
     '          if (qbody ~ /[<>|;&]/) { why("the quoted segment " qc qraw qc " carries a shell metacharacter, so it is blanked: it is text, not syntax")\n'
     '                                   # The mark carries a number, so a reader that needs the text back as\n'
     '                                   # a target has it, and every other word goes on seeing no syntax.\n'
     '                                   qtab[++qnum] = qraw\n'
     '                                   qout = qout "Q" qd qnum qd } else qout = qout qbody',
     '          qout = qout qbody'),
    ("a quoted path is still a path", "hooks/_classify.sh",
     '          if (qbody ~ /[<>|;&]/) { why("the quoted segment " qc qraw qc " carries a shell metacharacter, so it is blanked: it is text, not syntax")\n'
     '                                   # The mark carries a number, so a reader that needs the text back as\n'
     '                                   # a target has it, and every other word goes on seeing no syntax.\n'
     '                                   qtab[++qnum] = qraw\n'
     '                                   qout = qout "Q" qd qnum qd } else qout = qout qbody',
     '          qout = qout "Q"'),
    # The in-place test moved into inplace() with the M2.12 repair, so the anchor moved
    # with it. Same defect as before: a -i belonging to another command on the same line
    # counts as this one. Anchor counted with `grep -cF` against hooks/_classify.sh: 1.
    ("a flag from another command is not this one", "hooks/_classify.sh",
     '      if (c == "sed")  return owns(start, "^-[iI]")',
     '      if (c == "sed")  return ($0 ~ /-i/)'),
    # The heredoc branch also grew a second line for the trace, so the anchor spans both.
    # The defect is the one it always was: the delimiter is never recorded, so no body is
    # ever dropped and prose inside a heredoc is read as commands. Counted as a Python
    # substring against hooks/_classify.sh: 1.
    ("a heredoc body is data, not command text", "hooks/_classify.sh",
     '        if (d != "") { delim = d; inh = 1\n',
     '        if (d != "") { delim = d; inh = 0\n'),
    ("the guard refuses a work path", "hooks/role-guard.sh",
     '    "systemMessage": user_msg,\n', ''),
    ("the refusal names the role and the action", "hooks/role-guard.sh",
     'booked + "Refused: " + subject',
     'booked'),
    # Same move, same reason, and the same defect: the .md test stops matching anything.
    # Counted as a Python substring against hooks/_classify.sh: 1.
    #
    # IT KILLS NINE NAMES, and that is the .md axis carrying the suite rather than a
    # mutation gone wide: a Markdown path is the quiet half of half the tables in this file.
    # Two of the nine arrived with the narrowing, "a script written and run in one call"
    # and "a heredoc body an interpreter runs", and they belong there: the counter-case of
    # each is a script whose only write target is docs/notes.md, and with the .md test dead
    # that target is work and the shape stops being cancelled. Measured 2026-09-08 through
    # this loop, run on its own; it was 7 names before the narrowing was built.
    ("the guard is silent on bookkeeping", "hooks/_classify.sh",
     '    *.md)\n      # ONLY THE LAST', '    *.zzzz)\n      # ONLY THE LAST'),
    ("the guard leaves one liveness line a day", "hooks/role-guard.sh",
     'if [ "$NO_RECORD" = 0 ] && [ "$seen" != "$today" ]; then', 'if [ "$NO_RECORD" = 0 ]; then'),
    ("a missing guard log is inconclusive", "tools/week-verdict.sh",
     '    print("or never have run, or the file may have been removed or moved after it ran.")\n    sys.exit(3)',
     '    print("or never have run, or the file may have been removed or moved after it ran.")\n    sys.exit(0)'),
    ("a week the guard slept through is inconclusive", "tools/week-verdict.sh",
     'blind = sorted(commit_days - ran_days)', 'blind = []'),
    ("the guard stands down for a subagent", "hooks/role-guard.sh",
     'if [ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "$SESSION_ID" ]; then', 'if false; then'),
    ("a bash write is refused on both channels", "hooks/role-guard.sh",
     '  Bash) verdict=$(classify_bash "$CMD"); subject=$CMD ;;', '  Bash) exit 0 ;;'),
    # BOTH ANCHORS MOVED WITH THE MARKER: reading and spending it went into mk_kit_spend in
    # hooks/_sessions.sh (MK-A3). The defects these two turn back are the ones they always were.
    ("a declared crossing passes and is spent", "hooks/_sessions.sh",
     '\nos.unlink(name, dir_fd=home)\n', '\n'),
    ("a stale declaration cannot pay for a later one", "hooks/_sessions.sh",
     'if time.time() - st.st_mtime > 300:', 'if False:'),
    # THE ANCHOR MOVED WITH THE WRITER. This turns the append into a truncation, and the
    # append left role-guard.sh in 0.16.0: the shape of a log line is written once, in
    # mk_log_event in hooks/_sessions.sh, because mk_record_role became a second writer of
    # that same line and a shape typed twice drifts on the first rename. Pointed at the old
    # home this entry reported ERROR rather than RED, which is the probe working: a
    # mutation whose anchor has gone is a mutation that is measuring nothing.
    #
    # IT KILLS ONE NAME MORE THAN IT DID, and that one is a consequence of the move rather
    # than a mutation gone wide. Measured through this loop with MUTATIONS cut to this entry
    # alone, both sides of the move, 2026-10-19:
    #   at HEAD, pointed at hooks/role-guard.sh:  3 dead, "the guard leaves one liveness
    #     line a day", "the log holds lines, not a counter", "the count is read out of the
    #     log". A truncating log has always taken those three with it.
    #   here, pointed at hooks/_sessions.sh:      4 dead, the same three and "the guard line
    #     and the claim line are one shape". With the writer shared, a truncating write
    #     truncates the claim line too, so that assertion is left with one line in the log
    #     and cannot compare two writers at all.
    # The count at the foot of this file does not move for any of the four: every one of
    # them has an entry of its own, and `killed` is a UNION over the runs.
    #
    # Anchor counted as a Python substring against hooks/_sessions.sh: 1.
    ("the log holds lines, not a counter", "hooks/_sessions.sh",
     """"manager-kit.log", os.O_WRONLY | os.O_APPEND | os.O_CREAT)""",
     """"manager-kit.log", os.O_WRONLY | os.O_TRUNC | os.O_CREAT)"""),
    ("the count is read out of the log", "hooks/role-guard.sh",
     '            if ev == "stop":', '            if ev == "never":'),
    ("the prime is silent, valid and under budget", "hooks/role-text.md",
     None, PAD),
    # The anchor moved with the M3.5 repair: both carriers derive the project root once
    # and hand THAT in, where they used to hand in the working directory. It moved again
    # with MK-PHANTOM on 2026-11-03, when the call took a third argument, "$claim"; the old
    # anchor no longer resolved and "every mutation in the register still applies" said so.
    # Anchor counted as a Python substring against hooks/manager-reinject.sh: 1.
    ("prime and reinject are byte identical", "hooks/manager-reinject.sh",
     'role=$(mk_decide_role "$ROOT" "$SESSION_ID" "$claim")', 'role=carrier'),
    ("the stamp is one line under 200 characters", "hooks/manager-stamp.sh",
     "  line='manager-kit: you are the manager here.",
     "  line='PADDED PAST TWO HUNDRED CHARACTERS SO THE BUDGET IS BROKEN AND THE "
     "ASSERTION HAS SOMETHING TO CATCH, SAID AGAIN HERE SO THAT IT IS COMFORTABLY "
     "LONGER THAN THE LIMIT AND NOT MERELY CLOSE TO IT. you are the manager here."),
    ("auto compaction is reported, never set", "hooks/_identity.sh",
     r"      *) printf '\nDISABLE_AUTO_COMPACT is not set in this project. An auto-compaction fires\n'",
     "      *) printf ''"),
    ("the census prints its base set and sums", "hooks/_sessions.sh",
     r"""  printf '%s %s %s %s %s\n' "$_base" "$_alive" "$_dead" "$_here" "$_sumok" """.rstrip(),
     r"""  printf '%s %s %s %s\n' "$_base" "$_alive" "$_dead" "$_here" """.rstrip()),
    ("no branch of the census truncates", "hooks/_sessions.sh",
     '    _pids="$_pids$_pid', '    _pids="$(printf %s "$_pids" | head -3)$_pid'),
    ("one session is manager, two is carrier", "hooks/_identity.sh",
     '  if [ "$_here" -ge 2 ]; then', '  if false; then'),
    ("the example role carries version and date", "roles/example-implementer.md",
     'fassung: 1', 'version: 1'),
    # THE ANCHOR IS THE WORD THE ASSERTION READS, AND NOTHING AROUND IT. It used to carry
    # the whole sentence, "role file's `fassung:` in the order you give". That sentence was
    # rewritten on 2026-09-08 to get the file under the 1500 character budget, the anchor
    # went to 0, and this entry answered ERROR where it is supposed to answer RED: the
    # assertion stood green under a mutation that could no longer reach it. What the
    # assertion measures is `grep -qi fassung` and `grep -qi order` over the file, so the
    # backticks, the colon and the words on either side were never measured by anything and
    # only ever made the anchor breakable.
    #
    # `order` cannot be the anchor: it stands in the file twice, replace(.., 1) would leave
    # the second one, the grep would still match and the mutation would survive. `fassung`
    # stands once. The replacement is the word the sibling entry above puts into the role
    # file, and it is the defect plainly: the text asks for "the version" and stops naming
    # the field a role file carries, so no order can be traced to one. It is the same
    # length as the anchor, so the budget assertion on this same file is left where it was.
    # Counted the way this file counts, as a Python substring, against hooks/role-text.md: 1.
    #
    # What stays open is the case. The grep is -i and a Python substring is not, so a text
    # writing "Fassung" would satisfy the assertion and lose the anchor again. No shorter
    # literal is steadier than this one; counting every anchor in this list against the tree
    # is what catches that, not the anchor itself.
    ("the role text demands the version in the order", "hooks/role-text.md",
     'fassung', 'version'),
    ("no em or en dashes anywhere", "README.md", None, EMDASH),
    # Same move, same reason. Anchor counted with `grep -cF` against
    # hooks/manager-stamp.sh: 1.
    ("the two hooks never split one session", "hooks/manager-stamp.sh",
     '  role=$(mk_decide_role "$ROOT" "$SESSION_ID")', '  role=manager'),
    # THE ANCHOR MOVED WITH THE REPAIR and the edit is the same one: the line now sets
    # _counted beside _alone, because a census nobody could take and a census that found
    # company stopped being one fact. Replaced by true, both go back to their optimistic
    # defaults, the session reads solitude it never measured and CLAIMS, which is the
    # half this assertion's name is about. Anchor counted the way this file counts, as a
    # Python substring, against hooks/_identity.sh: 1.
    ("a failed measurement is not solitude", "hooks/_identity.sh",
     '  mk_here_is_measured "$@" || { _counted=0; _alone=0; }', '  true'),
    ("the guard stands down for a carrier", "hooks/role-guard.sh",
     r"  printf 'carrier\n'", r"  printf 'manager\n'"),
    ("an undecidable role counts as the manager", "hooks/role-guard.sh",
     r"""  kill -0 "$_ownerpid" 2>/dev/null || { printf 'manager\n'; return 0; }""",
     r"""  kill -0 "$_ownerpid" 2>/dev/null || { printf 'carrier\n'; return 0; }"""),
    ("a write verb counts only in command position", "hooks/_classify.sh",
     '        if (cmd && (isverb(w) ||', '        if ((isverb(w) ||'),
    ("a separator glued to a word is still a separator", "hooks/_classify.sh",
     '      gsub(/;/, " ; ")', '      gsub(/;/, ";")'),
    # The M2.15 takeover, and it is the one mutation written here rather than handed in:
    # it turns the branch repaired on 2026-09-07 back off, so the prompt hook goes back to
    # calling this session a carrier while the other two hand the role over.
    # RE-ANCHORED 2026-11-03: the stamp's case over field 1 became a call of
    # mk_field1_is_pid, and the old anchor, the arm `*) kill -0 "$ownerpid" ... ;;`, went
    # with it. Same edit on the line that now carries the same branch: the dead pid stops
    # being handed over, and a field that is no pid still is. It kills the same four names
    # on both anchors, measured 2026-11-03 through this file's own main() at d4e3e73 and
    # after the move: this one, "a restarted manager records itself", "one record gives one
    # role in every carrier" and "an unusable record stops in every carrier". Anchor
    # counted as a Python substring against hooks/manager-stamp.sh: 1.
    ("a dead entry is handed over by both hooks", "hooks/manager-stamp.sh",
     '    else kill -0 "$ownerpid" 2>/dev/null || role=manager\n',
     '    else :\n'),
    # Takes the record back out of the loop, which is 0.12.0 verbatim: every reader goes on
    # answering that a dead owner means a vacant chair, and not one of them writes that
    # answer down, so the record keeps naming a process that stopped existing and the next
    # session to START reads the same vacancy and claims it.
    #
    # Turned off rather than deleted, the way the subagent entry above is: what this turns
    # back is the ABSENCE of a write, and removing the block would take the case with it and
    # leave this probe answering ERROR where it is supposed to answer RED.
    #
    # THE FIRST TEST IS THE ANCHOR AND THE REST OF THE CONDITION IS LEFT STANDING, which is
    # not tidiness. `mine` is what says the record already names this session, and it is the
    # half that keeps the repair from taking a chair off anybody; the two counter-cases of
    # that assertion stay green under this mutation and go red under the loose shape this
    # build rejected. Cutting the whole condition would kill the assertion for the wrong
    # reason and say nothing about which half of it is load bearing.
    #
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/manager-stamp.sh: 1. Measured 2026-09-11 through this loop, run on its own, it
    # kills exactly 1 name: its own.
    ("a restarted manager records itself", "hooks/manager-stamp.sh",
     '  if [ "$mine" = 1 ] && [ -n "$SESSION_ID" ] &&',
     '  if false && [ -n "$SESSION_ID" ] &&'),
    # Puts the `|| printf 0` back on the days count. `grep -c` prints its own zero and
    # exits 1, so the fallback fires on top of it and the field carries two lines again.
    # Reachable only in a window with no commits, which is why the assertion carries a
    # window WITH commits as its counter-check.
    ("the days count is one line at zero commits", "tools/week-verdict.sh",
     """days_with_commits=$(printf '%s' "$commit_days" | sort -u | grep -c .)""",
     """days_with_commits=$(printf '%s' "$commit_days" | sort -u | grep -c . || printf 0)"""),
    # Defect A, the outside witness. Hands `git log` the raw string the caller typed
    # again. A bare YYYY-MM-DD makes git fill the time of day in from NOW, so a commit
    # from early this morning drops out of a window that opens today. Anchor counted
    # with `grep -cF` against tools/week-verdict.sh: 1.
    #
    # IT CAME BACK ALIVE ONCE AND THE ENTRY WAS NOT THE REASON. Measured 2026-09-08 at
    # 02:47 UTC in a full run: the assertion's fixture put its only commit of today at
    # 03:00, which at that hour had not happened yet, so the bound git fills in from NOW
    # could not reach past it and the mutated tool printed the shipped verdict line for
    # line. The defect is real and was measured the same minute in a throwaway repository
    # with one commit per hour: at 02:48 UTC bare `--since 2026-09-02` found the four
    # commits from 03:00 on, `--since '2026-09-02 00:00:00'` found all seven. So the
    # witness moved to midnight, which is behind every fill-in git can produce, and the
    # assertion now measures that placement instead of assuming it. Anchor, file and
    # replacement here are unchanged: what was too weak was the assertion.
    #
    # THE ANCHOR MOVED ON 2026-11-03, when the same `git log` line took the upper bound and
    # was broken in two. The mutation is the same one, the raw string handed to git as the
    # lower bound; the anchor is now the head of the line, up to the bound it turns back.
    # Counted as a Python substring against tools/week-verdict.sh: 1.
    ("a bare date reaches back to midnight", "tools/week-verdict.sh",
     'commits=$(TZ=UTC git -C "$PROJECT" log --since="$SINCE_GIT" ',
     'commits=$(TZ=UTC git -C "$PROJECT" log --since="$SINCE" '),
    # Defect B, the inside witness, and it fails the other way. Hands the log reader the
    # git bound instead of the day, so the ten character day out of `ts` is compared
    # against a longer string and every line sorts out of the window. Anchor counted
    # with `grep -cF` against tools/week-verdict.sh: 1.
    #
    # It kills, and it is worth writing down WHAT kills it, because it is not the string
    # comparison. Measured 2026-09-08 by hand against the fixture: the reader's length
    # precondition fires first, refuses '2026-09-08 00:00:00' out loud and exits 1, so
    # "days the guard ran:" is never printed at all and the assertion's first half dies on
    # a missing line. The silent-empty shape the paragraph above describes is what the
    # precondition exists to prevent; the assertion's blind-day half is what would catch
    # it if the precondition ever went away.
    ("a window with an hour still reads the log", "tools/week-verdict.sh",
     'MK_SINCE_DAY=$SINCE_DAY', 'MK_SINCE_DAY=$SINCE_GIT'),
    # The day set goes back to the AUTHOR date, which is the field `git log --since` never
    # filtered on. A rebased or amended commit is then inside the window by its committer
    # date and reports a day outside it, and that day falls out as blind. Anchor counted
    # with `grep -cF` against tools/week-verdict.sh: 1.
    ("the day a commit landed is the committer day", "tools/week-verdict.sh",
     '--format=%cd --date=short-local', '--format=%ad --date=short-local'),
    # The day goes back to being rendered in the zone RECORDED IN THE COMMIT while the
    # guard log stays in UTC, so a commit made just after local midnight carries the next
    # day and the guard line from the same second carries the previous one. The fixture's
    # +1000 commit is what makes this kill independent of the machine's own zone. Anchor
    # counted with `grep -cF` against tools/week-verdict.sh: 1.
    ("one day boundary for git and the guard log", "tools/week-verdict.sh",
     '--date=short-local "$c"', '--date=short "$c"'),
    # THE UPPER BOUND, seven entries, one per assertion. Every anchor below is counted as a
    # Python substring against tools/week-verdict.sh, the way this file applies it: 1 each.
    #
    # The outside witness loses its upper bound: the expansion that hands `git log` its
    # `--until` reads a name that is never set, so git reads to the end of history again,
    # which is the defect that put nine days too many into a closed week. The anchor stops
    # short of the `"--until=$UNTIL_GIT"}` the entry for the bare upper bound turns back:
    # measured 2026-11-03, with one anchor inside the other each of the two runs also killed
    # "every mutation in the register still applies", a kill of the register and not of the
    # behaviour.
    ("the upper bound closes the git history", "tools/week-verdict.sh",
     '"$SINCE_GIT" ${UNTIL_GIT:+', '"$SINCE_GIT" ${UNTIL_GIT_NEVER_SET:+'),
    # The inside witness loses its upper bound: the log reader is handed the open end.
    ("the upper bound closes the guard log", "tools/week-verdict.sh",
     'MK_UNTIL_TS=$UNTIL_TS', 'MK_UNTIL_TS='),
    # The closing second stops being inside the window, which is the off-by-one a bound
    # stated to the second must not have.
    ("an upper bound with a time holds to the second", "tools/week-verdict.sh",
     'stamp <= until_ts', 'stamp < until_ts'),
    # Hands git the upper bound as typed. A bare day is then filled in from NOW and the
    # window closes at the current hour of its last day.
    ("a bare upper bound reads its day to the end", "tools/week-verdict.sh",
     '"--until=$UNTIL_GIT"} \\\n', '"--until=$UNTIL"} \\\n'),
    # The open end goes silent again: the window line says where it opens and nothing
    # about where it ends.
    ("an open upper end is named with its newest line", "tools/week-verdict.sh",
     ', NO UPPER BOUND given: read to the end, newest line below', ''),
    # A window that closes before it opens is read instead of refused, and comes back as
    # an empty week rather than as the typing error it is.
    ("an upper bound before the lower one is refused", "tools/week-verdict.sh",
     'if [ "$_u" -lt "$_l" ]; then', 'if false; then'),
    # The lower bound goes back to reaching the log by day: the stops of the morning before
    # a window opened at noon are counted again.
    ("a lower bound with a time holds to the second", "tools/week-verdict.sh",
     'since_ts <= stamp', 'since_day <= stamp'),
    # M2.12, repair 1. Turns off the rule that the first bare operand of an in-place sed
    # or perl is the EXPRESSION, so the program text goes back to being read as the
    # target path. Anchor counted with `grep -cF` against hooks/_classify.sh: 1.
    ("an in-place expression is program text", "hooks/_classify.sh",
     '            if (owed) { owed = 0; continue }',
     '            if (0) { owed = 0; continue }'),
    # M2.12, repair 2. Takes the -delete branch back out, so find -delete is silent
    # again. The anchor moved on 2026-09-08 when the -exec repair split the reading of a
    # find in two: findpaths() RETURNS the search path now and findtarget() prints it, so
    # that the -exec of the same find can print it later out of the same string. The defect
    # this turns back is unchanged, and the line that REMEMBERS the search path is
    # deliberately outside the anchor, so what dies here is -delete alone and the -exec
    # fallback next to it stays alive. Counted the way this file counts, as a Python
    # substring, against hooks/_classify.sh: 1.
    ("find -delete is a write on its search path", "hooks/_classify.sh",
     '        if (cmd && w == "find" && owns(i + 1, "^-delete$")) { findtarget(fpaths, "the -delete of a find"); continue }',
     '        if (0) { findtarget(fpaths, "the -delete of a find"); continue }'),
    # Resets command position at EVERY line start again, which is the defect exactly: a
    # line continued with a backslash goes back to being read as a command of its own, so
    # a write verb inside a continued argument counts. The line grew the hw reset with the
    # -c repair and this anchor was left pointing at the old shape, so the probe answered
    # ERROR instead of RED: found 2026-09-08 by counting every anchor in this file against
    # the tree. The reset stays in the replacement, so what is turned back here is the cont
    # test and nothing else. Counted as a Python substring against hooks/_classify.sh: 1.
    ("a masked newline is not a separator", "hooks/_classify.sh",
     '      if (!cont) { expect = 1; skip = 0; hw = ""; xf = 0; fpaths = ""; if (cdir != "" && !cdx) cdsoft = (cdmade ? 0 : 1); cdx = 0 }',
     '      expect = 1; skip = 0; hw = ""; xf = 0; fpaths = ""'),
    # Puts "repeat the call right away" back into the general refusal, which is the
    # sentence that invited the declaration and the crossing into ONE command, where the
    # guard refuses the declaration along with the crossing. Anchor counted with
    # `grep -cF -e` against hooks/role-guard.sh: 1.
    ("the declaration goes in a call of its own", "hooks/role-guard.sh",
     '        " in a call of its own, and repeat this call right after. "',
     '        " and repeat the call right away. "'),
    # Blinds the guard to the marker path in the refused text, so a call that packed the
    # declaration in with the crossing goes back to being answered with the general
    # lecture: write a declaration, says the guard to somebody who just wrote one. Anchor
    # counted with `grep -cF -e` against hooks/role-guard.sh: 1.
    ("a declaration in the same call is named as one", "hooks/role-guard.sh",
     'packed = bool(marker) and marker in raw',
     'packed = False'),
    # The handover, and the seven below are the second way the role can move. Each turns
    # one thing in it back. Anchors counted with `grep -cF` against the file named: 1 each.
    #
    # The record goes back to naming the holder it was supposed to replace, which is the
    # whole of the old behaviour: the session that typed the command stays a carrier and
    # the one that had the role keeps it.
    # The anchor moved with the second field: the line writes $SID now, where SID is the
    # session id when one could be measured and the placeholder when none could. The defect
    # it turns back is unchanged, and both halves of the record go back with it: the record
    # names the holder this command was supposed to replace, pid and id together, so the
    # session that typed the command stays a carrier and the one that had the role keeps it.
    ("the command moves the role to this session", "tools/manager-claim.sh",
     'if ! printf \'%s %s\\n\' "$MYPID" "$SID" 2>/dev/null | mk_kit_write "$ROOT" manager-kit.role; then',
     'if ! printf \'%s %s\\n\' "${PREVPID:-0}" "$PLACEHOLDER" 2>/dev/null | mk_kit_write "$ROOT" manager-kit.role; then'),
    # Takes the gate off the pid, so a session that could not measure which one it is
    # writes anyway. That is the record this command must never produce: read back, its
    # first field is not a pid at all.
    ("a claim with no pid writes nothing", "tools/manager-claim.sh",
     'case "$MYPID" in\n  \'\'|*[!0-9]*)',
     'case "$MYPID" in\n  zzz-never-a-pid)'),
    # Files the transition under the event the week is measured on. A handover then spends
    # the false-alarm budget in GOAL.md on something that never stopped anybody.
    ("the handover is one line under its own event", "tools/manager-claim.sh",
     'EVENT=handover', 'EVENT=stop'),
    # Stops measuring whether the holder being replaced is still there and says it is,
    # every time. The report reads the same and has stopped carrying a finding.
    # RE-ANCHORED 2026-11-03: the tool's case over PREVPID became a call of
    # mk_field1_is_pid, and the old anchor, the arm `*)        if kill -0 "$PREVPID" ...`,
    # went with it. Same edit on the two lines that now carry that branch: a pid-shaped
    # field is called alive without being asked, a field that is no pid is still unusable.
    # It kills TWO names since the same day, measured through this file's own main(): this
    # one, and "the claim line calls a field 1 that is no pid unusable", which runs the
    # take-over now and dies on its dead pid alone ("previous <pid> alive", expected gone).
    # At 35166a7, on the old anchor and before that check reached the tool: this one only.
    # Anchor counted as a Python substring against tools/manager-claim.sh: 1.
    ("the handover names who it replaced and what lags", "tools/manager-claim.sh",
     '  elif kill -0 "$PREVPID" 2>/dev/null; then PREVSTATE=alive\n  else PREVSTATE=gone\n',
     '  else PREVSTATE=alive\n'),
    # Rewrites a record that already names this session, trading the session id a
    # SessionStart wrote for the placeholder and putting a line in the log for a transition
    # that did not happen.
    ("a record that is already ours is left alone", "tools/manager-claim.sh",
     'if [ -n "$PREVPID" ] && [ "$PREVPID" = "$MYPID" ]; then',
     'if false; then'),
    # THE SHAPE TEST TURNED LOOSE, and what comes back is the guess the header of that
    # command has refused since it was written: whatever the environment says goes into
    # field 2. The host id with its local_ prefix lands in the record, an id in the wrong
    # case lands in it, and so does a value with a space in it, which is a record with
    # three fields where four readers expect two. Counted as a Python substring against
    # tools/manager-claim.sh: 1.
    #
    # It kills exactly one name. The restart assertion below drives a well shaped id
    # through an environment that agrees with the pid, and a rule that accepts everything
    # accepts that one too, so nothing over there moves.
    ("a take-over records the session it can measure", "tools/manager-claim.sh",
     '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])',
     '*)'),
    # 0.14.0 PUT BACK IN ONE LINE. The id is never taken, field 2 is the placeholder
    # again, the pid is the whole of the identity in that record, and a restart of the
    # session that took the role erases it. The empty assignment is the smallest edit that
    # does it: the branch two lines further down already turns an empty SID into the
    # placeholder, so the fallback is exercised rather than bypassed and nothing else has
    # to move. Counted as a Python substring against tools/manager-claim.sh: 1.
    #
    # IT KILLS TWO NAMES AND BOTH ARE ITS OWN. The assertion above asks the same command
    # for the one case that may write an id, so a version that can never write one fails
    # there as well. The count at the foot of this file does not move for it: killed is a
    # union over the runs and that name has an entry of its own, directly above.
    ("a take-over survives the restart that took it", "tools/manager-claim.sh",
     'SID=$(mk_claim_session_id "$MYPID")', 'SID='),
    # The command block stops failing loudly when it cannot find the script. It prints the
    # sentence and then exits 0, so the turn looks like a handover that happened.
    ("the command resolves the script it calls", "commands/take-over.md",
     "  printf 'session was started after it was.\\n'\n  false",
     "  printf 'session was started after it was.\\n'\n  true"),
    # Puts a write to a work path into the block, which is what the name says the command is not. It
    # was a redirection to a file descriptor (`>&2`) until MK-R2, when the classifier had stopped
    # reading that as a write at MK-A6 and the entry had been alive since: measured 2026-11-07 at
    # 0464e26 with the guard on the bare command, `>&2` is silent and `> src/notice.txt` is refused.
    ("the command is not itself a write", "commands/take-over.md",
     "  printf 'manager-kit: tools/manager-claim.sh is not reachable from this session.\\n'",
     "  printf 'manager-kit: tools/manager-claim.sh is not reachable from this session.\\n' > src/notice.txt"),
    # M3.5. Anchors the guard back at the WORKING DIRECTORY, which is the defect verbatim:
    # measured 2026-09-07 in a live project, a session standing in .claude/agents wrote its
    # whole record into .claude/agents/.claude/, the only guard-ran line of that day went
    # in there, and the log tools/week-verdict.sh reads counted the day as one the guard
    # slept through. The role file and the exception marker split the same way and fail
    # silently. Anchor counted with `grep -cF` against hooks/role-guard.sh: 1.
    ("the record is kept at the project, not the cwd", "hooks/role-guard.sh",
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT', 'ROOT=${CWD:-$PWD}'),
    # M3.6, THE .git THAT IS A FILE. The climb tested it with -e, which is true of a file
    # and of a directory alike, so every linked worktree counted as a project of its own
    # and the record split across all of them. The four below are one repair and each
    # turns back ONE of its four decisions. All four anchors sit inside
    # mk_project_root_set and nowhere else, and the two case arms share one line, so two
    # of the entries carry the same anchor string with different replacements.
    #
    # The first two assertions of the repair could not be red on their own, and that is
    # worth writing down rather than hiding: "a submodule stays a project of its own" and
    # "a gitdir naming no repository keeps the worktree" both describe the answer the
    # BROKEN function already gave, because -e kept every .git file where it stood. Each
    # of them therefore carries the resolving half of its own minimal pair, which is what
    # made them red before the change, and that is also why the two entries below that
    # turn resolving off take a second name with them.
    #
    # Prefixes a gitdir that is ALREADY ABSOLUTE with the worktree, which is the naive
    # join and the state a first cut of this repair had: /main/.git/worktrees/a read
    # against /wt becomes /wt/main/.git/worktrees/a, no such repository exists, and every
    # worktree falls back to itself. It leaves the relative arm doing exactly what it does
    # now, so "a relative gitdir is read against the worktree" survives it.
    #
    # IT KILLS THREE NAMES, and the other two are resolving halves of the kind described
    # above rather than a mutation gone wide. Both hold an ABSOLUTE gitdir that has to
    # RESOLVE, which is the half this replacement breaks: "a gitdir naming no repository
    # keeps the worktree" resolves once its target becomes a repository, and "a barred main
    # repository keeps the worktree" resolves for the one main repository in it that the
    # bar does not stop. Measured 2026-09-09 through this loop with the five entries of
    # this group run one at a time: 3 names, its own and those two, and the difference set
    # was read line by line. The third name died on that one probe of five and on no other,
    # so the bar itself is not what this replacement touches. The entries that turn those
    # two rules themselves back kill exactly 1 each, so none of the three is one check
    # wearing several names. Anchor counted the way this file counts, as a Python
    # substring, against hooks/_sessions.sh: 1.
    # SINCE 2026-11-02 IT KILLS FOUR, measured run on its own: the three above and "every
    # mutation in the register still applies", because this edit takes the anchor of "a
    # relative gitdir is read against the worktree" with it, on the same line.
    ("a worktree is recorded at its main repository", "hooks/_sessions.sh",
     "            case $_gd in /*) ;; *) _gd=$_w/$_gd ;; esac",
     "            case $_gd in /*) _gd=$_w/$_gd ;; *) _gd=$_w/$_gd ;; esac"),
    # Cuts at ANY /.git/ instead of at /.git/worktrees/, which is the wide rule and the one
    # this repair had to say no to: a submodule points at <parent>/.git/modules/<name>, so
    # the wide cut hands the submodule's record to the repository above it. `git log` inside
    # a submodule reports the submodule's history, and that is the history
    # tools/week-verdict.sh weighs the guard's own record against, so the two would then
    # disagree about what week they are describing. It leaves every worktree resolving
    # exactly as it does now. Measured 2026-09-09 through this loop, run on its own, it
    # kills exactly 1 name: its own. Anchor counted as a Python substring against
    # hooks/_sessions.sh: 1.
    ("a submodule stays a project of its own", "hooks/_sessions.sh",
     "            case $_gd in */.git/worktrees/*) _main=${_gd%%/.git/worktrees/*}; _wtn=${_gd#*/.git/worktrees/} ;; esac",
     # The component test is turned back and so is the question asked of the file system (MK-R5): with -ef on the
     # line below, a submodule is no longer taken for a worktree by the component alone, and it would only be
     # swallowed if the name built here also reached it through worktrees/.. .
     "            case $_gd in */.git/*) _main=${_gd%%/.git/*}; _wtn=../${_gd#*/.git/} ;; esac"),
    # Takes the line at its word. Whatever the gitdir named becomes the project root with
    # no check that anything is there, so a worktree of a BARE repository, and one whose
    # main repository has been moved away, both anchor the log, the role file and the
    # exception marker in a directory nobody keeps bookkeeping in. It changes nothing for a
    # gitdir that does name a repository, so the other three survive it. Measured
    # 2026-09-09 through this loop, run on its own, it kills exactly 1 name: its own.
    # Anchor counted as a Python substring against hooks/_sessions.sh: 1.
    #
    # THE ANCHOR MOVED WITH THE BAR REPAIR, which put a second clause on the acceptance
    # test and broke the line this entry used to name whole. It is aimed at the clause it
    # was always about, the -d test, and it now leaves the bar clause standing rather than
    # taking both away with it: a replacement that removed both would kill two names and
    # this one still kills exactly its own. The defect it turns back is unchanged.
    # Anchor counted as a Python substring against hooks/_sessions.sh: 1.
    # Leaves a relative gitdir relative, which resolves it against the working directory of
    # whatever process the hook happens to be running in rather than against the worktree.
    # `git worktree add --relative-paths` and worktree.useRelativePaths write that form, and
    # under this replacement the same line names a different place on every call. The
    # absolute arm is untouched, so "a worktree is recorded at its main repository" survives
    # it.
    #
    # IT KILLS TWO NAMES for the same reason the first entry does: "a submodule stays a
    # project of its own" is a minimal pair whose other half is a RELATIVE worktree, and
    # this replacement breaks that half. Measured 2026-09-09 through this loop, run on its
    # own: 2 names, its own and that one. The entry that turns the submodule rule itself
    # back kills only that name, so the pair is not one check twice. Anchor counted as a
    # Python substring against hooks/_sessions.sh: 1, and it is the same line the first
    # entry of this group anchors on: two arms, two decisions, one line.
    # SINCE 2026-11-02 IT KILLS THREE, measured run on its own: the two above and the
    # register check, because this edit takes the anchor of "a worktree is recorded at its
    # main repository" with it.
    ("a relative gitdir is read against the worktree", "hooks/_sessions.sh",
     "            case $_gd in /*) ;; *) _gd=$_w/$_gd ;; esac",
     "            case $_gd in /*) ;; *) ;; esac"),
    # Lets the resolved main repository past mk_root_is_barred, which is the branch as this
    # repair found it: the bar is asked in every round of both walks, and this was the one
    # answer in the function naming a directory neither walk ever stood on. A dotfiles
    # repository keeps its .git at the home directory itself, so under this replacement
    # every worktree of one answers $HOME and the log, the role file, the seen marker and
    # the exception marker are written into the person's own .claude directory, which is
    # read by every project they own.
    #
    # Written as a swap for `true` rather than as a deletion, so the condition keeps its
    # shape and the two clauses in front of it keep deciding exactly what they decide now:
    # what comes back is the acceptance test of the previous build, byte for byte. It
    # changes nothing for a main repository that is not barred, which is every worktree in
    # the other four assertions of this group, so those survive it. Measured 2026-09-09
    # through this loop, run on its own, it kills exactly 1 name: its own. Anchor counted
    # the way this file counts, as a Python substring, against hooks/_sessions.sh: 1.
    ("a barred main repository keeps the worktree", "hooks/_sessions.sh",
     '! mk_root_is_barred "$_main"',
     'true'),
    # Turns the report off and leaves the search running, which is the state the kit was in
    # while three foreign names were removed by hand: something looked, nothing said so.
    # The ok line then prints over the finding, so all three red directions of the assertion
    # die at once. Anchor counted with `grep -cF` against check.sh: 1.
    ("nothing that ships names another project", "check.sh",
     'elif [ -n "$FOREIGN" ]; then', 'elif false; then'),
    # Takes the fourth name back off the list, which is the state the six lines of MK-NAMEN
    # shipped in: the report stays on, and the package of the project the frozen corpus
    # came from goes through it unnamed. Only the package probe of the assertion dies; the
    # other three names and the home path still go red. The anchor is the joined name with
    # the blank in front of it, so the line keeps the shape it had before the name came.
    # Anchor counted the way this file counts, as a Python substring, against check.sh: 1.
    ("nothing that ships names another project", "check.sh",
     ' "quiquer""y"', ''),
    # Puts the package root back at the repository root, which is the whole of the defect
    # this move repairs: `source` is the only thing that decides what an installer
    # receives, so pointing it at "./" hands out the bookkeeping again, 18 files of it and
    # 45 lines carrying foreign project paths and this machine's home directory. The
    # anchor is the one path in this list that sits OUTSIDE the package, because the file
    # that names the package cannot itself be inside it. Anchor counted with `grep -cF`
    # against .claude-plugin/marketplace.json: 1.
    #
    # The validator cannot see it: with `source` back at "./" the repository root carries no
    # plugin manifest at all, and `claude plugin validate` there still answers "Validation
    # passed" [measured 2026-09-07, exit 0, --strict included]. It follows `source` into a
    # package that has a manifest and says nothing when it finds none, so the packaging is
    # not something the manifest check can see. That is the reason this entry exists here.
    #
    # It no longer kills alone. "both manifests carry one version" reaches the package
    # manifest through the same `source`, so it dies here too and names the path it could
    # not read [measured 2026-09-07, both FAIL lines out of one run of this entry].
    ("the bookkeeping is not inside what ships", "../.claude-plugin/marketplace.json",
     '"source": "./kit",', '"source": "./",'),
    # THE FIVE BELOW HOLD THE TWO SHAPES OF THIS REPOSITORY, the build clone with .claude/
    # and the public one without, and each dies on a fixture, so each dies in both shapes.
    # They kill this name and no other, measured 2026-11-04 by applying each one and
    # reading every FAIL line of the run. Every anchor counted the way this file counts,
    # as a Python substring, against tests/run.sh: 1.
    #
    # The defect of MK-LEER, verbatim: a repository with no .claude/ is red again, which
    # is what a clone of the public repository saw. Dies on the fixture without one.
    ("the bookkeeping is not inside what ships", "tests/run.sh",
     'print("this repository keeps no bookkeeping',
     'sys.exit("this repository keeps no bookkeeping'),
    # The pass goes silent: check() stops showing what a passing checker said, so the
    # public shape is green and never says that it keeps no bookkeeping.
    ("the bookkeeping is not inside what ships", "tests/run.sh",
     "    [ -z \"$_out\" ] || printf '%s\\n' \"$_out\" | sed 's/^/         /'\n", ''),
    # The quiet half goes blind: no name is ever .claude/, so bookkeeping under `source`
    # is never seen. The build clone ships nothing of it under ./kit, so only the fixture
    # with `source` at ./ can see this, and it does by the reason it is given.
    ("the bookkeeping is not inside what ships", "tests/run.sh",
     '        if n == ".claude":', '        if n == ".claude/":'),
    # The strict half goes: a .claude/ that yields not one file to the walk passes as the
    # public shape, so an unreadable bookkeeping directory is a green measurement of it.
    ("the bookkeeping is not inside what ships", "tests/run.sh",
     'if not kept and os.path.lexists(book):', 'if False:'),
    # The line of the public shape is printed everywhere, so the build clone says it keeps
    # no bookkeeping while keeping it. Dies on the fixture that keeps some and keeps it out.
    ("the bookkeeping is not inside what ships", "tests/run.sh",
     'if not kept:', 'if True:'),
    # The defect this assertion was written for, in its first item: the line saying that
    # plan and evidence are not shipped gives way to the bullet that pointed at the plan,
    # verbatim from 3843ca2. The plan stands at the root of the build clone, and this copy
    # is of the build clone, so the assertion dies only because it resolves against the
    # package. It kills this name and no other, measured 2026-11-04 run on its own, in the
    # build clone and in the public cut. Anchor counted the way this file counts, as a
    # Python substring, against CLAUDE.md: 1.
    ("the map in CLAUDE.md names what ships, or says it stays", "CLAUDE.md",
     "- The build plan, with its endpoints, their one acceptance each and the decision log,"
     " and the\n  evidence the plan rests on stay in the author's source repository and are"
     " not shipped.\n",
     "- `.claude/plan-v1.md` is the build plan: endpoints, their one acceptance each, and the\n"
     "  decision log. It is the spine, and status lives there rather than in four other"
     " places.\n"),
    # The three below are one probe, and each of them turns one of its repairs back.
    # All three were measured against 46715 real commands of a foreign project on
    # 2026-09-07, where the measure stopped 3715 of them.
    #
    # Defect 1. Puts the old test back: apply, restore or checkout ANYWHERE among the
    # arguments of a git, and from then on every word behind the git word is a candidate
    # target, the subcommand itself included. That is the defect verbatim, and it was the
    # largest single class of false alarms the measure had: 613 stops of 3715, 16.5
    # percent, and the word it stopped on was "checkout". Anchor counted with `grep -cF`
    # against hooks/_classify.sh: 1.
    ("a git subcommand is not a target", "hooks/_classify.sh",
     '          if (gs && ($gs == "apply" || $gs == "restore")) gfrom = gs + 1',
     '          if (gs && owns(i + 1, "^(apply|restore|checkout)$")) gfrom = i + 1'),
    # Defect 2. Takes the mode and the owner back out of what a chmod owes, so the +x of
    # chmod +x .claude/hooks/x.sh is read as a path again and every chmod is a stop, one
    # on a path the coordinator owns included. Anchor counted with `grep -cF` against
    # hooks/_classify.sh: 1.
    ("a mode word is not a path", "hooks/_classify.sh",
     '          owed = (prog != "" || w == "chmod" || w == "chown"); pending = 0; np = 0',
     '          owed = (prog != ""); pending = 0; np = 0'),
    # Defect 3. Leaves the markers around a quoted operand exactly where they are and
    # stops reading them, so an owed operand is skipped one WORD at a time again and the
    # rest of an expression that carries a space stands as a target: "s/alt und mehr/neu/" (de-input)
    # read as the expression s/alt plus two files called und and mehr/neu/ (de-input). Anchor counted
    # with `grep -cF` against hooks/_classify.sh: 1.
    ("a quoted operand is one operand", "hooks/_classify.sh",
     '            if ($j == oq && (owed || pending)) { j = qend(j); owed = 0; pending = 0; continue }',
     '            if (0) { j = qend(j); owed = 0; pending = 0; continue }'),
    # Hands the operand of -c back to the wrapper skip, which is the defect verbatim: the
    # skip that exists for sudo -u root rm eats the first word of the COMMAND instead, and
    # the second word takes command position, so bash -c "npm install typescript" reads as
    # a write on install. The replacement is the line as it stood before the repair, so
    # nothing here carries the repair's own shape. Anchor counted the way this file counts,
    # as a Python substring, against hooks/_classify.sh: 1.
    ("the operand of -c is a command", "hooks/_classify.sh",
     '          if (w ~ /^-/) { if (!feeds_cmd(w, hw)) skip = 1; continue }',
     '          if (w ~ /^-/) { skip = 1; continue }'),
    # Reads the placeholder of a find -exec as a path again, which is the defect verbatim:
    # {} is where find substitutes what it matched and + is what ends the -exec, and both
    # came back as targets, so find apps/api/src -name __pycache__ -type d -exec rm -rf {} +
    # stopped on the word "{}". The replacement leaves the operand loop exactly as it was
    # before the repair. 27 distinct stops of 8234 carried the shape, 189 of 43160 weighted.
    #
    # It kills on TWO independent lines of its own assertion, which is why the entry is on
    # this half of the repair rather than on the search-path fallback next to it: the trace
    # goes back to saying "names {}", and find .claude/logs -name "*.tmp" -exec rm {} + goes
    # back to being a stop on a bookkeeping path. The fallback is held by the same assertion
    # from the other side, because with the placeholders skipped and the fallback gone that
    # command names nothing at all and the assertion demands work.
    #
    # It does NOT reach "find -delete is a write on its search path": with {} read as a path
    # again, find . -name "*.pyc" -execdir rm {} ; is a stop for the old reason and that
    # assertion stays green. Counted the way this file counts, as a Python substring,
    # against hooks/_classify.sh: 1.
    ("a find -exec placeholder is not a path", "hooks/_classify.sh",
     r'            if (xf && ($j == "{}" || $j == "+" || $j == "\\")) continue',
     '            if (0) continue'),
    # Empties the list of programs that hand a command somewhere else, which is the state
    # this file was in between the -c repair of 2026-09-08 and the one after it: no word is
    # a carrier, so the body behind the -c of a shell is read as command text of THIS
    # machine wherever the shell stands. That is the defect verbatim and it is the half
    # reading: docker exec api sh -c "rm -f src/x.py" stays quiet because docker hands
    # command position to nobody, while docker run img sh -c "echo hi > /data/x.py" and
    # docker exec api sh -c "cd /srv && rm -rf src/x.py" become stops on paths this machine
    # has never had.
    #
    # The list is what is turned back rather than the call in cmdtext(), because an empty
    # list is exactly the pre-repair state: offsite() is still called, still walks, and
    # still answers no. Counted as a Python substring against hooks/_classify.sh: 1.
    ("a body bound for elsewhere is not read", "hooks/_classify.sh",
     '      return (t == "ssh" || t == "docker" || t == "docker-compose" || t == "podman")',
     '      return 0'),
    # Hands the body of a shell back to the blanking rule, which is the silent pass
    # verbatim: a quoted body carrying [<>|;&] is wiped to "Q", so sh -c "cd /tmp && rm -rf
    # src/x.py" has nothing left on the line to read. Turning cmdtext() off rather than
    # deleting the unwrap keeps the mutation on the one decision that was added.
    #
    # IT KILLS A SECOND NAME, and that is one shared line rather than a mutation gone wide.
    # "a path in front of a shell is not a disguise" holds /bin/sh -c "cd /tmp && rm -f
    # src/x.py", whose body is blanked here before the path in front of the shell is ever
    # reached. Measured 2026-09-08 through this loop with MUTATIONS cut to these two
    # entries: this one killed 2 names and the other 1, and the two lines that carry the
    # path repair on their own, /bin/bash -c and /usr/bin/env rm, both survive this one.
    # So the pair does not collapse into one check wearing two names.
    # Anchor counted as a Python substring against hooks/_classify.sh: 1.
    ("the body of a shell is command text", "hooks/_classify.sh",
     '          if (cmdtext(qout)) {',
     '          if (0) {'),
    # Compares the whole word again, which is the defect verbatim: /bin/bash is not bash,
    # so it hands command position to nobody and the write behind its -c is never read.
    # The replacement is the line as it stood before the repair. Anchor counted as a Python
    # substring against hooks/_classify.sh: 1.
    ("a path in front of a shell is not a disguise", "hooks/_classify.sh",
     '          if (hands_on(shname(w))) hw = shname(w); else { expect = 0; hw = "" }',
     '          if (hands_on(w)) hw = w; else { expect = 0; hw = "" }'),
    # Steps over a bare VAR=x and forgets it again, which is the defect verbatim: the
    # value never reaches asgn, resolve() finds no name to look up, and every target that
    # arrived in a variable goes back to being read as the literal word "$L". That is the
    # one hole the guard was measured to have FIRED on, and it fired on the coordinating
    # session's own .claude/session-ledger.<id>.md.
    #
    # The replacement is the line as it stood before the repair, so nothing here carries
    # the repair's own shape. It leaves record() and resolve() in the file, unreached: a
    # mutation that deleted them would take the awk program with it and this probe would
    # answer ERROR where it is supposed to answer RED. Anchor counted the way this file
    # counts, as a Python substring, against hooks/_classify.sh: 1.
    ("a variable assigned in the same command", "hooks/_classify.sh",
     '          if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { record(i); i = opend; continue }',
     '          if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue'),
    # REFUSES THE SUBSTITUTION AGAIN WHEN A LITERAL STANDS BEHIND THE NAME, which is the
    # one line this build deleted, put back where it stood. "$F.log" goes back to being
    # read as the word "$F.log" and the five stops of the week come back with it. It is
    # written as an INSERTION in front of the next condition, because what it turns back is
    # a DELETED line and there is nothing in the file to swap; the anchor carries the line
    # behind it so the replacement cannot land twice.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("a variable with a literal behind it", "hooks/_classify.sh",
     '      } else return t\n'
     '      if (!(name in asgn)) {',
     '      } else return t\n'
     '      if (rest != "" && substr(rest, 1, 1) != "/") return t\n'
     '      if (!(name in asgn)) {'),
    # Silences the scan's half of the trace, which is turning the subject of that assertion
    # back exactly: the measure goes on deciding what it decided before and stops saying
    # WHICH WORD it decided on. The shell half in classify_path is left alone, so what dies
    # here is the naming of the verb and the target and not the whole file, and the
    # assertion has to be reading that naming to notice.
    #
    # The anchor carries the comment line under it because the function line alone occurs
    # TWICE, once in the heredoc stripper and once in the scan, and an anchor that matches
    # two places replaces the first one silently. Counted the way this file counts, as a
    # Python substring, against hooks/_classify.sh: 1 for the pair, 2 for the line alone.
    ("the measure says why, not only what", "hooks/_classify.sh",
     '    function why(s) { if (explain == 1) print s > "/dev/stderr" }\n'
     '    # The quote characters',
     '    function why(s) { if (0) print s > "/dev/stderr" }\n'
     '    # The quote characters'),
    # The tool goes back to documenting a call that carries its example in the COMMAND
    # LINE, which is the defect the file route exists for, one layer up: the help tells the
    # reader to make a call the guard then refuses. Measured 2026-09-08 against the shipped
    # function, that line comes back work.
    #
    # IT HAD TO BE THIS SHAPE AND NOT THE PLAIN ONE, and the reason is worth writing down:
    # `bash tools/mk-explain.sh "rm -rf src/x.py"` classifies as BOOKKEEPING, because a
    # write verb inside a quoted operand is nobody's command. Only an example carrying a
    # shell body of its own is stopped. So the trap the tool exists for is intermittent,
    # which is the worst kind: the manager tries the easy shape, it works, and the shape
    # that gets refused is the interesting one. Anchor counted as a Python substring
    # against tools/mk-explain.sh: 1.
    ("every call the tool documents is silent", "tools/mk-explain.sh",
     'bash tools/mk-explain.sh .claude/probe.txt\n',
     'bash tools/mk-explain.sh "bash -c \\"cd /tmp && rm -rf src/x.py\\""\n'),
    # THE SECOND AXIS OF THE PATH MEASURE, added 2026-09-08 on the owner's decision, and
    # the four below are one repair. Each turns one thing in it back.
    #
    # This one turns back the direction the decision is ABOUT: the rule going wide. The
    # replacement is the wide rule verbatim, everything under /tmp, and that rule was
    # measured and rejected. A second hand sample of 60, other seed and no overlap with the
    # first, found 2 real writes of production code whose only catch was a path outside the
    # work tree, at least 202 over the corpus, and the wide rule silences every one of them.
    #
    # It reaches none of the three entries below it, and the reason is worth writing down:
    # they name paths that lie inside the scratchpad either way, so a wider rule leaves
    # every one of their answers where it was. It does take one older name with it, and
    # that name is the wide rule's price in miniature: "a variable assigned in the same
    # command" holds `SP=/tmp/probe; cat > "$SP/w.out"` as WORK, and the wide rule answers
    # bookkeeping. Measured 2026-09-08 through this loop: 2 names dead, its own and that
    # one. Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("the session scratchpad is bookkeeping, /tmp is not", "hooks/_classify.sh",
     '    /tmp/claude-[0-9]*/*/*/scratchpad|/tmp/claude-[0-9]*/*/*/scratchpad/*)',
     '    /tmp/*)'),
    # The two spellings go back to being two directories. On macOS /tmp is a symlink to
    # /private/tmp and the session's own environment hands the long form out, so this is
    # not a curiosity: the long form is the spelling the guard is most likely to be given,
    # and under this mutation the guard refuses the scratchpad whenever it arrives written
    # that way and passes it when it arrives written the other. Anchor counted with
    # `grep -cF` against hooks/_classify.sh: 1.
    ("both spellings of /tmp are one directory", "hooks/_classify.sh",
     '  _sp=${_p#/private}', '  _sp=$_p'),
    # Takes the SUBTREE out and leaves the bare directory, so every file and every
    # subdirectory under the scratchpad goes back to being work. That is the whole of the
    # rule in practice: no tool call names the directory, they all name something under it.
    #
    # IT KILLS SIX NAMES, and that is the branch carrying them rather than a mutation
    # gone wide: with everything under the scratchpad back to work, the path table of "the
    # session scratchpad is bookkeeping, /tmp is not" and the cp source of "a copy out of
    # the scratchpad follows its target" go with it. The spread is what says the three are
    # not one check wearing three names, and it is measured rather than argued: the entry
    # above kills 2 names and neither of those two is on this list, the entry below kills 8
    # and this one is not among them, and "both spellings of /tmp are one directory" kills
    # exactly 1. Measured 2026-09-08 through this loop, the four entries run on their own.
    #
    # THREE OF THE SIX ARE THE NARROWING, and they arrived with it: "a script written and
    # run in one call", "a heredoc body an interpreter runs" and "a git write of the
    # working tree". They go with this mutation because the narrowing is a rule about paths
    # the scratchpad axis silenced, and this replacement stops it silencing anything under
    # the scratchpad at all, so there is nothing left for a shape to cancel. It was 3 names
    # before the narrowing was built. Anchor counted with `grep -cF` against
    # hooks/_classify.sh: 1.
    # SINCE 2026-11-02 IT KILLS EIGHT, measured run on its own: the six above, "prose in a
    # heredoc body is not a path", which joined later, and the register check, because
    # this edit takes the anchor of "the session scratchpad is bookkeeping" with it.
    ("a scratchpad script is silent, the run is not", "hooks/_classify.sh",
     '|/tmp/claude-[0-9]*/*/*/scratchpad/*)', ')'),
    # A DROPPED SOURCE ANSWERS FOR THE WHOLE COMMAND. The operand a copy only reads, named
    # once on the line and dropped with its reason, ends the walk as bookkeeping instead of
    # being stepped over, so the target behind it is never measured. For a cp out of the
    # scratchpad that is the verdict resting on the source, which is the defect this
    # assertion exists for.
    #
    # RE-AIMED 2026-11-03, because the old aim was no longer on this assertion's path. It
    # returned bookkeeping on the first path that came back bookkeeping, behind
    # `if [ "$(classify_path "$_t")" = work ]`, and since eb417e4 the source of
    # "cp <scratchpad>/probe.py src/probe.py" never gets that far: the copy arm marks it
    # @@q@@ and the loop drops it before the measure, so the target is the first and only
    # path measured. Run on its own on 959b3a5 the old entry came back ALIVE, its own name
    # standing and eleven others dead; each of the eleven has an entry of its own. What
    # makes a copy follow its target now is the drop, so the source is turned back where it
    # is handled now.
    #
    # IT KILLS TEN NAMES, measured 2026-11-03 run on its own with every FAIL line read, and
    # the nine beside its own are the same sentence: each carries a copy whose source is
    # named once and stands before a target in the work tree, and each goes quiet on it.
    # "a quoted path is still a path", "a write verb counts only in command position",
    # "a masked newline is not a separator", "the operand of -c is a command", "a
    # fragment of program text is not a path", "a copy is read by the operand it writes",
    # "a copy keeps the operand its call still writes", "a redirection word is not an
    # operand" and "a write split over lines keeps its stop". None of them is among the
    # eleven of the old aim.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("a copy out of the scratchpad follows its target", "hooks/_classify.sh",
     '          _mk_why "  $_q is only read by this copy and is named nowhere else on the line"\n'
     '          continue\n',
     '          _mk_why "  $_q is only read by this copy and is named nowhere else on the line"\n'
     "          printf 'bookkeeping\\n'; return 0\n"),
    # THE THREE SHAPES OF THE NARROWING, one entry each, and each one turns off the
    # DETECTION of its own shape rather than the branch that acts on all three. A single
    # entry on the acting branch would kill all three names at once and say nothing about
    # whether the three are three checks or one wearing three names.
    #
    # The first: the set of scripts this call WRITES is never filled, so no run can be
    # matched against it and G1 never fires. G2 and G3 do not read that set and are
    # untouched. Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1. Measured 2026-09-08 through this loop, run on its own, it
    # kills exactly 1 name: its own.
    ("a script written and run in one call", "hooks/_classify.sh",
     "        if (b ~ skript) geschrieben[b] = 1",
     "        if (0) geschrieben[b] = 1"),
    # The second: the CONSUMER of a heredoc is never read, so no heredoc is ever seen to be
    # run and G2 never fires. It is the quiet direction on purpose. The loud one, letting
    # the data sinks count, would kill this name too, but through the counter-case rather
    # than through the shape, and the defect this rule repairs is silence. Anchor counted
    # the way this file counts, as a Python substring, against hooks/_classify.sh: 1. Measured 2026-09-08 through this loop, run on its own, it
    # kills exactly 1 name: its own.
    ("a heredoc body an interpreter runs", "hooks/_classify.sh",
     "          k = kopfwort(letztes(substr(probe, 1, pos - 1)))",
     '          k = ""'),
    # Reads every quoted word with a slash in it as a path again, which is the defect of
    # 2026-11-02 verbatim: the literal scan of a heredoc body held "10/10" and "Hoch/Tief"
    # for files and stopped 16 of the 122 stops of one week on German prose. The line is
    # put back exactly as it shipped, so the two helper functions stay in the file and are
    # simply never asked. The assertion dies on its two prose bodies, and its third quiet
    # case, the price, comes back loud with them.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("prose in a heredoc body is not a path", "hooks/_classify.sh",
     '          if (index(t, "/") > 0 && (istanker(t) || hatendung(t)) && !(t in gesehen)) { gesehen[t] = 1; print t }',
     '          if (index(t, "/") > 0 && !(t in gesehen)) { gesehen[t] = 1; print t }'),
    # The third: the git shape is still recognised and no longer acted on. It is the whole
    # of G3 and nothing else, because G3 has no second condition to turn back: the eleven
    # calls it catches in the measured corpus are eleven real writes and it costs nothing.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1. Measured 2026-09-08 through this loop, run on its own, it
    # kills exactly 1 name: its own. Since 2026-11-03 it kills a second, "a stop names the
    # shape that cancelled the scratchpad", whose git case is then no stop at all: that is
    # the newer check holding the same shape, not this mutation gone wide. The anchor
    # carries benannt() since that day, which hands the naming line up under the trace.
    ("a git write of the working tree", "hooks/_classify.sh",
     '      if (g3) { benannt(); print "!git"; exit }',
     '      if (0) { benannt(); print "!git"; exit }'),
    # THE SHAPE OF THE WORD, and this turns back the branch that carries most of it: the
    # pattern stops matching anything, so a word ending in punctuation goes back to being
    # measured as a file name and "now()" is a path again. It is written as a pattern that
    # matches nothing, the way the .md entry above is, because deleting the branch would
    # leave the case list without its last arm and the file would not parse: this probe is
    # supposed to answer RED and not ERROR.
    #
    # The other two branches of the rule are deliberately left standing, so what dies here
    # is one sentence of it. Anchor counted the way this file counts, as a Python
    # substring, against hooks/_classify.sh: 1.
    ("a fragment of program text is not a path", "hooks/_classify.sh",
     """      *')'|*']'|*';'|*':'|*',')""",
     """      *'zzzz')"""),
    # TAKES THE LAST-OPERAND ARM OF A COPY BACK OUT, by making its condition unreachable
    # rather than deleting it: the arm stays in the file, under a guard that is never true,
    # so the brace it opens is not left dangling and this probe answers RED and not ERROR.
    # With the arm inert every operand of cp(1), install(1) and ln(1) is a candidate again,
    # which is the state this file shipped in until 2026-11-02 and the 13 false alarms of
    # one measured week come back with it.
    #
    # IT DOES NOT KILL THE ASSERTION BELOW, and that is deliberate: with the arm inert
    # nothing is ever dropped, so the two shapes that must not be dropped are still loud
    # and the -t cases are still loud. One edit, one assertion, measured.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("a copy is read by the operand it writes", "hooks/_classify.sh",
     '          } else if (prog == "" && !gfrom && np >= 2 && !zielvorn &&',
     '          } else if (0 && prog == "" && !gfrom && np >= 2 && !zielvorn &&'),
    # DROPS THE SOURCE OF A COPY UNCONDITIONALLY, which is the arm WITHOUT its second
    # exception and the defect of 2026-09-08 verbatim: the source is dropped even when the
    # line names it again. That is the shape of the ten silent passes of 46587 payloads,
    # measured 2026-09-09 and read by hand one at a time: back the file up out of the tree,
    # then rewrite it in place through a -c body or a heredoc this measure cannot read. The
    # test becomes always true, so every dropped operand stays dropped.
    #
    # It kills the backup shapes of its own assertion and leaves "a copy is read by the
    # operand it writes" alive, because what that one asserts is the drop itself.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("a copy keeps the operand its call still writes", "hooks/_classify.sh",
     '        if [ "$_nq" -le 1 ]; then',
     '        if [ "$_nq" -ge 0 ]; then'),
    # READS THE TARGET OPTION IN TWO SPELLINGS AGAIN, the exact words -t and
    # --target-directory that the pre-scan for a target in front still knows, and in none of
    # the others: tdopt() is never asked, so -tsrc/, -vtsrc/, --target-directory=src/,
    # --targ src/ and the rest are stepped over as flags with their value, and a copy, move,
    # install or link into the work tree goes quiet. That is the silent pass of 2026-11-02
    # verbatim, measured through role-guard.sh with a real PreToolUse payload.
    #
    # It kills nothing else: the only other assertion with a target in front, "a copy keeps
    # the operand its call still writes", spells it -t DIR, which the pre-scan still reads.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("a target option is read in every spelling", "hooks/_classify.sh",
     '            if (!tdend && (tk = tdopt($j, w))) {',
     '            if (!tdend && (tk = 0)) {'),
    # Reads a redirection as an operand of the command it stands behind again. The word
    # "2>/dev/null" goes back into the operand list, so a find cleanup stops on it instead
    # of on the directory it walks, and a write of a bookkeeping path behind it goes loud.
    # The body of the branch is left standing and unreachable, because a mutation that
    # deleted it would take the operand loop with it.
    # Anchor counted as a Python substring against hooks/_classify.sh: 1.
    ("a redirection word is not an operand", "hooks/_classify.sh",
     '            if ($j ~ /[<>]/) {',
     '            if (0) {'),
    # Reads a git apply by its OPERAND again instead of by the tree it writes, which is the
    # silent pass verbatim: the patch file answers for the whole call, so a patch lying in
    # the coordinator's own bookkeeping makes a rewrite of the work tree quiet.
    # Anchor counted as a Python substring against hooks/_classify.sh: 1.
    ("a git apply is read by the tree it writes", "hooks/_classify.sh",
     '          if (gfrom && $gs == "apply") {',
     '          if (0) {'),
    # Reads every name=value operand of a dd as a path again, so if= decides and the file
    # the call really writes is never measured. Turned off rather than deleted for the same
    # reason as the two above.
    # Anchor counted as a Python substring against hooks/_classify.sh: 1.
    ("a dd is read by its of= operand", "hooks/_classify.sh",
     '          } else if (w == "dd") {',
     '          } else if (0) {'),
    # PUTS THE BARE BACKSLASH BACK ON THE DROP LIST, which is the half built repair
    # verbatim and the one defect of this build that was found by reading rather than by
    # the suite. The backslash that masks a newline is the LAST operand of the line it
    # ends, and behind the rule that lets the last operand decide, dropping it leaves an
    # empty operand list: "git checkout HEAD -- \\" over paths on the continued lines
    # names nothing at all and goes silent. Measured over the frozen corpus it cost one
    # stop of 2877 and that one was a real write of six production files.
    #
    # It is written as an INSERTION in front of the next test rather than as a swap,
    # because there is nothing left in the file to swap: the rule this turns back is the
    # absence of a line. The anchor is the first test behind the operand drops and it
    # stands there once. Anchor counted the way this file counts, as a Python substring,
    # against hooks/_classify.sh: 1.
    ("a write split over lines keeps its stop", "hooks/_classify.sh",
     '            if (prog != "" && feeds($j, prog))       { pending = 1; owed = 0; continue }',
     '            if ($j == "\\\\") continue\n'
     '            if (prog != "" && feeds($j, prog))       { pending = 1; owed = 0; continue }'),
    # ------------------------------------------------------- the stop on a hand, 0.14.0
    # ONE ARM OF ONE HAND, AND THE SMALLEST EDIT THAT TURNS THE RULE BACK. The floor is
    # the half a hand can act on with nobody watching it, and low-readonly is the cheapest
    # hand, which is where a clause gets dropped when somebody trims a file for being too
    # long. The other three arms and the other five files are left exactly as they are, so
    # what dies here is the claim that EVERY hand carries the floor, and not the weaker
    # claim that some file somewhere mentions it.
    #
    # It also takes "the checker sees a hand with no stop" down with it, and that is the
    # two assertions overlapping rather than a mutation gone wide: that one copies the six
    # hands into a throwaway project and requires the clean run to be green, which a
    # broken sixth hand is not. The count at the foot of this file does not move for it,
    # because that name has an entry of its own below and is already in the union.
    #
    # Anchor counted the way this file counts, as a Python substring, against
    # agents/low-readonly.md: 1. It stands once per hand, and the replacement leaves a
    # readable sentence, so what fails is the arm and not the parse.
    ("every hand carries the stop and the handover", "agents/low-readonly.md",
     "150 tool calls or 300 KB", "no fixed number of tool calls"),
    # THE BACKGROUND IS THE WORD THE WHOLE COORDINATOR HALF HANGS ON, and the replacement
    # is the defect plainly rather than a nonsense token: a hand handed out in the
    # FOREGROUND blocks the session that handed it out, so the coordinator cannot take a
    # turn, cannot read the transcript and cannot send the stop. Every other word of the
    # paragraph survives, which is what makes this a test of the tie and not of the file.
    #
    # THE REPLACEMENT IS THE SAME LENGTH AS THE ANCHOR, ten characters for ten, for the
    # reason the fassung entry above gives: the budget assertion on this same file is
    # measured to two characters of headroom after the 0.14.0 raise, and a longer
    # replacement would kill that one instead and say nothing about this one.
    #
    # Anchor counted as a Python substring against hooks/role-text.md: 1.
    ("the role text hands the stop to the coordinator", "hooks/role-text.md",
     "BACKGROUND", "FOREGROUND"),
    # THE TYPED LIST, PUT BACK. This is check 8's defect reproduced deliberately inside
    # check 10: the six hands that exist today are named by hand, all six are read, all
    # six pass, and the seventh somebody adds next month is never opened. The checker
    # stays green over a hand that has no stop at all, which is the exact silent pass the
    # derivation was written to close, and nothing in the output says so.
    #
    # Turned into a typed list rather than deleted, because deleting the loop would take
    # the case with it and leave this probe answering ERROR where it has to answer RED.
    # What is turned back is the DERIVATION, so the replacement has to be the shape that
    # still works for every file that existed on the day it was typed.
    #
    # It kills exactly one name: the two text assertions read agents/ and role-text.md
    # directly and never go through the checker, and the older probe that does run the
    # checker builds a project with no agents/ at all, where check 10 stands down.
    #
    # Anchor counted as a Python substring against check.sh: 1.
    ("the checker sees a hand with no stop", "check.sh",
     r'''  HANDS="$(find "$AGENTS_DIR" -type f -name '*.md' 2>/dev/null | sort)"''',
     r'''  HANDS="$(printf '%s\n' agents/high.md agents/low-readonly.md agents/max.md agents/medium.md agents/xhigh-readonly.md agents/xhigh.md)"'''),
    # ------------------------------------------------ the turn limit and the hour cache (MK-E2)
    #
    # A HAND COPIED FROM BEFORE THE LIMIT. One of six loses its maxTurns; the client would let it
    # run to its context, and nothing else in the suite reads the field of a kit hand.
    # Anchor counted as a Python substring against agents/medium.md: 1.
    ("every hand stops at its turn limit", "agents/medium.md",
     "\nmaxTurns: 170\n---\n", "\n---\n"),
    # A DECIDED HAND THAT FELL BACK TO FIVE MINUTES. The decision still names max and the hand no
    # longer carries the block, which is the drift the one place exists to show.
    # Anchor counted as a Python substring against agents/max.md: 1.
    ("exactly the decided hands write the hour cache", "agents/max.md",
     "experimental:\n  cacheTtl: 1h\n", ""),
    # THE REPAIR OF THE ONE READER THAT SHIPS, TURNED BACK. An indented line is read as a key of the
    # top again, so the nested name: of the fixture renames the hand. It also takes down "the suite
    # reads a hand past a nested block", because the checks that one runs go through this reader.
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("a nested block hides no key of a hand", "hooks/_routing.sh",
     '                if line[:1] in (" ", "\\t"):\n                    continue\n', ""),
    # THE SUITE'S OWN READER, TURNED BACK. hands() in ROUTE_EFFORT_PY takes the nested keys again; with
    # the real hands nothing shows, only the copy with the wrong keys in every hand does.
    # Anchor counted as a Python substring against tests/run.sh: 1.
    ("the suite reads a hand past a nested block", "tests/run.sh",
     '            # An indented line belongs to the block above it, experimental: among them.\n'
     '            if line[:1] in (" ", "\\t"):\n                continue\n', ""),
    # THE LIMIT OF THE MEASUREMENT, CUT. The README then says the fields work for a plugin hand.
    # Anchor counted as a Python substring against README.md: 1.
    ("the documents say the turn limit and the hour cache", "README.md",
     "**For a plugin hand the hour cache is measured once and the turn limit is read, not measured.**",
     "**For a plugin hand both fields work.**"),
    # THE GUIDE NAMES TWO OF THE THREE. The decision and the hands agree, the guide does not.
    # Anchor counted as a Python substring against GUIDE.md: 1.
    ("the documents say the turn limit and the hour cache", "GUIDE.md",
     "`high`, `max` and `xhigh`. Each does it", "`high` and `max`. Each does it"),
    # THE INSTALL SECTION GOES BACK TO THE LOCAL PATH. The first command block no longer adds the public source.
    # Anchor counted as a Python substring against README.md: 1.
    ("the install section names the public source", "README.md",
     "marketplace add kaposty/manager-kit --scope local", "marketplace add /path/to/manager-kit --scope local"),
    # THE OLD SENTENCE BACK IN THE README, and in the GUIDE, to show that the list of documents is the glob and not
    # the one file. Each anchor is the sentence that now stands in its place, counted as a Python substring: 1.
    ("no document says the kit is unpublished", "README.md",
     "The public source is `kaposty/manager-kit`, and the two commands above name it.", "The kit is not published yet."),
    ("no document says the kit is unpublished", "GUIDE.md",
     "### The file the rule turns on\n",
     "### The file the rule turns on\n\nThe kit is not published yet.\n"),
    # EACH WORD THE DATED SENTENCE IS HELD TO, TURNED BACK ONE AT A TIME, in the README. Every anchor stands once there.
    ("the documents date what a plugin hand was measured to do", "README.md",
     "On 2026-11-09 a", "On a day a"),
    ("the documents date what a plugin hand was measured to do", "README.md",
     "one project, one hand", "every project, every hand"),
    ("the documents date what a plugin hand was measured to do", "README.md",
     "plugin hand `manager-kit:high` called without a model", "plugin hand `high` called without naming a model"),
    ("the documents date what a plugin hand was measured to do", "README.md",
     "a plugin hand `xhigh-readonly` called without a model", "a plugin hand `scout` called without naming a model"),
    # THE OLD CLAIM BACK, in the README: both fields only read. The heading is the anchor.
    ("the documents date what a plugin hand was measured to do", "README.md",
     "**For a plugin hand the hour cache is measured once and the turn limit is read, not measured.**",
     "**For a plugin hand both fields are read, not measured.**"),
    # ------------------------------------------------ the kit is published in English (MK-ENGLISCH)
    # THE VERDICT BACK IN GERMAN, in the tool: the output a user reads. Anchor counted as a Python substring against
    # tools/mk-cost.sh: 1.
    ("the public tree has no German user text", "tools/mk-cost.sh",
     '        print("Verdict: not distinguishable.")\n',
     '        print("Urteil: nicht unterscheidbar.")\n'),  # de-input
    # A GERMAN SENTENCE IN A DOCUMENT, to show the scan reads the documents and not the tools alone. Anchor counted as a
    # Python substring against GUIDE.md: 1.
    ("the public tree has no German user text", "GUIDE.md",
     "### The file the rule turns on\n",
     "### The file the rule turns on\n\nDie Datei ist nicht fertig.\n"),  # de-input
    # THE MARKER STOPS SPARING. A line that carries it is read like any other. It kills the check of the real tree as
    # well, which is the marker doing its work on the accept words. Anchor counted against tests/run.sh: 1.
    ("the German scan flags German and spares marked input", "tests/run.sh",
     '        if "de-input" in line:\n', '        if False:\n'),
    # THE DETECTOR LOSES ITS WORDS: only umlauts are seen. Anchor counted against tests/run.sh: 1.
    ("the German scan flags German and spares marked input", "tests/run.sh",
     "        m = words.search(line) or umlaut.search(line)\n", "        m = umlaut.search(line)\n"),
    # THE DETECTOR LOSES ITS UMLAUTS: only words are seen. Anchor counted against tests/run.sh: 1.
    ("the German scan flags German and spares marked input", "tests/run.sh",
     "        m = words.search(line) or umlaut.search(line)\n", "        m = words.search(line)\n"),
    # THE WORD BOUNDARY GOES: a German word inside an English one (listing) is flagged. Anchor counted against
    # tests/run.sh: 1 each.
    ("the German scan flags German and spares marked input", "tests/run.sh",
     '(?<![A-Za-z])(?:%s)(?![A-Za-z])', '(?:%s)'),
    # THE SCAN ENDS RED ON A PLAIN FILE: its exit status is part of what is asked. Anchor counted against tests/run.sh: 1.
    ("the German scan flags German and spares marked input", "tests/run.sh",
     "print(\"files read: %d\" % seen)\n", "print(\"files read: %d\" % seen); sys.exit(3)\n"),
    # THE PUBLIC TREE LOSES ITS TOOLS. Anchor counted against tests/run.sh: 1.
    ("the German scan reads every file of the public tree", "tests/run.sh",
     "find \"$ROOT\" -type f ! -path '*/__pycache__/*' | sort\n",
     "find \"$ROOT\" -type f ! -path '*/__pycache__/*' ! -path '*/tools/*' | sort\n"),
    # THE PUBLIC TREE LOSES THE MARKETPLACE MANIFEST. Anchor counted against tests/run.sh: 1.
    ("the German scan reads every file of the public tree", "tests/run.sh",
     'for _f in "$REPO/.claude-plugin/marketplace.json" "$REPO/README.md"', 'for _f in "$REPO/README.md"'),
    # THE PUBLIC TREE TAKES IN THE BOOKKEEPING: the walk starts at the repository. Anchor counted against tests/run.sh: 1.
    ("the German scan reads every file of the public tree", "tests/run.sh",
     "find \"$ROOT\" -type f", "find \"$REPO\" -type f"),
    # THE SCAN SKIPS A FILE IT WAS HANDED, before it counts it: the number read and the number listed part. (A skip after
    # the count is a mutant no count can see, and the first version of this entry was one.) Anchor counted against
    # tests/run.sh: 1.
    ("the German scan reads every file of the public tree", "tests/run.sh",
     "    except (UnicodeDecodeError, OSError):\n        continue\n    seen += 1\n",
     "    except (UnicodeDecodeError, OSError):\n        continue\n    if p.endswith(\"/check.sh\"):\n        continue\n    seen += 1\n"),
    # ------------------------------------------------ no secret form stands whole in the public tree
    # THE sk- KEY STANDS WHOLE AGAIN: only the sk- pattern of _KNOWN reads it. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     '"echo sk-" "FAKE0123456789abcdefghijKLMN > src/a.py"',
     '"echo sk-' 'FAKE0123456789abcdefghijKLMN > src/a.py"'),
    # THE ghp_ TOKEN STANDS WHOLE AGAIN. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     '"git push https://ghp_" "FAKE',
     '"git push https://ghp_FAKE'),
    # THE AKIA ID STANDS WHOLE AGAIN. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     '"echo AKIA" "FAKEFAKE12345678 > src/a.py"',
     '"echo AKIA' 'FAKEFAKE12345678 > src/a.py"'),
    # THE SLACK APP TOKEN STANDS WHOLE AGAIN (the refused one was the bot token, this is its twin). Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     'SLACK_APP = "xapp-" "1-A0FAKE',
     'SLACK_APP = "xapp-1-A0FAKE'),
    # THE SLACK BOT TOKEN STANDS WHOLE AGAIN, the very line GitHub refused. Read by _KNOWN and by the typed loose form alike. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     'SLACK = "xoxb-" "1234567890-FAKE',
     'SLACK = "xoxb-' '1234567890-FAKE'),
    # THE GOOGLE KEY STANDS WHOLE AGAIN. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     'GOOGLE = "AIza" + "SyFAKE',
     'GOOGLE = "AIzaSyFAKE'),
    # THE JWT STANDS WHOLE AGAIN. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     'JWT = "eyJhbGciOiJIUzI1NiJ9." "eyJ',
     'JWT = "eyJhbGciOiJIUzI1NiJ9.eyJ'),
    # A PRIVATE KEY HEADER STANDS WHOLE AGAIN: only the header of _PEM reads it. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     '"cat > src/k.pem <<EOF\\n-----BEGIN " "PRIVATE KEY-----',
     '"cat > src/k.pem <<EOF\\n-----BEGIN ' 'PRIVATE KEY-----'),
    # A STRIPE LIVE KEY STANDS WHOLE AGAIN: only the typed form reads it, the redactor names none. Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     '"echo sk_live_" "FAKE0123456789abcdefgh > src/a.py", "sk_live_" "FAKE',
     '"echo sk_live_' 'FAKE0123456789abcdefgh > src/a.py", "sk_live_' 'FAKE'),
    # A SLACK PREFIX WITH NO DIGIT STANDS WHOLE AGAIN: _KNOWN asks a digit, only the typed loose form reads it (the line the coarse grep of the order matched). Anchor counted against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     '"echo eyJhbGciOiJIUzI1NiJ9 xoxb-" "token-format',
     '"echo eyJhbGciOiJIUzI1NiJ9 xoxb-' 'token-format'),
    # THE SCAN SKIPS A FILE IT WAS HANDED, before it counts it: the number read and the number listed part. Anchor counted
    # against tests/run.sh: 1.
    ('no secret form stands in one piece in the public tree', "tests/run.sh",
     "    except (OSError, ValueError):\n        continue\n    seen += 1\n    for n, line in enumerate(lines, 1):\n        for f in forms:",
     "    except (OSError, ValueError):\n        continue\n    if p.endswith(\"/check.sh\"):\n        continue\n    seen += 1\n    for n, line in enumerate(lines, 1):\n        for f in forms:"),
    # ------------------------------------------------ the role that was taken in silence
    #
    # THE CLAIM ITSELF, turned back to what 0.15.0 shipped. The whole of the repair in
    # mk_decide_role is that a manager decision reached through the dead-owner branch does
    # not write the record, and the condition below is the whole of the mechanism, so this
    # entry removes exactly it. The role answer does not move: manager before, manager
    # after. What comes back is the write, and with it the 2026-10-19 day.
    #
    # It kills exactly one name. The assertions that watch the record from the other side
    # stay green because every one of them either writes the record again before each call
    # [prime_and_stamp_hand_over_a_dead_role_together], or builds a record whose owner is
    # ALIVE [a_restarted_manager_records_itself case 3, and the take-over one], or has no
    # record at all [one_session_is_manager_two_is_carrier].
    #
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_identity.sh: 1.
    ("a contested chair is not claimed", "hooks/_identity.sh",
     '  if [ "$_role" = manager ] && [ "$_claim" = claim ] && [ "$_contested" != 1 ]; then',
     '  if [ "$_role" = manager ] && [ "$_claim" = claim ]; then'),

    # A CONTINUED SESSION CLAIMS BY THE STARTUP'S RULE, AND ONLY OVER A RECORD NAMING NOBODY
    # LIVING [MK-PHANTOM, 2026-11-03]. Three entries for three assertions, all on the gate in
    # hooks/manager-reinject.sh, and each one is a repair somebody would plausibly write.
    #
    # The gate never opens: the hook behaves as it did at d6eb3e7, the record goes on naming
    # the phantom, and only the assertion of the take-back dies. Its anchor is NOT the one
    # the entry below uses: two entries on one anchor each delete the other's, and "every
    # mutation in the register still applies" then dies with both [measured: it did].
    # Anchor counted as a Python substring against hooks/manager-reinject.sh: 1.
    ("a resumed session takes back a chair whose holder is gone", "hooks/manager-reinject.sh",
     'if mk_kit_usable "$rf"; then', 'if false; then'),
    # "Whoever finds a dead record on resume writes itself in", past the census. The take-
    # back still lands, so the first of the three stays green. It kills THREE names, and
    # that is the shape rather than a wide mutation [measured 2026-11-03 with every dead name
    # listed]: its own; "a resume takes nothing a startup would not", because the contested
    # lage is a cell of that matrix by construction, where a startup writes nothing and this
    # writes; and "an unusable record stops in every carrier", which holds every carrier,
    # this hook included, off an unusable record while a second session is counted.
    ("a resumed session leaves a contested chair alone", "hooks/manager-reinject.sh",
     'then claim=claim; fi',
     'then mk_record_role "$ROOT" "$(mk_own_pid)" "$SESSION_ID"; fi'),
    # The gate loses its kill -0, so every record that is there opens it: a living foreign
    # pid outside the register [Fall A] is overwritten by a resume, and a compaction of the
    # holder writes a claim line. A startup takes the first one too, so the subset half of
    # the matrix stays green and the half that holds a resume off a pid that still answers
    # dies. Anchor counted as a Python substring against hooks/manager-reinject.sh: 1.
    ("a resume takes nothing a startup would not", "hooks/manager-reinject.sh",
     '|| ! kill -0 "$ownerpid" 2>/dev/null; then', '|| :; then'),

    # THE LINE THAT NAMES WHO TOOK THE CHAIR, turned into a line that names nobody. The
    # record is still written and a claim line is still filed, so the log goes on carrying
    # one line per write: what is turned back is the half the incident actually needed,
    # which is being able to read WHICH session the record now names. The handover line the
    # user's own take-over wrote on 2026-10-19 named pid 1366, and that is the only reason
    # the day could be reconstructed at all.
    #
    # AND THIS IS NOT THE OBVIOUS MUTATION, which would be deleting the mk_log_event call
    # outright. That one kills TWO names, and the second is not collateral in the usual
    # sense: "the guard line and the claim line are one shape" cannot compare two writers
    # when one of them no longer writes, so it dies for want of a subject rather than
    # because it was aimed at. Measured through this loop with MUTATIONS cut to the
    # deletion alone: 2 names dead, "every write of the record leaves a line" and "the
    # guard line and the claim line are one shape". The assertion that owns the existence
    # of that line is the first of the two, and this entry aims at it without taking the
    # other one's subject away.
    #
    # Anchor counted as a Python substring against hooks/_identity.sh: 1.
    ("every write of the record leaves a line", "hooks/_identity.sh",
     '    "pid $_rr_pid holds the role in $_rr_root" \\',
     '    "the role was recorded in $_rr_root" \\'),

    # ONE SHAPE, TYPED A SECOND TIME. The replacement is the copy role-guard.sh carried
    # until the writer moved into _sessions.sh, byte for byte, with subject and reason
    # swapped: the two keys the guard fills with the longest strings and the two a reader
    # is most likely to transpose. Every line is still valid JSON, every key is still
    # there, and every existing reader goes on working, which is exactly the point. A
    # shape that drifted in a second copy does not announce itself: json.loads keeps
    # parsing and rec.get() keeps answering None, and every number the kit derives by
    # counting gets quietly smaller.
    #
    # It kills exactly one name, the assertion that compares the ordered keys of the lines
    # the two writers produced. Nothing else in the suite reads the ORDER.
    #
    # Anchor counted as a Python substring against hooks/role-guard.sh: 1.
    ("the guard line and the claim line are one shape", "hooks/role-guard.sh",
     'append() { mk_log_event "$ROOT" "$1" "$2" "${3-}" "${4-}"; }',
     'append() {\n'
     '  printf \'%s\\037%s\\037%s\\037%s\' "$1" "$2" "${3-}" "${4-}" |\n'
     "    python3 -c '\n"
     'import sys, json, time\n'
     'parts = sys.stdin.read().split("\\x1f", 3)\n'
     'ev, tool, subject, reason = (parts + ["", "", "", ""])[:4]\n'
     'sys.stdout.write(json.dumps({\n'
     '    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),\n'
     '    "event": ev, "tool": tool,\n'
     '    "reason": reason[:400], "subject": subject[:400],\n'
     '}) + "\\n")\n'
     "' >> \"$LOG\" 2>/dev/null || true\n"
     '}'),

    # THE STAMP'S HALF OF THE SPLIT, TURNED BACK BY DELETING TWO WORDS. A record whose field
    # 1 is not a pid then gives manager in mk_guard_role and in mk_decide_role and carrier
    # here, which is the state 990901e shipped and the state the first repair of this defect
    # left standing: it moved mk_decide_role alone, compared two typed carriers, and its gate
    # reported 97 checks green. The assertion aimed at this is the only one that reads all
    # four wired carriers against each other, so this is the smallest edit that can kill it.
    #
    # RE-ANCHORED 2026-11-02 ON THE ARM AS IT STANDS. da1c515 widened it to ''|*[!0-9]*|0*)
    # and this entry hung on the old text, so it could not be applied on any of the eight
    # tips from there to aab6be6 [measured, with the count the runner uses]. Same
    # edit on the same arm: the action goes and the patterns stay, so 0 is no longer
    # turned to manager here either, because 0* is part of the arm and not a second one.
    # It kills TWO names now, measured by applying it and running tests/run.sh in a copy:
    # this one, and "an unusable record stops in every carrier", which reads this arm in
    # all four carriers and came in with da1c515 itself, so it never met this entry while
    # the entry applied. Sparing the second would take a mutant that splits the arm in
    # two, which is a shape the hook does not have.
    # RE-ANCHORED 2026-11-03, because the arm left the stamp: the patterns are in
    # mk_field1_is_pid now and the stamp asks that function. Old anchor
    # "      ''|*[!0-9]*|0*) role=manager ;;", new anchor the call that replaced it. Same
    # edit: the question stays and the action goes, so a field 1 that is no pid is a
    # carrier in the stamp alone.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/manager-stamp.sh: 1.
    ("one record gives one role in every carrier", "hooks/manager-stamp.sh",
     '    if ! mk_field1_is_pid "$ownerpid"; then role=manager\n',
     '    if ! mk_field1_is_pid "$ownerpid"; then :\n'),

    # ------------------------------------------------------- the model routing, seven
    # THE USER CHANNEL OF THE REFUSAL, DELETED. Same edit as the guard's own entry above
    # and for the same reason: the refusal still denies, the model is still told, and the
    # PERSON is never told that a policy whose gain is nobody's measurement just cost them
    # a handout. GOAL.md needs the person to notice, which is why the two channels are not
    # interchangeable.
    #
    # It is aimed here and not at the cheap-model test, which is the obvious mutation.
    # That one stops every refusal and takes the subject away from "every handout leaves a
    # line naming the model" as well, which would be two names dead for one edit.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("haiku on the repair hand is refused", "hooks/route-guard.sh",
     '    "systemMessage": user_msg,\n', ''),

    # THE DERIVATION, TYPED OUT AS THE SIX THIS KIT SHIPS. Every hand in agents/ keeps its
    # right effort, so the refusal still fires on manager-kit:xhigh and nothing else in the
    # suite moves; what disappears is every hand a PROJECT wrote for itself, and the
    # seventh hand somebody adds next month. That is the defect verbatim: a typed list of
    # role carriers let an incomplete fix through green on 2026-11-01 because the fourth
    # carrier was not in it.
    #
    # The replacement is the list as a reader would type it today, in the same order
    # GUIDE.md prints it, which is the point: it is correct on the day it is written.
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("the hand effort is derived, not typed", "hooks/_routing.sh",
     """  mk_route_table "${1-.}" "${2-effort}" | awk -F""",
     """  printf 'low-readonly\\tkit\\tlow\\nmedium\\tkit\\tmedium\\nhigh\\tkit\\thigh\\nxhigh-readonly\\tkit\\txhigh\\nxhigh\\tkit\\txhigh\\nmax\\tkit\\tmax\\n' | awk -F"""),

    # THE WIRING, LEFT AT THE NAME THE ORDER USED. Task alone still selects the tool today,
    # through a legacy alias table in the runtime, so this mutation is GREEN in every
    # behavioural sense: the hook is reached, the refusal fires, the log fills. What it
    # turns back is the kit's dependency on that shim, and the measured fact behind it,
    # that 4335 of 4335 real launches hand the hook tool_name "Agent" and none hands it
    # "Task". A hook that compared tool_name to "Task" would be selected by this matcher
    # and do nothing at all, silently, which is the shape of failure this kit is for.
    #
    # It is the only entry here that changes no shell code, and that is deliberate: the
    # assertion it kills is the one that asks whether the rule RUNS rather than whether it
    # works, and those are two different wirings.
    # Anchor counted as a Python substring against hooks/hooks.json: 1.
    ("the routing is wired to the tool that exists", "hooks/hooks.json",
     '"matcher": "Agent|Task",', '"matcher": "Task",'),

    # THE MODEL, DROPPED OUT OF THE LINE. The handout is still refused, the line is still
    # written, the event still names the verdict and the subject still names the order. One
    # field is gone, the one the whole record exists for: GOAL.md puts the trigger of the
    # switch on quality, and quality is read off WHICH MODEL drove which order. Without it
    # the log counts handouts and can say nothing about any of them.
    #
    # Every line stays valid JSON and every existing reader goes on working, which is
    # exactly why this is the shape worth probing.
    #
    # It also kills "a definition model is routed like a call model" and "a route line says
    # where its model came from", both of which read the model off this line [MK-VERSTEHEN,
    # run on its own: RED: 3 of 146]. Its anchor stops short of the from= word on purpose, so
    # the entry below does not delete it and the two stay apart in the register.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("every handout leaves a line naming the model", "hooks/route-guard.sh",
     '             "model=${MODEL:-(inherit)} effort=',
     '             "effort='),

    # THE ORIGIN, DROPPED FROM THE LINE. The model and the effort stay, so the older routing
    # assertions stay green and every number still counts; what goes is the one word that
    # can show whether managers choose, and model=sonnet reads the same typed or from the
    # file. It takes the word off the line and leaves the variable for the refusal text.
    # THE ANCHOR MOVED WITH MK-A8: it ended at the closing quote of the line, which stopped being
    # the end of the line when effort_from= was appended. It stops short of that word now and of the
    # quote, so it does not overlap the entry for effort_from= below, which is anchored on the
    # word behind it.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a route line says where its model came from", "hooks/route-guard.sh",
     ' from=$MODEL_FROM', ''),

    # THE EMPTY CASE, CALLED A CALL. Without this line a handout that named nothing reads
    # from=call, which is the variable's starting value, and every count of managers who
    # chose is inflated by the 99.0 percent of calls that named no model at all.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a route line says where its model came from", "hooks/route-guard.sh",
     '[ -n "$MODEL" ] || MODEL_FROM=none\n', ''),

    # THE DEFINITION'S MODEL, NEVER READ. A call with a model is judged as before and a
    # call without one goes back to (inherit), so every older routing assertion stays
    # green; what disappears is a haiku hand whose own definition says haiku, which is then
    # driven on the repair hand with no refusal and a line that says
    # inherit. That is exactly the gap the endpoint closed.
    #
    # It also kills "a route line says where its model came from", because a definition
    # that is never read has no origin to report, and "a definition model refusal names no
    # call parameter" [MK-VERSTEHEN, run on its own: RED: 3 of 146].
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a definition model is routed like a call model", "hooks/route-guard.sh",
     '  MODEL=$(mk_route_model "$ROOT" "$SUBAGENT" "$KIT_NAME")\n', ''),

    # THE ORIGIN OF THE MODEL, FORGOTTEN IN THE TEXT. The definition model is still read,
    # still logged and still refused, so the check above stays green; what goes is the one
    # sentence that knows where the model came from, and the refusal again tells the
    # coordinator to drop a model parameter its call never had.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a definition model refusal names no call parameter", "hooks/route-guard.sh",
     'from_definition = os.environ.get("MK_MODEL_FROM", "") == "definition"',
     'from_definition = False'),

    # THE SWITCH, TAKEN OUT OF THE VERDICT AND LEFT EVERYWHERE ELSE. mk_routing_is_off
    # still answers, so the role text goes on reporting the lage correctly and that
    # assertion does not move; the verdict simply stops asking. The result is the worst
    # version of a lever: a session is told the routing is stilled and the next handout
    # comes back refused.
    #
    # Aimed here rather than at mk_routing_is_off itself, which is the obvious mutation and
    # kills two names: the report reads the same function, so breaking it takes the subject
    # away from "the switch state is reported, never set" at the same time.
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("the routing switch falls back to inherit", "hooks/_routing.sh",
     """  if mk_routing_is_off; then printf 'off %s \\n' "$_rv_kind"; return 0; fi\n""", ''),

    # MK-D1: the refusal stands on the repair hand and nowhere else, only the kit's own prefix is the
    # kit's, nothing of the payload reaches the line raw, and the line counts the order. Every anchor
    # below is counted as a Python substring and stands once.
    #
    # THE NAME OF THE HAND, TAKEN OUT OF THE RULE. Haiku is refused on every hand of the kit again, which
    # is the old rule and more. "refused" still sees its own hand refused; only the rows that pass see it.
    ("the routing table holds, row by row", "hooks/_routing.sh",
     """  [ "${_rv_type#*:}" = "$MK_ROUTE_REPAIR_HAND" ] || { printf 'pass %s %s\\n' "$_rv_where" "$_rv_effort"; return 0; }\n""", ''),

    # THE WORD THAT SAYS WHOSE HAND IT WAS, gone from the line. A reader counting by the name would again
    # read anderes-plugin:xhigh as ours. Everything that asks the shape of the line dies with it.
    ("the routing table holds, row by row", "hooks/route-guard.sh",
     " hand=$HAND_WORD", ""),

    # A BARE NAME IS NOBODY'S. The repair hand with no prefix slips past on the shape of the string.
    ("the routing table holds, row by row", "hooks/_routing.sh",
     "    *) MK_RK=bare ;;\n", "    *) MK_RK=other ;;\n"),

    # ANY PREFIX IS OURS AGAIN, the behaviour before this order. Another plugin's xhigh inherits the refusal.
    ("only the kit own prefix is ours", "hooks/_routing.sh",
     """            "$2":*) MK_RK=own ;;\n""", """            *:*) MK_RK=own ;;\n"""),

    # THE NAME TYPED AS THE FALLBACK, which is the obvious way to read a manifest and it is the failure the
    # order names: the manifest cannot be read, a renamed kit prefixes as it likes, and the refusal is gone.
    ("only the kit own prefix is ours", "hooks/_routing.sh",
     """    except Exception:\n        return ""\ndef mk_order_marks""",
     """    except Exception:\n        return "manager-kit"\ndef mk_order_marks"""),

    # A NAME OF ANY SHAPE IS BELIEVED, so the manifest writes a word of the line and of the prefix.
    ("only the kit own prefix is ours", "hooks/_routing.sh",
     """return name if isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,64}", name) else \"\"""",
     """return name if isinstance(name, str) else \"\""""),

    # THE PIPE IS WAITED ON. The hook hangs on a manifest that never answers, past its budget.
    ("only the kit own prefix is ours", "hooks/_routing.sh",
     """        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)\n        try:\n""",
     """        fd = os.open(path, os.O_RDONLY)\n        try:\n"""),

    # THE ORIGIN OF THE FILE, IGNORED. A prefixed hand reads the first file of its name, which is the
    # project's: the merge this order took out, and a project file refuses or frees the plugin's hand.
    ("a project hand of the name is the project hand", "hooks/_routing.sh",
     """$1 == want && (kind == "bare" || $2 == "kit") {""", """$1 == want {"""),

    # A PROJECT'S xhigh COUNTS AS THE REPAIR HAND. A stop that a rename would lift.
    ("a project hand of the name is the project hand", "hooks/_routing.sh",
     """  [ "$_rv_where" != project ] || { printf 'pass %s %s\\n' "$_rv_where" "$_rv_effort"; return 0; }\n""", ''),

    # THE TEXT NAMES THE DEFINITION'S EFFORT, whatever the call said, which is what it did until now.
    ("the refusal says what applies and what goes instead", "hooks/route-guard.sh",
     "MK_EFFORT=$EFFORT_SHOWN MK_EFFORT_FROM=$EFFORT_FROM", "MK_EFFORT=$effort MK_EFFORT_FROM=definition"),

    # THE MEASUREMENT, CUT FROM THE TEXT. The refusal stands and no longer says what it rests on.
    ("the refusal says what applies and what goes instead", "hooks/route-guard.sh",
     '"repair of kit code twice and left one false report, n = 2 on one task, and haiku medium "',
     '"repair of kit code, and haiku medium "'),

    # THE WAY ON, CUT FROM THE TEXT, so a refused manager is told why and not what to do.
    ("the refusal says what applies and what goes instead", "hooks/route-guard.sh",
     '"this is no repair, send it to another hand: haiku is open on all of them, at your judgement. A "',
     '"this is no repair, say so. A "'),

    # THE MODEL, RAW ON THE LINE: the first finding of MK-A8, put back.
    ("no value of the payload forges a route line", "hooks/route-guard.sh",
     """say("MODEL", mk_word(ti.get("model")))""", """say("MODEL", ti.get("model"))"""),

    # WHAT THE FIRST GATE MARKED STAYS A QUESTION MARK, and a reader cannot tell it from a model called that.
    ("no value of the payload forges a route line", "hooks/route-guard.sh",
     """[ "$MODEL" != '?' ] || MODEL='(other)'\n""", ""),

    # A MODEL THAT CANNOT BE READ PASSES ON THE REPAIR HAND. The refusal falls out because something
    # could not be read, the first thing the order forbids.
    ("no value of the payload forges a route line", "hooks/_routing.sh",
     """  case " $MK_ROUTE_CHEAP (other) " in\n""", """  case " $MK_ROUTE_CHEAP " in\n"""),

    # THE PARSE FALLS ON A LIST AGAIN: the second finding of MK-A8, put back.
    ("a handout that cannot be read is refused aloud", "hooks/route-guard.sh",
     """ti = ti if isinstance(ti, dict) else {}\n""", ""),

    # WHAT IS UNREAD IS NOTED AND THEN PASSED. Parsed, on the record, and silent.
    ("a handout that cannot be read is refused aloud", "hooks/route-guard.sh",
     """case "$UNREAD:$verdict" in 1:pass) verdict=stop ;; esac\n""", ""),

    # A NAME OF ANY SHAPE GOES THROUGH TO THE WRITER, the separator in it splitting the record.
    ("a handout that cannot be read is refused aloud", "hooks/route-guard.sh",
     """if sub is not None and not (isinstance(sub, str) and len(sub) <= 256 and not re.search("[\\\\x00-\\\\x1f\\\\x7f]", sub)):""",
     """if False:"""),

    # A NAME OF ANY LENGTH GOES THROUGH TO THE PATTERNS OF THE SHELL. 200 KB holds the hook past its budget
    # and a hook that is held refuses nothing.
    ("a handout that cannot be read is refused aloud", "hooks/route-guard.sh",
     "isinstance(sub, str) and len(sub) <= 256 and not re.search", "isinstance(sub, str) and not re.search"),

    # THE VALUE OF A DEFINITION, RAW IN THE TABLE, so an effort of * is on the line as that and one of 600
    # characters cuts it.
    ("a glob in a definition stays a word", "hooks/_routing.sh",
     """effort = value if re.fullmatch(r"[A-Za-z0-9._\\[\\]-]{1,64}", value) else "(other)\"""",
     """effort = value"""),

    # THE THIRD FINDING OF MK-A8, PUT BACK: the verdict through an unquoted expansion. The gate above lets
    # a bracket through, as model names carry one, so this is what still widens against the directory.
    ("a glob in a definition stays a word", "hooks/route-guard.sh",
     """_verdict=$(mk_route_verdict "$ROOT" "$MODEL" "$SUBAGENT" "$KIT_NAME")\nverdict=${_verdict%% *}\n_verdict=${_verdict#* }\nHAND_WORD=${_verdict%% *}\neffort=${_verdict#* }\n""",
     """set -- $(mk_route_verdict "$ROOT" "$MODEL" "$SUBAGENT" "$KIT_NAME")\nverdict=$1\nHAND_WORD=${2-}\neffort=${3-}\n"""),

    # ANY FIRST WORD IS A COMMAND, so `ALL GREEN` counts as one and the mark says nothing.
    ("a route line counts the order and carries none of it", "hooks/_routing.sh",
     """(?:(?:bash|sh|zsh|git|""", """(?:(?:\\w+|bash|sh|zsh|git|"""),

    # A WIDER LIST, the words that looked right and were measured as noise, and one that is only near.
    ("a route line counts the order and carries none of it", "hooks/_routing.sh",
     """r"|all green)\\b", text, re.I)""", """r"|all green|green|gruen|annahme)\\b", text, re.I)"""),

    # ONE WORD OF THE ORDER ON THE LINE, the only thing this feature must never do.
    ("a route line counts the order and carries none of it", "hooks/_routing.sh",
     """return "len:%s,cmd:%d,accept:%d" % (size, 1 if cmd else 0, 1 if accept else 0)""",
     """return "len:%s,cmd:%d,accept:%d,%s" % (size, 1 if cmd else 0, 1 if accept else 0, text[:13])"""),

    # AN EDGE OF THE TIERS, one character off.
    ("a route line counts the order and carries none of it", "hooks/_routing.sh",
     '"500" if n < 500 else', '"500" if n <= 500 else'),

    # AN ORDER THAT IS NO TEXT FELLS THE PARSE, and with it every refusal of that call.
    ("a route line counts the order and carries none of it", "hooks/_routing.sh",
     """    if not isinstance(text, str):\n        return "(other)"\n""", ""),

    # MK-ZEIT: an order past 100000 characters costs the hook 8 s, against the 5 the check allows, in every try. The stall
    # that the check now survives (one try slow, the next not) is a different thing and is shown in the report.
    ("a route line counts the order and carries none of it", "hooks/_routing.sh",
     '    n = len(text)\n    size = "0" if n == 0',
     '    n = len(text)\n    if n > 100000:\n        import time; time.sleep(8)\n    size = "0" if n == 0'),

    # THE SENTENCES, each put back or cut in the file it stands in. The search is over the package.
    ("the documents say what the refusal is", "GUIDE.md",
     "Haiku on the repair hand `xhigh` is refused\nby", "A cheap model driving a hand whose definition carries high effort is refused\nby"),
    ("the documents say what the refusal is", "README.md",
     "The limit: a hook knows the name of a hand and not the work, so a repair sent to `medium` falls\nthrough, and the measurement says the same of it. ", ""),
    ("the documents say what the refusal is", "GOAL.md",
     " It sees\nthe name of a hand and not the work: a repair sent to another hand falls through.", ""),
    ("the documents say what the refusal is", "hooks/_identity.sh",
     "One refusal stays: haiku on the repair hand xhigh.", "One refusal stays: a cheap model on a hand of high effort."),
    ("the documents say what the refusal is", "hooks/route-guard.sh",
     "this handout puts haiku on the repair hand, or cannot be read.", "this handout puts a cheap model on a hand whose definition carries high thinking effort."),
    ("the documents say what the refusal is", "agents/xhigh-readonly.md",
     " Haiku: no false report here, but no effort was complete twice.", ""),

    # MK-A8: the route line names the effort that applies, says where it came from, and takes
    # nothing raw from the payload. Every anchor below is counted as a Python substring.
    #
    # THE CALL'S EFFORT, WRITTEN AS THE DEFINITION'S. The call arm prints the second argument, the
    # effort of the definition, under the word call: the origin word and the rungs are all as they
    # should be, and the one thing the whole order is about, which effort the line names, is the old
    # defect again. Aimed at the value and not at the call, which is the obvious edit
    # (mk_route_effort_applied "" ...) and kills the origin words along with it.
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("a route line names the effort that applies", "hooks/_routing.sh",
     "        printf '%s call\\n' \"$1\"\n", "        printf '%s call\\n' \"$2\"\n"),

    # THE ORIGIN OF THE EFFORT, DROPPED FROM THE LINE. The effort that applies is still right, the
    # three older words are untouched and every count still counts; what goes is the word that tells
    # a manager's effort from the file's. It stops short of the quote so it does not overlap the entry
    # for from= above, which is anchored on the word before it.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a route line says where its effort came from", "hooks/route-guard.sh",
     ' effort_from=$EFFORT_FROM', ''),

    # THE GATE ON THE PAYLOAD, WIDENED FROM LETTERS TO ANY CHARACTER. A NUL inside a rung passes
    # again, the command substitution that carries the value to the shell drops it, and "ma<NUL>x" is
    # written as the rung it was not sent as. Everything else is still caught by the scale behind it,
    # which is why this is the one edit that leaves the other hostile values red-free and the line
    # exactly forged in one case.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a route line takes no value it was not handed", "hooks/route-guard.sh",
     '[A-Za-z]{1,15}', '.{1,15}'),

    # THE SCALE BEHIND THE GATE, LEFT OPEN. Any word of letters is written as it was sent, which is
    # the raw value on the record for "ludicrous" and for every other word the scale does not know.
    # The gate on the payload is untouched, so a NUL, a line break and 10000 characters stay out.
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("a route line takes no value it was not handed", "hooks/_routing.sh",
     '      if [ "$(mk_route_rank "$1")" -gt 0 ]; then\n', '      if true; then\n'),

    # THE VERDICT, GIVEN THE EFFORT OF THE CALL. The function judging a handout reads the call's
    # effort when there is one and the definition's when there is not. A low hand driven at the top
    # rung is refused and a top hand driven at the bottom one is not, which is the next order done
    # inside this one and with nobody having decided it. The shell variable is the one route-guard.sh
    # sets from the payload; the function sees it because both run in one shell.
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("the verdict does not move with the effort of the call", "hooks/_routing.sh",
     """  [ "${_rv_type#*:}" = "$MK_ROUTE_REPAIR_HAND" ] || { printf 'pass %s %s\\n' "$_rv_where" "$_rv_effort"; return 0; }\n""",
     """  [ "${_rv_type#*:}" = "$MK_ROUTE_REPAIR_HAND" ] || { printf 'pass %s %s\\n' "$_rv_where" "$_rv_effort"; return 0; }\n  case "${EFFORT_CALL:-}" in low) printf 'pass %s %s\\n' "$_rv_where" "$_rv_effort"; return 0 ;; esac\n"""),

    # THE READER OF THE PAYLOAD, LET RAISE. The test that the value is a string is gone, so an object
    # or a number reaches re.fullmatch and raises, the parse comes back with an error, and the hook
    # answers that it is inert: the refusal that should have gone out does not. That is the shape
    # the order names, a refusal that falls out when the parameter cannot be read.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("the verdict does not move with the effort of the call", "hooks/route-guard.sh",
     'isinstance(ef, str) and ', ''),

    # A SECOND READER OF THE PAYLOAD. The effort rides the parse that runs anyway; here a further
    # python3 is started on every handout, the cost the order forbids, and nothing else changes: the
    # line and the verdict are the ones they were, so only the count of starts can see it.
    # Anchor counted as a Python substring against hooks/route-guard.sh: 1.
    ("a handout pays no process for the effort of the call", "hooks/route-guard.sh",
     'eval "$parsed"\n',
     'eval "$parsed"\n_=$(printf \'%s\' "$input" | python3 -I -c \'import sys; sys.stdin.read()\')\n'),

    # THE SENTENCE, PUT BACK IN THE THREE PLACES THAT CARRY A DOCUMENT, and the one place that
    # carries the reason in code. Each edit puts back the first half of the sentence and nothing
    # else; the search is over every file of the package and finds it wherever it stands.
    # Anchor counted as a Python substring against README.md: 1.
    ("the documents say what is measured about effort per call", "README.md",
     'It is paid because a hand is how a manager picks',
     'It is paid because `effort` cannot be set per call, so a manager picks'),
    # Anchor counted as a Python substring against GUIDE.md: 1.
    ("the documents say what is measured about effort per call", "GUIDE.md",
     'It is paid because a hand is how a manager picks',
     'It is paid because `effort` cannot be set per call, so a manager picks'),
    # Anchor counted as a Python substring against hooks/_routing.sh: 1.
    ("the documents say what is measured about effort per call", "hooks/_routing.sh",
     'effort was not in that schema, in 2.1.278, and',
     'effort is NOT in that schema at all, and'),
    # THE LIMIT, TAKEN OUT OF THE SENTENCE THAT CARRIES IT. The claim stays and the size it rests on
    # goes: a reader would take 14 runs of one question for a general finding.
    # Anchor counted as a Python substring against GUIDE.md: 1.
    ("the documents say what is measured about effort per call", "GUIDE.md",
     'one question, 14 runs', 'a few runs'),

    # THE REPORT, WITH ITS BRANCH NAILED SHUT. Both lages now get the ACTIVE paragraph, so
    # the variable is still named, the budget is unchanged, and a session with the routing
    # stilled is told that haiku on the repair hand will be refused. A report that
    # reads the same either way is not a report, and it is worse than no report: it is a
    # sentence a session will act on.
    #
    # The refusal itself is untouched, so the switch assertion stays green. It also kills
    # "the role text leaves the model to the manager" since 2026-11-06, and rightly: that one
    # asks that a stilled session is not promised a refusal, which is this same branch.
    # Anchor counted as a Python substring against hooks/_identity.sh: 1.
    ("the switch state is reported, never set", "hooks/_identity.sh",
     '    if mk_routing_is_off; then\n', '    if false; then\n'),

    # THE SENTENCE THE MANAGER NEEDS, GONE FROM THE ACTIVE LAGE. The switch, the lage and the
    # refusal stay, and so does the budget, so nothing else in the suite moves; what goes is
    # that the model is the manager's judgement, and a `model:` then reads as the rule.
    # Anchor counted as a Python substring against hooks/_identity.sh: 1.
    ("the role text leaves the model to the manager", "hooks/_identity.sh",
     "printf 'is your judgement per order: a hand", "printf 'is the rule of the hand: a hand"),

    # THE ADMISSION, CUT OUT OF THE FILE A STRANGER READS FIRST. What is left still says
    # the policy is on by default and still says the official help promises only a
    # direction; what goes is the sentence that the gain is not measured and that the one
    # instrument which could have shown it cannot resolve it. The result is a README that
    # sells a policy on a measurement nobody took, which is the exact failure the owner's
    # decision of 2026-11-01 created the duty against: ship it on, and name the limits.
    #
    # MK-G moved the anchor: the sentence now says what is estimated and measured, and the admission
    # that is cut is its last part, that the same quality in real work is unmeasured. It kills a second
    # name, "the routing gain says what is estimated, measured and unmeasured", because that check asks
    # the same paragraph for the open part; the two hold one sentence from two sides, and a cut of the
    # admission that left either green would be a cut neither reads.
    # Anchor counted as a Python substring against README.md: 1.
    ("the limits of the routing policy are on record", "README.md",
     "What is unmeasured is whether real work\n"
     "keeps the same quality at that lower price: no number in this repository says so, and the\n"
     "one instrument that shows spend cannot resolve it, since 269128 Opus tokens moved the weekly\n"
     "window by zero of a hundred points. ",
     ""),

    # MK-G. THE BARE SENTENCE BACK, in GOAL.md, with every part of the paragraph left standing: what is
    # estimated and measured is still said, and one sentence before it again calls the gain unmeasured.
    # Anchor counted as a Python substring against GOAL.md: 1.
    ("no text calls the routing gain unmeasured without saying what is", "GOAL.md",
     "Its gain is measured in two\nparts and open in the third.",
     "Its gain is NOT measured.\nIt is known in two parts and open in the third."),

    # THE PAIR COMPARISONS, CUT FROM THE README. The estimate and the open part stay, so the paragraph
    # reads as if a price were the only thing measured.
    # Anchor counted as a Python substring against README.md: 1.
    ("the routing gain says what is estimated, measured and unmeasured", "README.md",
     "Measured are pair comparisons per\n"
     "kind of work, each on one task of kit code, the three decided ones with n = 3 or fewer a side\n"
     "[2026-11-05 and 2026-11-08, the table in `GUIDE.md`]. ",
     ""),

    # MK-G, THE THREE LIMITS MK-R8 LEFT, one mutant each: the word that names the limit goes from its
    # point, or the way round does, and the rest of the point stays.
    # Anchor counted as a Python substring against README.md: 1.
    ("the limits MK-R8 left stand in the README list", "README.md",
     "- **A copy of another plugin that carries", "- **A copy of a plugin that carries"),
    # Anchor counted as a Python substring against README.md: 1.
    ("the limits MK-R8 left stand in the README list", "README.md",
     "in the register the one first in the file.**", "in the register the one found first.**"),
    # Anchor counted as a Python substring against README.md: 1.
    ("the limits MK-R8 left stand in the README list", "README.md",
     "The way round: `cd` into the directory the\n  session stood in", "`cd` into the directory the\n  session stood in"),

    # THE TOOL, TAKEN OUT OF THE REFUSAL AND LEFT IN THE PACKAGE. The guard still refuses,
    # both channels still answer, the boundary and the way out are still named, and
    # tools/mk-explain.sh is still delivered and still works. What goes is the one sentence
    # that tells a stranger where to ask the measure why, in the single text that arrives at
    # the moment the verdict is doubted. hooks/role-text.md goes on promising that tool at
    # every session start, so the mutated kit promises in one text what it withholds in the
    # other, which is the exact shape of a sentence nothing reads back.
    #
    # The name is dropped rather than misspelled on purpose: a wrong path would be caught by
    # the delivery test in the guard itself and never reach a refusal, so it would probe the
    # wrong thing.
    # Anchor counted as a Python substring against hooks/role-guard.sh: 1.
    ("the refusal carries the line, the way out and the tool", "hooks/role-guard.sh",
     "EXPLAIN=tools/mk-explain.sh", "EXPLAIN="),

    # THE DEADLOCK, PUT BACK IN ONE CLAUSE. This is what agents/medium.md said until
    # 09e24b3, and it ran the first handover of a stranger into a wait with no end: the hand
    # was told to ask for a role file, and of the five projects that switch this kit on, not
    # one has a .claude/roles/ directory [measured 2026-11-02]. The package delivers role
    # files only under roles/, as examples.
    #
    # Everything else in the file stays, the four arms of the stop included, so the hand
    # assertion that reads those arms does not move and this entry takes the one name aimed
    # at. The mutated hand is still a valid, shippable, perfectly reasonable looking hand,
    # which is why prose like it survived here for as long as it did.
    # Anchor counted as a Python substring against agents/medium.md: 1.
    ("no hand waits for a file the package has not got", "agents/medium.md",
     "you work from the order itself", "you ask for one before you start"),

    # THE SAME DEADLOCK, PUT BACK INTO THE EXAMPLE ROLE in the same clause. This is what
    # roles/example-implementer.md said until d6f85b0 in substance: with no version named,
    # ask for one before you start. The entry above reads roles/ only as the list of what
    # ships, so its name stays alive here, and this one takes the one name aimed at
    # [measured 2026-11-03, the full suite on this edit: RED: 1 of 129].
    # Anchor counted as a Python substring against roles/example-implementer.md: 1.
    ("no role file the package ships sends its hand back to ask",
     "roles/example-implementer.md",
     "you work from the order itself", "you ask for one before you start"),

    # THE ACCEPTANCE KEPT QUIET. The hand still writes its own acceptance and still works
    # against it, but no longer names it in the report, so the coordinator reads a result
    # held against a bar it never saw and cannot tell from one held against its own. The
    # sentence still reads as a reasonable instruction, which is the shape that survives a
    # trim. One hand only, a writing one, so what dies is the claim that EVERY hand carries
    # the arm. The other arm and the stop are untouched in that file.
    # Anchor counted as a Python substring against agents/high.md: 1.
    ("every hand writes its own acceptance when the order has none", "agents/high.md",
     "and name it in your report as self-set.", "and keep it to yourself."),

    # THE DEVIATION ABSORBED. One word: the hand that only reads takes the code's side and
    # folds the disagreement into its answer instead of reporting it, which is the silent
    # adjustment the arm exists to forbid. One reading hand, so that the two mutations
    # between them reach both forms of the section.
    # Anchor counted as a Python substring against agents/xhigh-readonly.md: 1.
    ("every hand reports an order claim that has no command", "agents/xhigh-readonly.md",
     "report the deviation", "absorb the deviation"),

    # A ROW THAT STILL READS WELL. README.md gives `max` the effort one rung below it, which
    # is a table nobody would stop at, and until this assertion nothing in the suite read the
    # table at all. The same text stands in GUIDE.md; the entry names README.md, so it
    # applies there and only there [measured 2026-11-03, the full suite on this edit: RED: 1
    # of 129]. Anchor counted as a Python substring against README.md: 1.
    ("the hand tables name every hand at its effort, and no other", "README.md",
     "| `max` | max |", "| `max` | xhigh |"),

    # THE DEFINITION MOVES AND THE TABLE STAYS. The repair hand goes back to opus in its own
    # frontmatter while GUIDE.md still routes a reader to sonnet for it, which is the drift
    # a reader cannot see: both files read well on their own. Aimed at the definition and
    # not at the table, because the definition is what the runtime runs.
    #
    # It also kills "every hand description names its model and when to leave it", which
    # is the same drift seen from the other text the manager reads [MK-VERSTEHEN, run on its
    # own: RED: 2 of 146].
    # Anchor counted as a Python substring against agents/xhigh.md: 1.
    ("the model table names every hand at its model, and no other", "agents/xhigh.md",
     "\nmodel: sonnet\n", "\nmodel: opus\n"),

    # THE DESCRIPTION DRIFTS FROM ITS DEFINITION. The manager is told one model and the
    # hand runs another, and both files read well on their own. Aimed at the sentence, so
    # the model tables stay green; moving the `model:` line instead is the entry above.
    # Anchor counted as a Python substring against agents/max.md: 1.
    ("every hand description names its model and when to leave it", "agents/max.md",
     "Suggested model opus:", "Suggested model sonnet:"),

    # A REFUSAL THE DESCRIPTION NO LONGER ANNOUNCES. The repair hand keeps its effort and the
    # guard keeps refusing; the manager finds out only by being refused.
    # Anchor counted as a Python substring against agents/xhigh.md: 1.
    ("every hand description names its model and when to leave it", "agents/xhigh.md",
     " Haiku is refused here.", ""),

    # THE QUESTION THE MEASUREMENT PAID FOR, CUT FROM THE GUIDE. The other four stand and
    # the table stands, so only the count and the sequence can see it.
    # Anchor counted as a Python substring against GUIDE.md: 1.
    ("the guide says how to choose the model", "GUIDE.md",
     "3. **Will you rely on the report?**", "**Will you rely on the report?**"),

    # THE OPEN ADMISSION, GONE. The questions and the table stand; what goes is the sentence
    # that the choice is not deterministic, and the table then reads as the answer.
    # Anchor counted as a Python substring against GUIDE.md: 1.
    ("the guide says how to choose the model", "GUIDE.md",
     "The choice is\nnot deterministic,", "The choice is\nfixed,"),

    # THE README ROW MOVES AND NOTHING ELSE DOES. README.md routes a reader picking `max`
    # to sonnet while the definition and GUIDE.md both still say opus, which is the table a
    # stranger reads first. Aimed at README.md alone, so it shows that the README side of
    # the assertion is held and not only GUIDE.md; the effort cell stays, so the effort
    # assertion that reads the same row does not move [MK-TEXTREST, run on its own]. The
    # anchor starts at the model cell on purpose: anchored on "| `max` | max | opus |" it
    # contained the effort entry's anchor above, so that entry's mutant deleted this anchor
    # and killed "every mutation in the register still applies" beside its own name.
    # Anchor counted as a Python substring against README.md: 1.
    ("the model table names every hand at its model, and no other", "README.md",
     "| opus | choosing the shape IS the work", "| sonnet | choosing the shape IS the work"),

    # MK-D3. THE JUDGING HAND BACK ON OPUS, the shape it had until 2026-11-08. Aimed at the
    # definition, because that is what the runtime runs and what the route line reads. It cannot
    # kill its assertion alone: every text held against the definition falls with it, which is the
    # design of the agreement checks, and so do "the model table names every hand at its model, and
    # no other", "every hand description names its model and when to leave it" and "the guide names
    # each kind of work at the model of its hand". What only this assertion holds, every text moved
    # back together, takes a mutation over four files, and the register applies one anchor per entry.
    # Anchor counted as a Python substring against agents/xhigh-readonly.md: 1.
    ("the judging hand runs on sonnet when the call names none", "agents/xhigh-readonly.md",
     "\nmodel: sonnet\n", "\nmodel: opus\n"),

    # THE LIMIT, CUT FROM THE SUGGESTION. The numbers and the model stay, and the description then
    # reads as a verdict without the one run that went the other way.
    # Anchor counted as a Python substring against agents/xhigh-readonly.md: 1.
    ("the judging hand says with numbers why it runs on sonnet", "agents/xhigh-readonly.md",
     ", n = 1. Name opus", ". Name opus"),

    # THE KIND PARAGRAPH DRIFTS FROM THE DEFINITION. The table, the definition and the description
    # all say sonnet, and only the prose under the table, the one place no check read before, says
    # opus for verify.
    # Anchor counted as a Python substring against GUIDE.md: 1.
    ("the guide names each kind of work at the model of its hand", "GUIDE.md",
     "**verify, on `xhigh-readonly`: sonnet `xhigh`", "**verify, on `xhigh-readonly`: opus `xhigh`"),

    # THE DATE, TAKEN OFF THE RESULT, and the result carries it twice: in the STAND line, and
    # in the sentence that says the number "moved from 72 to 73 on 2026-11-02, when one stop
    # was re-measured". Both days go. The whole measurement stays: the window, the 122 stops,
    # the 73 false alarms, the verdict that the week failed and that N stays 5. The two
    # timestamps left in the paragraph are the EDGES OF THE WINDOW and not a reading date,
    # which is why the assertion asks for a day rather than for any date at all.
    #
    # RE-AIMED 2026-11-03. This entry took the STAND day alone, which was the only day the
    # result carried when both were written [MK-TEXT.md: RED, 1 killed]. b8f67a1 added the
    # second, and from then on the paragraph stayed dated without its STAND day: run on its
    # own on 959b3a5 the old entry came back ALIVE with nothing dead. The assertion was right
    # to stay green, because that second day is a date OF the result, the day one stop was
    # re-measured and the 72 became 73; the entry was aimed short. The anchor spans both
    # days, six lines of GOAL.md, so an edit of any of them leaves it dangling, and "every
    # mutation in the register still applies" says so.
    #
    # Aimed at the dates rather than at the whole paragraph because the paragraph is also the
    # honesty half: a kit that failed its own measure has to be able to say so and still
    # ship green, and an entry that deleted the admission would have probed the wrong half.
    # It kills this name and no other, measured 2026-11-03 run on its own.
    # Anchor counted as a Python substring against GOAL.md: 1.
    ("a criterion in the goal carries its dated result", "GOAL.md",
     "**STAND, 2026-11-02: the first run of this measure failed it.** Window\n"
     "`2026-09-10T16:16:37Z` to `2026-10-08T22:09:15Z`, 28 days in one project, 277 log lines:\n"
     "122 stops, and **73 of them false alarms** against the five above, the fifth of them on day\n"
     "four. 38 stops were correct, and 11 are permanently undecidable because the transcripts\n"
     "behind them were deleted, so the 73 is a lower bound. The number moved from 72 to 73 on\n"
     "2026-11-02, when",
     "**STAND: the first run of this measure failed it.** Window\n"
     "`2026-09-10T16:16:37Z` to `2026-10-08T22:09:15Z`, 28 days in one project, 277 log lines:\n"
     "122 stops, and **73 of them false alarms** against the five above, the fifth of them on day\n"
     "four. 38 stops were correct, and 11 are permanently undecidable because the transcripts\n"
     "behind them were deleted, so the 73 is a lower bound. The number moved from 72 to 73\n"
     "when"),
    # A RULE THE GATE NEVER HAD, ADDED: a STAND line that reports a failure turns check.sh
    # red. That is the only way to turn this assertion back, because what it holds is an
    # ABSENCE, and it is the shape it was seen red against, by hand, when it was written:
    # MK-TEXT quotes that red with this RED line, and until now it lived in a report and
    # not here. The rule sits in the arm that has just read GOAL.md, so the gate stays
    # whole otherwise and the half of the assertion that wants the known red still gets it.
    # It kills this name and no other, measured by applying it and running tests/run.sh in
    # a copy. Anchor counted as a Python substring against check.sh: 1.
    ("a reported failure does not cost the green run", "check.sh",
     '*) OK "the goal names a stopping condition" ;;',
     '*) OK "the goal names a stopping condition"\n'
     "              if grep -qiE '^[*][*]STAND.*fail' GOAL.md; then\n"
     '                RED "the goal reports a failed measure" "GOAL.md"; fi ;;'),

    # A ROLE NOBODY CAN READ, TURNED INTO THE FREE PASS. Field 1 of the record is not a pid,
    # so no carrier can be established, and the arm that answers that case says manager
    # because every hole in the register has to cost a false stop and never a silent pass.
    # Turned to carrier the guard stands down AHEAD of its own log, so the write goes through
    # and leaves no trace at all.
    #
    # IT KILLS TWO NAMES, AND THE SECOND ONE IS THE POINT OF THE REPAIR THAT MADE THIS ENTRY
    # possible. "an undecidable role counts as the manager" wrote its fixture with an empty
    # field 2 until today and answered at the line BEFORE this case, so this mutation left it
    # green: the arm the check is named for was watched by nothing but "one record gives one
    # role in every carrier", which reads the same arm across all four carriers and therefore
    # dies here too. Measured both ways, same mutation, same tree: with the old fixture 1
    # name dies, with the repaired fixture 2. Narrowing it to kill only one is not available,
    # and buying that number would mean taking the grid off the arm.
    #
    # RE-ANCHORED 2026-11-02 ON THE ARM AS IT STANDS, ''|*[!0-9]*|0*) since da1c515; until
    # then this entry could not be applied. Same edit, the whole arm answers carrier. It
    # kills FOUR names now, measured by applying it and running tests/run.sh in a copy:
    # the two above, and two new ones, neither of them a mutation gone wide. "an unusable
    # record stops in every carrier" reads this arm in all four carriers, garbage, -1, 00
    # and 0 each split, and came in with da1c515 itself. "the guard line and the claim
    # line are one shape" claims through manager-prime.sh with no pid to measure, so its
    # record is "0 S1" [measured in a fresh project], the guard turned carrier stands down
    # for the very session the record names, and no stop line is written to compare.
    # RE-ANCHORED 2026-11-03 ON THE CALL THAT REPLACED THE ARM. The guard asks
    # mk_field1_is_pid now; old anchor the one-line case over "$_ownerpid", new anchor the
    # call. Same edit, a field 1 that is no pid answers carrier.
    # Anchor counted as a Python substring against hooks/role-guard.sh: 1.
    ("an undecidable role counts as the manager", "hooks/role-guard.sh",
     "  mk_field1_is_pid \"$_ownerpid\" || { printf \'manager\\n\'; return 0; }\n",
     "  mk_field1_is_pid \"$_ownerpid\" || { printf \'carrier\\n\'; return 0; }\n"),

    # ------------------------------------------------- the register and the two routings
    # THE REGISTER BACK TO A CONSTANT, which is 0.17.0 verbatim: one typed path, correct on
    # exactly one shape of machine. All three lages of the assertion die at once, which is
    # what makes this the defect turned back rather than a dent in one branch of it.
    # The explicit override is the other arm of that if, so the 32 probes in tests/run.sh
    # that hand a register in by hand are untouched and no other name goes with it.
    # Anchor counted as a Python substring against hooks/_sessions.sh: 1.
    ("the register is read where the platform keeps it", "hooks/_sessions.sh",
     '  MK_SOCKET_DIRS="$MK_SD_BASE/cc-socks${MK_NL}$MK_SD_PX/cc-socks-$MK_UID"',
     '  MK_SOCKET_DIRS=/tmp/cc-socks'),
    # THE PROJECT FILTER OFF, AND NOTHING ELSE. Every entry ranks the same, the sort is
    # stable, so the first entry in the file wins for every project: the state measured on
    # 2026-11-02, where a project recorded at 0.13.0 ran 0.9.0. It is aimed at the rank and
    # not at the hits list, because dropping the list would also stop the register being
    # read at all and take handover_command_resolves_the_script_it_calls with it. That one
    # runs against an EMPTY register [CLAUDE_CONFIG_DIR pointed at a fresh directory], so
    # it cannot see this edit at all. Anchor counted against commands/take-over.md: 1.
    ("the installation of this project is the one that runs", "commands/take-over.md",
     '        rank = covers(e["projectPath"]) if e.get("projectPath") else 0',
     '        rank = 0'),
    # ONE OF THE THREE CARRIERS THAT USED TO SAY carrier, PUT BACK. The prompt hook stops
    # asking mk_decide_role for the lage where there is no record, and answers carrier on
    # its own, which is 3 of the 4 readings measured on 2026-11-02 reduced to 1. The split
    # is then stamp against the other three.
    #
    # IT IS AIMED HERE RATHER THAN AT _identity.sh ON PURPOSE. The branch repaired in
    # mk_decide_role is read by a_failed_measurement_is_not_solitude as well, so any edit
    # to it kills two names and proves nothing about what the four carrier grid can see
    # that a single reader cannot. This edit is invisible to that assertion, which calls
    # mk_decide_role directly, and invisible to prime_and_stamp_never_split_a_session,
    # whose quiet case has prime saying carrier too [measured: it survives this edit]. So
    # the one name that dies is the one that reads all four carriers against each other.
    # Anchor counted against hooks/manager-stamp.sh: 1. It is a superstring of the anchor
    # of "the two hooks never split one session", which is the same line without its
    # closing fi; one mutation is applied per run, so the two cannot reach each other.
    # SINCE 2026-11-02 A SECOND NAME DIES, and it is not a carrier: "every mutation in the
    # register still applies", because this edit takes the anchor of "the two hooks never
    # split one session" with it. Measured run on its own: 2 names.
    ("an uncountable register gives one role everywhere", "hooks/manager-stamp.sh",
     '  role=$(mk_decide_role "$ROOT" "$SESSION_ID")\nfi',
     '  role=carrier\nfi'),
    # HALF OF THE RECORD REPAIR OF 2026-11-02 PUT BACK, in one carrier, by making one line
    # inert. The prompt hook stops asking whether field 2 names anybody, so a record
    # reading "<living pid>" with nothing behind it is a living foreign holder to it again
    # and it answers carrier, while the guard and both session start hooks answer manager
    # and the guard refuses. One session, two roles, one prompt.
    #
    # IT IS AIMED HERE RATHER THAN AT THE 0* ARM, which is the headline of the same repair,
    # and the reason is the one the entry above gives for its own aim. The arms are what
    # every_wired_carrier_gives_one_role_for_one_record classifies its shapes BY: with 0*
    # gone from any one of the three readers, that grid reads 0 as a usable pid in the
    # carriers that still carry the arm, and the edit kills two names instead of one and
    # proves nothing about what this assertion can see that the older grid cannot. This
    # edit is invisible to that grid, whose every lage but one carries a foreign session id
    # in field 2 and whose one exception has an empty field 1 that the arms catch first.
    #
    # BOTH HALVES OF THAT ARE MEASURED, 2026-11-02, by copying the repository, making the
    # one edit and running tests/run.sh in the copy: with 0* taken out of role-guard.sh
    # alone, "RED: 2 of 112 checks failed", the two being this assertion and the older
    # grid. With the line below made inert, "RED: 1 of 112", and this file's own run of
    # that entry reports "Distinct assertions killed across all of them: 1".
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/manager-stamp.sh: 1.
    ("an unusable record stops in every carrier", "hooks/manager-stamp.sh",
     '    [ -n "$ownersid" ] || role=manager',
     '    [ -n "$ownersid" ] || true'),
    # SINCE 2026-11-03 THE 0* ARM IS ONE ARM, in mk_field1_is_pid, and this is the entry
    # aimed at it: 0* taken out of the function, which is da1c515 turned back in all four
    # readers at once. The aim the entry above gives for staying off the arm no longer
    # applies, because there is no second copy left for the grid to read the arm out of.
    # IT KILLS TWO NAMES, measured 2026-11-03 through this file's own main(): this one, and
    # "the claim line calls a field 1 that is no pid unusable", because the writer asks the
    # same function and logs 0 alive again. "one record gives one role in every carrier"
    # SURVIVES it, and that is the grid's known blind spot rather than a gap in this entry:
    # it reads its arms out of this very function, so 0 is classified [usable alive], the
    # cell with no direction clause, and four carriers agreeing on carrier look like
    # agreement. The assertion about the direction is the one that sees it.
    # Anchor counted as a Python substring against hooks/_sessions.sh: 1.
    ("an unusable record stops in every carrier", "hooks/_sessions.sh",
     "  case \"${1-}\" in ''|*[!0-9]*|0*) return 1 ;; esac\n",
     "  case \"${1-}\" in ''|*[!0-9]*) return 1 ;; esac\n"),
    # A COPY OF THE RULE PUT BACK, AND NOTHING ELSE. mk_decide_role judges field 1 by an
    # inline case again, with the very arms of mk_field1_is_pid, so no shape changes its
    # role and every grid that probes the carriers through their input stays green. What
    # comes back is the state of d4e3e73: the rule standing in a second place, which is how
    # the writer's copy came to lack 0* without any reader noticing. Only the check that
    # reads where field 1 is judged can see it: measured 2026-11-03, it kills 1 name, its own.
    # Anchor counted as a Python substring against hooks/_identity.sh: 1.
    ("field 1 is judged in one place, by every reader", "hooks/_identity.sh",
     '! mk_field1_is_pid "$_ownerpid" ||',
     "! { case \"$_ownerpid\" in ''|*[!0-9]*|0*) false ;; *) true ;; esac; } ||"),
    # THE WRITER'S WORD PUT BACK, for the shape this repair was about: a field 1 that is no
    # pid is logged alive, so a record reading "0 S1" yields "previous 0 alive", the line
    # measured at d4e3e73. The call of mk_field1_is_pid stays, so the check that reads where
    # field 1 is judged stays green, and so does every carrier: the word is written after
    # the role has been decided. It also logs garbage and -1 as alive, which the same check
    # reads as its neighbours, so that is collateral inside the one assertion. Measured
    # 2026-11-03: it kills 1 name, its own.
    # Anchor counted as a Python substring against hooks/_identity.sh: 1.
    ("the claim line calls a field 1 that is no pid unusable", "hooks/_identity.sh",
     '    if ! mk_field1_is_pid "$_rr_prev"; then _rr_was=unusable\n',
     '    if ! mk_field1_is_pid "$_rr_prev"; then _rr_was=alive\n'),
    # THE FIFTH COPY PUT BACK, in the take-over, exactly as it stood at 35166a7: the tool
    # judges field 1 by its own arm without 0* again, so a record reading "0 <id>" is
    # handed over as "previous 0 alive". It is the smallest edit that turns this repair back
    # where it was made, and it kills TWO names by construction, each for its own reason:
    # this one, because a case over PREVPID is a place of its own and PREVPID no longer
    # reaches mk_field1_is_pid, and "the claim line calls a field 1 that is no pid
    # unusable", because the handover line says alive for 0 and 00. An edit that kills one
    # alone exists for each, an inline copy WITH 0* or the word alone, and neither would
    # show that both checks reach the tool, which is what was added here. Measured
    # 2026-11-03 through this file's own main(): exactly those two names.
    # Anchor counted as a Python substring against tools/manager-claim.sh: 1.
    ("field 1 is judged in one place, by every reader", "tools/manager-claim.sh",
     '  if ! mk_field1_is_pid "$PREVPID"; then PREVSTATE=unusable\n',
     "  if case \"$PREVPID\" in ''|*[!0-9]*) true ;; *) false ;; esac; then PREVSTATE=unusable\n"),
    # THE ORIGINAL DEFECT, RESTORED FOR THE FILE TOOLS. A stop of Edit, Write and the rest
    # goes back on the record with an empty reason, which is what every stop line carried
    # until 2026-11-02. It is aimed at the path branch rather than at the append, because an
    # empty reason for every tool kills the assertion below as well and proves nothing about
    # what this one sees that the other does not; the Bash stop of the cut command never
    # reaches this branch. Anchor counted the way this file counts, as a Python substring,
    # against hooks/role-guard.sh: 1.
    ("a stop line says which word stopped it and why", "hooks/role-guard.sh",
     '  *)    why=$(export MK_EXPLAIN=1; classify_path "$FPATH" 2>&1 >/dev/null) ;;',
     '  *)    why= ;;'),
    # THE WHOLE ACCOUNT INSTEAD OF THE LINE THAT DECIDED. Every line of the trace goes into
    # the reason, so a command that reads a run of bookkeeping paths before its one work
    # write fills the 400 characters of the field with that run and the word is cut away,
    # exactly as it is cut out of the subject. A short command keeps both lines inside the
    # field, and both are lines the recheck tool prints, so the assertion above survives.
    # Anchor counted as a Python substring against hooks/role-guard.sh: 1.
    ("a word past the subject cut is still in the reason", "hooks/role-guard.sh",
     "why=$(printf '%s\\n' \"$why\" | sed -n '$s/^ *//p')",
     "why=$(printf '%s\\n' \"$why\" | sed 's/^ *//')"),
    # THE SHAPE STAYS ABOVE THE LINE THAT DECIDES. The narrowing no longer hands the line
    # that named the shape up to its caller, so the last line of the trace says that the
    # scratchpad was cancelled and not by which shape, which is the defect of 2026-11-02 in
    # everything but its wording. The verdict does not move, because the hand up only ever
    # happens under the trace, and every line the trace printed before is still printed.
    # Anchor counted the way this file counts, as a Python substring, against
    # hooks/_classify.sh: 1.
    ("a stop names the shape that cancelled the scratchpad", "hooks/_classify.sh",
     '    function benannt(   s) { if (explain == 1) {',
     '    function benannt(   s) { if (0) {'),

    # ------------------------------------------------------------ the register itself
    # THE SHAPE OF da1c515, REPLAYED ON THE SAME ARM. That commit rewrote the arm that makes
    # an unreadable field 1 the manager, the suite stayed green [aab6be6: ALL GREEN: 118
    # checks], and the two entries hung on the old text dangled on eight tips in a row.
    # This edit rewrites the stamp's arm again, by swapping two of its patterns: a case
    # arm matches the union of its patterns in any order, so no carrier answers
    # differently, and it kills this name and no other [measured the same way]. What it
    # changes is TEXT, and "one record gives one role in every carrier" was anchored on
    # that text, so it no longer applies. Only the register check can see that, and only
    # because it holds every entry but the one that made the mutant.
    #
    # THE ANCHOR IS THE PART OF THE ARM THAT THE OTHER ENTRY KEEPS. That entry deletes
    # role=manager and leaves the patterns standing, so in ITS run this anchor is still
    # there and the register check does not die beside it.
    #
    # THE REGISTER CHECK ALSO DIES IN THE RUNS OF EVERY ENTRY WHOSE EDIT OVERLAPS A SECOND
    # ENTRY'S ANCHOR, because in that tree the second entry really does not apply any more.
    # Derived 2026-11-02 by applying every entry in memory and asking every other one, 9
    # entries: the pairs "the bash measure, six writes and three reads" and "a quoted path
    # is still a path", "the session scratchpad is bookkeeping" and "a scratchpad script
    # is silent", "a worktree is recorded at its main repository" and "a relative gitdir is
    # read against the worktree", "the two hooks never split one session" and "an
    # uncountable register gives one role everywhere", and "one day boundary for git and
    # the guard log" alone, which breaks "the day a commit landed" and not the other way.
    # They still die for their own names, and the runner reads only that.
    # RE-ANCHORED 2026-11-03, because the arm it swapped left the stamp for
    # mk_field1_is_pid. The shape is unchanged: a rewrite of the line "one record gives one
    # role in every carrier" is anchored on, here one space before the semicolon, which no
    # shell reads differently, and its anchor is again the part that entry keeps. Old
    # anchor "''|*[!0-9]*|0*)", new anchor the stamp's call up to its `then`.
    # Anchor counted as a Python substring against hooks/manager-stamp.sh: 1.
    ("every mutation in the register still applies", "hooks/manager-stamp.sh",
     'if ! mk_field1_is_pid "$ownerpid"; then',
     'if ! mk_field1_is_pid "$ownerpid" ; then'),
    # A CHECK ADDED WITHOUT AN ENTRY, the shape that once left "a reported failure does not
    # cost the green run" unpaired: one more line in the suite, a checker that passes, and no
    # entry of that name in this file. The suite runs it green and counts it; only the
    # pairing can see it.
    # It kills this name and no other, measured 2026-11-03 run on its own.
    # Anchor counted as a Python substring against tests/run.sh: 1.
    ("every check has an entry, and every entry a check", "tests/run.sh",
     "check 'every check has an entry, and every entry a check' mutation_register_names_every_check\n",
     "check 'every check has an entry, and every entry a check' mutation_register_names_every_check\n"
     "check 'a check the register has never heard of' true\n"),
    # A COMMENT THAT QUOTES AN ANCHORED LINE VERBATIM, which is how an anchor comes to stand
    # twice in this repository, whose comments quote code all the time. Appended past the
    # last line of the suite, where nothing runs it, and quoting the anchor of the first entry
    # of this file. That entry still applies, to the first of the two, so only a count can
    # see it. It appends, so it has no anchor of its own to count.
    # It kills this name and no other, measured 2026-11-03 run on its own.
    ("every anchor in the register stands exactly once", "tests/run.sh",
     None, '\n# quoted while repairing check():\n#  if _out=$("$@" 2>&1); then\n'),
    # ---------------------------------------------------------------- MK-STILL, 2026-11-06
    # Thirteen entries for eight assertions. Every anchor was counted as a Python substring
    # against its file, which is how this file and the register check count: 1 each. What an
    # entry killed besides its own name is not written here, because it is measured per run and
    # goes stale with the suite: .claude/uebergabe/MK-STILL.md has the table, and
    # python3 tests/mutate.py "<name>" reproduces a row.
    #
    # A call that lost its -I, in the one hook where the wrapper of the context is the only
    # python3 left to see. The scan sees it. It kills a second name, and that is the planted
    # file doing what the text promised it would: without -I the empty json.py of the
    # project empties the wrapper too.
    ("every python3 call in a hook or tool runs isolated", "hooks/manager-prime.sh",
     'mk_role_context "$role" "$ROOT" | python3 -I -c \'',
     'mk_role_context "$role" "$ROOT" | python3 -c \''),
    # THE SCAN THAT STOPS CARING WHICH OPTION COMES FIRST. Any option now counts as the
    # isolating one, so the fixture's calls without -I read as isolated. The real tree is
    # clean either way, which is why the assertion above stays green and only the one that
    # feeds the scan a call it must refuse can die.
    ("the isolation scan sees a call that is not isolated", "tests/run.sh",
     'iso = bool(re.match(r"[ \\t]+-I(?=[ \\t]|$)", rest))',
     'iso = bool(re.match(r"[ \\t]+-[A-Za-z](?=[ \\t]|$)", rest))'),
    # A CALL THE TEXT SCAN CANNOT SEE: the interpreter named through command -v, which is
    # not a call in command position. The scan and the plain grep both pass it, and the
    # planted file runs in the hook that writes the log line, which is the only way left to
    # find it. It is what makes the effect assertion more than a second reading of the text.
    ("a project file named like a module changes no verdict", "hooks/_sessions.sh",
     "    MK_DOOR_ROOT=$_le_root python3 -I -c \"$MK_PY_DOOR$MK_PY_REDACT\"'\nimport sys, json, time\n",
     "    MK_DOOR_ROOT=$_le_root $(command -v python3) -c \"$MK_PY_DOOR$MK_PY_REDACT\"'\nimport sys, json, time\n"),
    # THE LOG LINE THAT IS NOT AN OBJECT, in each of the three readers. The skip is turned
    # into a branch that never runs, so a list, a number or null reaches rec.get again.
    ("no line of the log, however broken, changes a verdict", "hooks/role-guard.sh",
     "            if not isinstance(rec, dict):\n",
     "            if False:\n"),
    ("no line of the log, however broken, changes a verdict", "hooks/route-guard.sh",
     "            if not isinstance(rec, dict):\n",
     "            if False:\n"),
    ("no line of the log, however broken, changes a verdict", "tools/week-verdict.sh",
     "            if not isinstance(rec, dict):\n",
     "            if False:\n"),
    # THE COUNT LEFT UNSAID: the reader still finishes and still skips, and no longer says
    # how many lines it skipped.
    ("week-verdict says how many log lines it could not read", "tools/week-verdict.sh",
     '    print("unreadable log lines:       %d (no event, and not counted above)" % unreadable)\n',
     "    pass\n"),
    # THE FIXED REFUSAL NEVER REACHED: the first arm takes every answer, so a printer that
    # died leaves the empty answer it left before. One entry per hook that has the arm.
    ("the refusal goes out when the program that prints it fails", "hooks/role-guard.sh",
     "  *'\"permissionDecision\": \"deny\"'*) ;;\n  *)\n    recheck=\n",
     "  *) ;;\n  *)\n    recheck=\n"),
    ("the refusal goes out when the program that prints it fails", "hooks/route-guard.sh",
     "  *'\"permissionDecision\": \"deny\"'*) ;;\n  *)\n    out='{\"hookSpecificOutput\"",
     "  *) ;;\n  *)\n    out='{\"hookSpecificOutput\""),
    # THE LIMIT THAT NEVER FIRES, then THE LIMIT ON THE WHOLE TEXT, which is the cheaper
    # repair that was weighed and not taken: it would refuse a 1.2 MB heredoc that writes a
    # note into .claude/, a command the measure reads in linear time and calls bookkeeping.
    ("a command too large to read is not let through", "hooks/_classify.sh",
     '  if [ "${#_s}" -gt "$MK_READ_LIMIT" ]; then\n',
     '  if [ "${#_s}" -gt 99999999 ]; then\n'),
    ("a command too large to read is not let through", "hooks/_classify.sh",
     '  if [ "${#_s}" -gt "$MK_READ_LIMIT" ]; then\n',
     '  if [ "${#_c}" -gt "$MK_READ_LIMIT" ]; then\n'),
    # THE WHOLE COMMAND BACK IN THE ENVIRONMENT, beside the pipe that carries it. The program
    # ignores the variable; the system does not, and the exec of it fails past the argument
    # limit, so the refusal that comes out is the fixed one and carries no count.
    ("a command too large to read is not let through", "hooks/role-guard.sh",
     "out=$(printf '%s' \"$subject\" 2>/dev/null |\n  MK_MARKER=$MARKER",
     "out=$(printf '%s' \"$subject\" 2>/dev/null |\n  MK_SUBJECT=$subject MK_MARKER=$MARKER"),
    # MK-ZEIT: the refusal of a command past the limit takes 8 s, against the 5 the check allows, in every try.
    ("a command too large to read is not let through", "hooks/_classify.sh",
     '  if [ "${#_s}" -gt "$MK_READ_LIMIT" ]; then\n',
     '  if [ "${#_s}" -gt "$MK_READ_LIMIT" ]; then\n    sleep 8\n'),
    # THE BROKEN INTERPRETER ANSWERED WITH NOTHING, where the missing one speaks.
    ("a python3 that does not run is said out loud like a missing one", "hooks/role-guard.sh",
     "  printf '%s\\n' '{\"systemMessage\":\"manager-kit: the role guard is inert, python3 is on PATH but does not run.\"}'\n",
     "  true\n"),
    # MK-A3: THE KIT'S OWN FILES ARE PLAIN FILES IN THE PROJECT. Thirty-four entries for nine
    # assertions. Every anchor was counted as a Python substring against its file, the way this
    # file and the register check count: 1 each. What an entry killed besides its own name is
    # measured per run and stands in .claude/uebergabe/MK-A3.md.
    #
    # The open follows a link again: the write of nachpruefung.sh part 3 lands on its target.
    ("a link under .claude reaches nothing outside the project", "hooks/_sessions.sh",
     '    flags |= os.O_NOFOLLOW\n', '    flags |= 0\n'),
    # The shell asks about a link no longer, so the role file is read through one.
    ("a link under .claude reaches nothing outside the project", "hooks/_sessions.sh",
     '  [ ! -L "$1" ] || return 1\n', '  true\n'),
    # Status 1 is read as spent: the defect of nachpruefung2.sh, a crossing out of a marker that
    # is still lying there, with an empty reason on the record.
    ("a marker that cannot be spent buys nothing", "hooks/role-guard.sh",
     '  case $? in\n    0)\n', '  case $? in\n    0|1)\n'),
    # A crossing passes although its line could not be written: a pass the record does not know.
    ("a marker that cannot be spent buys nothing", "hooks/role-guard.sh",
     '      if append exception "$TOOL" "$subject" "$reason"; then exit 0; fi\n',
     '      append exception "$TOOL" "$subject" "$reason"; exit 0\n'),
    # What the open found is no longer asked: a pipe as marker reads as an empty file, and the
    # refusal stops saying it cannot be spent.
    ("a marker that cannot be spent buys nothing", "hooks/_sessions.sh",
     '    if not stat.S_ISREG(st.st_mode) or st.st_nlink > 1:\n', '    if False:\n'),
    # The open waits on a pipe again.
    ("a pipe or a directory under .claude holds no hook", "hooks/_sessions.sh",
     '    flags |= os.O_NONBLOCK\n', '    flags |= 0\n'),
    # The shell test lets a pipe through, and awk and cat wait on it.
    ("a pipe or a directory under .claude holds no hook", "hooks/_sessions.sh",
     '  [ -f "$1" ] || return 1\n', '  [ -e "$1" ] || return 1\n'),
    # The definitions of hands are read by a plain open again.
    ("a pipe or a directory under .claude holds no hook", "hooks/_routing.sh",
     'fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)\n            # errors=', 'fd = os.open(path, os.O_RDONLY)\n            # errors='),
    # A pipe among the definitions counts as a hand with no effort and shadows the real one.
    ("a pipe or a directory under .claude holds no hook", "hooks/_routing.sh",
     '                if not stat.S_ISREG(os.fstat(fd).st_mode):\n', '                if False:\n'),
    # grep is handed a pipe named settings.json.
    ("a pipe or a directory under .claude holds no hook", "hooks/_sessions.sh",
     '    [ -f "$_ns_f" ] || continue\n', '    [ -e "$_ns_f" ] || continue\n'),
    # The readers no longer ask about home, so what lies in the home .claude is read as a record.
    ("a session at home leaves the home .claude alone", "hooks/_sessions.sh",
     '  mk_root_is_barred "${1-}" && return 1\n  if [ -L "${1-}/.claude" ]; then\n',
     '  if [ -L "${1-}/.claude" ]; then\n'),
    # The one writer that has no caller to ask for it: the line of a stop lands in the home .claude.
    ("a session at home leaves the home .claude alone", "hooks/_sessions.sh",
     '  mk_root_is_barred "$_le_root" && return 1\n', ''),
    # Home under a second spelling is a project again.
    ("a session at home leaves the home .claude alone", "hooks/_sessions.sh",
     '  [ "${1-}" -ef "$HOME" ] && return 0\n', '  :\n'),
    # "/" no longer lies above home.
    ("a session at home leaves the home .claude alone", "hooks/_sessions.sh",
     '    "${1%/}"/*) return 0 ;;\n', '    "${1-}"/*) return 0 ;;\n'),
    # The door, asked directly at home, writes.
    ("a session at home leaves the home .claude alone", "hooks/_sessions.sh",
     'mk_kit_write() {\n  mk_root_is_barred "${1-}" && return 1\n', 'mk_kit_write() {\n'),
    # The door, asked directly at home, spends.
    ("a session at home leaves the home .claude alone", "hooks/_sessions.sh",
     'mk_kit_spend() {\n  mk_root_is_barred "${1-}" && return 1\n', 'mk_kit_spend() {\n'),
    # The route refusal counts the log of the home .claude.
    ("a session at home leaves the home .claude alone", "hooks/route-guard.sh",
     'if mk_kit_make_home "$ROOT"; then DOOR_ROOT=$ROOT; fi', 'DOOR_ROOT=$ROOT'),
    # The guard refusal counts it.
    ("a session at home leaves the home .claude alone", "hooks/role-guard.sh",
     '[ "$NO_RECORD" = 0 ] || DOOR_ROOT=\n', ''),
    # The name comes back relative: the sentence a session in a subdirectory follows to the letter.
    ("the refusal names the marker where the guard reads it", "hooks/role-guard.sh",
     '        marker_path +\n', '        ".claude/manager-exception" +\n'),
    ("the refusal names the marker where the guard reads it", "hooks/role-guard.sh",
     '"declaration to " + marker_path + " in a call of its own', '"declaration to .claude/manager-exception in a call of its own'),
    ("the refusal names the marker where the guard reads it", "hooks/role-guard.sh",
     '    where=$MARKER\n', '    where=.claude/manager-exception\n'),
    # A quote in the path breaks the short form, and a broken answer does not refuse.
    ("the refusal names the marker where the guard reads it", "hooks/role-guard.sh",
     '    where=${where//\\"/\\\\\\"}\n', ''),
    # A backslash in the path does the same.
    ("the refusal names the marker where the guard reads it", "hooks/role-guard.sh",
     '    where=${where//\\\\/\\\\\\\\}\n', ''),
    # A raw read on a path no probe walks: only the derivation can see it.
    ("every read and write under .claude goes through the door", "tools/manager-claim.sh",
     'say_where() {\n', 'say_where() {\n  [ -z "${MK_NEVER-}" ] || cat "$RF"\n'),
    # The scan calls everything gated. The real tree stays clean under it, which is why only the
    # assertion that feeds it a fixture can die.
    ("the door scan sees a site with no door", "tests/run.sh",
     '        verdict = "RAW"\n', '        verdict = "gated"\n'),
    # THE OVER-REPAIR: every link is refused, inside the project too. That is the person this
    # order says must not silently be made worse off.
    ("a .claude linked inside the project keeps its record", "hooks/_sessions.sh",
     '"$_rh_root"/?*) return 0 ;; esac', '"$_rh_root"/?*) return 1 ;; esac'),
    # The same over-repair in the door: a linked .claude meets O_NOFOLLOW and the record is lost.
    ("a .claude linked inside the project keeps its record", "hooks/_sessions.sh",
     '    home = os.path.realpath(os.path.join(root, ".claude"))\n', '    home = os.path.join(base, ".claude")\n'),
    # The over-repair at what is not the kit's: linked definitions are no longer seen by the routing.
    ("a .claude linked inside the project keeps its record", "hooks/_routing.sh",
     '    for path in sorted(glob.glob(os.path.join(d, "*.md"))):\n',
     '    for path in sorted(p for p in glob.glob(os.path.join(d, "*.md")) if not os.path.islink(p)):\n'),
    # And a linked settings file is no longer read for the report.
    ("a .claude linked inside the project keeps its record", "hooks/_sessions.sh",
     '    [ -f "$_ns_f" ] || continue\n', '    [ -f "$_ns_f" ] && [ ! -L "$_ns_f" ] || continue\n'),
    # A link out of the project counts as a home: what lies out there is read as this record.
    ("a .claude that leaves the project says so and keeps the refusal", "hooks/_sessions.sh",
     'esac\n    return 1\n  fi\n', 'esac\n    return 0\n  fi\n'),
    # The door no longer asks where .claude leads: the log line lands out there.
    ("a .claude that leaves the project says so and keeps the refusal", "hooks/_sessions.sh",
     '    if not home.startswith(base + os.sep):\n', '    if False:\n'),
    # Worse off and in silence, the three places it is said.
    ("a .claude that leaves the project says so and keeps the refusal", "hooks/manager-prime.sh",
     'if trouble:\n    answer["systemMessage"] = trouble\n', ''),
    ("a .claude that leaves the project says so and keeps the refusal", "hooks/manager-reinject.sh",
     'if trouble:\n    answer["systemMessage"] = trouble\n', ''),
    ("a .claude that leaves the project says so and keeps the refusal", "hooks/role-guard.sh",
     'TROUBLE=$(mk_record_trouble "$ROOT")\n', 'TROUBLE=\n'),
    # MK-A4, a path that is not ASCII. The census stops reading lsof, and the census is the only
    # thing that keeps the second session from claiming.
    ("a session in a project that is not ASCII is counted where it stands", "hooks/_sessions.sh",
     '      mk_lsof_path_set "$_pcwd" || { _unread=1; continue; }\n      mk_project_root_set "$MK_LSOF_PATH"\n',
     '      mk_project_root_set "$_pcwd"\n'),
    # The reading itself goes, for both of its callers.
    ("the role stays with the first session in a project that is not ASCII", "hooks/_sessions.sh",
     """printf -v MK_LSOF_PATH '%b' "$MK_LSOF_PATH" ;;""", ': ;;'),
    ("a take-over in a project that is not ASCII lands in that project", "tools/manager-claim.sh",
     '  mk_lsof_path_set "$_cpc" || return 3\n  case $MK_LSOF_PATH in *"$MK_NL") return 3 ;; esac\n  MK_CLAIM_CWD=$MK_LSOF_PATH\n',
     '  MK_CLAIM_CWD=$_cpc\n'),
    # The file system is no longer asked, the two spellings are two projects again.
    ("two spellings of one directory are one project where the disk folds them", "hooks/_sessions.sh",
     '  [ "$1" = "$2" ] && return 0\n', '  [ "$1" = "$2" ]; return $?\n'),
    # The counter-direction: -ef for everybody hands a role to a session in an ASCII project.
    ("an ASCII project reached through a link is compared as before", "hooks/_sessions.sh",
     'case "$1$2" in *[![:ascii:]]*) [ "$1" -ef "$2" ] ;; *) return 1 ;; esac', '[ "$1" -ef "$2" ]'),
    # MK-R2 finds 8 and 9. The reading of an ASCII name that lsof escapes: a backslash is no longer
    # reversed, so a session in back\\slash is counted into a project that is not there.
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     r"""    *\\*) printf -v MK_LSOF_PATH '%b' "$MK_LSOF_PATH" ;;""", r"""    *\\*) ;;"""),
    # A name with ^A in it is read as it is printed again: it may be a control character, and is counted.
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     r"""_]*) MK_LSOF_PATH=""; return 1 ;;""", r"""_]*) ;;"""),
    # The class of what lsof prints with a caret leaves out one byte it does print that way (K, 11).
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     "*'^'[ABCDEFGKNOP", "*'^'[ABCDEFGNOP"),
    # And the other way: a byte lsof prints as an escape (H, \\b) joins the class, so a literal ^H, which
    # no control character is printed as, is refused. The counter-direction of the refusal.
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     "*'^'[ABCDEFGKNOP", "*'^'[ABCDEFGHKNOP"),
    # A command substitution in place of printf -v: a name that ends in a newline is read as its sibling.
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     r"""printf -v MK_LSOF_PATH '%b' "$MK_LSOF_PATH" ;;""", r"""MK_LSOF_PATH=$(printf '%b' "$MK_LSOF_PATH") ;;"""),
    # A census with a hole in it still says its sum adds up.
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     '[ $((_alive + _dead)) -eq "$_base" ] && [ "$_unread" != 1 ] && _sumok=1',
     '[ $((_alive + _dead)) -eq "$_base" ] && _sumok=1'),
    # The session it could not place is not remembered: the count says it is whole.
    ("a path lsof escapes is read back exactly or not read at all", "hooks/_sessions.sh",
     'mk_lsof_path_set "$_pcwd" || { _unread=1; continue; }', 'mk_lsof_path_set "$_pcwd" || continue'),
    # The same story in the guard: the second session claims in a path the census cannot place.
    ("the role stays with the first session in a path lsof escapes", "hooks/_sessions.sh",
     '[ $((_alive + _dead)) -eq "$_base" ] && [ "$_unread" != 1 ] && _sumok=1',
     '[ $((_alive + _dead)) -eq "$_base" ] && _sumok=1'),
    ("the role stays with the first session in a path lsof escapes", "hooks/_sessions.sh",
     r"""    *\\*) printf -v MK_LSOF_PATH '%b' "$MK_LSOF_PATH" ;;""", r"""    *\\*) ;;"""),
    # The take-over carries on in a directory it could not read, and makes it beside the project.
    ("a take-over off an escaped path lands in the project or is refused", "tools/manager-claim.sh",
     '  mk_lsof_path_set "$_cpc" || return 3\n', '  mk_lsof_path_set "$_cpc"\n'),
    # A name that ends in a newline is handed on through a command substitution and loses it.
    ("a take-over off an escaped path lands in the project or is refused", "tools/manager-claim.sh",
     '  case $MK_LSOF_PATH in *"$MK_NL") return 3 ;; esac\n', ''),
    # The overreach of the repair: anything not ASCII counts as here.
    ("a session elsewhere is not counted into a project that is not ASCII", "hooks/_sessions.sh",
     'mk_same_root() {\n', 'mk_same_root() {\n  case "$1$2" in *[![:ascii:]]*) return 0 ;; esac\n'),
    ("a character that cannot be printed leaves the refusal standing", "hooks/_sessions.sh",
     r"""text = re.sub("[\ud800-\udc7f\udd00-\udfff]", "\ufffd", "" if value is None else str(value))""",
     'text = "" if value is None else str(value)'),
    # The locale decides again, on the way in and on the way out.
    ("a hook reads its input as UTF-8 under any locale", "hooks/_sessions.sh",
     'd = json.load(io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="surrogateescape"))', 'd = json.load(sys.stdin)'),
    ("a hook reads its input as UTF-8 under any locale", "hooks/_sessions.sh",
     r"""sys.stdout.buffer.write(("%s=%s\n" % (name, shlex.quote(text))).encode("utf-8", "surrogateescape"))""",
     'print("%s=%s" % (name, shlex.quote(text)))'),
    ("a record line keeps its path under any locale", "hooks/_sessions.sh",
     r"""parts = sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\x00", 3)""",
     r"""parts = sys.stdin.read().split("\x00", 3)"""),
    # A reader that only takes ASCII: this assertion is the only one with such a line in its log.
    ("records a previous version wrote stay readable", "hooks/role-guard.sh",
     '"manager-kit.log", os.O_RDONLY), "rb") as fh:', '"manager-kit.log", os.O_RDONLY), "r", encoding="ascii") as fh:'),
    ("records a previous version wrote stay readable", "tools/week-verdict.sh",
     'os.O_RDONLY), "rb") as fh:', 'os.O_RDONLY), "r", encoding="ascii") as fh:'),
    # A site that is harmless today, because the role text is ASCII, and only the scan can see it.
    ("every hook reads its input through the one reader", "hooks/manager-prime.sh",
     'text = sys.stdin.buffer.read().decode("utf-8", "replace")\n', 'text = sys.stdin.read()\n'),
    # A new lsof that nothing reads, in a file nothing else looks at for it.
    ("every lsof answer that names a directory is read by the one reading", "tools/mk-explain.sh",
     '. "$HERE/../hooks/_classify.sh"\n', '. "$HERE/../hooks/_classify.sh"\n_mk_here=$(lsof -a -p $$ -d cwd -Fn 2>/dev/null)\n'),
    # The refusal tells a session in such a project a marker the guard does not read.
    ("a project that is not ASCII gets the answers of an ASCII one", "hooks/role-guard.sh",
     'marker_path = os.environ.get("MK_MARKER", "")\n',
     'marker_path = os.environ.get("MK_MARKER", "").encode("ascii", "ignore").decode()\n'),
    ("a hand file with an unreadable character keeps the routing refusal", "hooks/_routing.sh",
     'with os.fdopen(fd, encoding="utf-8", errors="replace") as fh:', 'with os.fdopen(fd, encoding="utf-8") as fh:'),
    ("a hand file with an unreadable character keeps the routing refusal", "hooks/_routing.sh",
     r"""sys.stdout.buffer.write(("%s\t%s\t%s\n" % (name, origin, seen[name])).encode("utf-8", "surrogateescape"))""",
     r"""sys.stdout.write("%s\t%s\t%s\n" % (name, origin, seen[name]))"""),
    # Each of the three programs on its own, because each answers nothing on its own.
    ("the classifier reads bytes under any locale", "hooks/_classify.sh",
     """for _nw in $(printf '%s' "${1-}" | LC_ALL=C awk -v""", """for _nw in $(printf '%s' "${1-}" | awk -v"""),
    ("the classifier reads bytes under any locale", "hooks/_classify.sh",
     """_s=$(printf '%s' "$_c" | LC_ALL=C awk -v""", """_s=$(printf '%s' "$_c" | awk -v"""),
    ("the classifier reads bytes under any locale", "hooks/_classify.sh",
     """_targets=$(printf '%s' "$_s" | LC_ALL=C awk -v""", """_targets=$(printf '%s' "$_s" | awk -v"""),
    ("the week reads a file name that is not ASCII as that file", "tools/week-verdict.sh",
     '-c core.quotePath=false show', 'show'),
    # The four places the classifier spells what a word is made of.
    ("a path that is not ASCII is one word for the classifier", "hooks/_classify.sh",
     r'pfad = "[\\200-\\377A-Za-z0-9_.$@{}~+-]*(/[\\200-\\377A-Za-z0-9_.$@{}~+-]+)+/?"',
     r'pfad = "[A-Za-z0-9_.$@{}~+-]*(/[A-Za-z0-9_.$@{}~+-]+)+/?"'),
    ("a path that is not ASCII is one word for the classifier", "hooks/_classify.sh",
     'gsub(/[^A-Za-z0-9_\\200-\\377]/, "", d)\n        if (d != "") {\n          delim = d;',
     'gsub(/[^A-Za-z0-9_]/, "", d)\n        if (d != "") {\n          delim = d;'),
    ("a path that is not ASCII is one word for the classifier", "hooks/_classify.sh",
     'gsub(/[^A-Za-z0-9_\\200-\\377]/, "", d)\n        if (d != "") { delim = d; inh = 1\n',
     'gsub(/[^A-Za-z0-9_]/, "", d)\n        if (d != "") { delim = d; inh = 1\n'),
    ("a path that is not ASCII is one word for the classifier", "hooks/_classify.sh",
     r"""if ($j !~ /^[A-Za-z0-9_.~$\/\200-\377]/) break""", r"""if ($j !~ /^[A-Za-z0-9_.~$\/]/) break"""),
    # The cut lands inside a character again.
    ("a take-over in a project that is not ASCII lands in that project", "tools/manager-claim.sh",
     """&& _cf=$_cf2 ;;""", """;;"""),
    # ---- MK-A5: what the guard writes into the record. One mutant for each rule of the redactor and each place that writes or prints.
    # NAME=value
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '        if not any(w in up for w in MK_REDACT_WORDS)',
     '        if True or not any(w in up for w in MK_REDACT_WORDS)'),
    # Authorization: and the key headers
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '        if e > i and text[i:e].strip():\n            spans.append((i, e))',
     '        if False:\n            spans.append((i, e))'),
    # Bearer on its own
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '    for m in _BEARER.finditer(text):',
     '    for m in ():'),
    # --password and kin
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '    for m in _FLAG.finditer(text):',
     '    for m in ():'),
    # mysql -pvalue
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '        for p in _MYSQL_P.finditer(text, m.end(), e):',
     '        for p in ():'),
    # user:password@ in a URL
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '    for m in _URL.finditer(text):',
     '    for m in ():'),
    # sk-, ghp_, AKIA
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     '    for pat in _KNOWN:',
     '    for pat in ():'),
    # the record, subject
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     'subject = mk_safe(subject, 400)',
     'subject = subject[:400]'),
    # the record, reason
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     'reason = mk_safe(reason, 400)',
     'reason = reason[:400]'),
    # the refusal of the role guard
    ('a secret in a refused command is not on the record', 'hooks/role-guard.sh',
     'subject = mk_safe(raw, 300)',
     'subject = raw[:300]'),
    # the refusal of the route guard
    ('a secret in a refused command is not on the record', 'hooks/route-guard.sh',
     'hand = mk_safe(os.environ.get("MK_SUBAGENT", ""), 400)',
     'hand = os.environ.get("MK_SUBAGENT", "")'),
    # a name is read only at the start of a word
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '_NAME_EQ = re.compile(r"(?<![^\\s;&|(){}`:?,\\"\\x27])([A-Za-z_]',
     '_NAME_EQ = re.compile(r"([A-Za-z_]'),
    # a value that starts with $ is not a secret
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '            if ch == "$":\n                continue\n',
     '            pass\n'),
    # _FILE, _PATH, _DIR, _NAME
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     'or up.endswith(MK_REDACT_NOT):',
     ':'),
    # a closing quote read as the start of a value
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '    if ch in "\\"\\x27" and ch != quote:',
     '    if ch in "\\"\\x27":'),
    # a Bearer value holds a digit
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '(?=[A-Za-z0-9._~+/=-]*\\d)([A-Za-z0-9._~+/=-]{8,})',
     '([A-Za-z0-9._~+/=-]{8,})'),
    # an sk- inside a path
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '(?<![A-Za-z0-9_./-])sk-',
     '(?<![A-Za-z0-9_-])sk-'),
    # the verdict is taken from the redacted command
    ('the verdict comes from the whole command', 'hooks/role-guard.sh',
     'say("CMD", ti.get("command"))',
     # LINEAR, AND THE SAME TEXT OUT. It was ([a-z_]*(key|token|secret|password)[a-z_]*)=..., which starts an attempt at
     # every letter of a long word and runs to the end of it each time: 5000 characters took 0.51 s, 20000 took 8.2 s and
     # 40000 took 32.6 s [measured 2026-11-07], so the 200000 of the longest test command took 13 minutes and the full
     # run never got past this entry. The lookbehind lets an attempt start only where a run of [a-z_] starts, so each
     # letter is read once, and the lookahead asks, lazily and once, whether the run holds one of the words: that is
     # what the old pattern asked by backtracking. A run without one is not consumed, so a name inside its value is
     # still found, as before. Same output as the old pattern on 300000 random strings: see MK-R4.md.
     'say("CMD", __import__("re").sub(r"(?i)(?<![a-z_])(?=[a-z_]*?(?:key|token|secret|password))([a-z_]+)=[^\\s;&|]+", r"\\1=[redacted]", ti.get("command") or ""))'),
    # mk_safe answers the text when it fails
    ('a failing redaction still refuses', 'hooks/_sessions.sh',
     'return "[withheld: the redaction failed]"',
     'return text'),
    # mode of a new log
    ('a new log is private and out of git reach', 'hooks/_sessions.sh',
     'flags | os.O_EXCL, 0o600,',
     'flags | os.O_EXCL, 0o666,'),
    # no exclusion
    ('a new log is private and out of git reach', 'hooks/_sessions.sh',
     '            mk_exclude(os.environ.get("MK_DOOR_ROOT", ""))',
     '            pass'),
    # the exclusion is written again and again
    ('a new log is private and out of git reach', 'hooks/_sessions.sh',
     '        missing = [line for line in MK_KIT_IGNORE if line not in have.split(b"\\n")]\n',
     '        missing = list(MK_KIT_IGNORE)\n'),
    # the exclusion for a log that was there
    ('a new log is private and out of git reach', 'hooks/_sessions.sh',
     '        except FileExistsError:\n            fd = os.open(name, flags, 0o600, dir_fd=home)',
     '        except FileExistsError:\n            fd = os.open(name, flags, 0o600, dir_fd=home)\n            mk_exclude(os.environ.get("MK_DOOR_ROOT", ""))'),
    # .git followed
    ('the exclusion does not leave the project', 'hooks/_sessions.sh',
     'git = os.open(".git", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=base)',
     'git = os.open(".git", os.O_RDONLY | os.O_DIRECTORY, dir_fd=base)'),
    # .git/info followed
    ('the exclusion does not leave the project', 'hooks/_sessions.sh',
     '        try:\n            info = os.open("info", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=git)\n        except FileNotFoundError:',
     '        try:\n            info = os.open("info", os.O_RDONLY | os.O_DIRECTORY, dir_fd=git)\n        except FileNotFoundError:'),
    # .git/info/exclude followed
    ('the exclusion does not leave the project', 'hooks/_sessions.sh',
     'os.O_CREAT | os.O_NOFOLLOW |',
     'os.O_CREAT |'),
    # a writer with no redactor, after the last exit
    ('every writer of the log and every refusal names the redactor', 'hooks/role-guard.sh',
     None,
     '\nprintf \'%s\' "$CMD" | mk_kit_write "$ROOT" manager-kit.log append\n'),
    # the scan stops seeing the claim line
    ('every writer of the log and every refusal names the redactor', 'tests/run.sh',
     'if "mk_kit_write" in l and "manager-kit.log" in l:',
     'if "mk_kit_write" in l and "manager-kit.logX" in l:'),
    # a bare key= stays, except in a query
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     'if m.group(1) in ("key", "Key") and (',
     'if False and ('),
    # a bare key= in a query is a secret
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     'text[m.start() - 1] not in "?&"):',
     'True):'),
    # the cut to 400 comes back before the redaction
    ('a secret in a refused command is not on the record', 'hooks/_sessions.sh',
     'reason = os.read(fd, 65536).decode("utf-8", "replace").translate({10: " ", 31: " "})',
     'reason = os.read(fd, 65536).decode("utf-8", "replace").translate({10: " ", 31: " "})[:400]'),
    # MK-R3, the shapes of a secret that are not NAME=value, and the words that only hold one. One entry for each rule
    # the redactor gained and for each neighbour it must leave alone. A rule that goes back kills the assertion that holds it.
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    for pat in (_KV_JSON, _KV_YAML):',
     '    for pat in (_KV_YAML,):'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    for pat in (_KV_JSON, _KV_YAML):',
     '    for pat in (_KV_JSON,):'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    for m in _CURL.finditer(text):\n        if m.start() < done:',
     '    for m in ():\n        if m.start() < done:'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    for m in _SSHPASS.finditer(text):',
     '    for m in ():'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    for m in _PEM.finditer(text):',
     '    for m in ():'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'xox[abposr]-(?=[A-Za-z0-9-]*\\d)[A-Za-z0-9-]{10,}',
     'xoy[abposr]-(?=[A-Za-z0-9-]*\\d)[A-Za-z0-9-]{10,}'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'xapp-\\d-',
     'xapq-\\d-'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'AIza[A-Za-z0-9_-]{35}',
     'AIzb[A-Za-z0-9_-]{35}'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'eyJ[A-Za-z0-9_-]{6,}\\.eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}',
     'eyK[A-Za-z0-9_-]{6,}\\.eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '            g = None if glued < 0 and not _PLAIN.fullmatch(text, i, j) else _GLUE.match(text, j)',
     '            g = None'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    if glued >= 0 and j < n and text[j] in "\\"\\x27":\n        return glued',
     '    if False:\n        return glued'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'glued < 0 and not _PLAIN.fullmatch(text, i, j)',
     'False'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '            bare = not (m.group(2) or m.group(3) or lead[-1:] in ("\\"", "\\x27"))',
     '            bare = False'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'm.group(2) or _HEADER_FLAG.search(lead) or _HEADER_SCHEME.match(text, i)):',
     'm.group(2) or _HEADER_SCHEME.match(text, i)):'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'or _HEADER_SCHEME.match(text, i)):\n                continue',
     '):\n                continue'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'if not (m.group(2) or _HEADER_FLAG.search(lead)',
     'if not (_HEADER_FLAG.search(lead)'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '        if bare:\n            s = _HEADER_SCHEME.match(text, i)\n            if s:',
     '        if bare:\n            s = None\n            if s:'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '_HEADER_END_BARE = re.compile(r"[\\s;&|<>()`\\"\\x27]")',
     '_HEADER_END_BARE = re.compile(r"[\\s\\"\\x27]")'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '"Negotiate", "NTLM", "OAuth")',
     '"Negotiate", "NTLM")'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '_KV_JSON = re.compile(r"(?<![A-Za-z0-9_])([\\"\\x27])(?P<name>',
     '_KV_JSON = re.compile(r"(?<![A-Za-z0-9_])(\\")(?P<name>'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '|(?<=[\\"\\x27]))(?P<name>',
     ')(?P<name>'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '^[ \\t]*(?:-[ \\t]+)?|(?<=',
     '^[ \\t]*|(?<='),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '(?:-[A-Za-z]*[uU][ \\t]+|',
     '(?:-[uU][ \\t]+|'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '--(?:proxy-)?user(?:=|[ \\t]+))',
     '--user(?:=|[ \\t]+))'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '(?:proxy-)?user(?:=|[ \\t]+))',
     '(?:proxy-)?user[ \\t]+)'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '--(?:proxy-)?user(?:=|[ \\t]+))',
     '--(?:proxy-)?user)'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '                if text[p.end()] in "\\"\\x27" and end - 1 > k and text[end - 1] == text[p.end()]:\n                    end -= 1',
     '                if False:\n                    end -= 1'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '-p(?:[ \\t]+(?=\\S)|(?=\\S))")',
     '-p[ \\t]+(?=\\S)")'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '(?:-[evV][ \\t]+)*-p',
     '-p'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '    for m in _SSHPASS.finditer(text):\n        i = m.end()\n        if i < n and text[i] != "$":',
     '    for m in _SSHPASS.finditer(text):\n        i = m.end()\n        if i < n:'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '                if end > k and text[k] != "$":',
     '                if end > k:'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     'xox[abposr]-(?=[A-Za-z0-9-]*\\d)',
     'xox[abposr]-'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     'AIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_-])',
     'AIza[A-Za-z0-9_-]*'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     'eyJ[A-Za-z0-9_-]{6,}\\.eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}',
     'eyJ[A-Za-z0-9_-]{6,}'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '([A-Za-z0-9+/=:,.\\s\\\\]+?)-----END',
     '([\\s\\S]+?)-----END'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '        if m.group(1).strip():',
     '        if True:'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '            if not (m.group(2) or _HEADER_FLAG.search(lead) or _HEADER_SCHEME.match(text, i)):\n                continue',
     '            if False:\n                continue'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '        if not mk_secret_name(m.group(1)):\n            continue',
     '        if False:\n            continue'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '        return -1 if end - i <= 2 or text[i + 1] == "$" else end',
     '        return end'),
    ('a redaction leaves what stands beside the secret', 'hooks/_sessions.sh',
     '    if j < n and text[j] not in " \\t\\r\\n,;})]#\\\\\\"\\x27":\n        return -1',
     '    if False:\n        return -1'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     'len(w) >= 16 or',
     'len(w) >= 99 or'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     ' and not w.isdigit()) else -1',
     ') else -1'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '(any(d.isdigit() for d in w)',
     '(True'),
    ('a word that holds a secret word keeps its value', 'hooks/_sessions.sh',
     'if s == w or (s.endswith(w) and (w != "KEY" or s[:-3] in MK_REDACT_BEFORE_KEY)):',
     'if s == w:'),
    ('a word that holds a secret word keeps its value', 'hooks/_sessions.sh',
     '(w != "KEY" or s[:-3] in MK_REDACT_BEFORE_KEY)',
     'True'),
    ('a word that holds a secret word keeps its value', 'hooks/_sessions.sh',
     '        for s in ((seg, seg[:-1]) if seg.endswith("S") else (seg,)):',
     '        for s in (seg,):'),
    ('a word that holds a secret word keeps its value', 'hooks/_sessions.sh',
     '_SEGMENT = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+")',
     '_SEGMENT = re.compile(r"[A-Za-z0-9]+")'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    while segs and segs[-1].isdigit():\n        segs.pop()',
     '    while False:\n        segs.pop()'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    last = segs[-1]\n    for w in MK_REDACT_WORDS:',
     '    last = max(segs, key=lambda x: x in MK_REDACT_WORDS)\n    for w in MK_REDACT_WORDS:'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '    last = segs[-1]\n    for w in MK_REDACT_WORDS:',
     '    last = segs[-1].rstrip("S")\n    for w in MK_REDACT_WORDS:'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '            return w != "KEY" or (len(segs) > 1 and segs[-2] in MK_REDACT_BEFORE_KEY)',
     '            return True'),
    ('the common secret shapes are not on the record', 'hooks/_sessions.sh',
     '        if last.endswith(w) and (w != "KEY" or last[:-3] in MK_REDACT_BEFORE_KEY):\n            return True',
     '        if False:\n            return True'),
    ('what the README says is not blacked out is not blacked out', 'hooks/_sessions.sh',
     '"SIGNING", "ENCRYPTION")',
     '"SIGNING", "ENCRYPTION", "STRIPE")'),
    ('what the README says is not blacked out is not blacked out', 'hooks/_sessions.sh',
     '_CURL = re.compile(r"(?<![A-Za-z0-9_.-])curl(?=[ \\t])")',
     '_CURL = re.compile(r"(?<![A-Za-z0-9_.-])[a-z]+(?=[ \\t])")'),
    ('what the README says is not blacked out is not blacked out', 'hooks/_sessions.sh',
     '_GLUE = re.compile(r"\\"[A-Za-z0-9._~+/@%!^*#-]*\\"|',
     '_GLUE = re.compile(r"\\"[^\\"\\s\\\\]*\\"|'),
    ('what the README says is not blacked out is not blacked out', 'README.md',
     'Other token forms: Stripe (',
     'Other token forms: ('),
    ('what the README says is not blacked out is not blacked out', 'README.md',
     'A header with no flag and no scheme word',
     'A header with neither flag nor scheme word'),
    ('what the README says is not blacked out is not blacked out', 'README.md',
     '(`Proc-Type: 4,ENCRYPTED`)',
     '(`ENCRYPTED`)'),
    ('the redactor stays linear on hostile input and never raises', 'hooks/_sessions.sh',
     '([A-Za-z0-9+/=:,.\\s\\\\]+?)-----END',
     '([A-Za-z0-9+/=:,.\\s\\\\-]+?)-----END'),
    ('the redactor stays linear on hostile input and never raises', 'hooks/_sessions.sh',
     '    for m in _CURL.finditer(text):\n        if m.start() < done:\n            continue',
     '    for m in _CURL.finditer(text):\n        if False:\n            continue'),
    ('the redactor stays linear on hostile input and never raises', 'hooks/_sessions.sh',
     '_KV_YAML = re.compile(r"(?:^[ \\t]*(?:-[ \\t]+)?|',
     '_KV_YAML = re.compile(r"(?:[ \\t]*(?:-[ \\t]+)?|'),
    ('the redactor stays linear on hostile input and never raises', 'hooks/_sessions.sh',
     '            lead = text[max(0, m.start() - 40):m.start()]',
     '            lead = text[:m.start()]'),
    ('the redactor stays linear on hostile input and never raises', 'hooks/_sessions.sh',
     '        return -1 if end - i <= 2 or text[i + 1] == "$" else end',
     '        return -1 if text[i + 1] == "$" or end - i <= 2 else end'),
    # MK-A6, the target of a write. One entry for each rule of the reading, so a rule that goes back
    # kills the assertion that holds it, and the neighbours in the same assertion say it was that rule.
    ("a path with .. is read the way the kernel reads it", "hooks/_classify.sh",
     '    */../*) if [ -z "${_mk_read:-}" ]; then _mk_landed "$_p" "${2-}"; return 0; fi ;;',
     '    */../*) : ;;'),
    # The walk takes the last component back. Without it .claude/.. stays under .claude.
    ("a path with .. is read the way the kernel reads it", "hooks/_classify.sh",
     '          */*) _wo=${_wo%/*}; [ -n "$_wo" ] || _wo=/ ;;\n          *) _wo= ;;',
     '          */*) _wo=${_wo%/*}; [ -n "$_wo" ] || _wo=/ ;;\n          *) : ;;'),
    # A process on the path with no link: what the silent path may not pay.
    ("a path with .. is read the way the kernel reads it", "hooks/_classify.sh",
     '_mk_abs() {\n  case $1 in',
     '_mk_abs() {\n  readlink /tmp >/dev/null 2>&1\n  case $1 in'),
    ("a symlink is read by where it lands", "hooks/_classify.sh",
     '          *)         _lr=${_p#*/.claude/}; _la=${_p%/.claude/"$_lr"}/.claude ;;\n        esac\n        if _mk_link_below "$_la" "$_lr"; then _mk_landed "$_p" "${2-}"; return 0; fi',
     '          *)         _lr=${_p#*/.claude/}; _la=${_p%/.claude/"$_lr"}/.claude ;;\n        esac\n        :'),
    ("a symlink is read by where it lands", "hooks/_classify.sh",
     '        if _mk_link_below "$_p" ""; then _mk_landed "$_p" "${2-}"; return 0; fi',
     '        :'),
    ("a symlink is read by where it lands", "hooks/_classify.sh",
     '          *)              _lr=; _la=$_p ;;\n        esac\n        if _mk_link_below "$_la" "$_lr"; then _mk_landed "$_p" "${2-}"; return 0; fi',
     '          *)              _lr=; _la=$_p ;;\n        esac\n        :'),
    # A link read as a pass when it cannot be read, the silent direction.
    ("a symlink is read by where it lands", "hooks/_classify.sh",
     '      _wl=$(readlink "$_mk_a" 2>/dev/null) && [ -n "$_wl" ] || return 1',
     '      _wl=$(readlink "$_mk_a" 2>/dev/null) && [ -n "$_wl" ] || { _wo=$_wx; continue; }'),
    # A self-link followed for ever would hang the hook, so the count is what ends it.
    ("a symlink is read by where it lands", "hooks/_classify.sh",
     '      [ "$_wn" -le 40 ] || return 1',
     '      [ "$_wn" -le 40 ] || { _wo=$_wx; continue; }'),
    # The verb that takes the link itself. Without it rm of a link is a false alarm.
    ("a symlink is read by where it lands", "hooks/_classify.sh",
     "      '@@n@@'*) _mk_nf=1; _t=${_t#@@n@@} ;;",
     "      '@@n@@'*) _t=${_t#@@n@@} ;;"),
    # The cwd the hook was handed, not its own.
    ("a symlink is read by where it lands", "hooks/role-guard.sh",
     'MK_CWD=${CWD:-}',
     'MK_CWD='),
    ("a quoted target is one path", "hooks/_classify.sh",
     '          for (k = j + 1; k < m; k++) s = s (k > j + 1 ? " " : "") $k',
     '          s = s $(j + 1)'),
    ("a quoted target is one path", "hooks/_classify.sh",
     '                                   qtab[++qnum] = qraw',
     '                                   qtab[++qnum] = ""'),
    ("a quoted target is one path", "hooks/_classify.sh",
     '(qnx != "" && qnx !~ /[ \\t;|&()<>]/ ? gl : "")',
     '""'),
    ("a quoted target is one path", "hooks/_classify.sh",
     '(qout != "" && qout !~ /[ \\t]$/ ? gl : "")',
     '""'),
    ("a quoted target is one path", "hooks/_classify.sh",
     '        if (qc == "\\\\" && substr(qs, qi + 1, 1) == " ") { qout = qout ss; qi += 2; continue }',
     ''),
    # Only a newline separates targets now: a space in the list is a space in a path.
    ("a quoted target is one path", "hooks/_classify.sh",
     "  _mk_ifs=$IFS\n  IFS='\n'\n",
     "  _mk_ifs=$IFS\n"),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '          if (w == "cd" || w == "pushd") cdread(i, hw)',
     '          if (0) cdread(i, hw)'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '        if (i > 1 && $(i - 1) ~ /[)`]$/) { cdir = ""; cdsoft = 0 }',
     ''),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '        if (w == uq) { cdir = ""; cdsoft = 0; continue }',
     '        if (w == uq) continue'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '      if (hw != "" && hw != "command" && hw != "builtin" && hw != "eval" && hw != "time" && hw != "sh" && hw != "bash" && hw != "zsh") {',
     '      if (0) {'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '                      else if (w != "&&" && w != "(" && w != "{" && w != "!") { cdir = ""; cdsoft = 0; cdx = 0 }',
     ''),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '        if (opens(w)) { cdir = ""; cdsoft = 0\n',
     '        if (opens(w)) {\n'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '          if (w == "fi" || w == "done" || w == "esac") { cdir = ""; cdsoft = 0 }',
     ''),
    # Behind a ; the disk decides. Believed, a cd that fails moves the target anyway.
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '        if [ -d "$_mk_a" ]; then _t=$_cd/$_cr;',
     '        if :; then _t=$_cd/$_cr;'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '                      if (w == ";") { if (cdir != "" && !cdx) cdsoft = (cdmade ? 0 : 1); cdx = 0 }',
     '                      if (w == ";") { }'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     'fpaths = ""; if (cdir != "" && !cdx) cdsoft = (cdmade ? 0 : 1); cdx = 0 }',
     'fpaths = "" }'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '      else if (d ~ /^[\\/~$]/) { cdir = cdpath(d); cdsoft = 0 }\n      else cdir = cdpath(cdir == "" ? d : cdir "/" d)',
     '      else { cdir = cdpath(d); cdsoft = 0 }'),
    ("a cd in the command moves a relative target", "hooks/_classify.sh",
     '        if (a[i] == ".." && k > 0 && st[k] != "..") { k--; continue }',
     ''),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     ' t == "touch" || t == "mkdir" ||',
     ' t == "mkdir" ||'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '              t == "chmod" || t == "chown" || t == "rmdir" || t == "touch" || t == "mkdir" ||',
     '              t == "chmod" || t == "chown" || t == "rmdir" || t == "touch" ||'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '        if (cmd && isoptwriter(w)) { tns = 1; optwrite(i + 1, w); tns = 0; continue }',
     ''),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     'vals = "AbcCdDeEFhHKmoPQrtTuUwxXyYz"; wv = "oDc"',
     'vals = "AbcCdDeEFhHKmoPQrtTuUwxXyYz"; wv = "Dc"'),
    # The value of an option that writes nothing: curl -d src/a.py sends a file.
    ("every writer the measure lists is read", "hooks/_classify.sh",
     'if (c == "wget" && (ch == "O" || ch == "P")) cwd = 0',
     'if (0) cwd = 0'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '        if (mode ~ /x/ && mode !~ /O/) {',
     '        if (mode ~ /x/) {'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '          if (f != "") wr(c, "-f", f); else why(c " writes its archive to stdout")',
     '          why(c " writes its archive to stdout")'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '            if (c == "unzip" && index(nw, ch)) { cwd = 0; continue }',
     ''),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '            else if (np >= 2 && cand[np] !~ /^[^\\/]*:/) { why(trig " writes its last operand, " cand[np]); tnf = 0; tgt(cand[np]); pr++ }',
     '            else if (np >= 2) { why(trig " writes its last operand, " cand[np]); tnf = 0; tgt(cand[np]); pr++ }'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '            if (cand[np] == "\\\\") { rs_pend = 1; pr++ }\n            else if (np >= 2',
     '            if (np >= 2'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '      if (c == "touch") a = "Adrt"; else if (c == "mkdir" || c == "mkfifo") a = "m"',
     '      if (c == "nobody") a = "x"'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '            else if (np) { why(trig " writes its first operand, " cand[1]); tgt(cand[1]); pr++ }',
     '            else if (np) { for (z = 1; z <= np; z++) tgt(cand[z]); pr++ }'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '            else { why(trig " names no file, so it writes the tree it stands in, and . is read"); tgt("."); pr++ }',
     ''),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '        if (cmd && w == "git" && gs && $gs == "clone") { tns = 1; clone_read(gs + 1); tns = 0; continue }',
     ''),
    # mkdir names a directory. Read as a file, mkdir -p .claude is a false alarm on the bare word.
    ("a quoted target is one path", "hooks/_classify.sh",
     '          tdir = (w == "mkdir")',
     '          tdir = 0'),
    # A new writer does not open the narrowing: 79 distinct commands of the corpus, 23 in a main session.
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '    if [ -z "$_mk_nn" ] && [ "$(MK_EXPLAIN=0; classify_path "$_t" strict)" = work ]; then',
     '    if [ "$(MK_EXPLAIN=0; classify_path "$_t" strict)" = work ]; then'),
    ("every writer the measure lists is read", "hooks/_classify.sh",
     '        if (rt != "" && rt !~ /^[^\\/]*:/) { why("the last line of this continued command',
     '        if (rt != "") { why("the last line of this continued command'),
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     '        if (w ~ /^([0-9]+|&)?>>?[|&]?/ && w !~ /^[0-9]+>=/) {\n          match(w, /^([0-9]+|&)?>>?[|&]?/);',
     '        if (w ~ /^>>?[|&]?/) {\n          match(w, /^>>?[|&]?/);'),
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     '          if (ro ~ /&$/ && (v ~ /^[0-9-]+([^A-Za-z0-9_.\\/].*)?$/ || (v == "" && i < NF && $(i + 1) ~ /^[0-9-]+$/))) continue',
     ''),
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     '          while (substr(w, 1, 1) == "(" && length(w) > 1 && substr(w, 2, 1) != "(") { w = substr(w, 2); depth++ }',
     ''),
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     '      if (depth > 0 && t ~ /\\)$/) sub(/\\)$/, "", t)',
     ''),
    # Glued to the operator, the variable behind it is still a variable.
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     '            rt = unclose(resolve(rt))',
     '            rt = unclose(rt)'),
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     '            if (v !~ qre && v ~ /[|&]/) sub(/[|&].*$/, "", rt)',
     ''),
    # A word the shell loop drops as no path is no path behind a cd either.
    ("a redirection is read in every spelling", "hooks/_classify.sh",
     ' && t !~ /^[0-9.:,)]*[0-9][0-9.:,)]*$/ && t !~ /^[=,#]$/ && (t ~ /\\// || t !~ /[)\\];:,]$/)) {',
     ') {'),
    ("an assignment is read in every spelling", "hooks/_classify.sh",
     '          if (w == "export" || w == "declare" || w == "typeset" || w == "readonly" || w == "local") {',
     '          if (0) {'),
    # A value in two pieces read as the first. It is the half MK-A5 line 81 stands on.
    ("an assignment is read in every spelling", "hooks/_classify.sh",
     '              if ($z ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { record(z); z = opend }',
     '              if ($z ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { z = NF }'),
    ("what the measure cannot read it says", "hooks/role-guard.sh",
     'model_reason = lead + booked + "Refused: " + subject + said + recheck',
     'model_reason = lead + booked + "Refused: " + subject + recheck'),
    ("what the measure cannot read it says", "hooks/role-guard.sh",
     '        "manager-kit stopped a write to %s.%s Stops %d, declared crossings %d%s."\n        % (subject, said, stops, crossings, tail)',
     '        "manager-kit stopped a write to %s.%s Stops %d, declared crossings %d%s."\n        % (subject, "", stops, crossings, tail)'),
    ("what the measure cannot read it says", "hooks/role-guard.sh",
     'said = (" " + mk_safe(unread, 400)) if unread else ""',
     'said = (" " + unread) if unread else ""'),
    ("what the measure cannot read it says", "hooks/role-guard.sh",
     '    [ -z "$UNREAD" ] || said="The target could not be read: spell the path out, or assign it in the same command. "',
     ''),
    ("what the measure cannot read it says", "hooks/role-guard.sh",
     "case $why in 'unreadable: '*) UNREAD=${why#unreadable: }; UNREAD=${UNREAD:0:1000} ;; esac",
     ''),
    ("what the measure cannot read it says", "hooks/_classify.sh",
     '            if ($(i + 1) == "(") rt = "$(...)"\n            else {',
     '            {'),
    ("what the measure cannot read it says", "hooks/_classify.sh",
     "      */*|'$('*) : ;;",
     "      */*) : ;;"),
    ("what the measure cannot read it says", "hooks/_classify.sh",
     '    _mk_why "unreadable: the command could not be read: it is ${#_s} characters long',
     '    _mk_why "the command is ${#_s} characters long'),
    ("a write in program text is read", "hooks/_classify.sh",
     '          if (name ~ /open$/) {\n            # The mode decides: it is the second argument, or mode= somewhere.',
     '          if (0) {\n            # The mode decides: it is the second argument, or mode= somewhere.'),
    # Every open a write: the false alarm this rule was told not to grow.
    ("a write in program text is read", "hooks/_classify.sh",
     '            if (m ~ /[wax+]/) tar(a[1])',
     '            tar(a[1])'),
    ("a write in program text is read", "hooks/_classify.sh",
     '            if (match(pre, "[A-Za-z_.]*\\\\([ \\t]*[rb]?" q2 "[^" sq dq "]*" q2 "[ \\t]*\\\\)$")) {',
     '            if (0) {'),
    ("a write in program text is read", "hooks/_classify.sh",
     '          else if (name ~ /\\.(move|rename|renames|replace)$/) { tar(a[1]); tar(a[2]) }',
     '          else if (name ~ /\\.(move|rename|renames|replace)$/) tar(a[1])'),
    ("a write in program text is read", "hooks/_classify.sh",
     '            js = "\\\\.(writeFile|writeFileSync|',
     '            js = "\\\\.(neverwritten|'),
    ("a write in program text is read", "hooks/_classify.sh",
     '            rb = "(File|IO)\\\\.(write|',
     '            rb = "(File|IO)\\\\.(neverwritten|'),
    ("a write in program text is read", "hooks/_classify.sh",
     '            pl = "(^|[^A-Za-z0-9_$])(open|unlink|',
     '            pl = "(^|[^A-Za-z0-9_$])(unlink|'),
    ("a write in program text is read", "hooks/_classify.sh",
     '            ak = "printf?[^;}\\n]*>>?[ \\t]*" dq "[^" dq "]+" dq',
     '            ak = "neverwritten"'),
    ("a write in program text is read", "hooks/_classify.sh",
     '        if (++hits > 64) { if (!pu_quiet) pw_add("@@p@@"); why(',
     '        if (++hits > 64) { why('),
    # A name the text assigns a literal is that literal. Without it p='src/r.py' goes quiet.
    ("a write in program text is read", "hooks/_classify.sh",
     '      if (l == "") l = named(t)',
     ''),
    ("a write in program text is read", "hooks/_classify.sh",
     '            } else if (match(pre, /[A-Za-z_][A-Za-z0-9_]*$/)) tar(substr(pre, RSTART))',
     '            }'),
    ("a write in program text is read", "hooks/_classify.sh",
     '      if (pw != "") insert(hline, hcol, pw)\n      hlang = ""',
     '      hlang = ""'),
    ("a write in program text is read", "hooks/_classify.sh",
     '        if (e) { pbuf = pbuf substr($0, 1, e - 1); prog_end() } else pbuf = pbuf $0 "\\n"',
     '        if (e) pq = ""; else pbuf = pbuf $0 "\\n"'),
    # The place of the word: at the head of the line, a cd in front of it would not count.
    ("a write in program text is read", "hooks/_classify.sh",
     '      if (pw != "") insert(pline, pcol, pw)',
     '      if (pw != "") insert(pline, 1, pw)'),
    ("a write in program text is read", "hooks/_classify.sh",
     '      prog(b, hlang)\n      if (pw != "")',
     '      if (pw != "")'),
    # MK-R1: the stop of git commit -a is taken back, and these turn it back. The first puts one line
    # in front of the clone arm that stops any commit with an -a in its own options; the second is the
    # sentence in README.md; the third is the old paragraph; the fourth leaves the old name behind in
    # the code, which the assertion also refuses.
    ("a commit is no write into the work", "hooks/_classify.sh",
     '        if (cmd && w == "git" && gs && $gs == "clone") { tns = 1; clone_read(gs + 1); tns = 0; continue }\n',
     '        if (cmd && w == "git" && gs && $gs == "commit" && owns(gs + 1, "^-[a-z]*a")) { print "@@p@@"; continue }\n'
     '        if (cmd && w == "git" && gs && $gs == "clone") { tns = 1; clone_read(gs + 1); tns = 0; continue }\n'),
    ("a commit is no write into the work", "README.md",
     'A commit is no write into the work, so it is free',
     'A commit is a write into the work, so it is stopped'),
    ("a commit is no write into the work", "README.md",
     '`git add -A && git commit` both pass',
     '`git commit -a` is the one that is stopped'),
    ("a commit is no write into the work", "hooks/_classify.sh",
     '# The measure, and it is the whole of it: a path, not a judgement and not a budget.',
     '# The measure, and it is the whole of it: a path. function commit_all(start) is gone.'),
    # MK-R1: the glued redirection. The first turns the whole split off; the others take back one exception each.
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '      if (glue_ok && index($0, ">")) glue_split(qopen)\n',
     '      if (0) glue_split(qopen)\n'),
    # MK-R1b: this line had five conditions, and the entry that took all of them back stayed alive because none of
    # them was held by a case. oq, cq and uq were dead (the scan lays them as words of their own, a > never
    # stands behind one) and are gone. The one left that is held is pm, a target a program text writes that carries a >:
    # this entry takes back that one and nothing else. The ( on the same line has NO entry on purpose: it hides
    # (>src/a.py), a write, so the right verdict for it is the other one, and an entry has to turn a measure back
    # toward the worse. It is named as a finding in .claude/uebergabe/MK-R1b.md.
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '      if ((c == "(" && substr(w, 2, 1) == "(") || c == pm) return 0\n',
     '      if ((c == "(" && substr(w, 2, 1) == "(")) return 0\n'),
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '      if (c == "=" || c == "-" || c == "<" || c == "|") return 0\n',
     ''),
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '      if (r == "=") return 0\n',
     ''),
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '      if (index(pre, "${") && !index(pre, "}")) return 0\n',
     ''),
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '      if (c == "&") return (length(pre) > 1 ? p - 1 : 0)\n',
     ''),
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '        if (w == "[[" || w == "((" || (w == "(" && i > 1 && $(i - 1) == "(")) db = 1\n',
     ''),
    ("a redirection glued to its word is read", "hooks/_classify.sh",
     '        if (db && (w ~ /^\\]\\]/ || w ~ /^\\)\\)/)) db = 0\n',
     ''),
    # MK-R1: a > glued to a word where the scan cannot tell text from syntax. Each one takes back one of the guards:
    # the stop at the word that holds the open quote, the state kept from line to line (set, kept inside, cleared by
    # an odd number of quotes), the escaped quote, the escaped >, and the placeholder, once removed and once widened.
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      if (glue_ok && index($0, ">")) glue_split(qopen)' + "\n",
     r'      if (glue_ok && index($0, ">")) glue_split("")' + "\n"),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      } else if (qopen != "") mlq = qopen' + "\n",
     r'      }' + "\n"),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'        if (qk % 2 == 1) mlq = ""' + "\n",
     r'        mlq = ""' + "\n"),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      if (mlq != "") {' + "\n" + r'        glue_ok = 0' + "\n",
     r'      if (mlq != "") {' + "\n"),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      if (index(qorig, "\\" dq) || index(qorig, "\\" sq)) glue_ok = 0' + "\n",
     ''),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      if (c == "\\") return 0' + "\n",
     ''),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      if (pre ~ /(^|[^A-Za-z0-9_])</) return 0' + "\n",
     ''),
    ("a glued > in quoted text is text", "hooks/_classify.sh",
     r'      if (pre ~ /(^|[^A-Za-z0-9_])</) return 0' + "\n",
     r'      if (index(pre, "<")) return 0' + "\n"),
    # MK-R1: a cd that cannot have failed. One mutation for each of the things that make it hold.
    ("a cd that cannot have failed holds", "hooks/_classify.sh",
     '                      else if (w == "||" && cdir != "" && cdexit(i + 1)) cdx = 1\n',
     ''),
    ("a cd that cannot have failed holds", "hooks/_classify.sh",
     '      cdx = 0; cdmade = (cdir != "" && cdcovered(cdir))\n',
     '      cdmade = (cdir != "" && cdcovered(cdir))\n'),
    ("a cd that cannot have failed holds", "hooks/_classify.sh",
     'fpaths = ""; if (cdir != "" && !cdx) cdsoft = (cdmade ? 0 : 1); cdx = 0 }',
     'fpaths = ""; if (cdir != "") cdsoft = (cdmade ? 0 : 1); cdx = 0 }'),
    ("a cd that cannot have failed holds", "hooks/_classify.sh",
     'if (tdir) made_add(cand[z]); ',
     ''),
    ("a cd that cannot have failed holds", "hooks/_classify.sh",
     '      cdx = 0; cdmade = (cdir != "" && cdcovered(cdir))\n',
     '      cdx = 0; cdmade = (cdir != "")\n'),
    # MK-R1: the budget. The first puts back the split of the whole text per quote; the second the scan of the
    # rest of the line per write; the third the count of every mention.
    ("a hostile command is read inside the hook budget", "hooks/_classify.sh",
     r"""      n = length(pre)
      while (n > 0 && (substr(pre, n, 1) == " " || substr(pre, n, 1) == "\t")) n--
      if (n < 2 || substr(pre, n, 1) != "c") return 0
      j = n - 1
      while (j > 0 && substr(pre, j, 1) ~ /[A-Za-z]/) j--
      if (j < 1 || substr(pre, j, 1) != "-" || (j > 1 && substr(pre, j - 1, 1) !~ /[ \t]/)) return 0
      n = length(pre)
      f = 1
      if (n > cmdwin) { pre = substr(pre, n - cmdwin + 1); f = 2 }
""",
     '      f = 1\n'),
    ("a hostile command is read inside the hook budget", "hooks/_classify.sh",
     '            if ($z ~ /[;|&]/ || $z == "(" || $z == ")") break\n            if ($z == "-t"',
     '            if ($z == "-t"'),
    ("a hostile command is read inside the hook budget", "hooks/_classify.sh",
     '; [ "$_nq" -lt 2 ] || break ;; *) break ;; esac',
     '; ;; *) break ;; esac'),
    # MK-ZEIT: a burn just over the limit, not a blow-up. The check holds the CPU of a command of the forms' length against
    # 4 s, asks again what is over and stretches the limit by how much slower the machine is than quiet; the entries above
    # are far past any stretch the cap allows, this one is the size a stretch could excuse, and at the quiet of a run
    # of its own (stretch 1) it must stay red. 900000 turns of a bash 3.2 loop are about 2.4 s of CPU on top of the 2.7.
    ("a hostile command is read inside the hook budget", "hooks/_classify.sh",
     'classify_bash() {\n  _c=${1-}\n',
     'classify_bash() {\n  _c=${1-}\n  if [ "${#_c}" -gt 60000 ]; then _i=0; while [ "$_i" -lt 900000 ]; do _i=$((_i + 1)); done; fi\n'),
    # MK-R1: the walk back to the -c in front of a quote. The first is the first repair of the budget, the last 64
    # characters, put back: a -c behind 70 blanks or inside an option of 70 letters is not found and its body is
    # text. The other two are the loud answers of the window of cmdwin characters, which the shapes past it need.
    ("a shell option is found behind any padding", "hooks/_classify.sh",
     r"""      n = length(pre)
      while (n > 0 && (substr(pre, n, 1) == " " || substr(pre, n, 1) == "\t")) n--
      if (n < 2 || substr(pre, n, 1) != "c") return 0
      j = n - 1
      while (j > 0 && substr(pre, j, 1) ~ /[A-Za-z]/) j--
      if (j < 1 || substr(pre, j, 1) != "-" || (j > 1 && substr(pre, j - 1, 1) !~ /[ \t]/)) return 0
      n = length(pre)
""",
     r"""      n = length(pre)
      t = (n > 64 ? substr(pre, n - 63) : pre)
      if (t !~ /-[A-Za-z]*c[ \t]*$/) return 0
"""),
    ("a shell option is found behind any padding", "hooks/_classify.sh",
     '      if (k < f + 1) return (f > 1)\n',
     '      if (k < f + 1) return 0\n'),
    ("a shell option is found behind any padding", "hooks/_classify.sh",
     '      if (m < f) return (f > 1)\n',
     '      if (m < f) return 0\n'),
    # MK-R1: the number of targets, counted in the loop. One off by one, one that moves the limit out of reach.
    ("a command naming too many targets is not let through", "hooks/_classify.sh",
     '    if [ "$_mk_nt" -gt "$MK_TARGET_LIMIT" ]; then',
     '    if [ "$_mk_nt" -ge "$MK_TARGET_LIMIT" ]; then'),
    ("a command naming too many targets is not let through", "hooks/_classify.sh",
     '    if [ "$_mk_nt" -gt "$MK_TARGET_LIMIT" ]; then',
     '    if [ "$_mk_nt" -gt 99999999 ]; then'),
    # The first version of the count, put back: the same verdicts, and 39 s for 8000 targets in bash 3.2. Only the
    # assertion that asks for the time can see it.
    ("a command naming too many targets is not let through", "hooks/_classify.sh",
     "  _mk_nt=0\n  _mk_ifs=$IFS\n",
     "  _mk_nt=0\n  if [ -n \"$_targets\" ]; then\n    _mk_nl=${_targets//$'\\n'/}\n"
     "    if [ $(( ${#_targets} - ${#_mk_nl} )) -ge \"$MK_TARGET_LIMIT\" ]; then printf 'work\\n'; return 0; fi\n  fi\n  _mk_ifs=$IFS\n"),
    # MK-ZEIT: eight seconds at the target that is the limit, against the six the check allows a command of that many. Not a
    # sleep on every call: only a command that reaches the limit pays, so the rest of the suite is not slowed with it.
    ("a command naming too many targets is not let through", "hooks/_classify.sh",
     '    _mk_nt=$((_mk_nt + 1))\n    if [ "$_mk_nt" -gt "$MK_TARGET_LIMIT" ]; then',
     '    _mk_nt=$((_mk_nt + 1))\n    if [ "$_mk_nt" -eq "$MK_TARGET_LIMIT" ]; then sleep 8; fi\n    if [ "$_mk_nt" -gt "$MK_TARGET_LIMIT" ]; then'),
    ("a target is read alike under any locale", "hooks/_classify.sh",
     '  _s=$(printf \'%s\' "$_c" | LC_ALL=C awk -v explain="${MK_EXPLAIN:-0}" "$_mk_p"\'',
     '  _s=$(printf \'%s\' "$_c" | awk -v explain="${MK_EXPLAIN:-0}" "$_mk_p"\''),
    ("the documents name what the measure cannot read", "README.md",
     'This is protection against a slip, not a sandbox',
     'This is protection'),
    ("the documents name what the measure cannot read", "README.md",
     '`curl -o`',
     '`curl`'),
    # MK-A7: the week says only what it knows, reads the stand it is told to, and reads its log through the door.
    ('a quiet week is not called held', 'tools/week-verdict.sh',
     '). This command cannot tell which.")',
     '). The coordinator never reached for a work path with its own hands.")'),
    ('a fired week states what the log holds', 'tools/week-verdict.sh',
     '% (stops, crossings))',
     '% (crossings, crossings))'),
    ('a fired week states what the log holds', 'tools/week-verdict.sh',
     'print("Done-when 2 wants more than a stop: that the work was then handed out, or the crossing")',
     'print("Done-when 2 is satisfied: that the work was then handed out, or the crossing")'),
    ('the week is read from the stand it is told to', 'tools/week-verdict.sh',
     '--format=%H "${HSHA:-HEAD}" --',
     '--format=%H HEAD --'),
    ('the week is read from the stand it is told to', 'tools/week-verdict.sh',
     '  if [ -z "$HSHA" ]; then\n    printf \'week-verdict: --ref %s names no commit',
     "  if false; then\n    printf 'week-verdict: --ref %s names no commit"),
    ('the week is read from the stand it is told to', 'tools/week-verdict.sh',
     "    ''|-*)\n",
     "    '')\n"),
    ('a window behind its upstream says so in one line', 'tools/week-verdict.sh',
     'if [ "$BEHIND" -gt 0 ]; then',
     'if [ "$BEHIND" -lt 0 ]; then'),
    ('a window behind its upstream says so in one line', 'tools/week-verdict.sh',
     '  UP=$(git -C "$PROJECT" rev-parse --abbrev-ref --symbolic-full-name',
     '  git -C "$PROJECT" fetch -q 2>/dev/null\n  UP=$(git -C "$PROJECT" rev-parse --abbrev-ref --symbolic-full-name'),
    ('a log that is no plain file is not read', 'tools/week-verdict.sh',
     'TROUBLE=$(mk_record_trouble "$PROJECT")',
     'TROUBLE='),
    ('every read and write under .claude goes through the door', 'tools/week-verdict.sh',
     'os.fdopen(mk_file(mk_home(os.environ["MK_DOOR_ROOT"]), "manager-kit.log", os.O_RDONLY), "rb")',
     'open(log, "rb")'),
    ('the week prints a path and a ref the same under any locale', 'tools/week-verdict.sh',
     'pathline("guard log:                NOT READ at ", log)',
     'print("guard log:                NOT READ at %s" % log)'),
    # MK-R2: the project's own files. One entry per assertion and per shape that has its own way to die.
    ('a big file in the project holds no hook', 'hooks/_sessions.sh',
     '  [ -r "$1" ] || return 1\n  mk_kit_small "$1"\n}\n',
     '  [ -r "$1" ]\n}\n'),
    ('a big file in the project holds no hook', 'hooks/_sessions.sh',
     '  [ "${#_ks_buf}" -le "$MK_KIT_SMALL" ]\n',
     '  [ "${#_ks_buf}" -le 99999999 ]\n'),
    ('a big file in the project holds no hook', 'hooks/_sessions.sh',
     "read -r -n $((MK_KIT_SMALL + 1)) -d '' _ks_buf",
     "read -r -d '' _ks_buf"),
    ('a big file in the project holds no hook', 'hooks/_sessions.sh',
     '    if [ -f "${1-}/.claude/$_rt_n" ] && ! mk_kit_small "${1-}/.claude/$_rt_n"; then\n',
     '    if false; then\n'),
    ('a big file in the project holds no hook', 'hooks/role-guard.sh',
     '    counted = len(data) <= cap\n',
     '    counted = True\n'),
    ('a big file in the project holds no hook', 'hooks/role-guard.sh',
     '        data = fh.read(cap + 1)\n',
     '        data = fh.read(cap)\n'),
    ('a .git file names its own repository or nothing', 'hooks/_sessions.sh',
     '              [ "$_bp" -ef "$_w/.git" ] || _main=""\n',
     '              :\n'),
    ('a .git file names its own repository or nothing', 'hooks/_sessions.sh',
     '              case $_bp in /*) ;; *) _bp=$_gd/$_bp ;; esac\n',
     '              case $_bp in /*) ;; *) ;; esac\n'),
    ('a .git file names its own repository or nothing', 'hooks/_sessions.sh',
     '              [ "$_bp" -ef "$_w/.git" ] || _main=""\n',
     '              [ "$_bp" = "$_w/.git" ] || _main=""\n'),
    ('a .git file names its own repository or nothing', 'hooks/_sessions.sh',
     '              [ "$_bp" -ef "$_w/.git" ] || _main=""\n',
     '              _main=""\n'),
    ('a .git file names its own repository or nothing', 'hooks/_sessions.sh',
     '    if [ -f "$_w/.git" ] || [ -f "$_w/.git/HEAD" ]; then\n',
     '    if [ -e "$_w/.git" ]; then\n'),
    ('a .git file names its own repository or nothing', 'hooks/_sessions.sh',
     '    if [ -f "$_w/.git" ] || [ -f "$_w/.git/HEAD" ]; then\n',
     '    if [ -f "$_w/.git/HEAD" ]; then\n'),
    ('a session inside the home .claude or above a linked home keeps no record', 'hooks/_sessions.sh',
     '      case "$MK_ROOT/" in */.claude/*) MK_ROOT=$_w ;; esac\n',
     '      :\n'),
    ('a session inside the home .claude or above a linked home keeps no record', 'hooks/_sessions.sh',
     '    [ "${1-}" -ef "$_rb_d" ] && return 0\n',
     '    :\n'),
    ('a session inside the home .claude or above a linked home keeps no record', 'hooks/_sessions.sh',
     '    [ "${1-}" -ef "$_rb_d" ] && return 0\n',
     '    return 0\n'),
    ('a session inside the home .claude or above a linked home keeps no record', 'hooks/_sessions.sh',
     '      case "$MK_ROOT/" in */.claude/*) MK_ROOT=$_w ;; esac\n',
     '      MK_ROOT=$_w\n'),
    ('a hardlink under .claude is not written through', 'hooks/_sessions.sh',
     '    if not stat.S_ISREG(st.st_mode) or st.st_nlink > 1:\n',
     '    if not stat.S_ISREG(st.st_mode):\n'),
    ('a hardlink under .claude is not written through', 'hooks/role-guard.sh',
     '        if stat.S_ISREG(st.st_mode) and st.st_nlink > 1:\n            hard = name\n',
     '        if False:\n            hard = name\n'),
    ('the files of the kit are all in the exclusion', 'hooks/_sessions.sh',
     'b"/.claude/manager-kit.seen", ',
     ''),
    ('the files of the kit are all in the exclusion', 'hooks/_sessions.sh',
     'b"/.claude/manager-kit.role", ',
     ''),
    ('the files of the kit are all in the exclusion', 'hooks/_sessions.sh',
     ', b"/.claude/manager-exception")',
     ')'),
    ('the files of the kit are all in the exclusion', 'hooks/_sessions.sh',
     'b"/.claude/manager-exception")',
     'b"/.claude/manager-*")'),
    ('a field of the log line cannot move into another', 'hooks/_sessions.sh',
     '  printf \'%s\\0%s\\0%s\\0%s\' "$_le_ev" "$_le_tool" "$_le_subject" "$_le_reason" |\n    MK_DOOR_ROOT=$_le_root python3 -I -c "$MK_PY_DOOR$MK_PY_REDACT"\'\nimport sys, json, time\n# Bytes and UTF-8, not the locale: under ISO8859-1 the path went on the record as mit-\\xc3\\xa4 in\n# characters, and under US-ASCII the line was lost and the call that wrote it never knew [measured\n# 2026-11-06 at 0bc14fe]. A byte that is no UTF-8 goes on the record as the escape it always was\n# under C, so the shape of a line is what it was and every older log reads the same.\n# NUL separates the fields: a shell variable cannot hold one, so no field can carry the separator in. It was\n# the unit separator, and a tool name with one in it moved the fields after it [measured 2026-11-07].\nparts = sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\\x00", 3)\n',
     '  printf \'%s\\037%s\\037%s\\037%s\' "$_le_ev" "$_le_tool" "$_le_subject" "$_le_reason" |\n    MK_DOOR_ROOT=$_le_root python3 -I -c "$MK_PY_DOOR$MK_PY_REDACT"\'\nimport sys, json, time\n# Bytes and UTF-8, not the locale: under ISO8859-1 the path went on the record as mit-\\xc3\\xa4 in\n# characters, and under US-ASCII the line was lost and the call that wrote it never knew [measured\n# 2026-11-06 at 0bc14fe]. A byte that is no UTF-8 goes on the record as the escape it always was\n# under C, so the shape of a line is what it was and every older log reads the same.\n# NUL separates the fields: a shell variable cannot hold one, so no field can carry the separator in. It was\n# the unit separator, and a tool name with one in it moved the fields after it [measured 2026-11-07].\nparts = sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\\x1f", 3)\n'),
    ('a field of the log line cannot move into another', 'tools/manager-claim.sh',
     "tr -d '\\000-\\037\\177'",
     "tr -d '\\000\\037\\177'"),
    ('every python3 call in a hook or tool runs isolated', 'commands/take-over.md',
     "python3 -I - <<'PY'",
     "python3 - <<'PY'"),
    ('a big file in the project holds no hook', 'hooks/_sessions.sh',
     '        IFS= read -r -n "$MK_KIT_SMALL" _gl 2>/dev/null',
     '        IFS= read -r _gl 2>/dev/null'),
    ('a big file in the project holds no hook', 'hooks/_sessions.sh',
     'IFS= read -r -n "$MK_KIT_SMALL" _bp 2>/dev/null',
     'IFS= read -r _bp 2>/dev/null'),
    # MK-R2 continued: the neighbours of the big file. The route log is counted whole again, or read to the cap
    # and counted anyway, and the refusal prints a number it cannot stand behind.
    ("a big log, definition or settings file holds no hook", "hooks/route-guard.sh", "    counted = len(data) <= cap\n", "    counted = True\n"),
    ("a big log, definition or settings file holds no hook", "hooks/route-guard.sh", "        data = fh.read(cap + 1)\n", "        data = fh.read(cap)\n"),
    # A definition is read whole again, so a key a long way down an unclosed frontmatter is found.
    ("a big log, definition or settings file holds no hook", "hooks/_routing.sh", "text = fh.read(DEF_HEAD)", "text = fh.read()"),
    # And read too short to hold a frontmatter, the other way: a definition loses its effort and model.
    ("a big log, definition or settings file holds no hook", "hooks/_routing.sh", "DEF_HEAD = 65536\n", "DEF_HEAD = 16\n"),
    # The settings file is read whole again.
    ("a big log, definition or settings file holds no hook", "hooks/_sessions.sh", '_ns_head=$(dd if="$_ns_f" bs=$((MK_SETTINGS_CAP + 1)) count=1 2>/dev/null)', '_ns_head=$(cat -- "$_ns_f" 2>/dev/null)'),
    # A file past the cap answers 1, which the report reads as "not set".
    ("a big log, definition or settings file holds no hook", "hooks/_sessions.sh", '  [ "$_ns_big" = 0 ] || return 2\n', '  [ "$_ns_big" = 0 ] || return 1\n'),
    # The word is no longer looked for in what was read.
    ("a big log, definition or settings file holds no hook", "hooks/_sessions.sh", '    case $_ns_head in *"${1-}"*) return 0 ;; esac\n', ''),
    # The report does not know the third answer.
    ("a big log, definition or settings file holds no hook", "hooks/_identity.sh", "      2) printf '\\nA settings file of this project", "      9) printf '\\nA settings file of this project"),
    # MK-R4: the temp of a run, and the full mutation run.
    # The EXIT trap is gone: a run that ends by itself leaves its root.
    ("a suite run to its end leaves nothing in its temp", "tests/run.sh", "trap mk_cleanup EXIT\n", ":\n"),
    # A path made outside the root is no longer recorded, so the fixture under /tmp stays there.
    ("a suite run to its end leaves nothing in its temp", "tests/run.sh",
     "/?*) printf '%s\\n' \"$_out\" >> \"$MK_EXTRA\" ;; esac\n", "/?*) ;; esac\n"),
    # TERM is no longer caught: the shell dies where it stands and the root with it.
    ("a suite taken off leaves nothing in its temp", "tests/run.sh", "trap 'mk_cleanup; exit 143' TERM\n", ":\n"),
    # INT and HUP likewise.
    ("a suite taken off leaves nothing in its temp", "tests/run.sh", "trap 'mk_cleanup; exit 130' INT\n", ":\n"),
    ("a suite taken off leaves nothing in its temp", "tests/run.sh", "trap 'mk_cleanup; exit 129' HUP\n", ":\n"),
    # A name that no check carries ends green with no check run.
    ("one named check runs alone and an unknown name is red", "tests/run.sh",
     'if [ "$((PASSED + FAILED))" -lt 1 ]; then printf', 'if [ "$((PASSED + FAILED))" -lt 0 ]; then printf'),
    # The first red check does not end the run.
    ("the first red check ends a run asked to stop there", "tests/run.sh",
     "[ -z \"${MK_STOP_AT_RED-}\" ] || { printf '\\nRED: stopped at the first red check\\n'; exit 1; }\n", ":\n"),
    # An entry that has ended keeps its root.
    ("a mutation run leaves nothing in its temp", "tests/mutate.py",
     "        remove_root(root)\n        with _lock:\n            _roots.discard(root)\n",
     "        with _lock:\n            _roots.discard(root)\n"),
    # The signal handlers are not installed: TERM ends the runner with its entries standing.
    ("a mutation run leaves nothing in its temp", "tests/mutate.py",
     "        signal.signal(s, handler)\n", "        pass\n"),
    # The last sweep of the group is gone, and what a check started and told to ignore TERM stays alive.
    ("a mutation run leaves nothing in its temp", "tests/mutate.py",
     "        os.killpg(proc.pid, signal.SIGKILL)\n", "        pass\n"),
    # An entry past its limit is called red.
    ("a mutant past its limit is a class of its own", "tests/mutate.py",
     # The anchors of the next three are cut in two: written whole, each stands a second time in this entry.
     '"TIMEOUT", "no verdict' + ' within %s s" % timeout', '"RED", "no verdict within %s s" % timeout'),
    # Results come back in the order they ended and not the order of the register.
    ("runs side by side judge every entry as runs one after the other do", "tests/mutate.py",
     "        out[i] = res\n", "        out[out.index(None)] = res\n"),
    # The own check is asked with all the others.
    ("the own check of an entry is asked first and alone", "tests/mutate.py",
     "dict(env, MK_ONLY_" + "CHECK=name), timeout, suite)", "env, timeout, suite)"),
    # An own check that lived is not looked behind.
    ("the own check of an entry is asked first and alone", "tests/mutate.py",
     "            if not late and name not in dead:\n", "            if False:\n"),
    # The look behind a living own check does not stop at the first red one.
    ("the own check of an entry is asked first and alone", "tests/mutate.py",
     'dict(env, MK_STOP_AT_' + 'RED="1")', "env"),
    # The report no longer names the anchor.
    ("the report of a run names every entry that is not red", "tests/mutate.py",
     '            lines.append("  anchor  %s" % (repr(r["anchor"])[:160] if r["anchor"] is not None else "(an append)"))\n',
     "            pass\n"),
    # The replacement of "the verdict comes from the whole command" starts an attempt at every letter again.
    # The anchor is cut in two so that this entry's own text does not hold it a second time. Without the lookbehind an
    # attempt starts at every letter and the lookahead runs to the end of the word each time: quadratic again.
    ("the whole command mutant reads a long command in linear time", "tests/mutate.py",
     "(?<![a-z_])(?=[a-z_]" + "*?(?:key", "(?=[a-z_]*?(?:key"),
    # MK-R4: where the root may lie.
    # The two anchors are the two halves of one line, side by side, so that neither edit takes the other's anchor away.
    ("the root of a run is never inside a project or a .claude", "tests/run.sh",
     'if [ -e "$_mkw/.git" ] || ', 'if '),
    ("the root of a run is never inside a project or a .claude", "tests/run.sh",
     '[ -e "$_mkw/.claude" ]; then _mkb=/tmp', 'false; then _mkb=/tmp'),
    ("the root of a run is never inside a project or a .claude", "tests/run.sh",
     '    _mkw=$(dirname "$_mkw")\n', '    break\n'),
    ("the runner keeps its roots out of a project and a .claude", "tests/mutate.py",
     "        parent = os.path.dirname(d)\n        if parent == d:\n            return base\n        d = parent\n",
     "        return base\n"),
    # MK-R4: the probe does not depend on how its caller was started.
    # The child of the probe is no longer given its signals at their default: what the caller ignored stays ignored in it.
    ("the temp probe does not depend on how its caller was started", "tests/run.sh",
     ",\n                             preexec_fn=lambda: [signal.signal(s, signal.SIG_DFL) for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)])",
     ")"),
    # One signal of the three is left out of the reset, each in turn. The three anchors are one line with three replacements.
    ("the temp probe does not depend on how its caller was started", "tests/run.sh",
     "for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)])", "for s in (signal.SIGINT, signal.SIGHUP)])"),
    ("the temp probe does not depend on how its caller was started", "tests/run.sh",
     "for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)])", "for s in (signal.SIGTERM, signal.SIGHUP)])"),
    ("the temp probe does not depend on how its caller was started", "tests/run.sh",
     "for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)])", "for s in (signal.SIGTERM, signal.SIGINT)])"),
    # MK-R5. One turn back of each repair, the smallest edit that restores the defect. Each anchor resolves once.
    ('a project whose name ends in a newline keeps its record in itself', 'hooks/role-guard.sh',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n',
     'ROOT=$(mk_project_root "${CWD:-$PWD}")\n'),
    ('a project whose name ends in a newline keeps its record in itself', 'hooks/route-guard.sh',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n',
     'ROOT=$(mk_project_root "${CWD:-$PWD}")\n'),
    ('a project whose name ends in a newline keeps its record in itself', 'hooks/manager-stamp.sh',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n',
     'ROOT=$(mk_project_root "${CWD:-$PWD}")\n'),
    ('a project whose name ends in a newline keeps its record in itself', 'hooks/manager-prime.sh',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n',
     'ROOT=$(mk_project_root "${CWD:-$PWD}")\n'),
    ('a project whose name ends in a newline keeps its record in itself', 'hooks/manager-reinject.sh',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n',
     'ROOT=$(mk_project_root "${CWD:-$PWD}")\n'),
    ('a project whose name ends in a newline keeps its record in itself', 'tools/week-verdict.sh',
     'mk_project_root_set "$GIVEN"; PROJECT=$MK_ROOT\n',
     'PROJECT=$(mk_project_root "$GIVEN")\n'),
    ('a project whose name ends in a newline keeps its record in itself', 'tools/week-verdict.sh',
     'GIVEN=$(CDPATH= cd -- "$PROJECT" && pwd -P && printf x) || exit 2\nGIVEN=${GIVEN%x}; GIVEN=${GIVEN%?}\n',
     'GIVEN=$(CDPATH= cd -- "$PROJECT" && pwd -P) || exit 2\n'),
    ('a take-over off an escaped path lands in the project or is refused', 'tools/manager-claim.sh',
     'mk_project_root_set "$SESSION_DIR"; ROOT=$MK_ROOT\n',
     'ROOT=$(mk_project_root "$SESSION_DIR")\n'),
    ('a gitdir naming no repository keeps the worktree', 'hooks/_sessions.sh',
     '        if [ -n "$_main" ] && [ "$_main/.git/worktrees/$_wtn" -ef "$_gd" ] &&\n',
     '        if [ -n "$_main" ] && [ -d "$_main/.git" ] &&\n'),
    ('a gitdir naming no repository keeps the worktree', 'hooks/_sessions.sh',
     '        if [ -n "$_main" ] && [ "$_main/.git/worktrees/$_wtn" -ef "$_gd" ] &&\n',
     '        if [ -n "$_main" ] &&\n'),
    ('a redirection glued to its word is read', 'hooks/_classify.sh',
     '      if ((c == "(" && substr(w, 2, 1) == "(") || c == pm) return 0\n',
     '      if (c == "(" || c == pm) return 0\n'),
    ('a redirection glued to its word is read', 'hooks/_classify.sh',
     '      if ((c == "(" && substr(w, 2, 1) == "(") || c == pm) return 0\n',
     '      if (c == pm) return 0\n'),
    ('the week says what it knows and refuses what it did not understand', 'tools/week-verdict.sh',
     '    -*) [ -n "$BAD_OPT" ] || BAD_OPT=$1 ;;\n',
     '    -*) : ;;\n'),
    ('the week says what it knows and refuses what it did not understand', 'tools/week-verdict.sh',
     '    --since) shift; SINCE=${1-}; SINCE_N=$((SINCE_N + 1)) ;;\n',
     '    --since) shift; SINCE=${1-} ;;\n'),
    ('the week says what it knows and refuses what it did not understand', 'tools/week-verdict.sh',
     '    --until) shift; UNTIL=${1-}; UNTIL_GIVEN=1; UNTIL_N=$((UNTIL_N + 1)) ;;\n',
     '    --until) shift; UNTIL=${1-}; UNTIL_GIVEN=1 ;;\n'),
    ('the week says what it knows and refuses what it did not understand', 'tools/week-verdict.sh',
     'or never have run, or the file may have been removed or moved after it ran.")\n',
     'or never have run.")\n'),
    ('the week says what it knows and refuses what it did not understand', 'tools/week-verdict.sh',
     '    print("when it counts, and those are two different wirings. This command cannot tell")\n',
     '    print("when it counts, and those are two different wirings. Fix the wiring before")\n'),
    ('the week prints a path and a ref the same under any locale', 'tools/week-verdict.sh',
     '    pathline("guard log:                MISSING at ", log)\n',
     '    print("guard log:                MISSING at %s" % log)\n'),
    ('a cheap model is the cheap model in any spelling', 'hooks/_routing.sh',
     '    *[Hh][Aa][Ii][Kk][Uu]*) printf \'stop own %s\\n\' "$_rv_effort"; return 0 ;;\n',
     '    *haiku*) printf \'stop own %s\\n\' "$_rv_effort"; return 0 ;;\n'),
    ('a cheap model is the cheap model in any spelling', 'hooks/_routing.sh',
     '    *[Hh][Aa][Ii][Kk][Uu]*) printf \'stop own %s\\n\' "$_rv_effort"; return 0 ;;\n',
     '    haiku) printf \'stop own %s\\n\' "$_rv_effort"; return 0 ;;\n'),
    ('a cheap model is the cheap model in any spelling', 'hooks/_routing.sh',
     '    *[Hh][Aa][Ii][Kk][Uu]*) printf \'stop own %s\\n\' "$_rv_effort"; return 0 ;;\n',
     '    *?*) printf \'stop own %s\\n\' "$_rv_effort"; return 0 ;;\n'),
    ('no fixture types the name of the kit', 'tests/run.sh',
     'route_pass "$d" haiku ${KITP}:low-readonly \'not the repair hand\'',
     'route_pass "$d" haiku manager-kit:low-readonly \'not the repair hand\''),
    # MK-R6, the glued redirection behind a closed arithmetic: ((x>src/a))>src/b.py writes src/b.py. The first takes the whole
    # of it back, the second counts only the two ( that open it, so a pair of its own inside, ((x>(a+1)))>f, ends it too soon
    # (the plain rows live on it, which is what makes it hold the nested row alone), and the last two read a > and nothing
    # else behind it.
    ('a redirection glued to its word is read', 'hooks/_classify.sh',
     '      if (c == "(" && substr(w, 2, 1) == "(" && (r = arith_tail(w))) return r\n',
     ''),
    ('a redirection glued to its word is read', 'hooks/_classify.sh',
     '        if (ch == "(") d++\n',
     '        if (ch == "(" && i < 3) d++\n'),
    ('a redirection glued to its word is read', 'hooks/_classify.sh',
     '      return (substr(w, i + 1) ~ /^([0-9]*|&)>/ ? i + 1 : 0)\n',
     '      return (substr(w, i + 1) ~ /^(&)>/ ? i + 1 : 0)\n'),
    ('a redirection glued to its word is read', 'hooks/_classify.sh',
     '      return (substr(w, i + 1) ~ /^([0-9]*|&)>/ ? i + 1 : 0)\n',
     '      return (substr(w, i + 1) ~ /^([0-9]*)>/ ? i + 1 : 0)\n'),
    # MK-R6, the name of the kit typed again as a string, in the two quotes the guard looks for.
    ('no fixture types the name of the kit', 'tests/run.sh',
     '        if e.get("name") == NAME:\n            e["version"] = marketplace_version\n',
     '        if e.get("name") == "%s":\n            e["version"] = marketplace_version\n' % NAME),
    ('no fixture types the name of the kit', 'tests/run.sh',
     'named = [e.get("source") for e in plugins if e.get("name") == NAME]\n',
     "named = [e.get(\"source\") for e in plugins if e.get(\"name\") == '%s']\n" % NAME),
    # MK-R6, check.sh asks for python3 without -I, which imports the json.py of the project it audits.
    ('every python3 call in a hook or tool runs isolated', 'check.sh',
     '    ERR="$(python3 -I -c \'import io,json,sys\n',
     '    ERR="$(python3 -c \'import io,json,sys\n'),
    # MK-R6, a line that asks for the project root inside a command substitution, put into a hook and into a tool (it
    # changes nothing a caller sees, so only the check of its own dies of it), and the scan without its backtick half.
    ('no command substitution asks for the project root', 'hooks/role-guard.sh',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n',
     'mk_project_root_set "${CWD:-$PWD}"; ROOT=$MK_ROOT\n: "$(mk_project_root "$ROOT")"\n'),
    ('no command substitution asks for the project root', 'tools/week-verdict.sh',
     'mk_project_root_set "$GIVEN"; PROJECT=$MK_ROOT\n',
     'mk_project_root_set "$GIVEN"; PROJECT=$MK_ROOT\n: "$(mk_project_root "$PROJECT")"\n'),
    ('no command substitution asks for the project root', 'tests/run.sh',
     "  grep -n -H -E '(\\$\\([^)]*|`[^`]*)mk_project_root' \"$@\"",
     "  grep -n -H -E '(\\$\\([^)]*)mk_project_root' \"$@\""),
    # MK-B1, THE COST METER: one entry per assertion, each turning back one rule of tools/mk-cost.sh, its price
    # file or its command. Every anchor counted as a Python substring against its file: 1 (the two haiku entries
    # share one anchor line and replace it differently). The table check dies beside every entry that changes a
    # row, because it IS every row; its own entry is the one only it can see, the order of the rows.
    ("mk-cost prints the table computed by hand from the fixtures", "tools/mk-cost.sh",
     "key=lambda k: (-round(agg[k][1], 6), k))", "key=lambda k: (round(agg[k][1], 6), k))"),
    ("mk-cost counts the last line of a streamed answer", "tools/mk-cost.sh",
     "            here[key] = (ts, d, m)\n", "            here.setdefault(key, (ts, d, m))\n"),
    ("mk-cost counts an answer in two files once", "tools/mk-cost.sh",
     "        best[key] = (ts, path, label, m)\n", "        best[(path,) + key] = (ts, path, label, m)\n"),
    ("mk-cost counts a line without requestId and names it", "tools/mk-cost.sh",
     '            key = (m.get("id"), d.get("requestId") or None)\n',
     '            if not d.get("requestId"):\n                continue\n            key = (m.get("id"), d.get("requestId") or None)\n'),
    ("mk-cost counts synthetic as a row of its own without a price", "tools/mk-cost.sh",
     '    if model == "<synthetic>":\n        pass\n', '    if model == "<synthetic>":\n        continue\n'),
    ("mk-cost keeps haiku at 100000 tokens on its first tier", "tools/mk-cost.sh",
     "        if tier and inp + cr + cw > tier[0]:", "        if tier and inp + cr + cw >= tier[0]:"),
    ("mk-cost prices haiku above 100000 tokens on its second tier", "tools/mk-cost.sh",
     "        if tier and inp + cr + cw > tier[0]:", "        if tier and inp > tier[0]:"),
    ("mk-cost prices cache creation by its 5m and 1h fields", "tools/mk-cost.sh",
     '    w1 = cc.get("ephemeral_1h_input_tokens") if isinstance(cc.get("ephemeral_1h_input_tokens"), int) else 0\n',
     '    w1 = 0\n'),
    ("mk-cost prices cache creation without ttl fields as 5m", "tools/mk-cost.sh",
     "    w5 += max(0, cw - w5 - w1)\n", "    w1 += max(0, cw - w5 - w1)\n"),
    ("mk-cost types a hand by attributionAgent before meta.json", "tools/mk-cost.sh",
     "    if isinstance(attr, str) and attr:\n",
     '    if isinstance(attr, str) and attr and not os.path.exists(path[:-len(".jsonl")] + ".meta.json"):\n'),
    ("mk-cost types a hand without attributionAgent by meta.json", "tools/mk-cost.sh",
     '        kind = None\n        mf = lines_of(path[:-len(".jsonl")] + ".meta.json")\n', "        kind = None\n        mf = None\n"),
    ("mk-cost counts a file under subagents as a hand, untyped as unknown", "tools/mk-cost.sh",
     '    hand = rel[-1].startswith("agent-") or "subagents" in rel[:-1]\n', '    hand = rel[-1].startswith("agent-")\n'),
    ("mk-cost keeps a line of the main session manager whatever it carries", "tools/mk-cost.sh",
     '        if not hand:\n            label = "manager"\n',
     '        if not hand and not d.get("attributionAgent"):\n            label = "manager"\n'),
    ("mk-cost excludes a project folder in any case", "tools/mk-cost.sh",
     "    if any(e.lower() in top.lower() for e in excl):\n", "    if any(e in top for e in excl):\n"),
    ("mk-cost excludes by the folder name, not the file name", "tools/mk-cost.sh",
     "                files.append(path)\n",
     "                if not any(e.lower() in path.lower() for e in excl):\n                    files.append(path)\n"),
    ("mk-cost takes --exclude more than once", "tools/mk-cost.sh",
     "        excl.append(v)\n", "        excl[:] = [v]\n"),
    ("mk-cost keeps the day --since names and drops the day before", "tools/mk-cost.sh",
     "            if since and day < since:\n", "            if since and day <= since:\n"),
    ("mk-cost keeps the day --until names and drops the day after", "tools/mk-cost.sh",
     "            if until and day > until:\n", "            if until and day >= until:\n"),
    ("mk-cost prints no number under 95 percent coverage", "tools/mk-cost.sh",
     "    if None not in val.values():\n",
     '    if None not in (val["input_tokens"], val["output_tokens"], val["cache_creation_input_tokens"]):\n'),
    ("mk-cost prints no number with an unknown model above 1 percent", "tools/mk-cost.sh",
     "if unknown * 100 > rounds:\n", "if unknown * 50 > rounds:\n"),
    # HOME in every call of the suite is a fixture directory, so this mutant reads a decoy and never a real
    # transcript.
    ("mk-cost reads the transcripts under CLAUDE_CONFIG_DIR", "tools/mk-cost.sh",
     "CFG=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}\n", "CFG=${HOME:-}/.claude\n"),
    # The anchor names the head of the table from its start since MK-B4: the heads of --what-if and --compare end the same.
    ("mk-cost heads its table with files, coverage, prices and LOWER BOUND", "tools/mk-cost.sh",
     'print("mk-cost  %s..%s  Files %d  Coverage %.1f%%  Prices as of %s  LOWER BOUND"',
     'print("mk-cost  %s..%s  Files %d  Coverage %.1f%%  Prices as of %s"'),
    ("mk-cost prices every row of prices.tsv as computed by hand", "tools/prices.tsv",
     "claude-opus-4-8\t5\t6.25\t10\t0.5\t25\t", "claude-opus-4-8\t5\t6.25\t10\t0.5\t20\t"),
    ("the cost command runs mk-cost and says what the number is", "commands/cost.md",
     'bash "$MK" $ARGUMENTS;', 'bash "$MK";'),
    ("the cost command finds the kit the way the take-over does", "commands/cost.md",
     '"installed_plugins.json"', '"installed.json"'),
    ("mk-cost refuses an option or a day it cannot read", "tools/mk-cost.sh",
     '    if a not in ("--since", "--until", "--exclude"):\n',
     '    if a not in ("--since", "--until", "--exclude"):\n        i += 1\n        continue\n'),
    ("mk-cost prints no number for a window without rounds", "tools/mk-cost.sh",
     "if rounds == 0:\n", "if False:\n"),
    # MK-B3, PLANNED AGAINST RAN: one entry per check, each turning back one rule of mk-cost.sh --hands or of the word
    # the route hook writes. The report check dies beside every entry that changes a row or a finding, because it IS
    # every row; its own entry is the one only it can see, the order of the hands. Three share the anchor of the
    # model comparison and replace it differently.
    ("mk-cost --hands reports a hand that ran on another model than its route", "tools/mk-cost.sh",
     "                off = dict((k, c) for k, c in models.items() if version_key(k) != pk)\n",
     "                off = {}\n"),
    ("mk-cost --hands names the share of a second model in one transcript", "tools/mk-cost.sh",
     "                off = dict((k, c) for k, c in models.items() if version_key(k) != pk)\n",
     "                top = max(models, key=lambda k: (models[k], k))\n"
     "                off = dict((k, c) for k, c in models.items() if version_key(top) != pk)\n"),
    ("mk-cost --hands reports no deviation where route and transcript agree", "tools/mk-cost.sh",
     "                off = dict((k, c) for k, c in models.items() if version_key(k) != pk)\n",
     "                off = dict((k, c) for k, c in models.items() if norm(k) != norm(pm))\n"),
    # TWO ASSERTIONS, TWO ENTRIES: the alias is the NEWEST of its family (h1), and a build date is no version (v1).
    ("mk-cost --hands resolves an alias to the newest version of its family", "tools/mk-cost.sh",
     "    return fam[-1] if fam else (None, None)\n", "    return fam[0] if fam else (None, None)\n"),
    ("mk-cost --hands resolves an alias to the newest version of its family", "tools/mk-cost.sh",
     '    return (mm.group(1), tuple(int(x) for x in mm.group(2)[1:].split("-") if len(x) < 8))\n',
     '    return (mm.group(1), tuple(int(x) for x in mm.group(2)[1:].split("-")))\n'),
    ("mk-cost --hands counts a hand without a route line openly", "tools/mk-cost.sh",
     "        if kv is None:\n            n_open += 1\n", "        if kv is None:\n            continue\n"),
    # THE LATEST LINE OF THE LOG FOR EVERY ID, which is what a match by time reads.
    ("mk-cost --hands tells two calls of one hand apart by tool_use_id", "tools/mk-cost.sh",
     '                        found[kv["tool_use_id"]] = kv\n',
     '                        found.update((x, kv) for x in list(found) + [kv["tool_use_id"]])\n'),
    ("mk-cost --hands finds the project from a cwd in a subdirectory", "tools/mk-cost.sh",
     "            a = os.path.dirname(a)\n", "            break\n"),
    ("mk-cost --hands reports an effort other than the route", "tools/mk-cost.sh",
     '            if re.fullmatch(r"[a-z]+", pe.lower()):\n', "            if False:\n"),
    ("mk-cost --hands compares no model for a route without one", "tools/mk-cost.sh",
     "            if pk is None:\n", "            if pk is None and False:\n"),
    ("mk-cost --hands prints the report computed by hand", "tools/mk-cost.sh",
     "    for stem, kind, tu, rr in sorted(hands, key=lambda h: h[0]):\n",
     "    for stem, kind, tu, rr in sorted(hands, key=lambda h: h[0], reverse=True):\n"),
    ("mk-cost --hands prints no number when toolUseId is missing above 5 percent", "tools/mk-cost.sh",
     "    if missing * 100 > 5 * len(hands):\n", "    if missing * 100 > 50 * len(hands):\n"),
    ("mk-cost --hands lists a hand without toolUseId at 5 percent", "tools/mk-cost.sh",
     "    if missing * 100 > 5 * len(hands):\n", "    if missing * 100 >= 5 * len(hands):\n"),
    ("the route line carries the tool_use_id of the call", "hooks/route-guard.sh",
     'say("TOOL_USE_ID", tu if tu is None or (isinstance(tu, str) and re.fullmatch("[A-Za-z0-9_-]{0,128}", tu)) else "?")\n',
     'say("TOOL_USE_ID", tu)\n'),
    ("a call without tool_use_id writes the route line as before", "hooks/route-guard.sh",
     "order=$ORDER${TOOL_USE_ID:+ tool_use_id=$TOOL_USE_ID}\"\n", "order=$ORDER tool_use_id=$TOOL_USE_ID\"\n"),
    # THE WRITER AND THE READER DRIFT APART: the hook spells the word another way. The two checks of the word die
    # with it, because they read its spelling too.
    ("mk-cost --hands reads the route line the hook writes", "hooks/route-guard.sh",
     "order=$ORDER${TOOL_USE_ID:+ tool_use_id=$TOOL_USE_ID}\"\n", "order=$ORDER${TOOL_USE_ID:+ tool_use=$TOOL_USE_ID}\"\n"),
    # MK-R8, ONE RULE FOR THE TYPE OF A HAND. --hands asks hand_type of tools/mk-cost.sh with the line it counts, as the table
    # does. This asks it with no line, so the meta.json alone types the hand, which is what --hands did before. The three
    # entries above that type a hand turn back the rule itself and die beside it, because the table and the report share it.
    ("mk-cost --hands types a hand by the rule of the table", "tools/mk-cost.sh",
     "            k = hand_type(d, path, cache)\n", "            k = hand_type({}, path, cache)\n"),
    # A hand of two types is named with one of them only: the share that names two models is not asked for the types.
    ("mk-cost --hands types a hand by the rule of the table", "tools/mk-cost.sh",
     "        kind = share(kinds, len(rr))\n", "        kind = sorted(kinds)[0]\n"),
    # MK-R8, THE COMMAND NAMES THE WORDS THE TOOL TAKES: the hint, the word, and where the plan comes from. Anchors counted
    # as a Python substring against commands/cost.md: 1 each.
    ("the cost command names the words the tool takes", "commands/cost.md",
     '[--exclude TEXT]... [--causes] [--context] [--hands] [--what-if]', '[--exclude TEXT]... [--causes] [--context] [--what-if]'),
    ("the cost command names the words the tool takes", "commands/cost.md",
     "With `--hands` the command prints", "With the flag the command prints"),
    ("the cost command names the words the tool takes", "commands/cost.md",
     "the same `tool_use_id` as the hand", "the same time as the hand"),
    # MK-B4, THE COMMAND NAMES THE NEW WORDS, each dropped from the hint in turn. The entry above moved its anchor with them
    # (the hint no longer ends after [--hands]). Anchors counted as a Python substring against commands/cost.md: 1 each.
    ("the cost command names the words the tool takes", "commands/cost.md",
     ' [--what-if] [--compare A B]"', ' [--compare A B]"'),
    ("the cost command names the words the tool takes", "commands/cost.md",
     ' [--compare A B]"', '"'),
    # MK-B4, THE COUNTER-RECKONING AND THE WINDOW COMPARISON: one entry or more per check, each turning back one rule of
    # --what-if, --compare, their words or their documents. Every anchor counted as a Python substring against its file: 1.
    # Three share the line that puts a hand round on Opus and replace it differently, two the order of the hand rows. The
    # whole reports die beside every entry that changes a row or a line, because they ARE every row and line; their own
    # entries are what only they see.
    ("mk-cost --what-if prices sonnet 5.5 hand rounds at the opus multiple of prices.tsv", "tools/mk-cost.sh",
     '    opus = resolve("opus")[1]\n', '    opus = sorted(x for x in P if x.startswith("claude-opus"))[0]\n'),
    ("mk-cost --what-if keeps opus 5.5 hand rounds and manager rounds as they ran", "tools/mk-cost.sh",
     '        alt = cost if label == "manager" or (k and k[0] == "opus") else list_price(opus, *t)\n',
     '        alt = cost if (k and k[0] == "opus") else list_price(opus, *t)\n'),
    ("mk-cost --what-if keeps a hand round on an older opus at its own price", "tools/mk-cost.sh",
     '        alt = cost if label == "manager" or (k and k[0] == "opus") else list_price(opus, *t)\n',
     '        alt = cost if label == "manager" or model == opus else list_price(opus, *t)\n'),
    # THE SHORTCUT: what ran, scaled by the output prices of the two models. It holds for sonnet, one multiple in every
    # column, and for haiku on its first tier; only the round above the tier shows it.
    ("mk-cost --what-if prices haiku under and above its tier at opus on the same tokens", "tools/mk-cost.sh",
     '        alt = cost if label == "manager" or (k and k[0] == "opus") else list_price(opus, *t)\n',
     '        alt = cost if label == "manager" or (k and k[0] == "opus") else cost * P[opus][4] / P[model][4]\n'),
    ("mk-cost --what-if leaves synthetic out on both sides", "tools/mk-cost.sh",
     '        if model == "<synthetic>":\n            synth += 1\n            continue\n',
     '        if model == "<synthetic>":\n            cost = 0.0\n'),
    ("mk-cost --what-if prints the report computed by hand", "tools/mk-cost.sh",
     '    hand_rows = sorted(k for k in sums if k != "manager")\n',
     '    hand_rows = sorted((k for k in sums if k != "manager"), reverse=True)\n'),
    # THE EDGE OF THE BAND, and a percentage offered inside it.
    ("mk-cost --compare prints not distinguishable without an intervention", "tools/mk-cost.sh",
     "    if abs(math.log(mb / ma)) <= band:\n", "    if abs(math.log(mb / ma)) < band:\n"),
    ("mk-cost --compare prints not distinguishable without an intervention", "tools/mk-cost.sh",
     '        print("Verdict: not distinguishable.")\n',
     '        print("Verdict: not distinguishable, %+.1f%%." % (100.0 * (mb / ma - 1)))\n'),
    # THE BAND SWALLOWS THE CHANGE: all of the history in it, the wild day included, or every day up to the end of B.
    ("mk-cost --compare prints the change beside the band for factor 2 in B", "tools/mk-cost.sh",
     "    band_days = before[-need:]\n", "    band_days = before\n"),
    ("mk-cost --compare prints the change beside the band for factor 2 in B", "tools/mk-cost.sh",
     "    before = [d for d in act if d < a_first]\n", "    before = [d for d in act if d <= b_last]\n"),
    # THE MINIMUM, and the active days between A and B left out of the shape of a pair.
    ("mk-cost --compare gives no verdict on a history too short for a band", "tools/mk-cost.sh",
     "    need = 4 * span\n", "    need = 3 * span\n"),
    ("mk-cost --compare gives no verdict on a history too short for a band", "tools/mk-cost.sh",
     "    span = len(in_a) + gap + len(in_b)\n", "    span = len(in_a) + len(in_b)\n"),
    ("mk-cost --compare counts a day active only when it costs more than nothing", "tools/mk-cost.sh",
     "    act = sorted(d for d in paid if paid[d] > 0)\n", "    act = sorted(paid)\n"),
    # FOUR RULES OF ONE CHECK: two reports at once, --since or --until with --compare, A after B, a window turned round.
    ("mk-cost refuses a window it cannot read and a mix of words it does not support", "tools/mk-cost.sh",
     "if len(mix) > 1:\n", "if len(mix) > 3:\n"),
    ("mk-cost refuses a window it cannot read and a mix of words it does not support", "tools/mk-cost.sh",
     "    if since or until:\n", "    if False:\n"),
    ("mk-cost refuses a window it cannot read and a mix of words it does not support", "tools/mk-cost.sh",
     "    if not a_last < b_first:\n", "    if False:\n"),
    ("mk-cost refuses a window it cannot read and a mix of words it does not support", "tools/mk-cost.sh",
     "    if last < first:\n", "    if False:\n"),
    # THE ORDER OF A HASH: the hand types as a set, which python3 -I orders anew in every process.
    ("mk-cost --what-if and --compare print the same bytes twice", "tools/mk-cost.sh",
     '    hand_rows = sorted(k for k in sums if k != "manager")\n',
     '    hand_rows = list(set(k for k in sums if k != "manager"))\n'),
    ("README and GUIDE name every word mk-cost takes", "README.md",
     "it can match. `--what-if` prints\n", "it can match. It also prints\n"),
    ("README and GUIDE name every word mk-cost takes", "GUIDE.md",
     "`--compare A B` compares two\n", "A comparison takes two\n"),
    ("README and GUIDE name every word mk-cost takes", "commands/cost.md",
     '**"not distinguishable"** means', '**"inside"** means'),
    # MK-R8, THE NAME TYPED BACK INTO A COMMAND: the filter that skipped every entry of the register not called manager-kit,
    # as it stood in both blocks (the suite holds them line for line, and each file has an entry of its own here). It types
    # the name on purpose, as the defect did: derived from the manifest it would be no fork's defect. Anchors counted as a
    # Python substring, one in each file: 1.
    ("the commands find the installation whatever the plugin is called", "commands/take-over.md",
     'for entries in (reg.get("plugins") or {}).values():\n',
     'for name, entries in (reg.get("plugins") or {}).items():\n    if name.split("@", 1)[0] != "manager-kit":\n        continue\n'),
    ("the commands find the installation whatever the plugin is called", "commands/cost.md",
     'for entries in (reg.get("plugins") or {}).values():\n',
     'for name, entries in (reg.get("plugins") or {}).items():\n    if name.split("@", 1)[0] != "manager-kit":\n        continue\n'),
    # MK-R8, THE TOOL JUDGES FOR THE DIRECTORY IT STANDS IN. Two entries share the anchor and replace it differently: the
    # name taken from the caller's environment again (the half of the check that was red before the repair), and the wrong
    # directory, the tool's own (the half that held before and holds after). Anchor counted as a Python substring against
    # tools/mk-explain.sh: 1.
    ("the tool judges as the guard does from a subdirectory", "tools/mk-explain.sh",
     "MK_CWD=$PWD\n", "MK_CWD=${MK_CWD:-$PWD}\n"),
    ("the tool judges as the guard does from a subdirectory", "tools/mk-explain.sh",
     "MK_CWD=$PWD\n", "MK_CWD=$HERE\n"),
    # MK-B2a, THE CAUSES OF CACHE WRITING: one entry per assertion of mk-cost.sh --causes, each turning back one rule.
    # Every anchor counted as a Python substring against tools/mk-cost.sh: 1, except the two that share a line with a
    # sibling and replace it differently (prev is None, the 5m bound, last_ttl). The report check dies beside every entry
    # that moves a row, because it IS every row; its own entry is the one only it can see, the order of the rows.
    ("mk-cost --causes names the first round of a file Start", "tools/mk-cost.sh",
     "                elif prev is None:\n", "                elif prev is None and False:\n"),
    ("mk-cost --causes names a write within the ttl of the round before Growth", "tools/mk-cost.sh",
     '                        c = "Growth"\n', '                        c = "Other"\n'),
    ("mk-cost --causes names a gap over a 5m ttl expired", "tools/mk-cost.sh",
     "                        c = EXPIRED[long[0]]\n", '                        c = EXPIRED["1h"]\n'),
    ("mk-cost --causes names a gap over a 1h ttl idle", "tools/mk-cost.sh",
     "                writes = [x for x, n in zip(TTL, (t[3], t[4])) if n > 0]\n", "                writes = [TTL[0]]\n"),
    ("mk-cost --causes names the first round after a compaction after-compaction", "tools/mk-cost.sh",
     "                if after:\n", "                if False:\n"),
    # A <synthetic> line taken as a round takes the compaction from the round after it (k9 before k2).
    ("mk-cost --causes names the first round after a compaction after-compaction", "tools/mk-cost.sh",
     '            if model == "<synthetic>":\n', '            if model == "<synthetic>" and False:\n'),
    # TWO ASSERTIONS, TWO ENTRIES: a write with no write before it is Other (r2), and a round that wrote nothing passes
    # the TTL of the last write on (r4).
    ("mk-cost --causes counts a write that follows no rule as Other", "tools/mk-cost.sh",
     "                elif prev is None:\n", "                elif prev is None or last_ttl is None:\n"),
    ("mk-cost --causes counts a write that follows no rule as Other", "tools/mk-cost.sh",
     "            if t[3] + t[4] > 0:\n                writes",
     "            last_ttl = last_ttl if t[3] + t[4] else None\n            if t[3] + t[4] > 0:\n                writes"),
    # THE BOUND ITSELF, two ways: the gap at the bound counted as past it (dies beside the 1h check, which shares the
    # comparison), and the 5m TTL a millisecond longer, which only the 5m check sees.
    ("mk-cost --causes keeps a gap of exactly 5m within the ttl and one past it out", "tools/mk-cost.sh",
     "                    if gap > long[1]:\n", "                    if gap >= long[1]:\n"),
    ("mk-cost --causes keeps a gap of exactly 5m within the ttl and one past it out", "tools/mk-cost.sh",
     '("5m", datetime.timedelta(minutes=5))', '("5m", datetime.timedelta(minutes=5, milliseconds=1))'),
    ("mk-cost --causes keeps a gap of exactly 1h within the ttl and one past it out", "tools/mk-cost.sh",
     '("1h", datetime.timedelta(hours=1))', '("1h", datetime.timedelta(hours=1, milliseconds=1))'),
    # A ROUND THAT WRITES BOTH holds the 5m part for the first bound (y2) and the 1h part for the second (z2).
    ("mk-cost --causes gives a round that writes 5m and 1h one cause and both ttls", "tools/mk-cost.sh",
     "                last_ttl = (writes[0], writes[-1])\n", "                last_ttl = (writes[-1], writes[-1])\n"),
    ("mk-cost --causes gives a round that writes 5m and 1h one cause and both ttls", "tools/mk-cost.sh",
     "                last_ttl = (writes[0], writes[-1])\n", "                last_ttl = (writes[0], writes[0])\n"),
    # FOUR PARTS OF ONE LINE, four entries: the copy in the second file, the trigger, the median, the context after.
    ("mk-cost --causes counts a compaction in two files once, with trigger and context", "tools/mk-cost.sh",
     '            k = d.get("uuid") if', '            k = path + str(d.get("uuid")) if'),
    ("mk-cost --causes counts a compaction in two files once, with trigger and context", "tools/mk-cost.sh",
     '(len(comp), trig.count("manual"), trig.count("auto"),', '(len(comp), trig.count("manuell"), trig.count("auto"),'),
    ("mk-cost --causes counts a compaction in two files once, with trigger and context", "tools/mk-cost.sh",
     '"%d" % ((xs[(len(xs) - 1) // 2] + xs[len(xs) // 2]) // 2)', '"%d" % xs[(len(xs) - 1) // 2]'),
    ("mk-cost --causes counts a compaction in two files once, with trigger and context", "tools/mk-cost.sh",
     '                mk["_after"] = t[0] + t[1] + t[2]\n', '                mk["_after"] = t[2]\n'),
    ("mk-cost --causes judges the first round of a window by the round before it", "tools/mk-cost.sh",
     "            if scan:\n                # Every round",
     "            if scan and not (since and day < since):\n                # Every round"),
    ("mk-cost --causes sums to the write share of the table in the same window", "tools/mk-cost.sh",
     "    total = sum(c for mo, c, t in kept.values() if c is not None)\n",
     "    total = sum(c for mo, c, t in kept.values() if c is not None and t[3] + t[4])\n"),
    ("mk-cost --causes goes with the window and with no other report", "tools/mk-cost.sh",
     '                       ("--causes", causes_mode)) if on]', "                       ) if on]"),
    ("mk-cost --causes prints the report computed by hand", "tools/mk-cost.sh",
     "    for r in ROLES:\n        for c in CAUSES:\n", "    for c in CAUSES:\n        for r in ROLES:\n"),
    # THE BYTES, which the table check reads with its blanks squeezed and so cannot see: one column a place wider.
    ("mk-cost prints the table and the three reports without --causes as at 92b9152", "tools/mk-cost.sh",
     'fmt = "%-44s %7s %10s %6s %12s %12s %12s %12s"', 'fmt = "%-45s %7s %10s %6s %12s %12s %12s %12s"'),
    # MK-B2b, THE OWN LOOPS AND THE CONTEXT CAP: one entry or more per assertion of mk-cost.sh --context, each turning back
    # one rule. The anchor of the hint above and the one of the window entry of --causes moved with this (the hint names
    # --context, the line reads scan for --causes and --context). Every anchor counted as a Python substring against its
    # file: 1.
    # THE CLASSES, an edge one round off (a length of 2^k - 1 in the class above), the share of the loops instead of all
    # costs, and a loop of exactly 8 rounds left out of "from 8".
    ("mk-cost --context counts the own loops of the main session in every class", "tools/mk-cost.sh",
     "            return max(j for j, lo in enumerate(CLASSES) if n >= lo)\n",
     "            return min(len(CLASSES) - 1, int(math.log2(n + 1)))\n"),
    ("mk-cost --context counts the own loops of the main session in every class", "tools/mk-cost.sh",
     '            return "%.1f" % (100.0 * usd / total if total else 0.0)\n',
     '            return "%.1f" % (100.0 * usd / sum(lp[1] for lp in loops))\n'),
    ("mk-cost --context counts the own loops of the main session in every class", "tools/mk-cost.sh",
     "        long_n = [lp for lp in loops if lp[0] >= LONG]\n", "        long_n = [lp for lp in loops if lp[0] > LONG]\n"),
    # A HAND FILE READ AS A MAIN FILE: its runs of 40 and 33 rounds become two loops of 32+.
    ("mk-cost --context counts no loop in a hand file", "tools/mk-cost.sh",
     "    if causes_mode or context_mode and not hand:\n", "    if causes_mode or context_mode:\n"),
    # THE INPUT RULE, three ways: every tool result an input, a list of text blocks none, a string none.
    ("mk-cost --context ends a loop at an input and not at a tool result", "tools/mk-cost.sh",
     '        return not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)\n', "        return True\n"),
    ("mk-cost --context ends a loop at an input and not at a tool result", "tools/mk-cost.sh",
     '        return not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)\n', "        return False\n"),
    ("mk-cost --context ends a loop at an input and not at a tool result", "tools/mk-cost.sh",
     "    return isinstance(c, str)\n", "    return False\n"),
    # A LINE CLAUDE CODE ADDS, and the summary after an automatic compaction, taken as inputs.
    ("mk-cost --context keeps a meta line and a compaction summary inside the loop", "tools/mk-cost.sh",
     '    if d.get("isMeta") is True:\n        return False\n', '    if False:\n        return False\n'),
    ("mk-cost --context keeps a meta line and a compaction summary inside the loop", "tools/mk-cost.sh",
     '    if d.get("isCompactSummary") is True:\n        return False\n', '    if False:\n        return False\n'),
    # EACH INPUT OF THE CAP turned back once: g by the median, a pair across a compaction, S by the smallest, K without
    # the estimated call, the measured part summed instead of per event, r of the first model by name, the median context
    # by the read alone, and the formula without its 2 and without S.
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "        g = float(sum(pairs)) / len(pairs) if pairs else None\n",
     "        g = float(sorted(pairs)[(len(pairs) - 1) // 2]) if pairs else None\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "                    if prev is not None and not wall:\n", "                    if prev is not None:\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "        S = int(median(after)) if after else None\n", "        S = min(after) if after else None\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "        K = k_first + k_call if k_first", "        K = k_first + 0 * k_call if k_first"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "        k_first = first[2] / first[0] if first[0] else None\n", "        k_first = first[2] if first[0] else None\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "        main = sorted(models.items(), key=lambda mc: (-mc[1], mc[0]))[0][0] if models else None\n",
     "        main = sorted(models)[0] if models else None\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "                    contexts.append(tk[0] + tk[1] + tk[2])\n", "                    contexts.append(tk[1])\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     "        t_star = math.sqrt(2 * K / (r * g))\n", "        t_star = math.sqrt(K / (r * g))\n"),
    ("mk-cost --context computes the cap C* from S, g, K and r by the formula", "tools/mk-cost.sh",
     '        print("C* %d tokens" % round(S + g * t_star))\n', '        print("C* %d tokens" % round(g * t_star))\n'),
    # NO NUMBER WITHOUT ITS INPUTS: S left out of the reason, and the compaction line no wall between two rounds.
    ("mk-cost --context gives no C* without a compaction, with the reason", "tools/mk-cost.sh",
     '        if S is None:\n            missing.append(', '        if False:\n            missing.append('),
    ("mk-cost --context gives no C* without a pair of rounds, with the reason", "tools/mk-cost.sh",
     "                while wi < len(walls) and walls[wi] < lineno:\n", "                while wi < len(walls) and walls[wi] < 0:\n"),
    ("mk-cost --context goes with the window and with no other report", "tools/mk-cost.sh",
     ' + (["--context"] if context_mode else [])\n', "\n"),
    # THE COMMAND AND THE DOCUMENTS: the word, the cap, the estimate; the hint; README and GUIDE, whose words the check
    # reads out of the tool.
    ("the cost command says what --context prints", "commands/cost.md",
     "With `--context` it prints instead", "With the word it prints instead"),
    ("the cost command says what --context prints", "commands/cost.md",
     "the context cap `C*` of\nthis machine", "the context cap of\nthis machine"),
    ("the cost command says what --context prints", "commands/cost.md",
     "that part of K is **estimated**", "that part of K is estimated"),
    ("the cost command names the words the tool takes", "commands/cost.md",
     " [--causes] [--context] [--hands] [--what-if] [--compare A B]\"", " [--causes] [--hands] [--what-if] [--compare A B]\""),
    ("README and GUIDE name every word mk-cost takes", "README.md",
     "after. `--context` prints instead the manager's own tool\n", "after. It also prints the manager's own tool\n"),
    ("README and GUIDE name every word mk-cost takes", "GUIDE.md",
     "the write of the table. `--context`\n", "the write of the table. A last report\n"),
    # THE BYTES of --causes, which its report check reads with its blanks squeezed and so cannot see: one column wider.
    ("mk-cost prints the five reports without --context as at be9243b", "tools/mk-cost.sh",
     'fmt = "%-28s %7s %12s %10s %6s %13s %11s"', 'fmt = "%-29s %7s %12s %10s %6s %13s %11s"'),
    # MK-NOTIZ-WEG, THE KIT SAYS NOTHING TO THE MANAGER OF COMPACT, OF ITS CONTEXT OR OF ITS LOOP: one entry per assertion of
    # the one check. Every anchor counted as a Python substring against its file: 1.
    # THE GUARD ON A CALL IT LETS THROUGH: a line put out where there was none (the shape of the old context line), and the
    # line of the verdict taken out, which hands every call to the refusal.
    ("the kit tells the manager nothing of compact, its context or its loop", "hooks/role-guard.sh",
     '[ "$verdict" = work ] || exit 0\n',
     '[ "$verdict" = work ] || { printf \'%s\\n\' \'{"suppressOutput": true, "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "manager-kit: the context is 400000 tokens, over the cap of 300000. The person can compact at the next pause."}}\'; exit 0; }\n'),
    ("the kit tells the manager nothing of compact, its context or its loop", "hooks/role-guard.sh",
     '[ "$verdict" = work ] || exit 0\n', ':\n'),
    # THE STAMP AT A PROMPT: a line under the role line (the shape of the old loop line, with the pause).
    ("the kit tells the manager nothing of compact, its context or its loop", "hooks/manager-stamp.sh",
     "  line='manager-kit: you are the manager here. Bookkeeping is .claude/ and *.md, everything else is handed out.'\n",
     "  line='manager-kit: you are the manager here. Bookkeeping is .claude/ and *.md, everything else is handed out.'\n"
     "  line=$line$MK_NL'manager-kit: your own tool loop has run 20 rounds since the last input, at 900000 tokens of context. The person can compact at the next pause.'\n"),
    # THE RIGHT BEHAVIOUR OF THE SAME SHAPE: the role line of the manager, and the refusal of a work write.
    ("the kit tells the manager nothing of compact, its context or its loop", "hooks/manager-stamp.sh",
     "you are the manager here. Bookkeeping", "you are here. Bookkeeping"),
    ("the kit tells the manager nothing of compact, its context or its loop", "hooks/role-guard.sh",
     '[ "$verdict" = work ] || exit 0\n', 'exit 0\n'),
]


def apply_mutation(workdir, rel, anchor, replacement):
    path = os.path.join(workdir, rel)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if anchor is None:
        new = text + replacement
    else:
        if anchor not in text:
            raise AssertionError("anchor not found in %s: %r" % (rel, anchor[:70]))
        new = text.replace(anchor, replacement, 1)
    if new == text:
        raise AssertionError("mutation changed nothing in %s" % rel)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)


def selected(argv):
    """The entries to run, filtered by a substring of the assertion name.

    WHY THERE IS A FILTER AT ALL, and it is not a convenience. The claim this file holds
    up is per assertion: THIS mutation kills THAT assertion and no other. Checking one
    entry used to mean editing MUTATIONS down to it and putting it back, which the
    comments above record being done three times; an edit that has to be undone is a copy
    of the list, and the copy is what gets left behind. The full run is the gate and takes
    the better part of an hour, so the per entry question had to be askable without it.

    No argument runs everything, so the gate is unchanged.
    """
    want = [a for a in argv if not a.startswith("-")]
    if not want:
        return MUTATIONS
    hit = [m for m in MUTATIONS if any(w in m[0] for w in want)]
    if not hit:
        sys.exit("no mutation's assertion name contains any of: %s" % ", ".join(want))
    return hit


# ------------------------------------------------------------------------ the runner
#
# WHAT ONE ENTRY LEAVES BEHIND IS NOTHING. Every entry gets one root, MK_RUN_ROOT, and the copy
# of the repository, the temp of the suite that runs in it (tests/run.sh puts all of it under the
# root, see "one root for the temp of this run" there) and anything the suite recorded outside it
# are removed when the entry ends: finished, out of time, or taken off by INT, TERM or HUP. The
# suite is started in a process group of its own, so a limit or a signal reaches what it started
# and not only its shell. MK_MEASURE_ROOT
#
# THE CLASSES. RED: the entry's own check died. ALIVE: it did not, whatever else died. ERROR: the
# anchor is not in the file. TIMEOUT: the limit passed before a verdict, which is not red and not
# alive, because nothing was seen. A run with a limit ends non-zero for any of the last three.
#
# --fast CHANGES THE TIME AND NOT THE VERDICT. The verdict of an entry is "its own check is dead",
# which is what `name in dead` below has always asked, and a check that is dead beside it changes
# nothing about it [the order for this said "a mutant is red as soon as any check is red": that is
# not what this file ever did, an entry killed only by a foreign check is ALIVE below]. So --fast
# asks the own check first, alone, in one run of the suite (MK_ONLY_CHECK), and stops there when it
# is dead. Only an entry whose own check lived is looked at further: a second run, which ends at
# the first red check (MK_STOP_AT_RED), to name that one for the reader. What is lost is the list
# of every check that died beside the own one, and with it the count "distinct assertions killed"
# at the foot: in --fast it counts the own checks and says so.

CLASSES = ("RED", "ALIVE", "TIMEOUT", "ERROR")

_lock = threading.Lock()
_running = {}     # pid of a suite in flight -> its Popen (its process group id is its pid)
_roots = set()    # the roots in use, for the signal handler


def suite_command(pkg_name=None):
    return ["bash", os.path.join(pkg_name or PKG_NAME, "tests", "run.sh")]


def temp_base():
    """Where the roots go: TMPDIR, unless that is no directory or has a .git or a .claude in it or above it.

    The same rule as tests/run.sh, and for the same reason: a fixture finds its project by walking up,
    and under a project it finds that one [measured: 16 and 23 of 60 checks red, see the root block there].
    """
    base = os.environ.get("TMPDIR") or "/tmp"
    if not os.path.isdir(base):
        return "/tmp"
    d = os.path.realpath(base)
    while True:
        if os.path.lexists(os.path.join(d, ".git")) or os.path.lexists(os.path.join(d, ".claude")):
            return "/tmp"
        parent = os.path.dirname(d)
        if parent == d:
            return base
        d = parent


def dead_of(stdout):
    return re.findall(r"^  FAIL (.+)$", stdout, re.M)


def stop_group(proc, grace=5.0):
    """TERM to the process group of a suite, KILL after the grace, and a last KILL for what is left.

    The leader is a bash with traps: given the TERM it removes the paths it made, and that is why
    it is asked first. What a check had started is in the same group and is swept at the end.
    """
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proc.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proc.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        pass


def remove_root(root):
    """The root, and the paths the suite recorded outside it in .extra.<pid>."""
    try:
        names = os.listdir(root)
    except OSError:
        names = []
    for n in names:
        if not n.startswith(".extra."):
            continue
        try:
            with open(os.path.join(root, n), encoding="utf-8", errors="replace") as fh:
                outside = [l.rstrip("\n") for l in fh]
        except OSError:
            continue
        for p in outside:
            if p.startswith("/") and p != "/" and os.path.lexists(p):
                shutil.rmtree(p, ignore_errors=True)
    shutil.rmtree(root, ignore_errors=True)
    if os.path.lexists(root):
        # A fixture that took its own permissions away is not removable until they are given back.
        subprocess.run(["chmod", "-R", "u+rwX", "--", root], capture_output=True)
        shutil.rmtree(root, ignore_errors=True)


def run_suite(copy, env, timeout, suite):
    """-> (stdout, ran_out_of_time)."""
    proc = subprocess.Popen(suite, cwd=copy, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, errors="replace",
                            start_new_session=True)
    with _lock:
        _running[proc.pid] = proc
    try:
        try:
            out, _ = proc.communicate(timeout=timeout)
            return out, False
        except subprocess.TimeoutExpired:
            stop_group(proc)
            try:
                out, _ = proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                out = ""
            return out or "", True
    finally:
        with _lock:
            _running.pop(proc.pid, None)


def run_one(entry, index, fast=False, timeout=None, suite=None, base=None, repo=None, pkg_name=None):
    """One entry, in a root of its own that is gone when this returns. -> a dict, see CLASSES."""
    name, rel, anchor, replacement = entry
    repo = repo or REPO
    pkg_name = pkg_name or PKG_NAME
    suite = suite or suite_command(pkg_name)
    began = time.time()
    res = {"name": name, "file": rel, "anchor": anchor, "class": None, "dead": [], "note": ""}
    root = tempfile.mkdtemp(prefix="mkm.", dir=base or temp_base())
    with _lock:
        _roots.add(root)
    try:
        copy = os.path.join(root, "case")
        shutil.copytree(repo, copy, ignore=shutil.ignore_patterns(".git"))
        try:
            apply_mutation(os.path.join(copy, pkg_name), rel, anchor, replacement)
        except AssertionError as exc:
            res["class"], res["note"] = "ERROR", str(exc)
            return res
        # THE ENTRY THAT MADE THIS COPY IS NAMED TO THE SUITE, by its index in
        # MUTATIONS, for the one check that reads this file: "every mutation in the
        # register still applies" excuses that entry, whose anchor is gone because it
        # was applied, and holds every other. Without the name that check died in every
        # run, and its own entry could not show that it catches ANOTHER entry left
        # dangling.
        # The two knobs are the runner's to set, per stage: one a caller left in its environment would
        # cut the whole suite of a full run down to one check.
        env = {k: v for k, v in os.environ.items() if k not in ("MK_ONLY_CHECK", "MK_STOP_AT_RED")}
        env.update(MK_MUTATION_APPLIED=str(index), TMPDIR=root, MK_RUN_ROOT=root)
        if not fast:
            out, late = run_suite(copy, env, timeout, suite)
            dead = dead_of(out)
        else:
            out, late = run_suite(copy, dict(env, MK_ONLY_CHECK=name), timeout, suite)
            dead = dead_of(out)
            if not late and name not in dead:
                # The own check lived. That is the verdict; what else is red is only named.
                left = None if timeout is None else max(1.0, timeout - (time.time() - began))
                out2, late2 = run_suite(copy, dict(env, MK_STOP_AT_RED="1"), left, suite)
                dead = dead_of(out2)
                if late2 and not dead:
                    res["note"] = "the look for another red check ran out of time"
        res["dead"] = dead
        if late:
            res["class"], res["note"] = "TIMEOUT", "no verdict within %s s" % timeout
        elif name in dead:
            res["class"] = "RED"
        else:
            res["class"] = "ALIVE"
        return res
    finally:
        remove_root(root)
        with _lock:
            _roots.discard(root)
        res["seconds"] = time.time() - began


def abort_all():
    """Stop every suite in flight and remove every root in use. Called by the signal handlers."""
    with _lock:
        procs = list(_running.values())
        roots = list(_roots)
    for proc in procs:
        stop_group(proc, grace=2.0)
    for root in roots:
        remove_root(root)


def install_signal_handlers():
    def handler(signum, frame):
        abort_all()
        os._exit(128 + signum)
    for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, handler)


def entry_lines(res):
    c, name = res["class"], res["name"]
    if c == "RED":
        return ["  RED    %s" % name]
    if c == "ALIVE":
        return (["  ALIVE  %s   <- the mutation did not kill its assertion" % name]
                + ["           also dead: %s" % o for o in res["dead"]]
                + (["           %s" % res["note"]] if res["note"] else []))
    if c == "TIMEOUT":
        return ["  TIMEOUT %s   <- %s" % (name, res["note"])]
    return ["  ERROR  %s\n           %s" % (name, res["note"])]


def run_all(chosen, jobs=1, fast=False, timeout=None, say=None, **kw):
    """The entries in register order -> their results in register order.

    With jobs > 1 they run side by side and `say` is called as each one ends, so the order of the
    lines is the order of arrival and the order of the returned list is still the register's.
    """
    indexed = [(MUTATIONS.index(e) if e in MUTATIONS else -1, e) for e in chosen]
    out = [None] * len(indexed)

    def one(i):
        res = run_one(indexed[i][1], indexed[i][0], fast=fast, timeout=timeout, **kw)
        out[i] = res
        if say:
            with _lock:
                say(res)

    if jobs <= 1:
        for i in range(len(indexed)):
            one(i)
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            for f in [pool.submit(one, i) for i in range(len(indexed))]:
                f.result()
    return out


def report_text(results, wall, jobs, fast, timeout):
    count = dict.fromkeys(CLASSES, 0)
    for r in results:
        count[r["class"]] += 1
    spent = sum(r.get("seconds", 0.0) for r in results)
    lines = ["manager-kit mutation report",
             "mode      %s, %d at a time, limit %s" % (
                 "fast (the own check of an entry first)" if fast else "the whole suite for each entry",
                 jobs, ("%s s" % timeout) if timeout else "none"),
             "entries   %d" % len(results),
             "time      %.0f s on the clock, %.0f s summed over the entries" % (wall, spent)]
    lines += ["%-9s %d" % (c, count[c]) for c in CLASSES]
    for c in ("ALIVE", "TIMEOUT", "ERROR"):
        for r in results:
            if r["class"] != c:
                continue
            lines.append("")
            lines.append("%s  %s" % (c, r["name"]))
            lines.append("  file    %s" % r["file"])
            lines.append("  anchor  %s" % (repr(r["anchor"])[:160] if r["anchor"] is not None else "(an append)"))
            if r["note"]:
                lines.append("  note    %s" % r["note"])
            for o in r["dead"]:
                lines.append("  also dead  %s" % o)
    slow = sorted(results, key=lambda r: -r.get("seconds", 0.0))[:5]
    lines.append("")
    lines.append("slowest entries")
    lines += ["  %6.1f s  %s" % (r.get("seconds", 0.0), r["name"]) for r in slow]
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="The mutation probe. With no argument: every entry, one after the other, the "
                    "whole suite for each, as it always was.")
    ap.add_argument("names", nargs="*", help="run the entries whose assertion name contains one of these")
    ap.add_argument("-j", "--jobs", type=int, default=1, help="entries run side by side (default 1)")
    ap.add_argument("--fast", action="store_true",
                    help="ask the own check of an entry first and alone; see the comment above run_one")
    ap.add_argument("--timeout", type=float, default=None,
                    help="seconds a suite may run for one entry; past it the entry is TIMEOUT")
    ap.add_argument("--report", default=None, help="write the report for a reader to this file")
    args = ap.parse_args(argv)
    if args.jobs < 1:
        ap.error("--jobs must be at least 1")
    chosen = selected(args.names)
    install_signal_handlers()
    print("manager-kit mutation probe\n", flush=True)
    began = time.time()

    def say(res):
        print("\n".join(entry_lines(res)), flush=True)

    results = run_all(chosen, jobs=args.jobs, fast=args.fast, timeout=args.timeout, say=say)
    count = dict.fromkeys(CLASSES, 0)
    killed = set()
    for r in results:
        count[r["class"]] += 1
        if r["class"] == "RED":
            killed.update(r["dead"])
    text = report_text(results, time.time() - began, args.jobs, args.fast, args.timeout)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(text)
    print()
    survived = count["ALIVE"] + count["ERROR"]
    if args.fast or args.timeout or args.jobs > 1 or count["TIMEOUT"]:
        print(text)
    if survived:
        print("RED: %d of %d mutations survived" % (survived, len(chosen)))
    if count["TIMEOUT"]:
        print("%d of %d mutations ran out of time and have no verdict" % (count["TIMEOUT"], len(chosen)))
    if survived or count["TIMEOUT"]:
        return 1
    print("Every mutation killed its own assertion.")
    print("Mutations run: %d. Distinct assertions killed across all of them: %d%s."
          % (len(chosen), len(killed), " (the own checks only, which is all --fast asks)" if args.fast else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
