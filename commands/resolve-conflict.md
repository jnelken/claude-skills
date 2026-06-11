You are resolving git merge/rebase conflicts. Follow this procedure, and **briefly tell the user what you're doing and what you found at each step** before moving to the next.

## Steps

1. **Identify conflicted files**: Run `git diff --name-only --diff-filter=U` to list all files with conflicts. Tell the user how many files are conflicted and which areas of the codebase they touch (e.g. "12 files — mostly routes and services, plus one migration").

2. **Understand the conflict pattern**: Sample 3-5 conflicted files using `grep -n '<<<<<<<\|=======\|>>>>>>>' <file>` and read the surrounding context to determine the nature of each side:
   - What does HEAD (ours) represent?
   - What does the incoming (theirs) represent?
   - Which side is correct, or does it require a manual merge of both?
   
   Tell the user what the conflict is actually about — e.g. "Every conflict is the same: theirs adds `deletedAt: null` filters, ours removed them because the extension handles it."

3. **Classify the resolution strategy** before touching any files:
   - **Accept ours**: HEAD is correct for all conflicts → `git checkout --ours <files> && git add <files>`
   - **Accept theirs**: Incoming is correct for all conflicts → `git checkout --theirs <files> && git add <files>`
   - **Mixed/manual**: Different files or hunks need different resolutions → resolve individually
   - If all conflicts follow the same pattern, batch-resolve. If not, group by pattern and resolve each group.
   - If there is a conflict in .understand-anything/, take the incoming changes and then run the `/understand` command to incrementally update the knowledge base.
   
   Tell the user which strategy you're going with and why — e.g. "Accepting ours across the board because the soft-delete extension makes those explicit filters redundant."

4. **Resolve conflicts**: Apply the chosen strategy. For manual merges, edit the file to remove conflict markers and keep the correct code. Tell the user as you go — e.g. "Resolved 65 files via `checkout --ours`, staging now."

5. **Verify**: After resolving, run `git diff --name-only --diff-filter=U` to confirm zero remaining conflicts. Then run a quick type-check or build if available to catch resolution errors. Tell the user the result — e.g. "Zero conflicts remaining, type-check passes."

6. **PR sanity check**: Check if there's an open PR for this branch (`gh pr view --json url,number 2>/dev/null`). If the command fails or returns ambiguous results (e.g. detached HEAD, multiple candidates, or no PR found despite expecting one), ask the user for the GitHub PR link rather than guessing. If one exists:
   - Fetch the PR diff from before the rebase: `gh pr diff <number>`
   - Compare against the current local diff to the base branch: `git diff $(gt parent)...HEAD`
   - Flag any unexpected differences — lines that appeared or disappeared that aren't explained by the conflict resolution strategy. These could be accidental inclusions from the wrong side.
   - Tell the user what you found — e.g. "PR diff matches the local diff, no unexpected changes" or "Found 3 files where the resolution introduced changes not in the original PR — here's what changed."

7. **Report**: Give a final summary — how many files, which strategy, why, and whether the PR diff check passed.

If the branch is managed by Graphite, do NOT run git-specific commands like `git rebase --continue` and only use Graphite's `gt continue`.
