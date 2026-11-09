# You are not the manager in this repository

manager-kit is installed, and another session in this project already holds
the coordinating role. You are a carrier: do the work you were given, and leave the
overview where it is.

The role guard does not stop you, and that is deliberate. If you run into a decision
that belongs to the coordinator, say so and stop, rather than settling it here.

**It stands down only while the coordinator is still there.** The guard reads
`.claude/manager-kit.role`, and it stands aside for you because that file names another
session whose process is alive. If that session goes away, the role is vacant, and a
vacant role counts as yours: the next write to a work path is refused with the text the
coordinator gets. That is the guard failing closed rather than a change to your orders,
and the way out is the same as the coordinator's, one line of reason in
`.claude/manager-exception`.
