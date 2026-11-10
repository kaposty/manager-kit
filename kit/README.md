# manager-kit

A Claude Code plugin for the case where one session coordinates and other hands carry.
It holds one boundary: **the coordinating session may write bookkeeping and hand work
out. It may not do the work with its own hands.**

The boundary is a path, not a resolution. Anything under a `.claude` directory, every
`*.md` file and the session scratchpad is bookkeeping. Everything else is work. A write
past that line is refused by a `PreToolUse` hook, so holding it is not a matter of
remembering it.

**The scratchpad is the session's own throwaway directory and nothing wider.** It is
`/tmp/claude-<uid>/<project>/<session>/scratchpad` [`/private/tmp` is the same directory
on macOS and classifies the same], and `/tmp` itself is NOT in it. Measured 2026-09-08
over 6919 stops of a foreign project: 2613 of them, 37.8 percent, land in that one
directory, and 26 of the 27 read by hand were false alarms. The wider rule was measured
too and rejected: taking everything outside the work tree would silence at least 202
stops that were writing real production code.

**And the scratchpad is bookkeeping only while the command around it stays in it.** Three
shapes reach the work tree without naming it anywhere on the command line, and for those
the scratchpad answer does not hold: a script written into the scratchpad and RUN by the
same call, a heredoc body handed to an interpreter that runs it, and a git subcommand that
rewrites the working tree [`rebase`, `merge`, `revert`, `cherry-pick`, `am`, `switch`,
`pull`, `clean`, a writing `stash`, `worktree add|remove|move`, `reset --hard|--merge|
--keep`]. The first two count only when the unreadable body names a path this same measure
calls work, which is what keeps a scratchpad script that rewrites a Markdown plan quiet.
Measured 2026-09-08 over the 2263 stops the scratchpad axis had silenced in a foreign
project: 165 become a stop again, 140 of the 141 silent passes a full reading found are
closed, and 25 calls that were false alarms before the axis are false alarms again. Nothing
outside those 2263 moved, in either direction.

## Why a path and not a judgement

The measured failure this exists for: a coordinating session produced 39 commits in one
day against its own written doctrine. The rule was never disputed. It was walked around,
because each single act of working was useful on its own. An intention cannot be
measured, and a rule nobody can fail is a rule nobody keeps.

## Install

```
claude plugin marketplace add kaposty/manager-kit --scope local
claude plugin install manager-kit --scope local
```

From a clone of the repository the source can be its path instead, as in
`claude plugin marketplace add /path/to/manager-kit --scope local`. Nothing else. Your project's `settings.json` is not touched.

### What the kit does to your repository, and what you do yourself

The record `.claude/manager-kit.log` holds the refused command itself, so it can hold a secret
that stood in that command, and the record lives in your project where `git add -A` finds it.
The kit does three things about that. It leaves two to you.

**The kit does:**

- **It blacks the value out of what it writes and repeats.** In the record, in the refusal and in
  the reason of a declared crossing, the value of a secret is replaced by `[redacted]` and the
  rest of the command stays. The verdict is taken first, from the whole command, so blacking out
  never changes what is refused. If the blacking out itself fails, the refusal still goes out and
  the record line is a short fixed text, never the command.
- **It makes a new log private.** A log this kit makes has mode 0600. A log that was already
  there keeps its mode and its lines: nothing in it is rewritten or blacked out afterwards.
- **It writes four lines into `.git/info/exclude`**, once, when it makes the log:
  `/.claude/manager-kit.log*`,
  `/.claude/manager-kit.seen`, `/.claude/manager-kit.role` and `/.claude/manager-exception`. That
  file belongs to the repository and not to the working tree, so the lines show in no `git status`,
  go into no commit and travel to no clone. It writes them only when `.git` is a directory inside
  the project. A `.git` that is a file or a link (a linked worktree, a submodule) is not followed
  and nothing is written, and the kit never touches your `.gitignore`. A log an older version made
  keeps the one line that version wrote; the other three are added when a new log is made, or by you.
  If you want the record in history, delete the lines, or `git add -f` the file.

**You do:**

- **Put the log in `.gitignore` if the team should share the exclusion.** `.git/info/exclude`
  is one clone's. A fresh clone gets its own line when its own log is made.
- **Add the line yourself where the kit does not:** in a submodule or a worktree whose `.git` is
  a file, and in a project that has no repository yet. The role file, the seen file and the
  marker hold a process number, a date and, for a few minutes, the reason you wrote.
- **Look through an old log before you commit it.** The kit does not rewrite what an earlier
  version wrote.

**What blacking out does not catch**, said here because the alternative was to make the record
unreadable. It reads these, and blacks out only the value:

- `NAME=value` where the name holds `PASSWORD`, `PASSWD`, `SECRET`, `TOKEN`, `KEY` or `CREDENTIAL` as a
  whole word (`DB_PASSWORD`, `apiKey`) or ends in one (`GITHUBTOKEN`). `KEY` at the end of a glued name
  counts only behind `API`, `ACCESS`, `SECRET`, `PRIVATE`, `AUTH`, `SSH`, `MASTER`, `LICENSE`, `SIGNING` or
  `ENCRYPTION`: `APIKEY=...` loses its value, `MONKEY=banana` and `KEYMAP=us` keep it. Not names ending
  `_FILE`, `_PATH`, `_DIR`, `_NAME`, not a value that starts with `$`.
- `"name": "value"` in JSON and `name: value` in YAML, when the last word of the name is one of those
  words (`api_key`, `client_secret`, `dbPassword`; `token_type`, `max_tokens` and `primary_key` keep their value).
- The value of `Authorization:` when `-H` or `--header` stands before it, a scheme word (`Bearer`, `Basic`,
  `Digest`, `Token`, `Negotiate`, `NTLM`, `OAuth`) stands after it, or the name is a quoted key; the scheme
  word stays. The `X-...-Key`, `-Token`, `-Secret` headers. A `Bearer` value with a digit in it.
- `--password`, `--token`, `--secret`, `--api-key` and their prefixed forms, `mysql -pvalue`,
  `curl -u user:password` (also `--user`, `--proxy-user`, only after `curl`), `sshpass -p value`, and the
  password in `scheme://user:password@host`.
- The forms `sk-...`, `ghp_...` (also `gho_`, `ghu_`, `ghs_`, `ghr_`), `github_pat_...`, `AKIA...`, `ASIA...`,
  `xoxb-...` (also the other `xox` kinds and `xapp-`), `AIza...`, a JWT, and the body of a
  `-----BEGIN ... PRIVATE KEY-----` block.

It does not catch:

- A secret that stands with no name beside it (`echo value | docker login --password-stdin`), the
  password flag of another tool (`docker login -p value`, `redis-cli -a`, `zip -P`, `ldapsearch -w`,
  `gpg --passphrase`), and `-u user:password` of any command that is not `curl`.
- `name = value` with blanks around the `=` (INI, TOML, a `.properties` file).
- An unquoted value in JSON or YAML that is a plain word (`password: postgres`), a number, or shorter than 16
  characters with no digit in it, and of an unquoted YAML value everything after the first word.
- A key that is not named by those words, or a `KEY` glued behind a word that is not listed (`STRIPEKEY`),
  and secrets named `PASS`, `PWD`, `PIN`.
- A header with no flag and no scheme word (`http GET url Authorization:value`).
- A quoted piece with a blank or a bracket in it inside a value that has no quotes (`--password=ab"c d"`
  keeps the part from the blank on). Only letters, digits and `. _ ~ + / @ % ! ^ * # -` count as plain.
- A private key block with headers (`Proc-Type: 4,ENCRYPTED`) and one with no END line.
- Other token forms: Stripe (`sk_live_...`), GitLab, npm, SendGrid, Twilio, and the rest of the world.
- A secret in a file name.

It over-reaches in these places, because they cost less than an unreadable record: in `NAME=value` a name
with the word as a whole word (`StrictHostKeyChecking=no`, `sort_keys=True`, `KEY_ID`, `max_tokens=1024`,
`keys=[...]`) loses its value; an `X-...-Key`
header without quotes takes the rest of the line with it; a JSON key that ends in `token` and holds a page
cursor loses it; and `Authorization: Bearer word` in prose loses `word`. Your own session transcript holds the
command whole whatever the kit does.

The public source is `kaposty/manager-kit`, and the two commands above name it. The `/plugin`
form from inside a session is not measured: whether it takes the same source and the same
scope as the shell form has not been run, so it is not written here as working.

**The scope is deliberate, not decoration.** Leaving it off installs at user scope, which
puts the guard in every project you open, including ones where you are the only carrier and
there is nobody to hand work to. It is needed on BOTH commands, not just the second.

**Never install at user scope while working on this kit itself.** `hooks/role-guard.sh`
is not a Markdown file and does not sit under a `.claude` directory, so by the kit's own
measure it is a work path, and the guard will refuse your edits to it. That is the measure
being consistent rather than a defect, but it makes developing the kit tedious. Scope the
install to the repository you are actually coordinating.

**After you change the kit, the running copy is still the old one.** A plugin taken from a
directory is copied into a version-keyed cache, not linked to your working tree, so editing
`hooks/` changes nothing about what actually runs. Worse, `claude plugin install` answers
"already installed" and does nothing at all. Three steps, and all three are needed:

```
# 1. raise the version in BOTH .claude-plugin/plugin.json and
#    ../.claude-plugin/marketplace.json, which sit one directory apart
claude plugin marketplace update manager-kit
claude plugin update manager-kit@manager-kit --scope local
```

Without the new version the cache key is unchanged and nothing is copied. Without the
qualified `plugin@marketplace` name, `update` reports "Plugin not found" even though it is
installed. Check that it worked rather than trusting it:

```
diff -r <your checkout>/kit/hooks ~/.claude/plugins/cache/manager-kit/manager-kit/<version>/hooks
```

This caught a real one on 2026-09-07: three repaired defects, a green suite, and a live
guard that still carried none of them.

**What ships is `kit/`, and that is the only thing that decides it.** The marketplace
manifest at the repository root points `source` at `./kit`, so an install receives that
directory and nothing above it. There is no exclusion field to reach for [checked
2026-09-07 against Claude Code 2.1.220: `files`, `exclude`, `excludeFiles`, `ignore`,
`include`, `gitignore`, `excludePaths` and `respectGitignore` are each answered with
"Unknown field ... Claude Code ignores it at load time"] and `.gitignore` is not consulted
either, so the repository's own `.claude/` bookkeeping is kept out by lying outside the
package root rather than by being named anywhere.

The plugin does not set environment variables, because a plugin cannot. If you want
`DISABLE_AUTO_COMPACT`, put it in your project's `.claude/settings.json` yourself. The
kit reports whether it is set and never sets it.

## What it does, in the turns where it does anything

**It stops you.** A write to a work path is refused. The refusal reaches the model with
what to do instead, and reaches you with what was stopped and how often that has now
happened. Those are two different channels of the hook protocol and both are used
[`permissionDecisionReason` and `systemMessage`, read out of Claude Code 2.1.220 on
2026-09-07].

**It lets a subagent through, and it lets a carrier through.** The guard stops your own
hands, not the hands you delegate to. That is the whole point: handing the work out is the
move it is pushing you toward, so handing it out has to be the easy path. A second session
in the same directory is one of those hands, and the guard steps aside for it as long as
the role file names a coordinator whose process is still alive.

Until 2026-09-07 it did not. A carrier got the refusal word for word, including the line
telling it that it was the coordinating session, about a session the kit had already
decided was not. Under the false-alarm budget in `GOAL.md` a single carrier would have
spent the whole week in an afternoon. A role that cannot be established still counts as
the coordinator, so a hole in the session register costs a false stop and never a silent
pass.

**It lets you cross, and remembers that you did.** Write one line of reason into
`.claude/manager-exception` in a call of its own, then repeat. It passes, the marker is
spent, and one
line goes into `.claude/manager-kit.log`. One declaration buys one crossing, so a
standing exception cannot quietly become a standing permission.

**Declare it immediately before the call it is for.** A marker older than five minutes is
discarded rather than honoured, and the call it was lying under gets the ordinary refusal.
Without that rule a declaration written for one call, and left unspent because that call
turned out to be invisible to the Bash half, quietly pays for an unrelated one later, and
the record then carries a crossing with the wrong reason attached to it. Seen happening
2026-09-07, which is why the rule exists.

The number of those lines is the measurement. A crossing that was worth making costs you
nothing. One that was not is on the record, and at the end of a week you can count them.

In every other turn the kit is silent, and that is deliberate: you should not be able to
tell from your terminal that it is installed, except where it stopped you.

## Moving the role without closing anything

Until now the role was handed out by order of arrival and by nothing else: the session that
`SessionStart` measured alone in the project took it, and moving it meant closing every
session there and starting exactly one. That failed in practice more than once.

Type `/manager-kit:take-over` in the session that should coordinate. From its next turn that
session is the manager and the one that held the role is a carrier. Nothing is closed and
nothing is restarted. It works because the role is read off `.claude/manager-kit.role` fresh
every time: `manager-stamp.sh` on every prompt, the role guard on every tool call. The
command writes that file and the next turn reads it. It finds the directory the session stands in by
asking the process, and `lsof` prints that name with escapes. A backslash, a tab, a newline and a few
more are reversed exactly. A control character is printed as `^A`, which a literal `^A` in a name is
printed as too, so a name with either cannot be read: the command refuses and writes nothing, and the
count of sessions in a project is not taken while such a session lives, so no session claims the role
by counting. The same goes for a name that ends in a newline, which the shell cannot carry.

**One thing lags, and the command says so.** The long role text is injected at
`SessionStart`, so a session that is already running does not get it. It gets the one-line
stamp every turn and the guard names the role when it refuses; the full text arrives after a
restart, a `/clear` or a compaction. That is a limit, not a fault.

**It refuses rather than guessing.** The record has to name the session's pid, measured off
the socket register. When that cannot be measured, the command writes nothing and says so: a
record with a pid that cannot be parsed makes the guard call every session in the directory
the manager and the prompt hook call every one of them a carrier, which is the split
identity this kit has already had to repair twice.

**It records the session id when it can measure one, and never when it cannot.** Until
0.15.0 it never could: nothing in the environment of a Bash call was found to carry the id
[measured 2026-09-07]. Measured 2026-09-29 under Claude Code 2.1.284, `CLAUDE_CODE_SESSION_ID`
carries the id the hooks are handed. A guess would still be worse than a gap, because both
readers compare the recorded session id before they compare the pid, so the value is taken
only when it has the shape the hooks are handed [36 characters, lowercase hex, grouped
8-4-4-4-12; 180 of 180 real session ids counted on the same day] AND `CLAUDE_PID` names the
very process this command measured off the parent chain. `CLAUDE_CODE_HOST_SESSION_ID` is
that id with a `local_` prefix and is refused rather than stripped.

Where either half is missing the second field is the literal `claimed-by-pid`, exactly as
before, the pid carries the identity, and this session's next PROMPT writes the real id in.
That fallback is what makes the repair safe; it is not sufficient on its own, because while
the placeholder stands the pid is the whole of the identity, so a restart before that prompt
erases it and the chair falls to whoever starts next. **With the id recorded, a restart of the
same conversation keeps the role with nothing typed. A new conversation does not: it carries
a different id, reads the record as somebody else's, and needs the command again.**

The transition is one line in `.claude/manager-kit.log` under its own event, `handover`. It
is not a stop and not a declared crossing, so the count the week is measured on does not move.

## The Bash gap, named rather than hidden

This is protection against a slip, not a sandbox: it stops a coordinator who is about to do
the work by hand, and somebody who means to get past it gets past it.

For `Edit`, `Write` and the other file tools the tool names the path, and the path is read
where it lands, the way the kernel walks it. A `..` is walked, in both directions:
`.claude/../src/a.py` is work and `src/../.claude/a.md` is bookkeeping. A symlink is followed:
a `.md` that is a link onto a work file is work, and so is a path through a directory link
that leads out of `.claude`. A link that does not resolve is work, and the refusal says it
could not be read. A relative path is asked against the `cwd` the hook was handed. No process
is started for this unless a link is really there.

**For `Bash` it is a pattern match over the command text, and a shell command is not
text.** It reads redirections in every spelling, with a space around the target or none
(`>`, `>>`, `2>`, `&>`, `>|`), the write verbs `rm`, `mv`, `cp`, `tee`, `truncate`, `patch`,
`dd`, `install`, `ln`, `shred`, `chmod`, `chown`, `rmdir`, `touch`, `mkdir`, `mkfifo`,
`unlink`, `rsync`, `scp`, `ditto` and `split`, the programs that name what they write in an
option (`curl -o`, `curl -O`, `wget -O`, `tar -x`, `tar -c`, `unzip -d`, `sort -o`, `zip`),
`sed -i`, `perl -i`, `ruby -i`, `git apply` and `git clone`. It drops heredoc
bodies because they are data rather than commands, and it blanks out a quoted segment only
when the content carries a shell metacharacter, so that `grep -rn "a > b" src/` is not read as
a redirection; a quoted segment that stands where a target stands is read whole, so
`echo x > "/x/Mobile Documents/.claude/a.txt"` is bookkeeping and `echo x > "src/a&b.py"` is
work. A relative target is read behind the `cd` of the same command: `cd src && echo x > a.py`
is work and `cd .claude && cat > a.txt` is not. Behind `&&` that needs no look at the disk;
behind a plain `;` or a newline it holds only if the directory is there, because a `cd` that
fails leaves the command where it stood. The one
quoted segment that is never blanked is the body a shell was handed with `-c`, because
that body is a command and not text: `sh -c "cd /tmp && rm -rf src/x.py"` is read right
through, as deep as the quotes go. Unless the shell stands behind an `ssh` or a `docker`.
Then the body is a command of another machine, it is blanked like any other text, and the
third hole below is what covers it.

**What it cannot read it says.** A target it could not read stays work, and the refusal says
so and says what makes it readable. That is the shape of `> $TMP/lauf.json`: a variable this
command assigns is read (`TMP=.claude/lauf; echo x > $TMP/a.json`, with `export`, `declare` and
the others), and one it does not assign is not, because the hook runs before the command does
and a variable of an earlier Bash call does not survive that call. A file named by `source` is
not read for it: it can compute what it sets. So `source umgebung.sh; echo x > $QQ_Q/a.txt` is
refused even when the variable points under `.claude/`, and the way out is one word longer:
spell the path, or assign it in the same command. The same goes for `$(...)` as a target, and for
a command too long to read.

The holes are written down rather than discovered later:

- **A write a program performs internally is invisible.** `python build.py` can rewrite
  your whole tree and the guard sees a command with no write verb in it. So can `npm install`,
  `pnpm add`, `make`, `cargo fmt`, `cargo add`, `go fmt`, `go mod tidy`, `black`, `ruff --fix`,
  `eslint --fix`, `prettier --write`, `pip install`, `uv add`, `mvn`, `gradle`, `dotnet build`,
  `composer`, `bundle install`, `alembic`, `psql -f`, `terraform apply` and `kubectl apply`: no
  target stands on their line in a form this measure reads, and stopping them all stops every build.
  A compiler's `-o`, `pandoc -o`, `openssl -out` and `base64 -o` are not read either: 0 to 4
  distinct uses in 136164 real commands.
- **A program text is read for the write it spells out, and for nothing else.** `python3 -c`,
  `node -e`, `ruby -e`, `perl -e` and `awk` are read for the calls that write by name: `open` with
  a write mode, `write_text`, `shutil`, `os.remove` and its neighbours, `writeFileSync`, `File.write`,
  `FileUtils`, `print > "x"`, in the text of a `-c` and in the body of a heredoc handed to an
  interpreter (`python3 - <<'PY'`) alike. A literal target is measured like any path, and so is a
  name the same text assigns a literal (`p = "src/a.py"; open(p, "w")`). Everything else passes in
  silence, and that is this limit: `open(sys.argv[1], "w")`, a path put together at runtime, an
  imported helper, `from shutil import copy`, a subprocess. Most of these programs only read,
  5797 distinct real `python3 -c` against 434 with a write word in them, and stopping the write to a
  name would have been 182 distinct stops, 127 of them in a main session, read by hand mostly
  bookkeeping edits. A named limit beats stopping every one-liner. A redirection on the line that
  OPENS a heredoc is still read, so `cat > src/x.py <<'EOF'` is caught. A heredoc handed to a
  shell (`bash <<'EOF'`) is not read.
- **A git subcommand that rewrites the tree and names no file passes alone.** `git stash pop`,
  `git pull`, `git merge`, `git rebase`, `git reset --hard`, `git cherry-pick` and `git clean`
  name nothing to measure. They count only as a shape behind a scratchpad path, see below.
  **A commit is no write into the work, so it is free, even when it takes along the work of a hand:**
  `git commit -a` and `git add -A && git commit` both pass. The boundary this kit holds is a path,
  and a commit writes none. Until 2026-11-07 `git commit -a` was stopped and `git add -A && git
  commit` was not, 10 distinct commands against 232 in the main sessions of one corpus, so the stop
  guarded nothing and was a false alarm each time it fired.
- **A redirection glued to its word is read, and the exceptions are the shell's own.** `echo x>file`
  and `echo x>>file` are `echo x` and a redirection, and read like `echo x > file`: since 2026-11-07,
  before that they passed, because a `>` inside a word is also what a comparison in program text
  looks like. What is left of a `>` once the quoted text and the heredoc bodies are gone is the
  shell's, with these exceptions that stay as they were: arithmetic (`$((1>2))`, `((a>b))`) and
  `[[ a>b ]]`, a descriptor alone (`2>file`, `2>&1`, `>&2`), `=>`, `->`, `>=`, and a `>` inside
  `${...}`. What is glued behind the `))` that closes `((...))` is read since 2026-11-08, because bash
  makes the file: `((a>b))>file` writes `file`. `[ a>b ]` is a redirection into a file named `b`, and read as one, like `[ a > b ]`.
  It is read only where the scan can tell text from syntax, and the scan reads one line at a time. A
  quoted string that runs over several lines (a commit message with its `Co-Authored-By: ... <a@b.c>"`
  trailer, the program text of `python3 -c "..."`) is text, so a `>` on its lines is not read; on the line
  that opens such a string the words up to the quote are. A line with an escaped quote (`\"`), a `\>`,
  and a `<` with no letter, digit or `_` before it (`<name>`, `/<id>/logs`) are not read either. Read
  without these guards it stopped 446 of 133542 distinct real commands that had passed, none of them a
  write. What they leave unread passes as it did before: `git commit -m "a` and `b" ; echo x>f`, with the
  redirection on the line where the string closes, is one.
- **A `cd` is only read where it is certain.** Behind `||` (but see below), a pipe, a `&`, a `then`,
  in a subshell that has closed or under `env`, `sudo` and `nohup` it does not move the target,
  because it either did not happen or happened elsewhere. `cd x || exit 1` and `|| return` are the
  exception since 2026-11-07: the command ends or the cd worked, so it holds as it does behind `&&`.
  `|| true`, `|| echo no` and `|| { echo no; exit 1; }` still do not move it: the first two go on after
  a failed cd, and the braces are not read. A `cd` into a directory the same command made earlier
  (`mkdir -p .claude/n; cd .claude/n; echo x > a.txt`) holds behind `;` and a newline too; one the
  command makes behind the `cd` does not. `cd` is read textually: a function that changes directory,
  or a sourced file, is not.
- **A hook that fails to answer lets the action through, and the classifier is held under its budget.**
  A hook that runs past its ten seconds, does not start or prints JSON that is invalid is a failure that
  Claude Code reports and then goes ahead from. The program (2.1.318) says it of the key `onFailure` of a
  hook entry: "'continue' (default): the failure is reported and the action goes ahead. 'block': the
  failure counts as exit code 2". No entry of `hooks.json` sets it, and the kit ships the default. An
  owner can set `"onFailure": "block"`; the price is that a fault in the guard, or a script that is not
  there, then blocks every action of the session. The kit is protection against a slip, not a sandbox. It is
  read out of the program and not run: a nested `claude -p` fails here with `OAuth session expired`. So the
  classifier answers in time on its own account: a command over `MK_READ_LIMIT` characters, or naming
  more than `MK_TARGET_LIMIT` targets, is work and says it could not read it. Before 2026-11-07 `a"b c"`
  four thousand times (24 KB) took 17.4 s, `rm a.md;` seven thousand times (56 KB) 14.6 s, and a work
  target behind them was never reached.
- **An unterminated quote falls through unparsed**, and the rest of that line is read as
  it stands.
- **A command sent to another machine is not read.** `ssh` is not in the list of programs
  whose arguments are inspected, and for `scp` and `rsync` a destination with a colon before its
  first slash is held to be on another machine, so `ssh host "rm -rf /srv/app/src/x.py"`
  passes as bookkeeping, and so does `scp local.py host:/srv/app/src/x.py`. Measured
  against 46742 real commands from a production corpus: 4460 of them, 9.5 percent, are
  ssh, and 635 carry a clear write in their text. This is deliberate and not an oversight.
  Closing it means classifying paths on a machine this kit has never measured, and a rule
  guessed rather than measured is how two false-alarm classes got built into this
  classifier before. The boundary this kit holds is the one in front of you.

  **`rsync` was measured on 2026-09-09 and left out on purpose, and it is in since 2026-11-07,
  because the condition below was met: the scan now follows a continued line to its last word,
  so the destination is read wherever somebody put the line break.** The frozen 46587-payload
  corpus carries 16 payloads naming it and 10 real calls in command position. Seven push a
  local tree to `root@host:/opt/...`, three pull a remote directory into `~/ingest-beweis-
  <stamp>/`. Adding `rsync` to the write verbs, with its destination read last the way
  `cp(1)` reads it and a destination carrying a colon before its first slash held to be on
  another machine, moves 5 stops and loses none: 3 of the 5 are the local pulls, correct
  under this measure, and 2 are pushes to a host, stopped on the BACKSLASH of a continued
  line because `rsync` calls are long enough to be written over several of them and the
  destination is never on the line the operands are read from. That is half a remote
  command read, which `elsewhere()` calls the worst of both halves, and it makes the
  verdict depend on where somebody put a line break. It becomes buildable when the operand
  scan crosses a masked newline; not before. `docker exec`
  and `docker run` are the same decision for the same reason, and they are not in that list
  either: measured 2026-09-08 against 93614 distinct real commands, 463039 weighted, 1159
  distinct and 9718 weighted hand a command to a container, so `docker exec api sh -c "rm -f
  src/x.py"` passes as bookkeeping. A bind mount makes that a write on your own disk, and
  the measure cannot see the mount.

  **That sentence was false for one version, and it is true again since 2026-09-08.** The
  `-c` repair in 0.8.0 reads the body behind the `-c` of a shell as command text, which is
  right, and it did so wherever that shell stood. So half a container body was read: a body
  carrying a metacharacter was, one without was not, and the two spellings of one decision
  were answered two ways. Measured against the shipped 0.8.0 function, `docker exec api
  sh -c "rm -f src/x.py"` came back bookkeeping while `docker run img sh -c "echo hi >
  /data/x.py"` and `docker exec api sh -c "cd /srv && rm -rf src/x.py"` came back work, on
  paths that do not exist on this machine. Half a remote command read is the worst of both
  halves: it does not catch what it would have to catch to be worth anything, and it stops
  on paths nobody here can check. The hole is one hole again: in a body whose surrounding
  command is `ssh`, `docker`, `docker-compose` or `podman`, nothing is read, redirections
  included.

  The list is measured and not guessed, because every name in it makes the guard QUIETER.
  Counted 2026-09-08 over 81089 distinct real commands, 451159 weighted: `ssh` stands in
  5123 distinct and 43280 weighted, `docker` in 2028 and 17213, `docker-compose` in 287 and
  2449, `podman` in 1 and 1. `kubectl`, `nerdctl` and `lxc` are not in it, because not one
  of them stands in that corpus even once, so a command handed to them stays loud.

  **The price is one command in that corpus and it is named here rather than left to be
  found.** Over the same 81089, closing the half hole moved 4 distinct and 5 weighted from
  a stop to silence and nothing the other way; the rate went from 10.1543 to 10.1493 percent
  distinct, 9.5665 to 9.5654 weighted. Three of the four write only inside the
  container. The fourth mounts a directory of this machine with `-v` and writes into it, so
  the write really does land on this disk; it was stopped before this repair, and it was
  stopped under the name of the path INSIDE the container, which is a name nothing here can
  resolve. Reading the host half of a `-v` is a rule of its own and it is not written: 69 of
  the 92 `docker run` calls in that corpus carry a bind mount, 559 of 637 weighted, so it is
  a real class and it is not one to guess at.
- **A write verb written with a path in front of it is not a write verb.** `/bin/rm -rf
  src/x.py` passes as bookkeeping, because the verb list is read off the whole word. The
  shell in front of a `-c` IS read by its name since 2026-09-08, and the verb list was left
  alone rather than widened along with it, because that is a rule of its own and it was not
  measured here. Same corpus: 3 distinct and 6 weighted carry the shape.
- **A variable given two values in two branches is resolved to one of them.** Since
  2026-11-02 a variable is replaced by the value the same command assigns it, whatever
  stands behind the name, so `F=.claude/x; date > $F.log` is read as the bookkeeping write
  it is. The price is a branch: `if true; then F=src/b; else F=.claude/a; fi; date > $F.log`
  writes `src/b.log` and passes in silence, measured with real hook input against the
  shipped guard. It was paid on purpose. Over the 122 stops of the week this kit failed
  its measure in, the three narrowings of that day took 33 false alarms off and silenced
  none of the 50 stops that were correct or could not be decided.
- **An operand the scan cannot see as a path is not judged.** Two shapes, both measured
  with real hook input on 2026-11-02 and both silent before and after that day's repairs:
  `find src -exec mv -t .claude/x/ {} +` empties `src/` into the bookkeeping, because the
  files `mv` removes are named by `{}` and not on the line; and `mv -- -tsrc/ .claude/a.md`
  moves a work file whose name starts with a dash, because the scan skips such a word even
  behind the `--` that makes it an operand. The second needs a file nobody names that way;
  the first is a real command and the reason `find ... -exec` deserves suspicion.

Five more used to be on that list and are not any more, two repaired on 2026-09-07 and
three on 2026-09-08.

**A path in a shell variable.** An assignment made by the SAME command is resolved before
its target is judged, so `L=.claude/x.md; cat > "$L"` is measured on the path it writes
instead of on the literal word `$L`, and passes the way the same write spelled out
already did. This is the
one hole on that list the guard was ever measured to have fired on, and it fired on the
worst possible file: on 2026-09-07T23:46:12Z it refused a coordinating session its own
`.claude/session-ledger.<id>.md`, which is bookkeeping under both halves of the measure at
once and which the kit tells that session to keep.

Only a LITERAL value is resolvable. `D=$(mktemp -d)` puts no value on the line, a variable
this command never assigns comes out of the environment, and both stay **work**, which is
the loud direction and the one the measurement demands: of 727 hand-resolved stops of this
shape in a foreign corpus, 636 resolve to a work path and only 28 to bookkeeping, so a
resolution that read a variable as bookkeeping BECAUSE it is a variable would be a silent
pass 636 times over. Measured 2026-09-08 over 95490 distinct real commands, 466001
weighted: 65 distinct and 216 weighted went from a stop to silence and none went the other
way, while 3716 distinct stops had an assignment resolved and stayed loud on the work path
it resolved to. Written out in full, every one of the 65 was already bookkeeping to the
measure before this repair. The rate moved from 10.2304 to 10.1623 percent distinct, 9.6238
to 9.5774 weighted.

**The body of a shell.** A quoted body carrying a metacharacter was blanked whether it was
text or a command, so everything a coordinator ran through `sh -c` went past the guard in
silence: `sh -c "cd /tmp && rm -rf src/x.py"`, `bash -c "npm install x; rm -f src/x.py"`
and `bash -c "echo hi > src/x.py"` all came back bookkeeping. The body of a shell is now
unwrapped and read by the same rules as the line around it, nested bodies included, and
what ends the unwrapping is the buffer rather than a depth counter: each unwrap drops two
quote characters off a line of finite length. Measured over 93614 distinct real commands,
463039 weighted: 3 changed verdict, every one of them a redirection into a path that is not
bookkeeping, and none went the other way. The rate moved from 10.221 to 10.224 percent
distinct, 9.614 to 9.624 weighted.

**The placeholder of a `find -exec`.** `{}` is where find substitutes what it matched, `+`
and `\;` are what end the `-exec`, and not one of the three is a name on disk. They were
read as paths, so every cleanup stopped on a word that is not a file:
`find apps/api/src -name __pycache__ -type d -exec rm -rf {} +` came back **work** naming
`{}` and `+`. They are stepped over now, the way the mode of a `chmod` already was, and the
skip is scoped to the `-exec` the same way, so `rm -rf "{}"` standing on its own is still a
write on a file that really is called that.

**The verdict of that command did not change, and that is the repair rather than a gap in
it.** A `find -exec` whose operands are all placeholders names no path of its own, so the
SEARCH PATH of the find is read, exactly the way `find -delete` is read. `find(1)` makes
the two spellings one command, so a measure that stopped `find . -name '*.py' -delete` and
waved `find . -name '*.py' -exec rm {} +` through would ship its own way around itself, in
one line, in this file. What moved is WHICH path the refusal names, and that name is the
whole of what you get to read when it stops you. Measured 2026-09-08 over 81089 distinct
real commands, 451159 weighted: 27 distinct stops and 189 weighted carried the shape, 48
readings of a placeholder as a path went to 0, and not one verdict in the corpus moved.

**A quoted path.** A quoted segment keeps its content unless that content carries a shell
metacharacter, so `rm -rf "src/x.py"` is caught while `grep -rn "a > b" src/` still
passes. The earlier wholesale replacement was measured to hide every quoted path, which
is the ordinary way to write one.

**A write verb in argument position.** A write verb is now read in COMMAND position only,
and the risk in that rule is that command position is not the first word of the line:
`&&`, `|`, `;`, `$( )`, `sudo`, `env VAR=x`, a bare `VAR=x`, `nohup`, `time`, `xargs`,
`then`, `do`, `find -exec` and `sh -c` all put the next word back into it, and
`tests/run.sh` asserts every one of them. Measured against 30877 real commands, the
change moved 36 of them: 15 false stops out, 19 real writes in, and the rate stayed at
15.8 percent.

**The source operand of a copy stays a target, and that is measured rather than assumed.**
In `cp src/x.py /tmp/bak` the first path is READ and only the second is written, so the
stop names a file nobody wrote. Measured 2026-09-08 against 9704 distinct stops, 44631
weighted: at most 23 distinct and 132 weighted of them, 0.24 and 0.30 percent, would go
silent if the source operands of a `cp` stopped being read, because in almost every one of
them the destination is a work path too and stops the command on its own. The bound is an
upper one, derived by dropping every non-final operand of every run of `cp` targets, which
merges `cp a b && cp c d` into one run and therefore drops more than the rule would. It is
not repaired for its size: `mv src/x.py /tmp/` REMOVES its source, so the same operand is a
write there, and the same measurement puts that separation at 2 distinct and 2 weighted. A
rule worth this little is not worth the second thing it can get wrong.

That was the size. On 2026-09-09 the rule was built anyway, measured against the frozen
46587-payload corpus, and taken back out, and this is the second thing it gets wrong. It
silences 44 of the 2921 stops there, and TEN of the 44 are silent passes on production
code. All ten are one shape:

```
cp apps/api/src/example_api/llm/service.py <scratchpad>/service.orig.py &&
  <venv>/python -c "... p = Path('apps/api/src/example_api/llm/service.py')
                        p.write_text(t.replace(alt, neu)) ..."
```

Back the file up, then rewrite it in place through an interpreter. The file the `cp` READS
is the file the call WRITES, and the write sits in a `-c` body or a heredoc, where neither
the scan nor the narrowing can see it, so dropping the source takes the last loud word off
the line. The 34 remaining are false alarms, and their stop keeps a reason that is wrong
about which operand was written. That trade is refused here for the reason it is refused
everywhere else in this file: what silence costs is a guard that is quiet exactly where
somebody reached for the shape that works. The arm becomes safe when the measure can read
what a `-c` body writes.

**The unterminated quote stays, and that is a decision rather than a leftover.** Carrying
quote state across lines was built and measured on the same 30877 commands. It trades a
noisy false alarm for a silent pass: a single apostrophe in a trailing comment swallows
the next line, so `git commit -m "wip"   # don't forget` followed by `rm -rf src/x.py`
reads as bookkeeping. One command in the real history already falls that way, and the
shape the change would fix is caught today anyway. By the rule this project set for
itself when it repaired the quoted path, a silent pass is the worse half, so the trade
is not one to make.

This is a string check, which is exactly the class of check this project's own house
rules argue against. It is here anyway because the alternative is no cover on Bash at
all, and it is written down here rather than discovered later.

## Reading the measure yourself

**The coordinating session could not run this measure at all**, and that is not a figure
of speech. Every route to `classify_bash` puts the example commands into a COMMAND LINE,
and a command line carrying an example is read by the very function under test. Measured
2026-09-08 against the shipped guard with real hook input on stdin: the seven examples of
one probe, written into a single line, came back a stop, and so did the one line
``classify_bash "bash -c \"cd /tmp && rm -rf src/x.py\""`` on its own. So the manager was
blind to its own instrument and had to hand every check of it out, which is the one thing
delegation cannot settle: the report that comes back is about the function the reader
cannot run. It happened twice on 2026-09-08, and once an agent contradicted a diagnosis
that was then believed rather than checked.

```
bash tools/mk-explain.sh .claude/probe.txt
```

The examples live in the file, one per line, and the call carries nothing but a
bookkeeping path. Write the file with the `Write` tool or with a heredoc, `cat >
.claude/probe.txt <<'EOF'`; both are writes to a `.claude` path, which is bookkeeping by
the kit's own measure. `--whole` reads the whole input as ONE command instead, which is the
only way to measure a heredoc or a line continued with a backslash, because both of those
carry a newline inside a single command.

**It prints the reason, not only the verdict.** Which word was read as the write verb,
which word as the target, and why that target is work. On a quiet verdict it says why
nothing was found:

```
--- 5 ---------------------------------------------------------------
  command  bash -c "cd /tmp && rm -rf src/x.py"
  verdict  work
  reason   the quoted body "cd /tmp && rm -rf src/x.py" is the command text of a shell, so it is unwrapped and read
           the write verb "rm" in command position names src/x.py
             src/x.py is work: it lies under no .claude directory, does not end in .md and is not in the session scratchpad
```

**There is no second copy of the rules.** The reasons are printed by
`hooks/_classify.sh` itself, out of the branches that decide, under `MK_EXPLAIN=1`, and
the tool only lays them out. A second implementation of the measure would report on the
second implementation, which is a mistake this kit has already paid for once. The switch
does not touch the verdict: measured 2026-09-08 over 450735 real Bash commands, the
verdict of every single one is the same character before and after, and the rate stayed
at 9.6152 percent.

**The pipe does not solve it.** `printf '%s\n' "..." | bash tools/mk-explain.sh` puts the
example straight back into the command line, which is exactly where the guard reads it.
Measured: that pipe passes with a plain example and is a stop with
``"bash -c \"cd /tmp && rm -rf src/x.py\""`` in it. The trap is intermittent, which is the
worst kind, because the easy example works and the interesting one does not.

**The heredoc works, and it works through a hole this README already lists.**

```
bash tools/mk-explain.sh <<'EOF'
bash -c "cd /tmp && rm -rf src/x.py"
EOF
```

passes in silence because the guard reads a heredoc BODY as data rather than as command
text, which is the first of the five holes above. Measured 2026-09-08: bookkeeping, with
the nested shell body included. It is the most comfortable route and it is named here
rather than left to be discovered, because it closes the day that hole closes and the file
route does not.

`bash tools/mk-explain.sh --calls` prints the calls the tool claims pass in silence, and
`tests/run.sh` measures every one of them with the shipped function. A call this kit tells
you to make and then refuses is a red suite, not a surprise in your session.

To find out whether some call would be stopped, put that call in the file. It is a command
like any other.

## The six hands it ships with

`agents/` carries six subagent definitions. They are not domain roles, and a catalogue of
those is deliberately still not shipped. These are the six SHAPES a hand-out takes.

**Each one is named after its thinking depth and not after a job**, and that is the whole
of the rename of 2026-09-08. A name like `scout` or `architect` is a claim about what the
work IS, and the manager picking a hand does not know that yet; what it does know is how
much depth the question is worth. The name that says `xhigh` says it, and a `-readonly`
suffix says the other thing a manager has to decide before it hands anything out.

| | effort | model | reach for it when |
|---|---|---|---|
| `low-readonly` | low | haiku | you need a fact: locate, count, list. Not a judgement |
| `medium` | medium | opus | one named endpoint, finished, with the command that shows it works |
| `high` | high | opus | several files and a few real choices, but no assertion is owed |
| `xhigh-readonly` | xhigh | sonnet | you need to know whether something is TRUE. It changes nothing |
| `xhigh` | xhigh | sonnet | a named defect. Red first, and a mutation that kills its own assertion |
| `max` | max | opus | choosing the shape IS the work, and typing it is the small half |

**The ladder is measured, not assumed.** Same prompt, same model, two definitions differing
only in `effort`: 3334 tokens in 17 seconds against 12322 in 129. The expensive one did not
restate the answer, it found the answer was implementation-dependent and named the part it
had not checked. Depth is bought where a question has depth; on a specified lookup the cheap
tier is not weaker, only cheaper.

**The price, measured rather than waved away:** the six descriptions are 3221 characters,
roughly 805 tokens at four characters a token, and they sit in the context on every turn.
[Counted 2026-11-08 as the sum of the `description:` fields of `agents/*.md`, 2019 before
each named its suggested model; 1923 on 2026-09-09, when the five they replaced were 1793.] That is real, and it is the
same budget this kit exists to protect. It is paid because a hand is how a manager picks
depth by name, and the other way to set it is not the kit's to use. The Agent tool also takes
`effort` in the call, and the call then wins over the definition in both directions, but the
tool's own text allows that only when the user, or an instruction file such as CLAUDE.md or a
skill, asks for a specific effort, and this kit asks for none. [Measured 2026-11-06 on one
Mac, one question, 14 runs: a `low` hand on haiku spent 7.6 times the output tokens with
`effort: max` in the call, and a `max` hand on sonnet spent 523 and 535 with `effort: low`,
like the `low` hand's 376 and 377. That shows the parameter taking effect. It does not show an answer
getting better: every answer was 1. The binary of Claude Code 2.1.318 carries the parameter
in the schema of the tool and the binary of 2.1.278 carries none, read as strings on
2026-11-07.] Delete the directory if you do not want it.

**Picking wrong costs twice.** Depth on a lookup is waste. A lookup's effort on a judgement
produces a confident answer nobody checked, which is worse than no answer.

## The model a hand runs on, and the one refusal

The depth of a hand lives in its definition, and so does its model: each of the six names
the model the measurements of 2026-11-05 and 2026-11-08 found for its kind of work, or opus
where that work was not measured, and a model named in the handout still wins, as does an effort.
`GUIDE.md` carries the table, hand by hand, with the reason. A hook refuses one combination of the two: haiku on the
repair hand `xhigh`, at every effort, and that hand comes on sonnet. `hooks/route-guard.sh` does it on
the subagent launch, both channels, and every handout leaves one line on
`.claude/manager-kit.log` naming a model: the one the call names, or else the one the
hand's definition carries on disk at that moment. That is not always the model that ran.
The hook reads the file on every call and the runtime keeps the definition from session
start, so a session started before a definition changed runs on the old one until it
restarts. [Reported 2026-11-05 by a session of another project, started before the
delivery of the `model:` lines, and not measured here: the log said `model=sonnet
effort=xhigh` for `manager-kit:xhigh-readonly`, `message.model` in the hand's transcript
said `claude-opus-5-5`, on 83 of 83 lines.] Only the hand's transcript proves the model
that ran. The line also names the effort that applies, the call's when the call names one and
else the definition's, and where it came from, as `effort=` and `effort_from=`; the refusal does not
depend on the effort, and its text names the one that applied. Behind them stand `hand=`, whose hand it
was, and `order=`, which is what can be counted about the order and not one word of it: a tier of its
length, whether a command stands in backticks, whether a word of acceptance stands in it. Last comes
`tool_use_id=`, the id of the call, when the call carries one: it ties the line to the transcript of
the hand, and `bash tools/mk-cost.sh --hands` sets the two side by side. Everything
else passes. A handout with no model in it at all, 99.0 percent of real
calls, is judged on the model of the hand's definition, and every hand this kit ships
passes that way.

**Two limits of this policy, written down rather than closed, decided 2026-11-02.** First,
the hook reaches a model only where one is WRITTEN: in the handout, which wins, or else in
the `model:` key of the hand's own definition, read from the file the call means, as its
effort is: `manager-kit:xhigh` the plugin's, a bare name the project's first. A model the hand inherits from the
SESSION it does not reach. The six hands no longer inherit, so on the 99.0 percent of real
calls that carry no model at all the hook now reads the model of the definition. What
stays out of its reach is a hand that still says `inherit` or names no model, a project's
own or a built-in one, and that is the shape of the case this policy would most like to
catch: a session already running on a cheap model hands such work out on that same
model, no `model` is written anywhere, and nothing is refused. The policy raises the
floor for a cheap route named in the call or in a definition and does nothing for one
inherited from the session. Second, the matcher is `Agent|Task`, and the reason the dead
spelling is kept is read out of the shipped program, where the matcher list is
canonicalised through a legacy alias table before it is matched. It has not been measured
live. What IS measured is the payload: 4335 of 4335 real subagent launches carry `Agent`
and none carries `Task`, so a hook that compared the payload against `Task` would be
selected and then silently do nothing.

Why haiku on the repair hand and no other combination: it is the one a measurement says does harm. Haiku at
`high` held a repair of kit code twice and left one false report, n = 2 on one task, and haiku at
`medium` reported falsely on it too [2026-11-05 and 2026-11-06]. Any other hand is open to haiku at any
effort, at your judgement; on `xhigh-readonly` its description warns that no effort came complete
twice. The limit: a hook knows the name of a hand and not the work, so a repair sent to `medium` falls
through, and the measurement says the same of it. `GUIDE.md` carries the full table of what is refused
and what is not, each row with its reason.

**Read this before you inherit it.** The policy is on by default, everywhere on, and that
was a decision rather than a measurement. Its gain, as far as the machine this kit was
built on measured it, in three parts. The price is an estimate: `tools/mk-cost.sh --what-if`
over the UTC days 2026-11-06 and 2026-11-07, one private project excluded, put the hand
rounds at $440.67 against $632.03 for the same tokens on the newest Opus, 30.3 percent less,
an upper bound at list price and no evidence of quality. Measured are pair comparisons per
kind of work, each on one task of kit code, the three decided ones with n = 3 or fewer a side
[2026-11-05 and 2026-11-08, the table in `GUIDE.md`]. What is unmeasured is whether real work
keeps the same quality at that lower price: no number in this repository says so, and the
one instrument that shows spend cannot resolve it, since 269128 Opus tokens moved the weekly
window by zero of a hundred points. This kit names no number for your project; the same
tool gives your own. The official help promises only a direction, "Opus costs several times more per turn than
Sonnet, and Sonnet more than Haiku", a direction and not a number. So the function ships
with a way out, and the way out is one variable.

**`MANAGER_KIT_NO_ROUTING` stills it.** Set it in the environment and no handout is refused
for its model. It does not touch a definition: the hands keep the model their `model:`
line names, and turning that table back is an edit of those six lines. Empty and `0`
count as unset. Its state is reported in the role text at every session start and is never written by the kit, which
is the same rule the auto-compaction report beside it follows: an instrument that changes
a project's settings has stopped being an instrument. `GOAL.md` carries the condition under
which the routing gets switched off rather than tuned, and the threshold is on quality,
because the cost side cannot falsify anything.

**`/manager-kit:cost` measures your own number.** Type it, or run `bash tools/mk-cost.sh`, and it reads the
transcripts of every project on this machine (`~/.claude/projects`, or `CLAUDE_CONFIG_DIR`) and prints a table:
list price in dollars from `tools/prices.tsv`, per role and model. That is a lower bound, since calls that write no
transcript line, compaction first among them, are not in it, and it is not limit points: what a plan counts against
its weekly limit cannot be read off it. `--since` and `--until` take a UTC day, and `--exclude TEXT` drops every
project folder whose name holds TEXT, compared without regard to upper and lower case, because macOS does not tell
them apart in a path. When the transcripts no longer look the way the meter reads them, it prints one line of reason
and no number. `--hands` prints instead, per hand, the model and effort its route line planned beside the ones its
transcript ran on, names every deviation, and counts every hand without a route line it can match. `--what-if` prints
instead what the hand rounds would have cost with every hand on the newest Opus of `tools/prices.tsv`, on the same
tokens, beside what they did cost; a round on any Opus and every manager round keep their price, and the saving is an
upper bound. `--compare A B`, each window `YYYY-MM-DD..YYYY-MM-DD`, sets the dollars per active day of two windows side
by side and judges them only against an A/A band cut from the active days before A: inside it the verdict is "not
distinguishable", and with too little history there is no verdict, only the reason. `--causes` prints instead what the
cache writing comes from: each round that writes cache gets one cause, the first round of a file (Start), the first after
a compaction, a gap to the round before past the 5m or the 1h TTL of the last write (expired, idle), a gap within
it (Growth), or Other, with rounds, dollars, share of all costs and the size of one event, and the compactions counted
once each with their trigger and the median context before and after. `--context` prints instead the manager's own tool
loops, the rounds of the main session between two inputs (a tool result does not end one, a hand has none), by length
with rounds, dollars and share of all costs, and the context cap `C* = S + g T*` of this machine with each input and
where it comes from: S the context after a compaction, g the mean growth per round, K the first round after a
compaction, measured, plus the compaction call, estimated, and r the read price; without a compaction it gives no C*,
only the reason.

**The kit says nothing to the manager about compacting or about the size of its context.** Whether and when to compact is
yours. What the kit gives on that subject is a report when you ask for it, `/manager-kit:cost --context`, and at a session
start the role text notes when `DISABLE_AUTO_COMPACT` is not set in your project; neither is a message about the context
of the session that reads it.

## The stop on a hand, and who watches it

**A hand handed out keeps working until something stops it, and its answers get worse on
the way.** Measured 2026-09-29 over 1494 subagent runs of the machine this was built on,
out of the `<usage>` blocks their finished reports leave behind: 93 runs (6.2 percent)
reached 600000 tokens of context, and 26 (1.7 percent) reached 900000, where the last
answer is worth little. The 93 took a median of 263 tool calls to get there and **the
fastest took 26**, which is the whole case against a rule that only counts calls.

The number that matters is the largest context of ONE turn, not the sum over the run; the
two differ by about fourteen times. [Calibrated over 258 finished runs against the agent
transcripts: the `subagent_tokens` of a report is the per turn maximum at a median ratio
of 0.956.]

**The watch sits with the coordinating session, because only it knows a hand's id.** Hands
go out to the background, the id is kept, and on each turn the coordinator takes anyway it
reads the hand's context out of the transcript on disk. At 600000 it sends one message:
write the handover and stop. The successor is then briefed with that file and not with the
old order.

**Every hand also carries a floor of its own: 150 tool calls or 300 KB read, whichever
comes first.** This is deliberately a parachute and not a measure. The coordinator looks
only when it takes a turn, so between its turns nobody is watching, and the floor covers
that gap. Priced against the same 1494 runs: 210 (14.1 percent) would reach the floor, 125
of those never came close to 600000 and are stopped for nothing, and 8 of the 93 dangerous
runs slip under 150 calls anyway. It buys the gap and it is not free.

**Every hand also carries `maxTurns: 170`, and that is a backstop, not the floor.** The
field stands in the frontmatter of all six files under `agents/`. The client cuts a hand
off at that many turns and the caller gets "stopped at its N-turn limit (partial result)"
back. It writes no handover file, so a hand cut there leaves a seam nobody can pick up,
and that is why the limit lies above the floor: the floor is the stop that hands over, the
limit only catches a hand that forgot its floor. A turn can carry more than one tool call,
and what the client counts as a turn is not measured. Measured is only that `maxTurns: 3`
stopped a project hand at its limit while the same hand without it ran to the end (client
2.1.317, 2026-11-08).

**Three hands keep their prompt cache for an hour, the rest for five minutes.** The hands
that write a one hour cache are `high`, `max` and `xhigh`. Each carries `experimental:`
with `cacheTtl: 1h` indented under it, the only place the client reads the key (read in
the client, 2.1.317), and in the same probe the nested form wrote every cache token as one
hour where the hand without it wrote five minutes. A one hour write costs twice the input price
and a five minute write 1.25 times it (`tools/prices.tsv`), so the hour pays only where a
hand often sits idle for 5 to 60 minutes. Reckoned on measured shares of all cost (the
council pyramid of 2026-11-06; an expired hand cache was 14.7 percent of all cost by
`tools/mk-cost.sh --causes` over 2026-10-01 to 2026-11-07): `xhigh` saves 1.94 percent,
`high` 1.95 and `max` 0.81, while `medium` would save 0.04 and `xhigh-readonly` would pay
0.53 more. The set is decided in one place, `HOUR_CACHE_HANDS` in `tests/run.sh`, and the
suite holds the hands and this text against it.

**For a plugin hand the hour cache is measured once and the turn limit is read, not measured.**
Both fields were first measured in a project hand under `.claude/agents/`. On 2026-11-09 a
plugin hand `manager-kit:high` called without a model ran on Opus and wrote every cache token
as one hour (7 answers), and a plugin hand `xhigh-readonly` called without a model ran on
Sonnet and wrote five minute cache, as decided, because it is not in `HOUR_CACHE_HANDS`
(4 of 4 answers). The size of each is one project, one hand. That a plugin hand stops at
`maxTurns` has not been run, so nothing here says that a plugin hand stops at 170 turns.

At the line a hand stops where it is, even mid task, and writes a handover file into the
session scratchpad: the order as understood, what is DONE with the command for each point,
what is HALF done and where, the next concrete move, what the successor must not repeat,
and the numbers already measured. Its path is the first line of the report. A half task
with a clean seam beats a whole one nobody trusts.

`GUIDE.md` carries the procedure, the file layout it reads, and what the rule deliberately
does not promise.

## Limits measured and left open

Each of these was measured, is named with its size, and was left standing on purpose (the first four MK-R5,
2026-11-07, measured at a7dc5a9; the next two MK-R6 and MK-R7, 2026-11-08; the last three MK-R8, 2026-11-08, measured
at 3812c8e). None of the first four lets a write pass in silence into the wrong project; the first two are false
alarms, the third is a gap nobody could rank, the fourth is a cost. Of the next two, the first is a false alarm and the
second DOES let a write pass in silence. The last three decide no write: two say which copy of the kit a command runs,
the third which verdict the explaining tool prints.

- **`cd X || exit 1`, then a blank line, makes the `cd` soft again.** `cd .claude/missing || exit 1`, an empty line
  and `echo x > a.txt` read as work, without the empty line as bookkeeping (`hooks/_classify.sh`, `cdx = 0` at every
  line break). It is the loud side (a stop that was not needed) and only for a directory that is not on the disk.
  Closing it is one condition at that line and a replay of the corpus (about 20 minutes of machine time).
- **A bare `xhigh` hand from `~/.claude/agents` is refused as if it were the kit's repair hand.** `mk_route_table`
  reads the kit's `agents/` and the project's, and not the user's. Loud, and a rename removes it. About 5 lines.
- **`CLAUDE_CODE_SUBAGENT_MODEL` in the environment is not judged.** The name is in the program of 2.1.318 and its
  rank against `model` was not measured. If it names haiku and wins, `xhigh` runs on haiku under a line that says
  sonnet, and the guard does not stop it. Measure the rank first (one call of each, with the variable set), then one
  line in the verdict.
- **`check.sh` reads a settings file whole** (the `grep -c` over `settings.json` and the JSON parse of every
  `settings*.json`). Measured with 100 MB files: `grep -c` 5 s on 50 million lines, the parse 2 s and 536 MB resident.
  It holds at that size and it is not bounded. A bound loses the RED on a broken file above it, which is why it was not
  put in; about 12 lines at two places.
- **A session whose `cwd` lies under a `.claude` directory gets a false stop.** A relative name with no `.claude` in
  the word (`echo x > a.log`, `| tee a.log`) reads as work, although bash writes it under `.claude/`. Measured
  2026-11-08: 3 of 3 a false stop, no silent pass in 12 cases. It is the loud side. The way round: write the path out
  as `.claude/...`, or stand at the project root. Why it is not repaired (MK-R7, discarded): reading a relative word
  against the `cwd` needs a model of every move of the directory, and an alias or a function with a `cd` in it would
  then have passed in silence.
- **Four rare shapes of a redirection behind arithmetic pass in silence as bookkeeping.** `(( x>0))>file` (a space
  after `((`), `(((x>0))>file)`, `((x>0))&&((a>b))>file` and `((1))<in>file` write, and the classifier says
  bookkeeping (MK-R6, `hooks/_classify.sh`, `glue_split` and `arith_tail`). The Bash classifier is coarse and full of
  holes by its own account above, and none of these is a shape a manager writes by accident. The way round, for a
  reader who wants the stop: `(( x>0 ))>file`, with a space at both ends, is already read as work. About 3 to 4
  lines each.
- **A copy of another plugin that carries the script is taken as this kit.** The block in `commands/take-over.md` and
  in `commands/cost.md` asks no name (its comment says why: the name is in the manifest of the copy it is looking for)
  and takes the first candidate holding `tools/manager-claim.sh` or `tools/mk-cost.sh`, whichever plugin it belongs
  to. Measured 2026-11-08 on a throwaway register: such a copy was taken, one without the script was not. The way
  round: install no other plugin with a file of that name for the project, or run `bash <copy>/tools/manager-claim.sh`
  of the copy you mean. Closing it needs the name from the manifest, about 8 lines per command and a check.
- **Of two copies of the kit for one project, the first one asked wins, in the register the one first in the file.**
  The same block in `commands/take-over.md` and `commands/cost.md` asks the candidates in order: `CLAUDE_PLUGIN_ROOT`,
  the `PATH` of the session, then the entries of `installed_plugins.json` by how closely they cover the project, a
  tie in the order of the file. Measured 2026-11-08: a fork and the original entered for one project under two
  names, the fork stood first and ran. The way round: keep one copy installed per project, or run
  `tools/manager-claim.sh` or `tools/mk-cost.sh` of the copy you mean. Deciding by name needs `CLAUDE_PLUGIN_ROOT` in
  the call, which the block notes as "possibly" and nobody measured; about 8 lines per command once it is.
- **`tools/mk-explain.sh` judges from the directory it stands in.** It sets `MK_CWD` from its own working directory, the
  way the guard sets it from the call, and ignores one in the environment (its comment says so), so a `..` or a link
  is read as the guard reads it for a session standing there and nowhere else. Measured 2026-11-08 on 18 commands
  with `..` and links: run where the session stood, the tool differed from the guard on 0, run from another
  directory on 1. The way round: `cd` into the directory the
  session stood in before you run it. A `--cwd DIR` option was not built, about 10 lines and a check.

What the repair of the same day closed, so that nobody looks for it here: a project whose name ends in a newline
records in itself and not in its neighbour; a worktree whose `gitdir` folds onto another real repository stands; a
`(` in front of a redirection (`(>src/a.py)`, `(a>b)`) is read as the write it is; `Haiku`, `HAIKU` and
`claude-haiku-5-5` are the cheap model on the repair hand. In a CALL the runtime refuses those words before any hook
runs (the model is a closed list of four words, read in the program text of 2.1.318, not run), so the third is a
gap in a hand's definition only.

## What it is not

- **It does not decide who the coordinator is.** The first session in a project takes
  the role; a second one is told it is a carrier, as long as the recorded
  holder's process is still alive. `/manager-kit:take-over` moves it, deliberately, to
  whichever session runs it, and that is the only way to move it without closing every
  session in the project first. When it is not, every live session in the project
  reads itself as the manager, and the guard then stops all of them, which is the
  fail-closed side of the same rule and the cheaper half of being wrong. Measured
  2026-09-07 against the shipped copy. What changed in 0.13.0 is the RECORD and not that
  rule: a session the record already names writes its own pid into it on its next prompt,
  so a coordinating session that comes back as a new process stops leaving a dead entry
  behind. Until then the next session to start in that project read that entry as an empty
  chair and took the role, without a command and without a line on the record [measured
  2026-09-11 against the delivered 0.12.0 in a live project; `GUIDE.md` carries the day and
  the two cases this still does not close]. Whether that is right
  for your project is your call, not the kit's.
- **It does not start, name or stop sessions.** Only a person can.
- **It does not set anything in your project.** It reports and it refuses. The one thing it
  writes outside `.claude/` is a line in `.git/info/exclude`, under Install.

## Files it writes, in the project it runs in

| Path | What it is |
|---|---|
| `.claude/manager-kit.log` | one JSON line per stop, per declared crossing, per handover, per role claim and per subagent launch, and one `guard-ran` a day |
| `.claude/manager-kit.role` | which session currently holds the coordinating role |
| `.claude/manager-kit.seen` | the date of the day the guard last proved it ran, one line |
| `.claude/manager-exception` | you write it, the guard spends it |

The log is kept out of a commit by the kit itself, with mode 0600, and all four files with
lines in `.git/info/exclude`; what that covers and what it leaves to you is under Install. They
are yours to put in `.gitignore` wherever the kit did not write its lines, rotated
`manager-kit.log.*` files included. Leaving a tracked file
out costs a stop of its own: a `git restore --staged` on the guard's own log is a work write
like any other.

**They are plain files inside the project, or the kit does not touch them.** A link, a pipe
or a directory under one of these names is not followed and not waited on, and neither is a file
with a second name (a hard link), which would change the file at the other end: nothing is written
through it, nothing is read from it, it buys no crossing, and every refusal stands. A role file or a
seen file longer than 4096 bytes is no such file and counts as absent, so a file of any size cannot
hold a hook. The refusal counts the log only up to 16 MiB; past that it says it did not count, and
`tools/week-verdict.sh` still reads all of it, which takes about 5 s for 200 MB. The refusal of a
handout counts its log the same way. The definition of a hand is read by its first 64 KiB, which
holds its frontmatter, and a settings file is searched for `DISABLE_AUTO_COMPACT` up to 1 MiB: past
that the session start says it did not check, and does not say the variable is missing. A `.claude`
that is itself a link keeps everything when it leads to a directory inside the project. When
it leads out of the project, and for a session standing in `$HOME` or above it, the kit keeps
no record at all: no log, no role, and no declaration can be spent, so a work write can only be
handed out. It says so at session start and in every refusal, and the guard goes on refusing.
`.claude/agents` and the two settings files are not the kit's, and they are read through a link
the way the runtime reads them; the kit never writes them.

All three sit at the top of the PROJECT, never in the directory a session happens to stand
in, and the project is the repository. A linked worktree is recorded at its MAIN repository
since 0.12.0, so a repository with many worktrees keeps one record and not one per
worktree, provided the main repository names that worktree back (`<gitdir>/gitdir`, which git
writes; a worktree moved by hand stays a project of its own until `git worktree repair`), so that a
`.git` file pointing into somebody else's repository leads nowhere; a submodule stays a project of
its own. A directory named `.git` that holds no `HEAD` is not a repository for git and is not a
project for the kit. Without a repository it is the nearest
directory above you that already keeps a `.claude/`, and the walk stops before `$HOME`,
which is your Claude configuration and not a project, worktrees included. `GUIDE.md` gives
the measurement this rule came out of, and the price it carries when several sessions run
in sibling worktrees at the same time.

## Verifying it

```
bash tests/run.sh
python3 tests/mutate.py
```

The first is the mechanics. The second is why you should believe the first: it turns
each assertion's subject back, one at a time, and requires that assertion to go red.

Run as it stands, the second runs the whole suite once for each entry of its register, one
entry after the other. The full register in hours and not days:

```
python3 tests/mutate.py --jobs 4 --fast --timeout 900 --report mutation-report.txt
```

`--jobs` is how many entries run side by side. `--fast` asks the check an entry is aimed at
first and alone: the verdict of an entry is whether that check went red, which is what the
slow run has always asked, and the rest of the suite is looked at only for an entry whose check
lived, to name the first check that died beside it. What `--fast` does not make is the list of
every check that died beside the own one. `--timeout` is the seconds a suite may take for one
entry; past it the entry is TIMEOUT, which is neither red nor alive. `--report` writes the count
of each class and, for each entry that is not red, its name, file and anchor. What an entry
makes in the temp is removed when it ends, and when the run is taken off.

Neither settles what the kit is for. That is settled by a week of real coordination,
read off `git log` against the stopping condition in `GOAL.md`.
