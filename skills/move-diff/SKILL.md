---
name: move-diff
description: Use when you want to relocate unstaged git changes from the current workspace to a different branch or worktree without committing — e.g. "move these changes to branch X", "apply my diff to another worktree", "I started work on the wrong branch".
---

# move-diff

Moves the current unstaged diff to another branch's worktree, then reverts the source.

## Usage

```bash
move-diff <target-branch>          # strict context match
move-diff --3way <target-branch>   # 3-way merge fallback for diverged branches
```

## Behavior

1. Captures `git diff` (unstaged tracked changes only)
2. Finds an existing worktree for `<target-branch>`, or creates a temporary one
3. Applies the patch with `git apply` (+ `--3way` if flagged)
4. Runs `git restore .` to revert the source
5. On failure, cleans up any temp worktree and leaves source untouched

## When to use `--3way`

Use when the patch fails with `patch does not apply` — this happens when the target branch has diverged enough that context lines no longer match. `--3way` falls back to a 3-way merge using git's object store, resolving minor divergence automatically.

## Notes

- Only moves **unstaged** changes. Staged changes are unaffected.
- If target branch has no worktree, a temp one is created under `/tmp/`. The path is printed; clean up with `git worktree remove <path>`.
- Changes land **unstaged** in the target — review and commit there as normal.
