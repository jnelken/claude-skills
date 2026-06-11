#!/usr/bin/env bash
# find-rebase-base.sh
#
# When you try to rebase a branch onto main but main squash-merged a parent
# branch, `git rebase main` will conflict on every commit whose patch is
# already bundled into the squash commit.
#
# This script finds the correct `<old-base>` for:
#     git rebase --onto <upstream> <old-base> <branch>
#
# It prints, on stdout, a single line of the form:
#     ONTO=<upstream-sha> OLD_BASE=<sha> NEW_COMMITS=<n>
# followed by a human-readable plan on stderr.
#
# Exit codes:
#   0 — clean recommendation produced
#   1 — nothing to do (branch is already up to date or has no new commits)
#   2 — ambiguous (interleaved squashed+new commits); caller should prompt user
#   3 — usage / git error

set -euo pipefail

upstream=${1:-main}
branch=${2:-HEAD}

if ! git rev-parse --verify --quiet "$upstream" >/dev/null; then
    echo "error: upstream ref '$upstream' not found" >&2
    exit 3
fi

upstream_sha=$(git rev-parse "$upstream")
branch_sha=$(git rev-parse "$branch")

# git cherry prints one line per commit in <branch> not reachable from <upstream>:
#   "- <sha>"  => patch is already present in <upstream> (squash-equivalent)
#   "+ <sha>"  => patch is genuinely new
# Commits are printed in topological order (oldest first).
cherry_output=$(git cherry "$upstream" "$branch" || true)

if [[ -z "$cherry_output" ]]; then
    echo "info: $branch has no commits beyond $upstream — nothing to rebase." >&2
    exit 1
fi

# Walk the cherry output. A well-formed "squashed parent" situation looks like:
#   - sha1
#   - sha2
#   - sha3   <- last squashed-equivalent commit; this is OLD_BASE
#   + sha4
#   + sha5
# i.e. all "-" come before all "+".
last_minus=""
first_plus=""
saw_plus_before_minus=0
new_count=0
squashed_count=0

while IFS= read -r line; do
    sign=${line:0:1}
    sha=${line:2}
    if [[ "$sign" == "-" ]]; then
        squashed_count=$((squashed_count + 1))
        last_minus="$sha"
        if [[ -n "$first_plus" ]]; then
            saw_plus_before_minus=1
        fi
    elif [[ "$sign" == "+" ]]; then
        new_count=$((new_count + 1))
        if [[ -z "$first_plus" ]]; then
            first_plus="$sha"
        fi
    fi
done <<<"$cherry_output"

{
    echo "Branch:   $branch ($branch_sha)"
    echo "Upstream: $upstream ($upstream_sha)"
    echo "Commits already squash-equivalent in $upstream: $squashed_count"
    echo "Commits genuinely new on $branch:              $new_count"
} >&2

if [[ $squashed_count -eq 0 ]]; then
    # No squash problem — a normal rebase will work fine.
    echo "info: no squash-equivalent commits detected — plain 'git rebase $upstream' is safe." >&2
    echo "ONTO=$upstream_sha OLD_BASE=$(git merge-base "$upstream" "$branch") NEW_COMMITS=$new_count"
    exit 0
fi

if [[ $new_count -eq 0 ]]; then
    # Everything on this branch was squashed into upstream. The "rebase" is just
    # a fast-forward/reset to upstream.
    echo "info: all commits on $branch are squash-equivalent in $upstream." >&2
    echo "      You can simply: git reset --hard $upstream" >&2
    echo "ONTO=$upstream_sha OLD_BASE=$branch_sha NEW_COMMITS=0"
    exit 0
fi

if [[ $saw_plus_before_minus -eq 1 ]]; then
    # Interleaved — we can't cleanly recommend a single --onto base because
    # some "new" commits depend on being applied before some "squashed" ones.
    # Caller should fall back to gh PR lookup or ask the user.
    echo "warning: squashed and new commits are interleaved on $branch." >&2
    echo "         A single 'git rebase --onto' boundary won't work." >&2
    echo "         Fallbacks: (1) interactive rebase dropping '-' commits by hand," >&2
    echo "                    (2) gh pr view <parent-PR> --json headRefOid," >&2
    echo "                    (3) cherry-pick only the '+' commits onto $upstream." >&2
    exit 2
fi

# Clean case: OLD_BASE is the last squashed-equivalent commit.
echo "" >&2
echo "Recommended command:" >&2
echo "  git rebase --onto $upstream $last_minus $branch" >&2
echo "" >&2
echo "This will replay only the $new_count new commit(s) onto $upstream," >&2
echo "skipping the $squashed_count commit(s) already folded into the squash." >&2

echo "ONTO=$upstream_sha OLD_BASE=$last_minus NEW_COMMITS=$new_count"
