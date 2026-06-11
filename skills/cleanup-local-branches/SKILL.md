---
name: cleanup-local-branches
description: Use when the user wants to tidy up local git branches across one or more repos — survey, classify, delete merged/abandoned branches, and surface salvageable work as draft PRs. Trigger phrases include "clean up local branches", "delete merged branches", "branch audit", "tidy git branches", "review my local branches", "git branches getting messy". Also use when the user mentions branches with attached worktrees they want to clean up, or asks "what branches haven't been merged yet?".
---

# Cleanup Local Branches

A phased, interactive workflow for getting a repo's (or several repos') local branches under control. Designed for the case where you have **dozens to hundreds** of branches accumulated over months: stale `jake/*` work, leftover `codex/*` agent worktrees, mysterious `main2`/`main3` clones, squash-merged PRs whose branches were never deleted, and `--wip--` placeholders from sessions long forgotten.

## When this fits

- Multiple repos, sprawling branches, you've lost track.
- You want to be **conservative** — preserve uncommitted work, surface anything ambiguous as a draft PR, leave a recovery trail.
- You want the model to **classify and propose**, not blindly delete.

## When this is overkill

- Single branch, you know exactly what to do — just `git branch -D` it.
- Repo has < 10 branches and you can eyeball them.

## The four phases

The skill works in phases. Each phase is independently confirmable so the user stays in control. After each phase, summarize what was deleted and ask before moving on.

```
Phase 1: ancestor-of-main         (mechanical — branch tip already in main)
Phase 2: PR state triage          (GitHub query — merged-via-squash / closed / open / no PR)
Phase 3: worktree-attached        (need worktree removal before branch delete)
Phase 3.5: surface salvageable    (dirty / spared branches → draft PRs with [dev] prefix)
```

At the end, write an archive log to `~/.claude/local-branch-archive.md` so deleted branches can be recovered from git reflog (~90-day window) if needed.

## Setup

1. **Identify the repos.** The user typically names them ("clean up `<repo>`", "do all three of my repos"). If unclear, ask.
2. **Fetch + prune each.** `git -C <repo> fetch origin --prune --quiet` — without fresh remote state, ancestry checks lie.
3. **Note worktrees.** `git -C <repo> worktree list` — many branches will be attached to worktrees, which complicates deletion.
4. **Identify the current cwd's worktree.** If the user is running this from inside a worktree whose branch we'd otherwise delete, flag it and skip — removing the worktree from inside it orphans the session. They'll do it manually after.

## Phase 1 — Branches whose tip is in `origin/main`

These are the easy wins. The branch tip is reachable from `origin/main` (merge ancestry intact, not squash-merged) → the work is in main and the branch is just a stale name.

```bash
git -C <repo> for-each-ref --format='%(refname:short)' refs/heads/ | while read -r b; do
  [ "$b" = "main" ] && continue
  # Skip if branch has a worktree attached
  if git -C <repo> worktree list --porcelain | grep -q "^branch refs/heads/$b$"; then continue; fi
  if git -C <repo> merge-base --is-ancestor "$b" origin/main 2>/dev/null; then
    echo "$b"
  fi
done
```

These can be deleted with `git branch -d` (lowercase, refuses non-merged → safer).

**Watch for:** suspicious-looking names like `main2`, `mainxxx`, numbered branches `5174`-`5180`, `worktree-agent-*`. They're safe by ancestry (tip is in main), but flag them in the proposed delete list so the user can confirm. Local-only delete is non-destructive (doesn't touch remote), so the user can be liberal here.

**Confirm with user before deleting.** Show counts per repo and the full list. Bulk-delete all with one `git branch -d <names...>` per repo.

## Phase 2 — Unmerged branches: classify by GitHub PR state

For branches that *aren't* ancestors of main, the work might still be in main via a squash-merge (which breaks ancestry), or the branch might just be abandoned. Query GitHub to find out:

```bash
# Fetch all PRs once per repo (much faster than per-branch lookup)
gh pr list --repo <owner>/<repo> --state all --limit 1000 --json number,state,headRefName
```

Then join locally — for each unmerged-no-worktree branch, find its PR (if any) and bucket:

| PR state | Action |
|---|---|
| `MERGED` (squash) | **Delete with `-D`** — code is in main, branch is a dead name |
| `CLOSED` (abandoned) | **Likely delete with `-D`** — confirm with user |
| `OPEN` | **Keep** — active work |
| No PR | **Move to NO_PR triage** (next step) |

`backup/*` branches are usually explicit user backups — classify separately and ask before deleting.

## NO_PR triage — per-branch judgment

Branches with no PR are a mix: unpushed WIPs, abandoned scratch, real local-only work the user forgot about. For each, gather:

```bash
# Diff vs merge-base (not vs main!) — shows the branch's actual contribution
mb=$(git -C <repo> merge-base "$branch" origin/main)
git -C <repo> diff "$mb..$branch" --shortstat
git -C <repo> diff "$mb..$branch" --name-only | head -15
```

**Critical:** Diff against the **merge-base**, not against `origin/main` directly. Otherwise the stat shows main's accumulated changes since the branch was created — wildly misleading (e.g. "1,200 files changed" when the branch only touched 3).

### Decision rules (user-validated)

- **`fix*` branches that never PR'd** → safe to delete. Tied to a specific code state at a specific time. If the bug still exists, file it fresh.
- **Documentation / eslint rules / style guides / OpenAPI MDX** → **keep**. These are long-standing improvements that survive code churn. Worth surfacing as a draft PR (Phase 3.5) so the user can decide whether to ship them.
- **Stale codex/agent branches > 8 weeks old** → safe to delete. Agent output that wasn't reviewed quickly is rarely worth reviving.
- **WIP / `--wip-- [skip ci]` placeholders > 4 weeks old** → safe to delete. The user has moved on.
- **Branches whose work has already shipped via another PR** → safe to delete. Check by greping the commit subject or ticket ID in `git log origin/main`.

### Watch for mismatches

The branch name and the commit content can disagree (e.g. `neon-stage-reset-control` whose actual commit was a Linear webhook simplification). When they disagree, read the actual commit and decide based on content, not name.

## Phase 3 — Worktree-attached branches

These are the gnarliest because a branch with a worktree can't be deleted until the worktree is removed first. Most are leftover from PR work that already merged.

For each worktree-attached branch, gather:
- Worktree path
- Locked? (`locked` line in `worktree list --porcelain`)
- PR state
- Dirty? Untracked files?
- Last commit date

### Lock check before forcing

If a worktree is "locked" with a reason like `claude agent agent-XYZ (pid 39764)`, **check if the PID is alive** before forcing removal:

```bash
ps -p 39764 -o pid,command  # exits non-zero if dead
```

If the PID is dead, the lock is stale and `git worktree remove -f -f` is safe. If alive, leave it — there's a running agent that owns it.

### Buckets

| Bucket | Action |
|---|---|
| PR MERGED, clean tree | `git worktree remove <path>` then `git branch -D <branch>` |
| PR CLOSED, clean tree | Same — confirm with user (PR closed = work explicitly abandoned) |
| Detached HEAD (no branch) | Just `git worktree remove <path>` — no branch to delete |
| Locked + PID dead | `git worktree remove -f -f <path>` then `git branch -D <branch>` |
| Locked + PID alive | **Skip** — live process owns it |
| Dirty (uncommitted work) | **Skip & flag** — surface to user, don't auto-delete |
| Open PR | **Keep** — active work |
| `~/code/<repo>` and similar "alternative main" clones (main2, main3, w2oodrow) | **Ask** — these are intentional setups, not garbage |

### The cwd trap

If the user invoked this skill from inside one of the worktrees we'd otherwise remove, **skip it** and give them the manual command for after the session ends:

```bash
cd ~/code/<repo>
git worktree remove --force <cwd-path>
git branch -D <branch>
```

### Pruning stale refs

After bulk removals, `git -C <repo> worktree prune -v` cleans up any orphan worktree refs (e.g. worktrees whose directory was deleted manually).

## Phase 3.5 — Surface salvageable branches as draft PRs

For branches the user opted to **keep** that have either uncommitted work or unmerged commits worth reviewing, push them as **draft PRs with `[dev]` prefix in the title**. This lets the user use GitHub's UI to decide later.

### Pre-checks per branch

```bash
ahead=$(git -C <wt> rev-list --count origin/main..HEAD)
dirty=$(git -C <wt> status --short | grep -v "^##" | wc -l)  # exclude the ## header line
```

**Gotcha:** `git status --short` always emits a leading `## branch-name` line. Don't count it as a modification — filter with `grep -v "^##"`.

### Cases

| ahead | dirty | What to do |
|---|---|---|
| 0 | 0 | Branch is empty vs main. **Delete it** — nothing to PR. GitHub rejects empty-diff PRs anyway. |
| ≥1 | 0 | Push as-is. Create draft PR. |
| ≥0 | ≥1 | Commit dirty as `[WIP] uncommitted state — surfaced for draft PR review`, push, create draft PR. The WIP commit is squashable later. |

### PR creation pattern

```bash
git -C <wt> push --no-verify -u origin <branch>
gh pr create --draft --base main --head <branch> \
  --title "[dev] <branch> — <one-line description>" \
  --body "$(cat <<EOF
## Summary
<why this branch surfaced, what's in it>

## Changes
<bullet diff summary>

## Why draft
Surfaced from local-branch cleanup. <decide: finish / rebase / scrap.>
EOF
)"
```

**`--no-verify` is fine here** because:
- Worktrees often lack `node_modules` → pre-commit/pre-push hooks fail on missing tooling, not real issues.
- The PR is **draft** — CI on GitHub validates code quality before promotion to ready.
- These are WIP captures meant for visual review, not production-ready work.

Mention the `--no-verify` in your report to the user so they know.

## Archive log

After all phases, write or append to `~/.claude/local-branch-archive.md`. Include for each deleted branch:
- Repo
- Branch name
- **Last-known SHA** (so `git reflog` recovery works within ~90 days)
- Why deleted (PR state, age, content category)

This is the single most important output beyond the deletions themselves. Without the SHA log, accidentally-deleted work is much harder to recover.

Include a "Reflog recovery" snippet:

```bash
cd /path/to/repo
git reflog | grep <branch-name>
git branch <branch-name> <sha>
```

## Conversation pattern

The whole flow is interactive — ask before destructive operations, summarize after, let the user opt into each phase. Use `AskUserQuestion` with multi-select where natural ("which buckets to delete?") and single-select for branching paths ("dive in now or pause?"). Don't bury the user under choices — group decisions where possible.

After each phase report:
- What was deleted (count + names)
- What was kept and why
- What's left to decide

## Final tally

End with a clean before/after table per repo:

| Repo | Branches before → after | Worktrees before → after |
|---|---|---|

And the path to the archive log.

## Common mistakes

- **Diffing vs `origin/main` instead of merge-base** — gives wildly inflated stats. Always use `git merge-base ... && git diff <mb>..HEAD`.
- **Counting the `## header` line as dirty** — `git status --short | wc -l` over-counts by 1. Use `grep -v "^##"` first.
- **Removing the cwd worktree mid-session** — orphans the session. Skip + provide manual command.
- **Force-removing a "locked" worktree without checking the PID** — could kill a running codex/claude agent's working state. Check `ps -p <pid>` first.
- **Forgetting to fetch + prune** — stale `origin/main` makes ancestry checks lie, and stale tracking branches show up as "merged" when they aren't.
- **Treating squash-merged branches as unmerged** — their tip isn't reachable from main, but the work IS in main. Always check PR state too.
- **Deleting `backup/*` branches without asking** — those were created on purpose, not garbage. Always confirm.
- **Logging tip SHAs after deletion** — too late. Capture them in the proposed-delete list, then write the archive log immediately after delete confirmation.
- **Creating PRs for empty branches** — GitHub rejects "No commits between main and X". Filter those out and offer to delete them instead.
- **Filtering "new reviewer activity" without excluding own GitHub user** — replies you post via the API appear in `pulls/N/comments` authored by you. Filter `--jq 'map(select(.user.login != "<your-login>"))'` to find genuine new feedback.

## What success looks like

- 60-80% reduction in local branch count is normal on first run.
- Open-PR branches and explicit backups are untouched.
- Every deleted branch has a row in `~/.claude/local-branch-archive.md` with its SHA.
- Dirty/spared branches are visible as draft `[dev]` PRs in GitHub.
- The user is more confident about their repo state, not less.
