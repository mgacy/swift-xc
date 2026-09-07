#!/usr/bin/env bash

set -euo pipefail

readonly RELEASE_BRANCH="release"
readonly VERSION_FILE="Sources/xc/Version.swift"

usage() {
    printf 'Usage: %s <patch|minor|major>\n' "$(basename "$0")" >&2
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

release_pr_url() {
    gh pr list \
        --base main \
        --head "$RELEASE_BRANCH" \
        --state open \
        --json url,isCrossRepository \
        --jq 'map(select(.isCrossRepository == false))[0].url // empty'
}

if [[ "$#" -ne 1 ]]; then
    usage
    exit 2
fi

readonly RELEASE_TYPE="$1"
case "$RELEASE_TYPE" in
    patch | minor | major)
        ;;
    *)
        usage
        exit 2
        ;;
esac

for required_command in gh git swift; do
    command -v "$required_command" >/dev/null 2>&1 ||
        fail "required command '$required_command' was not found"
done

REPOSITORY_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    fail "run this command from the swift-xc repository"
readonly REPOSITORY_ROOT
cd "$REPOSITORY_ROOT"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    fail "prepare-release requires a clean worktree"
fi

CURRENT_BRANCH="$(git branch --show-current)"
readonly CURRENT_BRANCH
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    fail "prepare-release must run from main, not '$CURRENT_BRANCH'"
fi

gh auth status --hostname github.com >/dev/null 2>&1 ||
    fail "GitHub CLI is not authenticated; run 'gh auth login'"

git fetch --prune origin

LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_MAIN_HEAD="$(git rev-parse refs/remotes/origin/main)"
readonly LOCAL_HEAD REMOTE_MAIN_HEAD
if [[ "$LOCAL_HEAD" != "$REMOTE_MAIN_HEAD" ]]; then
    fail "local main must exactly match origin/main"
fi

EXISTING_PR_URL="$(release_pr_url)"
readonly EXISTING_PR_URL
if [[ -n "$EXISTING_PR_URL" ]]; then
    fail "a release pull request already exists: $EXISTING_PR_URL"
fi

if git show-ref --verify --quiet "refs/remotes/origin/$RELEASE_BRANCH"; then
    fail "remote release branch already exists"
fi

if git show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH"; then
    if git merge-base --is-ancestor "$RELEASE_BRANCH" refs/remotes/origin/main; then
        git branch -d "$RELEASE_BRANCH"
    else
        fail "local release branch exists and is not merged into origin/main"
    fi
fi

git switch -c "$RELEASE_BRANCH"

if ! NEW_VERSION="$(
    swift package \
        --allow-writing-to-package-directory \
        version-file \
        --target xc \
        --bump "$RELEASE_TYPE"
)"; then
    fail "version-file plugin failed; the local release branch was preserved"
fi
readonly NEW_VERSION

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "version-file plugin returned unexpected version '$NEW_VERSION'"
fi

WORKTREE_STATUS="$(git status --porcelain --untracked-files=all)"
readonly WORKTREE_STATUS
if [[ "$WORKTREE_STATUS" != " M $VERSION_FILE" ]]; then
    fail "version bump must change only $VERSION_FILE"
fi

if ! git diff --check; then
    fail "version bump introduced whitespace errors; the local release branch was preserved"
fi

if ! grep -Fq "static let number = \"$NEW_VERSION\"" "$VERSION_FILE"; then
    fail "$VERSION_FILE does not contain the reported version '$NEW_VERSION'"
fi

git add -- "$VERSION_FILE"

STAGED_FILES="$(git diff --cached --name-only)"
readonly STAGED_FILES
if [[ "$STAGED_FILES" != "$VERSION_FILE" ]]; then
    fail "release commit must stage only $VERSION_FILE"
fi

git commit -m "Bump Version.swift -> $NEW_VERSION"

COMMITTED_FILES="$(git diff-tree --no-commit-id --name-only -r HEAD)"
readonly COMMITTED_FILES
if [[ "$COMMITTED_FILES" != "$VERSION_FILE" ]]; then
    fail "release commit must contain only $VERSION_FILE; inspect the preserved local commit"
fi

if ! git show "HEAD:$VERSION_FILE" | grep -Fq "static let number = \"$NEW_VERSION\""; then
    fail "release commit does not contain the reported version '$NEW_VERSION'"
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    fail "a Git hook modified the worktree during commit; inspect the preserved local commit"
fi

if ! git push -u origin "$RELEASE_BRANCH"; then
    fail "push failed; the local release commit was preserved on '$RELEASE_BRANCH'"
fi

set +e
PR_OUTPUT="$(
    # The PR body is literal Markdown, not a shell expansion.
    # shellcheck disable=SC2016
    gh pr create \
        --base main \
        --head "$RELEASE_BRANCH" \
        --title "[CI] Prepare Version $NEW_VERSION Release" \
        --body 'Update `Version.swift` with bumped version number.' \
        --label ci 2>&1
)"
PR_STATUS=$?
set -e
readonly PR_OUTPUT PR_STATUS

if [[ "$PR_STATUS" -ne 0 ]]; then
    printf '%s\n' "$PR_OUTPUT" >&2

    RECONCILED_PR_URL="$(release_pr_url)"
    readonly RECONCILED_PR_URL
    if [[ -n "$RECONCILED_PR_URL" ]]; then
        set +e
        PR_EDIT_OUTPUT="$(gh pr edit "$RECONCILED_PR_URL" --add-label ci 2>&1)"
        PR_EDIT_STATUS=$?
        set -e
        readonly PR_EDIT_OUTPUT PR_EDIT_STATUS

        if [[ "$PR_EDIT_STATUS" -ne 0 ]]; then
            printf '%s\n' \
                "$PR_EDIT_OUTPUT" \
                "error: pull request exists, but ensuring the ci label failed." \
                "Recover with:" \
                "  gh pr edit $RECONCILED_PR_URL --add-label ci" \
                >&2
            exit "$PR_EDIT_STATUS"
        fi

        git switch main
        printf 'Created release pull request: %s\n' "$RECONCILED_PR_URL"
        exit 0
    fi

    printf '%s\n' \
        "error: release branch was pushed, but pull request creation failed." \
        "Recover with:" \
        "  gh pr create --base main --head release --title '[CI] Prepare Version $NEW_VERSION Release' --body 'Update \`Version.swift\` with bumped version number.' --label ci" \
        >&2
    exit "$PR_STATUS"
fi

git switch main
printf 'Created release pull request: %s\n' "$PR_OUTPUT"
