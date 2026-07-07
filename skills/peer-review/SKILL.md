---
name: peer-review
description: Use when the user wants a Codex code review run locally against the current branch (or uncommitted changes) and the mechanical findings applied as edits, before pushing — so the GitHub Codex bot has less to flag on the PR. Trigger phrases include "peer review", "run codex on this", "self-review before I push", "codex my changes", "do a local review first", "keep reviewing until clean", "cycle codex locally".
---

# Peer Review

## Overview

One pass: run `codex review` against the current branch's diff, triage its findings, apply the mechanical fixes, and commit. Designed to be run *before* pushing (or as a follow-up commit) so the GitHub Codex bot on the PR has fewer threads to open. Composes with `/loop` for iterative convergence.

**This is local-only.** No `gh` calls, no PR threads, no GraphQL. The whole skill is `codex review` → edits → optional commit. If you find yourself reaching for GitHub APIs, you want [[babysit-pr]] instead.

## How to invoke

Single pass:
```
/peer-review
```

Iterative until clean (recommended for non-trivial diffs) — **this is how you cycle** through multiple review→fix→review rounds; step 7 owns the loop-continue decision and the anti-loop ceiling:
```
/loop /peer-review
```

For the *PR* side (after pushing, driving Codex on GitHub instead of locally), see [[cycle-review-pr]].

The user may pass an optional scope hint, e.g. `/peer-review uncommitted` or `/peer-review base=develop`. Honor it; otherwise auto-detect (see step 1).

## When NOT to use

- Diff is empty (nothing changed vs base, no uncommitted work) — exit immediately, tell the user there's nothing to review.
- User wants to address comments **already posted** on a GitHub PR — that's [[babysit-pr]], not this.
- User explicitly asked for a different reviewer (Claude itself, CodeRabbit, etc.) — this skill is Codex-specific.
- `codex` CLI not installed (`command -v codex` empty) — surface that to the user with the install path; don't try to substitute.

## One iteration

### 1. Determine scope

Pick exactly one mode based on repo state (and any user hint):

| State | Mode | Command |
|---|---|---|
| User said `uncommitted` OR branch is `main`/`master` with dirty tree | uncommitted | `codex review --uncommitted` |
| User said `base=X` | branch vs X | `codex review --base X` |
| Current branch != main/master AND clean tree | branch vs main | `codex review --base main` (or `master` if that's the default) |
| Clean tree on main/master | nothing to review | exit |

Detect the default branch with `git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@'`, falling back to `main`.

If both committed-branch-changes AND uncommitted changes exist, ask the user which scope they want — don't guess.

### 2. Run the review

```bash
codex review --base "$BASE" 2>&1 | tee /tmp/peer-review-$$.txt
```

(Or `--uncommitted` per step 1.) Pipe through `tee` so you have a stable transcript to refer to while planning — Codex's output can be long and you don't want to re-read it from your scrollback.

If `codex` exits non-zero, surface the stderr verbatim to the user and stop. Common causes: not logged in (`codex login`), config error, network. Don't try to work around.

### 3. Triage findings — DO NOT edit yet

Codex's review output is free-form prose, usually structured as numbered findings with severity hints (P1/P2/nit, or "Critical/Major/Minor", or just inline tone). Read the whole thing, then build a working list — one row per finding:

| # | severity | file:line | summary | action | reason |
|---|---|---|---|---|---|
| 1 | P1 | src/foo.ts:42 | null deref on `user.email` | apply | mechanical, clear fix |
| 2 | P2 | src/bar.ts:88 | rename `tmp` → `pendingUpload` | apply | naming nit, low risk |
| 3 | P1 | src/auth.ts:120 | session token TTL too long | **skip** | policy/security judgment — surface to user |
| 4 | nit | src/x.ts:5 | could use `?.` | **skip** | nitpick, not worth churn |
| 5 | P2 | docs/api.md:30 | stale example | apply | doc fix |

**Decision rules:**

| Situation | Action |
|---|---|
| Bug, null-safety, or correctness fix with a clear mechanical change | **apply** |
| Naming, formatting, or local refactor with clear intent and small blast radius | **apply** |
| Doc/comment fix that matches the code | **apply** |
| Suggestion requires architectural/security/policy judgment, or spans multiple files in non-obvious ways | **skip** — surface to user at end |
| Nit (style preference, ultra-minor) | **skip** by default; apply only if a cluster of nits exists in one file (batch cheap fixes) |
| Codex is wrong (you can verify by reading the file) | **skip**, note why |
| Finding is already fixed in the working tree (Codex reviewed a stale snapshot) | **skip**, note |

Treat Codex's confidence as a hint, not gospel. Read the actual file before applying anything — Codex sometimes hallucinates line numbers, variable names, or "current behavior" that's already different from what's on disk.

### 4. Apply the fixes

Apply every `apply` row from the working list, in file order (one file at a time, multiple edits per file batched). After each file, re-read it to confirm the edit landed cleanly. If an edit fails because the surrounding code doesn't match Codex's description, downgrade that row to `skip` and continue — don't force it.

**Do not** add comments referencing Codex, the review, or the finding number ("// per Codex review", "// addresses P1 #3"). The fix should be indistinguishable from any other commit; CLAUDE.md's no-noise-comments rule applies.

### 5. Commit (only if you applied fixes)

If at least one fix landed, commit. Follow the repo's commit conventions — check `CLAUDE.md` / `AGENTS.md` / recent `git log` first. Many repos require a ticket-ID suffix; reuse the ID from the branch name or the most recent commit on this branch.

```bash
git add -A && git commit -m "<short message following repo convention>"
```

Suggested message shape: `Address local Codex review feedback (CON-1234)` or similar, but defer to repo style.

**Do not push as part of this skill.** Pushing is the user's call — they may want to inspect the diff first, or batch with other work. State explicitly at the end whether you committed and remind them to push when ready.

If zero fixes were applied, do not create an empty commit.

### 6. Report

Always end with a short summary, even if no fixes landed:

```
Codex review summary
- Findings: 5 total (2 P1, 2 P2, 1 nit)
- Applied: 3 (src/foo.ts:42, src/bar.ts:88, docs/api.md:30)
- Skipped: 2
  - src/auth.ts:120 (P1, session TTL) — needs policy decision: <one-line summary>
  - src/x.ts:5 (nit) — too minor
- Committed: yes, <sha>  (push when ready)
```

Surface skipped P1/P2 items as a bulleted list with one-line context each — the user needs to see those before pushing.

### 7. Decide whether to continue (only under `/loop`)

If invoked under `/loop`:

| State | Next |
|---|---|
| Applied ≥1 fix this iteration | `ScheduleWakeup(60s)` — re-run review to confirm convergence or catch second-order issues |
| Zero fixes this iteration AND zero P1/P2 findings | omit `ScheduleWakeup` — clean, exit `/loop` |
| Zero fixes this iteration AND skipped findings remain | omit `ScheduleWakeup` — the remaining work needs the user, exit `/loop` |
| Three consecutive iterations with no progress (same findings keep coming back) | omit `ScheduleWakeup`, escalate to user — Codex disagrees with itself or you're misreading it |

State the phase in `ScheduleWakeup.reason`, e.g. `"re-running codex review to verify 3 fixes converged"`.

## Anti-loop safeguards

- **Hard ceiling.** Five iterations max under `/loop`. Even if Codex still has findings, stop and report.
- **Repeated finding.** If the *same* `file:line + summary` finding appears for 3 iterations after you've "fixed" it, stop touching it — your fix isn't what Codex wants. Surface to user.
- **Cost guard.** Each `codex review` invocation is non-trivial. If the diff hasn't changed since the last review (`git diff $BASE...HEAD` digest matches), don't re-run — exit immediately.

## Common mistakes

- **Auto-applying every finding** — Codex's job is to be thorough; yours is to be selective. Skipping is fine and often correct.
- **Editing during step 3** — step 3 is planning only. Edits in step 4. Otherwise you'll forget which findings were applied vs. skipped when you write the summary.
- **Trusting Codex's line numbers blindly** — read the file first. Codex reviews diffs and can be off by a few lines or refer to code that was moved/deleted.
- **Adding "// per Codex" comments** — noise; the commit message captures the why, the code shouldn't.
- **Pushing automatically** — this skill commits but never pushes. The user owns the push decision.
- **Creating empty commits** — if no fixes applied, don't commit. Just report and exit.
- **Running on `main` without `--uncommitted`** — `codex review` with no scope on `main` will fail or review against itself. Always pick a mode in step 1.
- **Skipping the summary** — even on a clean review, report it. The user invoked the skill expecting output.

## Why this exists

Codex's GitHub bot review on a PR is the same engine as `codex review` locally. Running it pre-push collapses the feedback loop from "push → wait for bot → babysit-pr → push fixes → wait again" to "review locally → apply → push once". The user pays for fewer mandatory PR review rounds and a faster merge.
