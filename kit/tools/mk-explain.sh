#!/usr/bin/env bash
# The measure, run by the session the measure is pointed at.
#
# Usage: bash tools/mk-explain.sh [--whole] [FILE]
#        bash tools/mk-explain.sh --calls
#        bash tools/mk-explain.sh --help
#
# WHY THIS EXISTS, and it is not convenience. The coordinating session could not run this
# measure at all. Every way of handing example commands to classify_bash puts those
# commands into a COMMAND LINE, and a command line carrying "rm -rf src/x.py" is refused by
# classify_bash itself. Measured 2026-09-08 against the shipped guard, with real hook input
# on stdin: the seven example commands of one probe, written into a single line, came back
# a stop, and so did the one line `classify_bash "bash -c \"cd /tmp && rm -rf src/x.py\""`
# on its own. So the manager was blind to its own instrument and had to hand every check of
# it to somebody else, which is the one thing a coordinator cannot verify by delegating:
# the report it gets back is about the very function it cannot run.
#
# The way out is that the examples never touch the command line. They come out of a FILE,
# and the call that names that file carries nothing but a bookkeeping path.
#
# It reports the REASON and not only the verdict. A verdict alone sends the reader back to
# an agent to ask why, which happened three times on 2026-09-08. The reasons are printed by
# hooks/_classify.sh itself, out of the branches that decide, and this file only lays them
# out: a second copy of the rules here would be a second measure, and a measurement run
# against a second copy of the measure is a defect this kit has already paid for once.

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../hooks/_classify.sh"

# THE DIRECTORY A RELATIVE PATH IS ASKED OF THE DISK AGAINST is the one this tool stands in, set here the way
# hooks/role-guard.sh sets it from the cwd of the call it judges, and never taken from the caller's environment: a link
# on the way and a ".." out of a subdirectory are read from the same place, so the verdict is the guard's for a session
# standing there. Run it from the directory the session stood in.
MK_CWD=$PWD

# THE CALLS THIS TOOL CLAIMS ARE SILENT, in one place, because the claim is testable and a
# claim that lives only in prose is not. tests/run.sh runs every line of this through
# classify_bash and requires bookkeeping, so a documented call that would be refused is a
# red suite rather than a surprise in somebody's session. The path in front of the script
# does not matter: the measure reads a program by its last segment, so an absolute path or
# the plugin cache directory classifies the same way.
calls() {
  cat <<'CALLS'
bash tools/mk-explain.sh .claude/probe.txt
bash tools/mk-explain.sh --whole .claude/probe.txt
bash tools/mk-explain.sh < .claude/probe.txt
bash tools/mk-explain.sh --calls
bash tools/mk-explain.sh --help
cat > .claude/probe.txt
CALLS
}

usage() {
  cat <<'USAGE'
mk-explain: what the guard reads in a command, and why.

  bash tools/mk-explain.sh [--whole] [FILE]

FILE holds the commands to measure, one per line; empty lines are skipped. With no FILE,
or with "-", the commands are read from standard input. --whole reads the whole input as
ONE command instead, which is the only way to measure a heredoc or a line continued with a
backslash, because both of those carry a newline inside one command.

  --calls   print the calls this tool claims pass the guard in silence
  --help    this text

WHERE THE FILE GOES. Under .claude/, which is bookkeeping by the kit's own measure, so
writing it is not a crossing. The Write tool does it, and so does a heredoc:

  cat > .claude/probe.txt <<'EOF'
  rm -rf src/x.py
  EOF

THE PIPE DOES NOT SOLVE THE PROBLEM THIS TOOL EXISTS FOR. Writing

  printf '%s\n' "rm -rf src/x.py" | bash tools/mk-explain.sh

puts the example back into the command line, which is exactly where the guard reads it.
Whether that call is refused then depends on what the examples say, and the shapes that
get refused are the interesting ones. Measured 2026-09-08: that pipe passes, and the same
pipe carrying "bash -c \"cd /tmp && rm -rf src/x.py\"" is a stop. Use a file.

THE HEREDOC WORKS, AND IT WORKS THROUGH A KNOWN HOLE.

  bash tools/mk-explain.sh <<'EOF'
  rm -rf src/x.py
  EOF

passes in silence because the guard reads a heredoc BODY as data rather than as command
text. That is the first of the holes README.md lists under "The Bash gap, named rather than
hidden", and this is the same hole, used deliberately and named here rather than found
later. If that hole is ever closed, this route closes with it and the file route does not.

CHECKING A CALL BEFORE YOU MAKE IT. Put the call in the file. It is a command like any
other, and this tool will tell you whether the guard would stop it.
USAGE
}

WHOLE=0
FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --calls)   calls; exit 0 ;;
    --whole)   WHOLE=1 ;;
    -)         FILE="" ;;
    --*)       printf 'mk-explain: unknown option %s\n' "$1" >&2
               printf 'usage: bash tools/mk-explain.sh [--whole] [FILE]\n' >&2; exit 2 ;;
    *)         FILE=$1 ;;
  esac
  shift
done

if [ -n "$FILE" ]; then
  [ -r "$FILE" ] || { printf 'mk-explain: %s is not readable.\n' "$FILE" >&2; exit 2; }
  exec < "$FILE"
fi

# The trace comes back on STDERR, because the verdict is stdout and every caller of
# classify_bash reads that with a command substitution. See hooks/_classify.sh.
export MK_EXPLAIN=1
TRACE=$(mktemp) || exit 2
trap 'rm -f "$TRACE"' EXIT INT TERM

N=0; WORK=0; BOOK=0

# One record. The command is printed back before the verdict, because a file of examples is
# read once and the reader has to be able to tell which line the verdict belongs to. Every
# line of it carries the same gutter, so a command with a newline in it cannot be mistaken
# for two records.
report() {
  _i=$1; _cmd=$2
  _v=$(classify_bash "$_cmd" 2>"$TRACE")
  N=$((N + 1))
  if [ "$_v" = work ]; then WORK=$((WORK + 1)); else BOOK=$((BOOK + 1)); fi
  printf '%s\n' "--- $_i ---------------------------------------------------------------"
  printf '%s' "$_cmd" | sed 's/^/  command  /'
  printf '\n'
  printf '  verdict  %s\n' "$_v"
  # The gutter is written once and the rest of the trace hangs under it, because the
  # reasons are one account of one command and not a list of separate findings.
  sed '1s/^/  reason   /; 2,$s/^/           /' "$TRACE"
}

if [ "$WHOLE" -eq 1 ]; then
  whole=$(cat)
  [ -n "$whole" ] || { printf 'mk-explain: nothing on the input.\n' >&2; exit 2; }
  report 1 "$whole"
else
  i=0
  # The || test keeps the last line when the file ends without a newline, which is how a
  # file written by `printf` rather than by an editor usually ends.
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    i=$((i + 1))
    report "$i" "$line"
  done
fi

printf '\n'
if [ "$N" -eq 0 ]; then
  printf 'Nothing to measure: the input carried no command.\n'
  exit 2
fi
printf '%s commands: %s work, %s bookkeeping.\n' "$N" "$WORK" "$BOOK"
printf 'work is what the guard refuses when the coordinating session runs it with its own\n'
printf 'hands; bookkeeping passes in silence. A subagent is not stopped either way.\n'
