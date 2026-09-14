---
name: reference-task-artifacts
description: Where swift-xc task artifacts live (.claude-tracking) and how to write review.md through the worktree symlink
metadata:
  type: reference
---

Task artifacts live in `.claude-tracking/NNN_slug/` at the repo root:
`research.md` → `plan.md` → `implementation.md` (its Files Affected table defines the expected
change set) → `progress.json` (per-work-unit `observations` and `deviations`) → `review.md`.

`.claude-tracking` is gitignored. Inside a worktree under `.claude/worktrees/` it is a **symlink to
the main checkout**, and the Write/Edit tools refuse to write through it. Stage `review.md` in the
session scratchpad and `cp` it into place with Bash.

`progress.json` observations are unusually rich in this project — executors record compile gotchas
and fixture pitfalls there. Read them before reviewing; they explain choices the diff alone does not.

Milestone specs are cited as `Probe.md:NN` in the planning docs but that file is **not in the
repository** — do not go looking for it. The repo has no JSON schema doc either (`README.md` is one
line, `docs/summary/index.md` is empty), so the source types in `Sources/XCCore/Output/` are the
entire contract for `result.json` consumers.
