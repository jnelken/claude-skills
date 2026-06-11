---
name: rebase-after-squash
description: Rebase a branch onto main (or any upstream) when a parent branch was squash-merged, so the original commits live on this branch but their content is already in upstream as a single squash commit. Use when the user reports per-commit conflicts rebasing onto main, says "my parent branch was squashed," or asks how to rebase after a squash-merge. Trigger phrases include "rebase onto main squashed," "every commit conflicts during rebase," "parent branch got squash-merged."
---

# Rebase After Squash-Merge

## The situation

A parent branch was squash-merged into the upstream (usually `main`):

```
main:   A──B──C──────S          (S = squash-merge of parent branch)
               \
parent:         P1──P2──P3      (squashed into S; branch may be deleted)
                         \
current:                  X1──X2 (HEAD — what we want to rebase)
```

`git rebase main` tries to replay `P1, P2, P3, X1, X2` onto `S`. But `S`
already contains the patches from `P1..P3`, so each of those commits will
appear to conflict with itself. You'll get N "empty after conflict resolution"
rebases in a row.

The correct operation is:

```
git rebase --onto main P3 HEAD
```

which replays only `X1, X2`. The script in this skill finds `P3`.

## How `git cherry` detects the situation

`git cherry <upstream> <branch>` prints one line per commit in `<branch>` not
reachable from `<upstream>`:

- `- <sha>` — patch-equivalent to a commit already in upstream (squashed)
- `+ <sha>` — genuinely new

Matching is by **patch ID** (a hash of the diff), not SHA. So a commit on your
branch and its squashed counterpart in main share a patch ID even though
everything else differs.

Well-formed squash-and-rebase looks like:

```
- P1
- P2
- P3      ← last "-"; this is OLD_BASE
+ X1
+ X2
```

## Workflow

### 1. Diagnose

Run the helper:

```bash
~/.claude/skills/rebase-after-squash/scripts/find-rebase-base.sh main HEAD
```

It prints a human plan to stderr and a machine-readable line to stdout:

```
ONTO=<upstream-sha> OLD_BASE=<sha> NEW_COMMITS=<n>
```

Exit codes:

- `0` — clean recommendation; proceed
- `1` — branch has no commits beyond upstream; nothing to do
- `2` — **ambiguous**: squashed and new commits are interleaved. A single
  `--onto` boundary won't work; fall back to the gh PR lookup below or drop
  `-` commits in an interactive rebase.
- `3` — usage / git error

### 2. Back up before rebasing

Always create a backup branch before a non-trivial rebase:

```bash
git branch "backup/$(git rev-parse --abbrev-ref HEAD)-$(date +%Y%m%d-%H%M%S)"
```

If anything goes wrong, `git reset --hard <backup-branch>` restores state.
`git reflog` is a second safety net.

### 3. Rebase

Using the values parsed from the helper's stdout:

```bash
git rebase --onto "$ONTO" "$OLD_BASE" HEAD
```

### 4. Verify

```bash
git log --oneline "$ONTO..HEAD"   # should show only the NEW_COMMITS
git diff "$ONTO"                   # full diff vs upstream
```

## Fallback: gh PR lookup (for exit code 2, or when patch-id matching fails)

If `git cherry` can't cleanly identify the boundary — usually because the
squash-merge resolved conflicts differently from the linear branch diff — use
GitHub's record of the parent PR:

```bash
# Find merged PRs targeting main, sorted by merge date
gh pr list --state merged --base main --limit 50 \
  --json number,title,headRefName,headRefOid,mergedAt \
  --jq '.[] | "\(.mergedAt)  #\(.number)  \(.headRefName)  \(.headRefOid)  \(.title)"'
```

`headRefOid` is the tip SHA of the parent branch at merge time — exactly the
`P3` we want, assuming it's still in your local history. Verify with:

```bash
git merge-base --is-ancestor <headRefOid> HEAD && echo "yes, use this as OLD_BASE"
```

Then:

```bash
git rebase --onto main <headRefOid> HEAD
```

## Fallback: cherry-pick only the new commits

If even the gh lookup fails (the parent tip is no longer in local history and
can't be fetched), the nuclear option is:

```bash
# Identify the "+" commits from git cherry
git cherry main HEAD | awk '$1=="+"{print $2}'

# Reset to upstream and cherry-pick them
git branch backup/pre-reset HEAD
git reset --hard main
git cherry-pick <each "+" sha in order>
```

## Recovery

Mid-rebase things gone wrong:

```bash
git rebase --abort               # return to pre-rebase state
git reset --hard backup/<name>   # if --abort isn't available
git reflog                       # last-resort history archaeology
```

## When NOT to use this skill

- The branch has genuinely independent commits that *happen* to conflict with
  main for unrelated reasons — that's a normal rebase, resolve conflicts
  manually.
- The parent branch was **merge-committed** (not squashed) into main — a normal
  `git rebase main` works because the original commits are in main's history.
- You want to preserve the parent branch's individual commits in history — in
  that case you don't want to rebase at all; merge instead.
