#!/bin/bash
# shellcheck shell=bash
# Fixes common header issues in uncommitted Swift files created by Claude Code.
#
# The expected header comes from .swiftpm/xcode/xcshareddata/IDETemplateMacros.plist:
#
#   //
#   //  ___FILENAME___
#   //  ___TARGETNAME___
#   //
#   //  Created by ___FULLUSERNAME___ on ___DATE___.
#   //  Copyright © ___YEAR___ ___FULLUSERNAME___. All rights reserved.
#   //
#
# Fixes:
#   1. Wrong author name ("Claude" -> system user's full name)
#   2. Wrong copyright holder ("Claude" -> system user's full name, matching
#      ___FULLUSERNAME___; this project is copyrighted to the author, not an org)
#   3. Zero-padded month in date ("on 0M/" -> "on M/")
#   4. Zero-padded day in date ("/0D/" -> "/D/")
#   5. Missing trailing period on "Created by" line

set -o pipefail

# Resolve correct author name (macOS only)
if ! command -v id &> /dev/null || ! FULL_NAME=$(id -F 2>/dev/null); then
    echo "Warning: Cannot determine full name (id -F). Skipping header fixes." >&2
    exit 0
fi

if [[ -z "$FULL_NAME" ]]; then
    echo "Warning: Full name is empty. Skipping header fixes." >&2
    exit 0
fi

# Escape characters that are special in sed replacement strings
FULL_NAME=$(printf '%s' "$FULL_NAME" | sed 's/[&|\\]/\\&/g')

# Change to project root (allows script to be invoked from any directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.." || { echo "Error: Cannot find project root" >&2; exit 1; }

# Collect uncommitted .swift files (staged + unstaged + untracked)
files=()
while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
done < <(
    {
        git diff --name-only HEAD -- '*.swift' 2>/dev/null
        git diff --name-only --cached HEAD -- '*.swift' 2>/dev/null
        git ls-files --others --exclude-standard -- '*.swift' 2>/dev/null
    } | sort -u
)

if [[ ${#files[@]} -eq 0 ]]; then
    exit 0
fi

fixed_count=0

for file in "${files[@]}"; do
    # Skip files that no longer exist (e.g., deleted but still in git diff)
    [[ -f "$file" ]] || continue

    # Capture before state to detect changes
    before=$(head -7 "$file")

    # Skip files whose header needs no fixing. This pathspec also matches
    # manifests like Package.swift, and rewriting those in place would bump
    # their mtime on every run and make SwiftPM redo work for nothing.
    printf '%s\n' "$before" | grep -qE \
        'Created by Claude on|© [0-9]{4} Claude\.|on 0[1-9]/|/0[1-9]/|Created by .* [0-9]+/[0-9]+/[0-9]+$' \
        || continue

    # Fix author name: "Created by Claude on" -> "Created by <full name> on"
    sed -i '' "1,7 s|Created by Claude on|Created by ${FULL_NAME} on|" "$file"

    # Fix copyright holder: "© <year> Claude." -> "© <year> <full name>."
    sed -i '' "1,7 s|\(© [0-9]\{4\}\) Claude\. All rights reserved\.|\1 ${FULL_NAME}. All rights reserved.|" "$file"

    # Strip leading zero from month: "on 0M/" -> "on M/"
    sed -i '' '1,7 s|on 0\([1-9]\)/|on \1/|' "$file"

    # Strip leading zero from day: "/0D/" -> "/D/"
    sed -i '' '1,7 s|/0\([1-9]\)/|/\1/|' "$file"

    # Add missing trailing period on "Created by" line
    sed -i '' '1,7 s|\(Created by .* [0-9]*/[0-9]*/[0-9]*\)$|\1.|' "$file"

    after=$(head -7 "$file")
    if [[ "$before" != "$after" ]]; then
        fixed_count=$((fixed_count + 1))
    fi
done

if [[ $fixed_count -gt 0 ]]; then
    echo "fix-headers: Fixed headers in $fixed_count file(s)."
fi
