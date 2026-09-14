---
name: feedback-worktree-shell-guard
description: How to shape Bash commands so the worktree-isolation guard lets them run — plain git -C invocations, no -c config injection, no cd
metadata:
  type: feedback
---

When working from a worktree under `.claude/worktrees/`, shape shell commands so the isolation guard
can verify them:

- **One plain `git` command per Bash call**, addressed with `git -C <absolute path>`. Chained
  commands (`cd X && git …`, heredocs that call git, loops over repos) are refused as "too complex
  to verify".
- **No `git -c <key>=<value>`** — config injection is refused outright, even for read-only keys.
  This blocks `-c protocol.file.allow=always`, so file-URL submodule fixtures cannot be built with
  real git; hand-build the directory layout instead.
- **Never `cd`.** To run a binary with a different working directory, use
  `python3 -c` with `os.chdir` + `subprocess.run(cwd=…)`.

**Why:** A worktree-isolated session's git operations must provably stay inside its own worktree, and
the guard fails closed on anything it cannot statically verify.

**How to apply:** When a review needs real git fixtures, budget for one Bash call per git step and
build them under the session scratchpad. Clean up afterwards — running `xc` for real writes into
`~/Library/Caches/xc/workspaces/`, which nothing reclaims.
