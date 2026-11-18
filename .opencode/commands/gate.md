---
description: Director milestone-gate report; asks the human to approve
agent: director
---

Prepare the gate report for the current milestone (see "Current milestone" in
AGENTS.md and the milestone table). Do this:

1. Read `docs/backlog.md`, `docs/bugs.md`, and the milestone's gate criterion.
2. Run `make check` and paste the real final output (do not summarise it away).
3. List: backlog items done / not done, open bugs, open critic findings.
4. List exactly what the human must do or test by hand for this gate.
5. Then STOP and use the question tool to ask the human: approve the gate,
   approve with changes, or reject. Do not start or delegate next-milestone work.
   If approved, propose (do not make) the "Current milestone" edit in AGENTS.md.

Extra context from the human: $ARGUMENTS
