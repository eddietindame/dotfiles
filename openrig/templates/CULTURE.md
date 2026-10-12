# @@RIG@@

Feature branch `@@BRANCH@@` in @@REPO@@. The task is in the lead's living brief,
`.rig/BRIEF.md` in the lead's worktree, which the lead keeps current. Read the
repository's AGENTS.md / CLAUDE.md before changing anything.

## Who is where

| Seat | Address | Worktree | Branch |
|---|---|---|---|
@@SEAT_TABLE@@

All worktrees share one git repository, so every branch above is visible from
every worktree. Work only in your own worktree.

## How work moves

1. The lead splits the brief into slices that share no files and assigns one
   slice at a time to a builder through `rig queue` (see `rig queue --help`).
   The queue is the work record; chat text is not.
2. The builder implements the slice on its own branch, runs the checks below,
   commits, and hands the slice to the reviewer with the commit range and the
   check results.
3. The reviewer approves or returns numbered findings to the builder. Approved
   slices go to the lead.
4. The lead merges the builder branch into `@@BRANCH@@`, runs the checks on the
   merged result, and tells the builder to rebase before its next slice.

## Done means the checks pass

Run in your own worktree:

```
@@CHECKS@@
```

Report the actual result. A failure you did not cause is a finding for the
lead, not something to fix inside your slice.

## Lead-only files

Only the lead edits these. A builder that needs a change in one of them asks
the lead for it:

- `package.json`, lockfiles, and dependency changes of any kind
- global styles, Tailwind/PostCSS config, tsconfig, lint config
- barrel / index files that re-export across slices
- anything else the brief lists as shared

## After a restart

Your conversation may not survive a crash or compaction; the queue does. On
re-entry, read your queue (`rig queue list --owned`) before doing anything,
and continue the item in flight rather than starting over.

## Boundaries

- Never push, force-push, reset another branch, or rewrite history that the
  lead has merged. Publishing is the human's decision.
- Commit only on your own branch. No `git add -A` of files outside your slice.
- No new dependencies without the lead, and the lead asks the human.
- A permission prompt or an unanswerable question is a blocker: record it on
  the queue item and say exactly what decision is needed.
