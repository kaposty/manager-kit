#!/usr/bin/env bash
# Which role this session holds, and the text that says so.
#
# Both SessionStart carriers build their text through mk_role_context, so the primed
# text and the reinjected text come from one source and cannot drift apart.

HERE_ID=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$HERE_ID/_sessions.sh"
# The routing rule is sourced for ONE function, mk_routing_is_off, which mk_role_context
# uses to report the lage. Nothing here decides the rule; route-guard.sh does, out of the
# same file, so the report and the refusal cannot drift apart.
. "$HERE_ID/_routing.sh"

# EVERY <root> BELOW IS A PROJECT ROOT, never a working directory. The three carriers
# derive it once each with mk_project_root and hand it in, so the role file, the guard log
# and the exception marker are one set of files per project rather than one set per
# directory somebody happened to stand in.

# mk_role_file <root>
mk_role_file() { printf '%s/.claude/manager-kit.role\n' "${1-.}"; }

# mk_record_role <root> <pid> <session_id> -> puts this session into the record.
#
# THE ONLY WRITER OF THAT FILE INSIDE THE HOOKS, and it is a function rather than a second
# printf because there are now two call sites: mk_decide_role below, when a session claims
# an empty chair at SessionStart, and manager-stamp.sh, when a restarted session finds the
# record still naming the process it used to be. Four readers take the pid off field 1 and
# the session id off field 2 with the same one-line awk, and a writer that drifted by a
# single space would not go quiet: mk_field1_is_pid finds no pid in the field, every carrier
# of the role then answers manager for every session in the project, and the guard refuses
# all of them. Until 2026-11-02 manager-stamp.sh answered carrier for the same record, which
# is the split identity this kit has had to repair twice.
# tools/manager-claim.sh writes the same line from outside the hooks and says in its own
# header why it cannot share this function: it has no session id to put in field 2.
#
# AND EVERY WRITE LEAVES A LINE, which is the half of the 2026-10-19 incident that made it
# take seven days to come to light. Until now this function wrote the record in silence,
# and tools/manager-claim.sh was the only writer that logged, so the log could only ever
# show the transitions somebody had TYPED. In that incident the morning's guard lines are
# all there, and between the last of them and the user's own take-over the file says
# nothing happened, while the role had in fact left a living session. The line is written
# AFTER the record, through the one writer in _sessions.sh, so a line in the log is a
# record that landed rather than one that was attempted.
#
# The previous owner is read BEFORE the write and with the same one-line awk the four
# readers use, and its state is named with the same four words tools/manager-claim.sh uses
# for the handover line [none, unusable, alive, gone]. One vocabulary for the two kinds of
# transition, so a reader asking "who took this, and from whom" does not have to learn the
# answer twice. WHETHER FIELD 1 IS A PID AT ALL is mk_field1_is_pid's to say, the same
# function the three readers ask, so a 0 in field 1 is logged unusable: the role decision
# found no holder in it, and a line calling it alive told the reader the opposite. Until
# 2026-11-03 this writer asked an arm of its own without 0*, kill -0 0 succeeded, and the
# line said "previous 0 alive". tools/manager-claim.sh did the same in its handover line and
# asks mk_field1_is_pid too since the same day.
mk_record_role() {
  _rr_root=${1-}; _rr_pid=${2-0}; _rr_sid=${3-}
  _rr_file=$(mk_role_file "$_rr_root")
  _rr_prev=""
  mk_kit_usable "$_rr_file" && _rr_prev=$(awk 'NR==1 {print $1}' "$_rr_file" 2>/dev/null)
  _rr_was=none
  if [ -e "$_rr_file" ]; then
    if ! mk_field1_is_pid "$_rr_prev"; then _rr_was=unusable
    elif kill -0 "$_rr_prev" 2>/dev/null; then _rr_was=alive
    else _rr_was=gone
    fi
  fi
  mk_kit_make_home "$_rr_root" || return 0
  # A RECORD THAT DID NOT LAND GETS NO LINE, which is what the paragraph above promises and what
  # a write that could fail in silence did not keep.
  printf '%s %s\n' "$_rr_pid" "$_rr_sid" | mk_kit_write "$_rr_root" manager-kit.role || return 0
  mk_log_event "$_rr_root" claim "" \
    "pid $_rr_pid holds the role in $_rr_root" \
    "previous ${_rr_prev:-none} $_rr_was"
}

# mk_decide_role <root> <session_id> [claim]
#   Prints "manager" or "carrier". With claim=claim it also records the decision, which
#   is what makes the manager stay the manager once a second session joins.
mk_decide_role() {
  _root=${1-}; _sid=${2-}; _claim=${3-}
  _rf=$(mk_role_file "$_root")
  _mypid=$(mk_own_pid)

  set -- $(mk_session_census "$_root")
  _here=${4:-0}

  # Alone in the project is a finding, and it is the only thing that entitles a session
  # to claim. The census answers 0 for a project nobody is in and 0 for a count it could
  # not take [measured 2026-09-07: MANAGER_KIT_SOCKET_DIR=/nonexistent-register answers
  # 0 0 0 0 1, and an lsof that fails answers the same], so the second one is asked for
  # separately. Read as solitude, that 0 hands the role to every session at once.
  _alone=1
  if [ "$_here" -ge 2 ]; then
    _alone=0
  fi
  # A CENSUS NOBODY COULD TAKE IS NOT A CROWD, and until 0.18.0 both arrived here as the
  # same _alone=0. _counted keeps them apart, and the one branch below that reads it is
  # the branch where there is no record either: see the note there for what the two
  # being one fact cost.
  _counted=1
  mk_here_is_measured "$@" || { _counted=0; _alone=0; }

  _role=manager
  # A CHAIR SOMEBODY ELSE MAY BE SITTING ON. Set only in the branch below, and it suppresses
  # the claim without touching the role: see the long note at that branch.
  _contested=0
  if [ "$_alone" != 1 ]; then
    # Somebody else is in the project too, or nobody could be counted at all. Either way this
    # session is not entitled to assume the chair is empty: the role file decides, and
    # only if it names me.
    _role=carrier
    if mk_kit_usable "$_rf"; then
      _ownerpid=$(awk 'NR==1 {print $1}' "$_rf" 2>/dev/null)
      _ownersid=$(awk 'NR==1 {print $2}' "$_rf" 2>/dev/null)
      if [ -n "$_mypid" ] && [ "$_ownerpid" = "$_mypid" ]; then
        _role=manager
      elif [ -n "$_sid" ] && [ "$_ownersid" = "$_sid" ]; then
        _role=manager
      # A FIELD 2 THAT NAMES NO SESSION IS NOT A LIVING OWNER EITHER, and it is asked first
      # because it is the cheaper half of the same question: mk_guard_role asks it one line
      # ahead of its own question over field 1 and answers manager for it. Left out here, this
      # function answered carrier for a record reading "<living pid>" with nothing behind
      # it, and so did manager-stamp.sh, while the guard refused the same session on the
      # same prompt. Measured 2026-11-02 against the delivered hooks: guard manager, prime
      # carrier, reinject carrier, stamp carrier. One session, two roles, one turn.
      # A FIELD 1 THAT IS NOT A PID IS NOT A LIVING OWNER EITHER, and mk_field1_is_pid in
      # _sessions.sh is the one place that decides it, for this function, the guard, the
      # stamp and the writer above alike, with the measurement of why -1 and 0 are no pid.
      # Only a field that IS a pid goes on to kill -0.
      elif [ -z "$_ownersid" ] || ! mk_field1_is_pid "$_ownerpid" ||
           ! kill -0 "$_ownerpid" 2>/dev/null; then
        # The recorded manager is gone. Somebody has to hold the overview, and a guard
        # that goes silent because its owner died is the failure this kit exists to
        # catch, so the role is taken over rather than left vacant.
        #
        # BUT IT IS NOT CLAIMED, AND THE DISTINCTION IS THE WHOLE OF THIS REPAIR. Getting
        # here means somebody else is in this project too, or nobody could be counted at
        # all: either way this session cannot prove the chair is free, and a dead pid in
        # field 1 does not prove it either. The holder may be sitting right there under a
        # process the record has stopped naming, which is what a take-over plus a restart
        # leaves behind [tools/manager-claim.sh wrote "<pid> claimed-by-pid" until 0.15.0,
        # and manager-stamp.sh names that exact leftover as the one case its repair cannot
        # reach]. So the chair is BESTRITTEN rather than empty, and only
        # /manager-kit:take-over resolves it, which writes a handover line by hand.
        #
        # MEASURED IN A LIVE PROJECT, 2026-10-19, through the delivered 0.13.0:
        #   10-12 16:37:34Z  a take-over writes "32580 claimed-by-pid". The session that
        #                    ran it comes back as new processes at 16:43 and 16:45, so from
        #                    its next prompt on nothing on disk names it: manager-stamp.sh
        #                    repairs only a record that ALREADY names the session, and this
        #                    one names neither its pid nor its id.
        #   10-12 .. 10-19   it coordinates seven days, guarded, told "you are the manager
        #                    here" on every prompt, because all three carriers of this
        #                    identity read a dead owner as a vacant chair.
        #   10-19 12:52:05Z  an unrelated session starts, 1.7 seconds after its process
        #                    began, reads the same dead pid HERE, and claims.
        #   10-19 12:52:09Z  the session that had worked all morning is told it is a
        #                    carrier. Its guard stood down at role-guard.sh:107, which is
        #                    ahead of the log, so that turn leaves no trace at all.
        #   10-19 12:52:29Z  the user takes the role back by hand. That command's handover
        #                    line is the ONLY line in the log about any of it.
        # The same shape is in that session's own record twice more, 10-05 14:20:55Z and
        # 10-08 12:58:45Z, each one ended by a take-over within five minutes.
        #
        # THE ROLE STAYS manager HERE, and that is not a compromise. A carrier leaves
        # role-guard.sh at the stand-down ahead of the log, so answering carrier would be a
        # SILENT PASS, and this kit has written down twice that a hole in the register
        # costs a false stop and never one of those. Both sessions are called the manager,
        # both are guarded, and NEITHER writes the record.
        _role=manager
        # AND BESTRITTEN FOR EVERY RECORD THAT REACHES HERE, which is where this branch
        # used to make one distinction too many. Until 2026-11-02 a record whose field 1
        # would not parse was still CLAIMED here, and the reason given was that an unusable
        # record ought to be replaced by a usable one. It is the wrong trade, and it is the
        # same trade the paragraph above refuses: manager WITH a claim is the silent pass
        # one step on. Getting here means somebody else is in this project too, or nobody
        # could be counted at all, so this session cannot prove the chair is free, and an
        # unreadable record is no proof of it either. Recorded here, the second session to
        # start would overwrite the first, and the first would then read a record naming
        # somebody alive, become a carrier, and stand its guard down at the return ahead of
        # the log. So every shape that reaches this branch leaves the record where it is:
        # all of them are called the manager, all of them are guarded, and NONE of them
        # writes. A record nobody can read is replaced by /manager-kit:take-over, which
        # writes a handover line by hand, rather than by whoever started next.
        _contested=1
      fi
    elif [ "$_counted" != 1 ]; then
      # NO RECORD TO READ AND NO COUNT TO LEAN ON, which is the one lage where the four
      # carriers of this identity used to part company. mk_guard_role answers manager for
      # a role file it cannot read and says why: a hole in the register costs a false stop
      # and never a silent pass. This branch is that same convention, reached from the
      # other side, and it is not a new rule.
      #
      # WHAT WAS BROKEN, measured 2026-11-02 against the delivered hooks with no record on
      # disk and the register pointed at a directory that is not there:
      #   role-guard.sh manager | manager-prime.sh carrier
      #   manager-reinject.sh carrier | manager-stamp.sh carrier
      #   census [0 0 0 0 1], here not measured
      # One session, one absent record, two roles in one turn. The three that said carrier
      # are the three that carry the TEXT, so the person is told to do the work they were
      # given while the guard refuses them for being the coordinator.
      #
      # AND THE CHAIR IS NOT TAKEN, which is the half that makes this safe rather than
      # merely agreed. A session that cannot count the register cannot prove the chair is
      # free. Recorded here, the second session to start would overwrite the first, and
      # the first would then read a record naming somebody alive, become a carrier, and
      # stand its guard down: the silent pass, reached through the repair instead of
      # around it. So both are the manager, both are guarded, and NEITHER writes.
      #
      # IT IS THE UNCOUNTABLE CENSUS ONLY, and the narrowness is deliberate. A census that
      # WAS taken and found company, with no record on disk, still answers carrier here,
      # and that is a user decision rather than an oversight: what a session should be told
      # when nobody has claimed is held until after the operating week, and
      # prime_and_stamp_never_split_a_session pins today's answer to it.
      _role=manager
      _contested=1
    fi
  fi

  if [ "$_role" = manager ] && [ "$_claim" = claim ] && [ "$_contested" != 1 ]; then
    mk_record_role "$_root" "${_mypid:-0}" "$_sid"
  fi
  printf '%s\n' "$_role"
}

# mk_role_context <role> <root> -> the text that gets injected, on stdout
mk_role_context() {
  _r=${1-manager}; _c=${2-.}
  if [ "$_r" = manager ]; then
    cat "$HERE_ID/role-text.md"
    # Reported, never set. A kit that quietly changes a project's settings has stopped
    # being an instrument and become a participant.
    mk_kit_names_setting DISABLE_AUTO_COMPACT "$_c"
    case $? in
      0) ;;
      2) printf '\nA settings file of this project is longer than %s bytes. Whether it sets\n' "$MK_SETTINGS_CAP"
         printf 'DISABLE_AUTO_COMPACT was not checked.\n' ;;
      *) printf '\nDISABLE_AUTO_COMPACT is not set in this project. An auto-compaction fires\n'
         printf 'no SessionStart at all, so after one you may hold this role without being\n'
         printf 'told again until your next prompt. Setting it is the project owner'"'"'s call.\n' ;;
    esac
    # THE MODEL ROUTING, REPORTED THE SAME WAY AND FOR THE SAME REASON. A session has to
    # know which lage it is coordinating in, because the two answer differently: with the
    # routing active haiku on the repair hand comes back refused, and with it stilled
    # the same handout goes through and the hand runs on the model it names. A session
    # that cannot tell them apart reads one of those as a defect.
    #
    # The STATE is asked, never a second copy of the rule: mk_routing_is_off in
    # _routing.sh is the only thing that decides it, here and in the hook, so a change of
    # spelling cannot leave the report saying one thing and the refusal doing another.
    #
    # IT IS THREE LINES AND NOT A PARAGRAPH, and the reason is the budget this injection
    # is held to. The text carried on every session start cost 1797 of 1800 characters
    # before this, so the first draft of this report, which explained the rule here, was
    # 355 characters and would have needed the cost control raised by a fifth for prose
    # that GUIDE.md already carries. What a session cannot get out of GUIDE.md is which
    # lage it is standing in, and since 2026-11-06 that the model is its own judgement per
    # order and where the suggestion and the reason are: the manager does not read
    # GUIDE.md while handing out, so without that sentence the `model:` of a hand reads as
    # the rule. It fits in the room the old wording took, the budget did not move.
    if mk_routing_is_off; then
      printf '\nMANAGER_KIT_NO_ROUTING is set, so model routing is STILLED: no handout is\n'
      printf 'refused for its model. GUIDE.md has the rule.\n'
    else
      printf '\nMANAGER_KIT_NO_ROUTING is not set: routing ACTIVE, gain not measured. The model\n'
      printf 'is your judgement per order: a hand'"'"'s description suggests one, GUIDE.md says\n'
      printf 'why. One refusal stays: haiku on the repair hand xhigh. The switch is\n'
      printf 'the owner'"'"'s, this kit never sets it.\n'
    fi
  else
    cat "$HERE_ID/carrier-text.md"
  fi
}
