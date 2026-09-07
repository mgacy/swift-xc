#!/bin/bash
# shellcheck shell=bash
# SessionStart hook: prepares a git worktree under .claude/worktrees so that
# mise-managed tooling (sextant, swiftlint, actionlint, shellcheck, ...) is
# usable without manual setup.
#
# mise refuses to load a config file it has not been told to trust, and every
# new worktree is a new path, so an agent starting work in a fresh worktree
# otherwise hits an untrusted-config prompt before it can run anything.
#
# Trust is granted only when the worktree's config is byte-identical to the one
# on the main checkout: trusting identical bytes grants nothing the main
# checkout does not already have. A config that differs is left untrusted and
# reported, since that is precisely the case where trusting it would run code
# nobody has reviewed.
#
# Skips silently when not in a worktree under .claude/worktrees.

set -euo pipefail

continue_session() {
    echo '{"continue": true}'
    exit 0
}

git rev-parse --is-inside-work-tree &>/dev/null || continue_session

current_root=$(git rev-parse --show-toplevel 2>/dev/null) || current_root=""
git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || git_common_dir=""

[[ -n "$current_root" && -n "$git_common_dir" ]] || continue_session

main_repo_root="${git_common_dir%/.git}"

# The main checkout needs no setup
[[ "$current_root" != "$main_repo_root" ]] || continue_session

# Only manage the worktrees this project creates
[[ "$current_root" == "$main_repo_root/.claude/worktrees/"* ]] || continue_session

# --- Worktree-specific setup below ---

if ! command -v mise &> /dev/null; then
    echo "setup-worktree: mise not found; skipping trust setup." >&2
    continue_session
fi

for config in .mise.toml .mise.local.toml; do
    worktree_config="$current_root/$config"
    main_config="$main_repo_root/$config"

    [[ -f "$worktree_config" ]] || continue

    if [[ ! -f "$main_config" ]]; then
        echo "setup-worktree: $config has no counterpart on the main checkout; leaving it untrusted." >&2
        continue
    fi

    if ! cmp -s "$worktree_config" "$main_config"; then
        echo "setup-worktree: $config differs from the main checkout; leaving it untrusted." >&2
        echo "setup-worktree: review the difference, then run 'mise trust $worktree_config' if it is sound." >&2
        continue
    fi

    if ! mise trust "$worktree_config" > /dev/null 2>&1; then
        echo "setup-worktree: 'mise trust $config' failed; mise-managed tools may be unavailable." >&2
    fi
done

continue_session
