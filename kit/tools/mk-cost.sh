#!/usr/bin/env bash
# What the transcripts on this machine cost at list price, per role and model.
#
# Usage: bash mk-cost.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--exclude TEXT]... [--hands | --what-if | --causes | --context]
#        bash mk-cost.sh --compare YYYY-MM-DD..YYYY-MM-DD YYYY-MM-DD..YYYY-MM-DD [--exclude TEXT]...
#
# READS ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/**/*.jsonl and nothing else, writes nothing. The
# number is LIST PRICE in dollars from tools/prices.tsv, not limit points, and it is a LOWER BOUND: calls
# that write no transcript line, the compaction call first among them, are not in it, and the head says so.
#
# Both bounds are UTC days and both are included. --exclude drops every project folder whose name holds
# TEXT, compared in lower case, because macOS does not tell case apart in a path: a filter on the upper
# case spelling of a name read the lower case folder of the same project along with the rest. It may be
# given more than once, and an excluded folder is not opened at all.
#
# THE COUNTING RULE. One round is one answer, keyed by (message.id, requestId), and the LAST line that
# carries it counts: a streamed answer writes several lines and the first carries only part of the output
# (measured 2.4 times too little). Within a file the last line is the later one; the same answer in two
# files (a resumed session copies it) is counted once, the copy with the later timestamp, then the later
# path. A line without requestId is counted, by its message.id, and named in the head.
#
# THE ROLE. A file called agent-*.jsonl or a file below a subagents/ directory is a hand; everything else is
# the manager or the main session. A hand is typed by the attributionAgent of the counted line, else by
# agentType in <file without .jsonl>.meta.json, else it is "unknown" and counted in the head.
#
# THE FORMAT GUARD. The transcript format is no promised contract. Under 95 percent of rounds with all four
# of input_tokens, output_tokens, cache_read_input_tokens and cache_creation_input_tokens, or a model with no
# price row in more than 1 percent of the rounds, this prints one line of reason and no number, exit 3.
# <synthetic> has no price, is no unknown model, and gets a row of its own.
#
# --hands PUTS EACH HAND'S PLAN BESIDE WHAT RAN, and prints that instead of the table. Planned is the route line of
# hooks/route-guard.sh whose tool_use_id= is the toolUseId of the hand's meta.json, looked for in .claude/manager-kit.log
# of every directory from each cwd of the transcript up to the root: the id decides, not the time or the name. Ran is
# message.model and the top level effort of each counted round, <synthetic> left out, several of them named with their
# share. An alias in the route (opus) stands for the newest model of its family in prices.tsv, a full id for itself, and
# a build date in an id is no version. Every other model is a deviation, an older and a newer one alike: both are what
# the manager did not choose, and a newer one also means a row is missing in prices.tsv. A route without a model,
# (inherit), is not compared and is counted. A hand whose id no line carries is "without route" and counted, never left
# out. A hand is named in it by the rule that types it in the table (THE ROLE above), round by round: a hand whose rounds
# carry two types is named with both and their share. ITS GUARD: toolUseId missing in more than 5 percent of the
# meta.json files prints one line of reason and no report, exit 3, the bound the table holds its own fields to; at 5
# percent and below such a hand is "without route".
#
# --what-if PUTS EVERY HAND ON OPUS, and prints that instead of the table: the rounds of the table by its counting rule,
# per hand type and in sum what ran, what it would have cost with every hand round on the newest Opus of prices.tsv (the
# alias rule of --hands) with the same tokens, and the difference, in dollars and in percent of the Opus sum. A round
# that ran on an Opus keeps its price, an older Opus too: it ran on Opus, and the counterfactual changes nothing for it,
# while pricing it at the newest would count a version difference as a routing saving. A manager round keeps its price.
# A round is priced by THE ONE PRICE RULE below for the model it is put on, so a second tier is the tier of that model: a
# haiku round above its bound costs what Opus asks for the same tokens, and no haiku premium is carried over. <synthetic>
# and a model without a price are on neither side, counted in the head. The same tokens are the assumption, and they
# favour the small model, which thinks longer: the saving is an upper bound, and the head says so.
#
# --compare A B SETS TWO WINDOWS SIDE BY SIDE in dollars per active day, and prints that instead of the table. A and B are
# FIRST..LAST in UTC days, both included, and A ends before B begins. A day is active when its rounds cost more than 0
# dollars. The judgement is made only against an A/A band from the transcripts of this machine. A pair has the shape of
# the comparison in active days: nA days, the g active days between A and B, nB days. The pairs are cut one per active day
# from the 4 * (nA + g + nB) active days right before A, so that 4 of them do not overlap, and the band is the largest
# change among them, as a factor either way. Neither A nor B nor any day after the first of A is in it. Why 4 and the
# largest, measured on synthetic days (lognormal, i.i.d. and AR(1)): a comparison without an effect fell outside in 4.8
# to 7.8 percent, where the p90 of the same pairs let 11 to 24 percent through; more days make the largest grow and hide
# any effect. Fewer days before A: no verdict, one line of reason, exit 3. Inside the band, its edge included, the verdict
# is "not distinguishable" and no percentage; outside it is the change beside the band. It reads every day up to the end
# of B, so the format guard holds for all of them, and --since and --until do not go with it.
#
# --causes SAYS WHAT THE CACHE WRITING OF THE WINDOW COMES FROM, and prints that instead of the table: the rounds of the
# table by its counting rule, its role (Main for the manager, Hand for every hand), its window and --exclude. Every
# counted round that writes cache gets exactly one cause, judged in the file it is counted in, against every round of
# that file, those before the window included, <synthetic> left out:
#   after-compaction  the first round after a compaction line (type system, subtype compact_boundary) of the file;
#   Start             else the first round of the file, a hand's or the manager's;
#   expired>5m        else the gap to the round before, first line to first line, is past the 5m TTL of the last
#   idle>1h           write at or before that round, or past its 1h TTL. A round that wrote 5m and 1h has both: past
#                     the 1h is idle, past the 5m only is expired. At the bound itself the cache still lives;
#   Growth            else, within the TTL;
#   Other             what no rule reads: no write before in the file, or a gap that cannot be read.
# Per cause: rounds, tokens, dollars of the write by THE ONE PRICE RULE (the round's price less its price without the
# write), their share of all costs of the window, and tokens and dollars per round. The causes sum to the write of the
# table. Compactions are counted once by the uuid of their line, which a resumed session copies into its new file, with
# their trigger (manual, auto) and the median context before (preTokens of the line) and after (input, read and written
# cache of the first round after it in the file). The compaction call itself writes no round and is not in it.
#
# --context PUTS THE MANAGER'S OWN LOOPS AND ITS CONTEXT CAP side by side, and prints that instead of the table, on the
# rounds of the table by its counting rule, its window and --exclude, in main files only: a hand is no loop of the manager.
# THE INPUT RULE. A loop is the rounds of a main file between two inputs, a round placed by its first line. An input is a
# line of type user that carries no tool_result block in message.content, no isMeta and no isCompactSummary: a tool result
# continues the loop, and so do the text Claude Code adds by itself and the summary after a compaction, which an automatic
# compaction writes in the middle of a loop. Its origin (human, task-notification, peer) is not asked: each starts a turn.
# <synthetic> is no round. A loop counts with the rounds counted in the file and the window, so one over the edge of the
# window counts with its part inside. Classes 1, 2-3, 4-7, 8-15, 16-31, 32+, each with loops, rounds, dollars and share of
# all costs of the window, hands included; then the loops from 8 rounds, and the median context of the main session. The
# context of a round is its input, read and written cache, as --causes reads it after a compaction.
# THE CAP, C* = S + g T* with T* = sqrt(2 K / (r g)), the sawtooth: a compaction costs K, a round reads its context at r,
# and the context grows by g a round from the floor S. Each input from the main files of the window, printed with its count:
#   S  the median context of the first round after a compaction, the compactions of --causes, counted once by uuid;
#   g  the MEAN of the differences of two rounds that follow each other in a main file with no compaction line between:
#      the context after T rounds is S plus the sum of T differences, which is T times their mean, and a median would
#      leave out the few large tool results that make most of the growth;
#   K  measured: the write of the first round after a compaction, dollars per event of Main/after-compaction in
#      --causes; ESTIMATED: the compaction call, which writes no line, as preTokens (median) read at r, plus postTokens
#      (median) at the output price of the same model. postTokens is all the context after the compaction, so it bounds
#      the summary from above, and the thinking of that call is not seen at all;
#   r  the read price in tools/prices.tsv of the model that ran the most rounds of the main session, its first tier.
# Missing any input (no compaction, no pair of rounds, a growth not above 0, no preTokens or postTokens, no price), it
# prints the loops and every input it has, then one line of reason and no C*, exit 3 as the format guard.
#
# One report at a time: --hands, --what-if, --compare, --causes and --context do not mix, and a mix ends with exit 2 and one
# sentence. Exit 0 the table or a report, 2 a word, a day, a window or a mix it cannot read, 3 no number (format guard, no
# round at all, no band for --compare, or no C* for --context).

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CFG=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
if [ "$CFG" = /.claude ]; then
  printf 'mk-cost: neither CLAUDE_CONFIG_DIR nor HOME is set, so there is no transcript directory to read.\n'
  exit 2
fi
python3 -I - "$CFG" "$HERE/prices.tsv" "$@" <<'PY'
import datetime, json, math, os, re, stat, sys

cfg, price_file, args = sys.argv[1], sys.argv[2], sys.argv[3:]
NEED = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
COLUMNS = ["model", "input", "write_5m", "write_1h", "read", "output", "as_of", "source"]


def stop(code, text):
    print("mk-cost: " + text)
    sys.exit(code)


def lines_of(path):
    # Opened without waiting on a pipe, and read only when it is a plain file.
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None
    fh = os.fdopen(fd, "rb")
    if not stat.S_ISREG(os.fstat(fh.fileno()).st_mode):
        fh.close()
        return None
    return fh


def hand_type(d, path, cache):
    # THE ONE RULE for the type of a hand, asked by the table and by --hands alike: the attributionAgent of the line, else
    # agentType in <file without .jsonl>.meta.json, else "unknown". The meta file is read once per file (cache) and only
    # when a line has no attributionAgent: a hand of an SSH session has a meta.json with nothing but toolUseId.
    attr = d.get("attributionAgent")
    if isinstance(attr, str) and attr:
        return attr
    if not cache:
        kind = None
        mf = lines_of(path[:-len(".jsonl")] + ".meta.json")
        if mf is not None:
            with mf:
                try:
                    kind = json.loads(mf.read().decode("utf-8", "replace")).get("agentType")
                except (ValueError, AttributeError):
                    kind = None
        cache.append(kind if isinstance(kind, str) and kind else None)
    return cache[0] or "unknown"


# ---- the words
def day_of(word, v):
    # THE ONE DAY RULE, for --since, --until and either end of a window of --compare.
    try:
        if not re.fullmatch(r"\d{4}-\d\d-\d\d", v):
            raise ValueError
        datetime.date.fromisoformat(v)
    except ValueError:
        stop(2, "%s %s is no day of the form YYYY-MM-DD. Nothing was read." % (word, v))
    return v


def window(v):
    m = re.fullmatch(r"(.*)\.\.(.*)", v)
    if not m:
        stop(2, "--compare %s is no window of the form YYYY-MM-DD..YYYY-MM-DD. Nothing was read." % v)
    first, last = day_of("--compare", m.group(1)), day_of("--compare", m.group(2))
    if last < first:
        stop(2, "--compare %s closes before it opens. Nothing was read." % v)
    return first, last


since = until = None
excl = []
hands_mode = whatif_mode = causes_mode = context_mode = False
compare = None
i = 0
while i < len(args):
    a = args[i]
    if a == "--hands":
        hands_mode = True
        i += 1
        continue
    if a == "--context":
        context_mode = True
        i += 1
        continue
    if a == "--what-if":
        whatif_mode = True
        i += 1
        continue
    if a == "--causes":
        causes_mode = True
        i += 1
        continue
    if a == "--compare":
        if i + 2 >= len(args):
            stop(2, "--compare needs two windows, A and B, each YYYY-MM-DD..YYYY-MM-DD. Nothing was read.")
        compare = (window(args[i + 1]), window(args[i + 2]))
        i += 3
        continue
    if a not in ("--since", "--until", "--exclude"):
        stop(2, "%s is no word of this command (--since DAY, --until DAY, --exclude TEXT, --hands, --what-if, --compare A B, --causes, "
             "--context). Nothing was read." % a)
    if i + 1 >= len(args) or args[i + 1] == "":
        stop(2, "%s needs a value. Nothing was read." % a)
    v = args[i + 1]
    i += 2
    if a == "--exclude":
        excl.append(v)
        continue
    if a == "--since":
        since = day_of(a, v)
    else:
        until = day_of(a, v)
if since and until and until < since:
    stop(2, "--until %s closes the window before --since %s opens it. Nothing was read." % (until, since))
mix = [w for w, on in (("--hands", hands_mode), ("--what-if", whatif_mode), ("--compare", compare),
                       ("--causes", causes_mode)) if on] + (["--context"] if context_mode else [])
if len(mix) > 1:
    stop(2, "%s and %s do not go together: each prints a report of its own instead of the table. Nothing was read."
         % (mix[0], mix[1]))
# --causes and --context both read every round of a file and its compaction lines, by the same rules.
scan = causes_mode or context_mode
if compare:
    (a_first, a_last), (b_first, b_last) = compare
    if since or until:
        stop(2, "--compare takes its days from A, B and the days before A, so --since and --until do not go with it. "
             "Nothing was read.")
    if not a_last < b_first:
        stop(2, "--compare A %s..%s does not end before B %s..%s begins. Nothing was read." % (a_first, a_last, b_first, b_last))
    # Every day up to the end of B is read, the days of the band before A with them, and the format guard holds for all.
    until = b_last

# ---- the prices
P, TIER, stands = {}, {}, []
fh = lines_of(price_file)
if fh is None:
    stop(2, "the price file %s cannot be read." % price_file)
with fh:
    rows = [l for l in fh.read().decode("utf-8", "replace").splitlines() if l.strip() and not l.startswith("#")]
if not rows or rows[0].split("\t") != COLUMNS:
    stop(2, "the price file %s does not start with the columns %s." % (price_file, " ".join(COLUMNS)))
for r in rows[1:]:
    f = r.split("\t")
    try:
        if len(f) != len(COLUMNS):
            raise ValueError
        p = tuple(float(x) for x in f[1:6])
    except ValueError:
        stop(2, "the price file %s has a row it cannot read: %s" % (price_file, r))
    # A second tier is a row of its own, "<model>><tokens>": those prices hold for a request whose input,
    # read and written cache together are MORE than <tokens>, on every part of it, output included.
    if ">" in f[0]:
        base, n = f[0].split(">", 1)
        TIER[base] = (int(n), p)
    else:
        P[f[0]] = p
    stands.append(f[6])

def tokens_of(u):
    # THE ONE TOKEN RULE, asked by the table and by --causes: the four fields of NEED, each a count or None, and the
    # tokens of the round as (input, read, written, written 5m, written 1h, output).
    val = {}
    for k in NEED:
        v = u.get(k)
        val[k] = v if isinstance(v, int) and not isinstance(v, bool) and v >= 0 else None
    inp, out, cr, cw = (val[k] or 0 for k in NEED)
    cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else {}
    w5 = cc.get("ephemeral_5m_input_tokens") if isinstance(cc.get("ephemeral_5m_input_tokens"), int) else 0
    w1 = cc.get("ephemeral_1h_input_tokens") if isinstance(cc.get("ephemeral_1h_input_tokens"), int) else 0
    # Creation the two TTL fields do not account for is priced as 5m, the cheaper of the two.
    w5 += max(0, cw - w5 - w1)
    return val, (inp, cr, cw, w5, w1, out)


def is_input(d):
    # THE INPUT RULE of --context: a user line that is no tool result, no line Claude Code adds by itself (isMeta) and no
    # summary after a compaction (isCompactSummary). Its content is a string or a list of blocks.
    if not isinstance(d, dict) or d.get("type") != "user":
        return False
    if d.get("isMeta") is True:
        return False
    if d.get("isCompactSummary") is True:
        return False
    m = d.get("message")
    c = m.get("content") if isinstance(m, dict) else None
    if isinstance(c, list):
        return not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)
    return isinstance(c, str)


# ---- the files, an excluded folder never opened
root = os.path.join(cfg, "projects")
files, dropped = [], 0
try:
    tops = sorted(os.listdir(root))
except OSError:
    tops = []
for top in tops:
    tp = os.path.join(root, top)
    if not os.path.isdir(tp):
        if top.endswith(".jsonl"):
            files.append(tp)
        continue
    if any(e.lower() in top.lower() for e in excl):
        dropped += 1
        continue
    for d, dirs, names in os.walk(tp):
        dirs.sort()
        for n in sorted(names):
            if n.endswith(".jsonl"):
                path = os.path.join(d, n)
                files.append(path)

# ---- the rounds
best = {}
broken = 0
hand_rounds = []
in_files, inputs_of = [], {}
for path in files:
    rel = os.path.relpath(path, root).split(os.sep)
    hand = rel[-1].startswith("agent-") or "subagents" in rel[:-1]
    meta = []
    fh = lines_of(path)
    if fh is None:
        continue
    here = {}
    seq, marks, inputs = {}, [], []
    with fh:
        for lineno, raw in enumerate(fh, 1):
            if scan and b'"compact_boundary"' in raw:
                try:
                    d = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    d = None
                if isinstance(d, dict) and d.get("subtype") == "compact_boundary":
                    marks.append((lineno, d))
                    continue
            if context_mode and not hand and b'"user"' in raw:
                # A user line is no round: it is an input that ends a loop, or it is not.
                try:
                    d = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    d = None
                if isinstance(d, dict) and d.get("type") == "user":
                    if is_input(d):
                        inputs.append(lineno)
                    continue
            if b'"usage"' not in raw:
                continue
            try:
                d = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                broken += 1
                continue
            m = d.get("message") if isinstance(d, dict) else None
            if not isinstance(m, dict) or not isinstance(m.get("usage"), dict):
                continue
            ts = d.get("timestamp") if isinstance(d.get("timestamp"), str) else ""
            day = ts[:10]
            key = (m.get("id"), d.get("requestId") or None)
            if scan:
                # Every round of the file, the window or not: its first line and time, and the model and tokens of its
                # last line, not the line itself, so that a long history does not stay in memory.
                seq.setdefault(key, [lineno, ts, None])[2] = (m.get("model"), tokens_of(m["usage"])[1])
            if (since or until) and not day:
                continue
            if since and day < since:
                continue
            if until and day > until:
                continue
            here[key] = (ts, d, m)
    if hand:
        hand_rounds.append((path, here))
    if causes_mode or context_mode and not hand:
        in_files.append((path, seq, marks))
        inputs_of[path] = inputs
    for key, (ts, d, m) in here.items():
        if key in best and (best[key][0], best[key][1]) > (ts, path):
            continue
        if not hand:
            label = "manager"
        else:
            label = "hand:" + hand_type(d, path, meta)
        best[key] = (ts, path, label, m)

# ---- the hands, planned against ran (--hands). Everything above this ran as it runs without the word, and nothing of
# the table below runs with it: the report has its own guard and its own exit.
def norm(name):
    return re.sub(r"\[[^\]]*\]$", "", name.strip().lower())


def version_key(name):
    # claude-<family>-<n>-<n>...: the family and the version. A part of eight digits or more is the day of a build and
    # no version, so claude-haiku-4-5-20251001 is haiku 4.5 and older than claude-haiku-5-5.
    mm = re.fullmatch(r"claude-([a-z]+)((?:-[0-9]+)+)", norm(name))
    if not mm:
        return None
    return (mm.group(1), tuple(int(x) for x in mm.group(2)[1:].split("-") if len(x) < 8))


def resolve(planned):
    # A full id stands for itself. An alias stands for the newest model of its family in prices.tsv.
    k = version_key(planned)
    if k:
        return k, norm(planned)
    fam = sorted((version_key(x), x) for x in P if version_key(x) and version_key(x)[0] == norm(planned))
    return fam[-1] if fam else (None, None)


def pct(v, n):
    return (200 * v + n) // (2 * n)


def share(counter, n):
    items = sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))
    if len(items) == 1:
        return items[0][0]
    return ", ".join("%s %d%%" % (k, pct(v, n)) for k, v in items)


routes = {}


def routes_of(log):
    # The route lines of one log that carry a tool_use_id, by that id, read once per log.
    if log not in routes:
        found = {}
        fh = lines_of(log)
        if fh is not None:
            with fh:
                for raw in fh:
                    if b"tool_use_id=" not in raw:
                        continue
                    try:
                        rec = json.loads(raw.decode("utf-8", "replace"))
                    except ValueError:
                        continue
                    if not isinstance(rec, dict) or rec.get("event") not in ("route", "route-stop", "route-off"):
                        continue
                    kv = {}
                    for word in str(rec.get("reason", "")).split(" "):
                        key, _, value = word.partition("=")
                        kv.setdefault(key, value)
                    if kv.get("tool_use_id"):
                        found[kv["tool_use_id"]] = kv
        routes[log] = found
    return routes[log]


def find_route(cwds, tu):
    # Every cwd of the transcript, climbed to the root: the id decides which log holds the line, so the climb does not
    # have to know where the hook put the root.
    for c in cwds:
        a = os.path.normpath(c)
        while a != os.path.dirname(a):
            kv = routes_of(os.path.join(a, ".claude", "manager-kit.log")).get(tu)
            if kv is not None:
                return kv
            a = os.path.dirname(a)
    return None


if hands_mode:
    hands, missing = [], 0
    for path, here in hand_rounds:
        rr = [(d, m) for ts, d, m in sorted(here.values(), key=lambda x: x[0]) if m.get("model") != "<synthetic>"]
        if not rr:
            continue
        meta = None
        mf = lines_of(path[:-len(".jsonl")] + ".meta.json")
        if mf is not None:
            with mf:
                try:
                    meta = json.loads(mf.read().decode("utf-8", "replace"))
                except ValueError:
                    meta = None
        meta = meta if isinstance(meta, dict) else {}
        tu = meta.get("toolUseId") if isinstance(meta.get("toolUseId"), str) and meta.get("toolUseId") else None
        if tu is None:
            missing += 1
        kinds, cache = {}, []
        for d, m in rr:
            k = hand_type(d, path, cache)
            kinds[k] = kinds.get(k, 0) + 1
        kind = share(kinds, len(rr))
        hands.append((os.path.basename(path)[:-len(".jsonl")], kind, tu, rr))
    if not hands:
        stop(3, "no number for --hands: no hand with a round was read (%d files, window %s..%s)."
             % (len(files), since or "*", until or "*"))
    if missing * 100 > 5 * len(hands):
        stop(3, "no number for --hands. toolUseId is missing in %.1f%% of the meta.json files, over 5%%: %d of %d hands. "
             "The transcript format has probably changed." % (100.0 * missing / len(hands), missing, len(hands)))
    rows, notes = [], []
    n_route = n_open = n_blind = n_off = all_rounds = with_effort = 0
    for stem, kind, tu, rr in sorted(hands, key=lambda h: h[0]):
        name = "%s (%s)" % (stem, kind)
        models, efforts, cwds = {}, {}, []
        for d, m in rr:
            mo = m.get("model") if isinstance(m.get("model"), str) and m.get("model") else "(no model)"
            models[mo] = models.get(mo, 0) + 1
            ef = d.get("effort") if isinstance(d.get("effort"), str) and d.get("effort") else "?"
            efforts[ef] = efforts.get(ef, 0) + 1
            c = d.get("cwd")
            if isinstance(c, str) and c.startswith("/") and c not in cwds:
                cwds.append(c)
        n = len(rr)
        all_rounds += n
        with_effort += n - efforts.get("?", 0)
        kv = find_route(cwds, tu) if tu else None
        found = []
        if kv is None:
            n_open += 1
            planned = "-"
            if tu:
                found.append("without route %s: no route line with tool_use_id %s in the log over %s"
                             % (name, tu, ", ".join(cwds) or "(no cwd)"))
            else:
                found.append("without route %s: meta.json names no toolUseId" % name)
        else:
            n_route += 1
            pm, pe = kv.get("model", ""), kv.get("effort", "")
            planned = "%s/%s" % (pm, pe)
            pk, pname = resolve(pm)
            if pk is None:
                n_blind += 1
                found.append("not comparable %s: %s, model=%s"
                             % (name, "the route names no model" if pm[:1] in ("", "(") else "prices.tsv has no model for it", pm))
            else:
                off = dict((k, c) for k, c in models.items() if version_key(k) != pk)
                if off:
                    found.append("Deviation %s: model planned %s = %s, ran %s" % (name, pm, pname, ", ".join(
                        "%s %d%%" % (k, pct(c, n)) for k, c in sorted(off.items(), key=lambda kc: (-kc[1], kc[0])))))
            if re.fullmatch(r"[a-z]+", pe.lower()):
                off = dict((k, c) for k, c in efforts.items() if k != "?" and k.lower() != pe.lower())
                if off:
                    found.append("Deviation %s: effort planned %s, ran %s" % (name, pe, ", ".join(
                        "%s %d%%" % (k, pct(c, n)) for k, c in sorted(off.items(), key=lambda kc: (-kc[1], kc[0])))))
            if any(f.startswith("Deviation ") for f in found):
                n_off += 1
        rows.append((name, planned, "%s / %s" % (share(models, n), share(efforts, n)), n))
        notes.extend(found)
    print("mk-cost --hands  %s..%s  Hands %d  with route %d  without route %d  model not comparable %d  deviation %d"
          % (since or "*", until or "*", len(hands), n_route, n_open, n_blind, n_off))
    print("Rounds %d, of them with effort %d. Planned by the route line with the same tool_use_id, ran by the transcript, "
          "<synthetic> not counted." % (all_rounds, with_effort))
    fmt = "%-40s %-24s %-56s %6s"
    print(fmt % ("Hand", "planned", "ran model / effort", "Rounds"))
    for r in rows:
        print(fmt % r)
    for f in notes:
        print(f)
    sys.exit(0)

# ---- the price of each round
def list_price(model, inp, cr, cw, w5, w1, out):
    # THE ONE PRICE RULE, asked by the table for the model that ran and by --what-if for the newest Opus, on the same
    # tokens. A second tier is the tier of the model priced: its prices hold when input, read and written cache together
    # are MORE than its bound.
    if model in P:
        p = P[model]
        tier = TIER.get(model)
        if tier and inp + cr + cw > tier[0]:
            p = tier[1]
        return (inp * p[0] + w5 * p[1] + w1 * p[2] + cr * p[3] + out * p[4]) / 1e6
    return None


rounds = len(best)
if rounds == 0:
    stop(3, "no number: no round was read (%d files, window %s..%s), so there is nothing to count."
         % (len(files), since or "*", until or "*"))
agg, counted, kept = {}, [], {}
covered = unknown = untyped = no_rid = 0
unknown_models = set()
for key, (ts, path, label, m) in best.items():
    rid = key[-1]
    val, (inp, cr, cw, w5, w1, out) = tokens_of(m["usage"])
    if None not in val.values():
        covered += 1
    model = m.get("model") if isinstance(m.get("model"), str) and m.get("model") else "(no model)"
    cost = None
    if model == "<synthetic>":
        pass
    elif model in P:
        cost = list_price(model, inp, cr, cw, w5, w1, out)
    else:
        unknown += 1
        unknown_models.add(model)
    if label == "hand:unknown":
        untyped += 1
    if rid is None:
        no_rid += 1
    row = agg.setdefault(label + "/" + model, [0, None, 0, 0, 0, 0])
    row[0] += 1
    if cost is not None:
        row[1] = (row[1] or 0) + cost
    row[2] += cr
    row[3] += w5
    row[4] += w1
    row[5] += out
    counted.append((ts[:10], label, model, cost, (inp, cr, cw, w5, w1, out)))
    kept[key] = (model, cost, (inp, cr, cw, w5, w1, out))

# ---- the format guard, in integers so that a bound is the bound
if covered * 100 < 95 * rounds:
    stop(3, "no number. Coverage of the required fields %.1f%% under 95%%: %d of %d rounds without one of %s. "
         "The transcript format has probably changed." % (100.0 * covered / rounds, rounds - covered, rounds, ", ".join(NEED)))
if unknown * 100 > rounds:
    stop(3, "no number. Model without a price in %.2f%% of the rounds, over 1%%: %s (%d of %d). A row is missing in %s."
         % (100.0 * unknown / rounds, ", ".join(sorted(unknown_models)), unknown, rounds, price_file))

# ---- --causes and --context, on the rounds counted above and past their guard. Nothing of the table runs with them.
if scan:
    TTL = (("5m", datetime.timedelta(minutes=5)), ("1h", datetime.timedelta(hours=1)))
    EXPIRED = {"5m": "expired>5m", "1h": "idle>1h"}
    ROLES = ("Main", "Hand")
    CAUSES = ("Start", "Growth") + tuple(EXPIRED[name] for name, span in TTL) + ("after-compaction", "Other")

    def when(ts):
        try:
            return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            return None

    cause_of, comp, n_lines = {}, {}, 0
    for path, seq, marks in in_files:
        order = sorted(((v[0], k, v[1], v[2]) for k, v in seq.items()), key=lambda r: r[0])
        ms = sorted(marks, key=lambda r: r[0])
        mi, prev, last_ttl, open_marks = 0, None, None, []
        for lineno, key, ts, (model, t) in order:
            if model == "<synthetic>":
                # No call: no round before the next one and no first round after a compaction, and a write it claims
                # is Other.
                if t[3] + t[4] > 0 and best.get(key, (None, None))[1] == path:
                    cause_of[key] = "Other"
                continue
            after = False
            while mi < len(ms) and ms[mi][0] < lineno:
                after = True
                open_marks.append(ms[mi][1])
                mi += 1
            for mk in open_marks:
                mk["_after"] = t[0] + t[1] + t[2]
            open_marks = []
            if t[3] + t[4] > 0 and best.get(key, (None, None))[1] == path:
                gap = None
                if prev is not None and when(ts) is not None and when(prev) is not None:
                    gap = when(ts) - when(prev)
                if after:
                    c = "after-compaction"
                elif prev is None:
                    c = "Start"
                elif last_ttl is None or gap is None or gap < datetime.timedelta(0):
                    c = "Other"
                else:
                    short, long = last_ttl
                    if gap > long[1]:
                        c = EXPIRED[long[0]]
                    elif gap > short[1]:
                        c = EXPIRED[short[0]]
                    else:
                        c = "Growth"
                cause_of[key] = c
            if t[3] + t[4] > 0:
                writes = [x for x, n in zip(TTL, (t[3], t[4])) if n > 0]
                last_ttl = (writes[0], writes[-1])
            prev = ts
        for lineno, d in ms:
            ts = d.get("timestamp") if isinstance(d.get("timestamp"), str) else ""
            day = ts[:10]
            if (since or until) and not day or since and day < since or until and day > until:
                continue
            n_lines += 1
            md = d.get("compactMetadata") if isinstance(d.get("compactMetadata"), dict) else {}
            k = d.get("uuid") if isinstance(d.get("uuid"), str) and d.get("uuid") else (ts, md.get("preTokens"),
                                                                                   md.get("trigger"))
            pre = md.get("preTokens") if isinstance(md.get("preTokens"), int) and not isinstance(md.get("preTokens"), bool) else None
            post = md.get("postTokens") if isinstance(md.get("postTokens"), int) and not isinstance(md.get("postTokens"), bool) else None
            old = comp.get(k, (None, None, None, None))
            comp[k] = (md.get("trigger"), pre if pre is not None else old[1],
                       d.get("_after") if d.get("_after") is not None else old[2], post if post is not None else old[3])
    total = sum(c for mo, c, t in kept.values() if c is not None)
    rows = dict(((r, c), [0, 0, 0.0]) for r in ROLES for c in CAUSES)
    noprice = 0
    for key, c in cause_of.items():
        model, cost, t = kept[key]
        row = rows[("Main" if best[key][2] == "manager" else "Hand", c)]
        row[0] += 1
        row[1] += t[3] + t[4]
        if cost is None:
            noprice += 1
        else:
            row[2] += cost - list_price(model, t[0], t[1], t[2], 0, 0, t[5])

    def median(xs):
        xs = sorted(xs)
        return "-" if not xs else "%d" % ((xs[(len(xs) - 1) // 2] + xs[len(xs) // 2]) // 2)

    # ---- --context, on the main files only (in_files holds no hand with it), the causes and compactions above with them.
    if context_mode:
        CLASSES = (1, 2, 4, 8, 16, 32)
        LONG = 8

        def klass(n):
            return max(j for j, lo in enumerate(CLASSES) if n >= lo)

        def label(j):
            lo = CLASSES[j]
            if j + 1 == len(CLASSES):
                return "%d+" % lo
            hi = CLASSES[j + 1] - 1
            return "%d" % lo if hi == lo else "%d-%d" % (lo, hi)

        def share_of(usd):
            return "%.1f" % (100.0 * usd / total if total else 0.0)

        loops, pairs, contexts, models = [], [], [], {}
        for path, seq, marks in in_files:
            order = sorted(((v[0], k, v[2]) for k, v in seq.items() if v[2][0] != "<synthetic>"), key=lambda r: r[0])
            cuts, walls = sorted(inputs_of[path]), sorted(m[0] for m in marks)
            ci = wi = 0
            loop = prev = None
            for lineno, key, (model, t) in order:
                new = wall = False
                while ci < len(cuts) and cuts[ci] < lineno:
                    new, ci = True, ci + 1
                while wi < len(walls) and walls[wi] < lineno:
                    wall, wi = True, wi + 1
                if new or loop is None:
                    loop = [0, 0.0]
                    loops.append(loop)
                if best.get(key, (None, None))[1] == path:
                    mo, cost, tk = kept[key]
                    loop[0] += 1
                    loop[1] += cost or 0.0
                    contexts.append(tk[0] + tk[1] + tk[2])
                    if cost is not None:
                        models[mo] = models.get(mo, 0) + 1
                    if prev is not None and not wall:
                        pairs.append((t[0] + t[1] + t[2]) - (prev[0] + prev[1] + prev[2]))
                prev = t
        loops = [lp for lp in loops if lp[0]]
        cls = [[0, 0, 0.0] for lo in CLASSES]
        for n, usd in loops:
            r = cls[klass(n)]
            r[0] += 1
            r[1] += n
            r[2] += usd
        long_n = [lp for lp in loops if lp[0] >= LONG]
        long_usd = sum(lp[1] for lp in long_n)

        print("mk-cost --context  %s..%s  Files %d  Excluded folders %d  Coverage %.1f%%  Prices as of %s  LOWER BOUND"
              % (since or "*", until or "*", len(files), dropped, 100.0 * covered / rounds, min(stands) if stands else "?"))
        print("The manager's own loops: the rounds of a main file between two user inputs. Not an input are "
              "a tool result, a line with isMeta and the summary after a compaction. Hands and "
              "<synthetic> not counted.")
        print("All costs of the window %.2f $, %% is the share of it. A loop over the edge of the window counts with "
              "its rounds inside it." % total)
        lfmt = "%-8s %10s %10s %10s %6s"
        print(lfmt % ("Length", "Loops", "Rounds", "$-eq", "%"))
        for j, r in enumerate(cls):
            print(lfmt % (label(j), r[0], r[1], "%.2f" % r[2], share_of(r[2])))
        all_usd = sum(r[2] for r in cls)
        print(lfmt % ("Total", len(loops), sum(r[1] for r in cls), "%.2f" % all_usd, share_of(all_usd)))
        print("From %d rounds: %d loops, %d rounds, %.2f $, %s%%, %s $ per loop. Context of the main session, median %s, "
              "from %d rounds." % (LONG, len(long_n), sum(lp[0] for lp in long_n), long_usd, share_of(long_usd),
                                  "%.3f" % (long_usd / len(long_n)) if long_n else "-", median(contexts), len(contexts)))

        # THE CAP. Each input, or the reason it is missing.
        missing = []
        after = [v[2] for v in comp.values() if v[2] is not None]
        pres = [v[1] for v in comp.values() if v[1] is not None]
        posts = [v[3] for v in comp.values() if v[3] is not None]
        S = int(median(after)) if after else None
        if S is None:
            missing.append("S is missing, no first round after a compaction in a main file")
        g = float(sum(pairs)) / len(pairs) if pairs else None
        if g is None:
            missing.append("g is missing, no pair of consecutive rounds with no compaction between them")
        elif g <= 0:
            missing.append("g is missing, the growth per round is not above 0")
        main = sorted(models.items(), key=lambda mc: (-mc[1], mc[0]))[0][0] if models else None
        r = P[main][3] / 1e6 if main else None
        o = P[main][4] / 1e6 if main else None
        first = rows[("Main", "after-compaction")]
        k_first = first[2] / first[0] if first[0] else None
        pre = int(median(pres)) if pres else None
        post = int(median(posts)) if posts else None
        k_call = pre * r + post * o if pre is not None and post is not None and main else None
        gone = [why for why, miss in (("no first round after a compaction that writes cache", k_first is None),
                                      ("no compaction line with preTokens", pre is None),
                                      ("no compaction line with postTokens", post is None)) if miss]
        if gone:
            missing.append("K is missing, " + ", ".join(gone))
        if main is None:
            missing.append("r is missing, no round of the main session with a price")
        K = k_first + k_call if k_first is not None and k_call is not None else None

        def num(v, f):
            return "-" if v is None else f % v

        print("Context cap C* = S + g T*, T* = sqrt(2 K / (r g)), each quantity from the transcripts of this machine in the "
              "window:")
        print("S  %s tokens: context of the first round after a compaction in a main file, median of %d."
              % (num(S, "%d"), len(after)))
        print("g  %s tokens per round: mean of the differences of consecutive rounds of a main file with no compaction "
              "between them, from %d pairs." % (num(g if g is None else round(g), "%d"), len(pairs)))
        print("K  %s $ = %s measured + %s estimated. Measured: cache write of the first round after a compaction, "
              "mean of %d, as --causes. Estimated, not in the transcript: the compaction call, preTokens median %s * r "
              "+ postTokens median %s * output price %s $/M, from %d and %d lines."
              % (num(K, "%.3f"), num(k_first, "%.3f"), num(k_call, "%.3f"), first[0], num(pre, "%d"), num(post, "%d"),
                 num(o if o is None else o * 1e6, "%g"), len(pres), len(posts)))
        print("r  %s $/M: read price of %s in prices.tsv, the model of %d of the %d rounds of the main session with a price."
              % (num(r if r is None else r * 1e6, "%g"), main or "-", models.get(main, 0), sum(models.values())))
        if missing:
            print("no C*: %s." % "; ".join(missing))
            sys.exit(3)
        t_star = math.sqrt(2 * K / (r * g))
        print("T* %.1f rounds" % t_star)
        print("C* %d tokens" % round(S + g * t_star))
        sys.exit(0)

    def cline(name, r):
        n, tok, usd = r
        return fmt % (name, n, tok, "%.2f" % usd, "%.1f" % (100.0 * usd / total if total else 0.0),
                      "%d" % round(tok / n) if n else "-", "%.3f" % (usd / n) if n else "-")

    print("mk-cost --causes  %s..%s  Files %d  Excluded folders %d  Coverage %.1f%%  Prices as of %s  LOWER BOUND"
          % (since or "*", until or "*", len(files), dropped, 100.0 * covered / rounds, min(stands) if stands else "?"))
    print("Cache writing by cause: %d of %d rounds write, without a price %d. All costs of the window %.2f $, %% is the "
          "share of it. Not seen: the compaction call itself." % (len(cause_of), rounds, noprice, total))
    print("Gap to the previous round of the same file against the TTL of its last write (5m, 1h); at the bound the "
          "cache still lives. Start is the first round of a file, after-compaction the first after a compaction.")
    fmt = "%-28s %7s %12s %10s %6s %13s %11s"
    print(fmt % ("Role/Cause", "Rounds", "Tokens", "$-eq", "%", "Tok/event", "$/event"))
    for r in ROLES:
        for c in CAUSES:
            print(cline("%s/%s" % (r, c), rows[(r, c)]))
    print(cline("Total", [sum(v[j] for v in rows.values()) for j in range(3)]))
    trig = [v[0] for v in comp.values()]
    print("Compactions %d, manual %d, automatic %d, no trigger %d, from %d boundary lines. Context before: median %s, "
          "after: median %s, without a value before %d, after %d."
          % (len(comp), trig.count("manual"), trig.count("auto"), len(trig) - trig.count("manual") - trig.count("auto"),
             n_lines, median([v[1] for v in comp.values() if v[1] is not None]),
             median([v[2] for v in comp.values() if v[2] is not None]),
             sum(1 for v in comp.values() if v[1] is None), sum(1 for v in comp.values() if v[2] is None)))
    sys.exit(0)

# ---- --what-if, on the rounds counted above and past their guard. Nothing of the table runs with it.
if whatif_mode:
    opus = resolve("opus")[1]
    if opus is None:
        stop(2, "the price file %s has no row of the family opus, so --what-if has no price to put a hand on." % price_file)
    sums, synth, noprice = {}, 0, 0
    for day, label, model, cost, t in counted:
        if model == "<synthetic>":
            synth += 1
            continue
        if cost is None:
            noprice += 1
            continue
        k = version_key(model)
        alt = cost if label == "manager" or (k and k[0] == "opus") else list_price(opus, *t)
        r = sums.setdefault(label, [0, 0.0, 0.0])
        r[0] += 1
        r[1] += cost
        r[2] += alt
    hand_rows = sorted(k for k in sums if k != "manager")

    def summed(keys):
        return [sum(sums[k][j] for k in keys) for j in range(3)]

    def wline(name, r):
        n, ran, alt = r
        return "%-44s %7s %10s %10s %10s %6s" % (name, n, "%.2f" % ran, "%.2f" % alt, "%.2f" % (alt - ran),
                                                "%.1f" % (100.0 * (alt - ran) / alt) if alt else "-")

    print("mk-cost --what-if  %s..%s  Files %d  Excluded folders %d  Coverage %.1f%%  Prices as of %s  LOWER BOUND"
          % (since or "*", until or "*", len(files), dropped, 100.0 * covered / rounds, min(stands) if stands else "?"))
    print("What-if: every hand round on %s, with the same tokens. A round on an Opus and every manager round "
          "keep their price. Not counted: <synthetic> %d, no price %d." % (opus, synth, noprice))
    print("Assumption: the same tokens. Sonnet thinks longer, so the saving is an upper bound. "
          "List price in dollars, not limit points.")
    print("%-44s %7s %10s %10s %10s %6s" % ("Role", "Rounds", "ran", "all-Opus", "saving", "%"))
    for k in hand_rows:
        print(wline(k, sums[k]))
    print(wline("Hands", summed(hand_rows)))
    print(wline("manager", sums.get("manager", [0, 0.0, 0.0])))
    print(wline("Total", summed(list(sums))))
    sys.exit(0)

# ---- --compare, on the rounds counted above (every day up to the end of B) and past their guard.
if compare:
    paid = {}
    for day, label, model, cost, t in counted:
        if cost is not None:
            paid[day] = paid.get(day, 0.0) + cost
    act = sorted(d for d in paid if paid[d] > 0)
    in_a = [d for d in act if a_first <= d <= a_last]
    in_b = [d for d in act if b_first <= d <= b_last]
    gap = sum(1 for d in act if a_last < d < b_first)
    for name, first, last, ds in (("A", a_first, a_last, in_a), ("B", b_first, b_last, in_b)):
        if not ds:
            stop(3, "no verdict for --compare. %s %s..%s has no active day." % (name, first, last))
    span = len(in_a) + gap + len(in_b)
    need = 4 * span
    before = [d for d in act if d < a_first]
    if len(before) < need:
        stop(3, "no verdict for --compare. A band needs 4 pairs without overlap of %d+%d+%d active days, so %d "
                "active days before A; there are %d%s." % (len(in_a), gap, len(in_b), need, len(before),
                                                     ", %s..%s" % (before[0], before[-1]) if before else ""))
    band_days = before[-need:]

    def per_day(ds):
        return sum(paid[d] for d in ds) / len(ds)

    band = max(abs(math.log(per_day(band_days[j + len(in_a) + gap:j + span]) / per_day(band_days[j:j + len(in_a)])))
               for j in range(need - span + 1))
    ma, mb = per_day(in_a), per_day(in_b)
    lo, hi = "%+.1f%%" % (100.0 * (math.exp(-band) - 1)), "%+.1f%%" % (100.0 * (math.exp(band) - 1))
    print("mk-cost --compare  A %s..%s  B %s..%s  Files %d  Excluded folders %d  Dollars per active day  "
          "Prices as of %s  LOWER BOUND" % (a_first, a_last, b_first, b_last, len(files), dropped,
                                            min(stands) if stands else "?"))
    print("A %d active days, %.2f $ per day. B %d active days, %.2f $ per day. Between them %d active days. "
          "A UTC day is active with more than 0 dollars." % (len(in_a), ma, len(in_b), mb, gap))
    print("Band without intervention %s to %s: the largest change among %d pairs of %d+%d+%d active days, on the %d "
          "active days before A, %s..%s." % (lo, hi, need - span + 1, len(in_a), gap, len(in_b), need, band_days[0],
                                            band_days[-1]))
    if abs(math.log(mb / ma)) <= band:
        print("Verdict: not distinguishable.")
    else:
        print("Verdict: change %+.1f%% from A to B, outside the band %s to %s." % (100.0 * (mb / ma - 1), lo, hi))
    sys.exit(0)

# ---- the table
total = sum(r[1] for r in agg.values() if r[1] is not None)
priced = sorted((k for k in agg if agg[k][1] is not None), key=lambda k: (-round(agg[k][1], 6), k))
rest = sorted(k for k in agg if agg[k][1] is None)
print("mk-cost  %s..%s  Files %d  Coverage %.1f%%  Prices as of %s  LOWER BOUND"
      % (since or "*", until or "*", len(files), 100.0 * covered / rounds, min(stands) if stands else "?"))
print("Rounds without requestId %d, with an unknown model %d, hands without a type %d. Unreadable lines %d. Excluded folders %d."
      % (no_rid, unknown, untyped, broken, dropped))
print("Not seen: the compaction call and every call that writes no line to the transcript. "
      "List price in dollars, not limit points.")
fmt = "%-44s %7s %10s %6s %12s %12s %12s %12s"
print(fmt % ("Role/Model", "Rounds", "$-eq", "%", "Read", "Wr5m", "Wr1h", "Out"))
for k in priced + rest:
    r = agg[k]
    if r[1] is None:
        dollars = pct = "-"
    else:
        dollars = "%.2f" % r[1]
        pct = "%.1f" % (100.0 * r[1] / total if total else 0.0)
    print(fmt % (k, r[0], dollars, pct, r[2], r[3], r[4], r[5]))
print(fmt % ("Total", rounds, "%.2f" % total, "100.0", sum(r[2] for r in agg.values()), sum(r[3] for r in agg.values()),
             sum(r[4] for r in agg.values()), sum(r[5] for r in agg.values())))
PY
