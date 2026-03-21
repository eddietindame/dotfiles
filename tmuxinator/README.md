# Tmuxinator Dev Config

Spins up a full Bertie development environment using git worktrees, with separate tmux windows for each repo.

## Quick start

```sh
tmuxinator start dev <branch> [options]
# or
mux start dev <branch> [options]
```

## Options

| Flag | Long | Description |
|------|------|-------------|
| (positional) | | Branch name (required). Used for frontend, backend, and packages by default. |
| `-be` | `--backend` | Backend branch, if different from frontend. |
| `-d` | `--docker` | Docker instance number (default: 1). Offsets postgres port (5432+n) and backend port (3000+n). |
| `-b` | `--base` | Base branch to branch off for both repos. Only applies when creating new worktrees. |
| `-bfe` | `--base-fe` | Base branch for frontend only. Overrides `-b`. |
| `-bbe` | `--base-be` | Base branch for backend only. Overrides `-b`. |
| `-r` | `--rebase` | Rebase existing worktrees onto their base branch instead of creating new ones. Requires `-b`, `-bfe`, or `-bbe`. |

## Examples

```sh
# Basic - same branch for all repos, docker instance 1
tmuxinator start dev feat/my-feature

# Separate backend branch
tmuxinator start dev feat/fe-branch -be feat/be-branch

# Docker instance 2 (postgres on 5434, backend on 3002)
tmuxinator start dev feat/my-feature -d 2

# Branch off a base branch (new worktree only)
tmuxinator start dev feat/my-feature -b develop

# Separate base branches for frontend and backend
tmuxinator start dev feat/my-feature -bfe feat/fe-base -bbe feat/be-base

# Rebase existing worktrees onto a base branch
tmuxinator start dev feat/my-feature -b develop -r

# Everything combined
tmuxinator start dev feat/fe-branch -be feat/be-branch -d 3 -bfe feat/fe-base -bbe feat/be-base -r
```

## What it does

### On startup (`on_project_start`)

1. Creates git worktrees for **frontend** (`bertie-desktop`), **backend** (`bertie-backend`), and **packages** (`bertie-packages`) using `ensure-worktree.sh`.
2. Generates `tmp/.env` in the backend worktree with connection details:
   ```
   POSTGRES_PORT=5433
   BACKEND_PORT=3001
   DOCKER_INSTANCE=1
   FRONTEND_ROOT=~/Documents/bertie/bertie-desktop/feat-my-feature
   BACKEND_ROOT=~/Documents/bertie/bertie-backend/feat-my-feature
   PACKAGES_ROOT=~/Documents/bertie/bertie-packages/feat-my-feature
   ```
3. Generates `tmp/repos.txt` in all three worktrees with labelled paths to each repo (for AI agent discovery).

### Windows

| Window | Repo | Panes |
|--------|------|-------|
| `bbs` | backend | Docker compose (backend + auth), db setup + backend dev server, auth dev server |
| `bb` | backend | nvim, claude |
| `bd` | frontend | nvim, claude |
| `bds` | frontend | npm install, sqlitbd |
| `sqlbb` | backend | sqlitbb (connects to offset postgres port) |
| `bp` | packages | nvim, claude |

### Worktree paths

Branch slashes are replaced with dashes in directory names:
- `feat/my-feature` -> `~/Documents/bertie/bertie-desktop/feat-my-feature`

The actual git branch name is preserved (with slashes). The tmux session name also uses the original branch name.

### Port offsets

The `-d` flag offsets ports to allow multiple instances to run simultaneously:

| Instance (`-d`) | Postgres port | Backend port |
|-----------------|---------------|--------------|
| 1 (default) | 5433 | 3001 |
| 2 | 5434 | 3002 |
| 3 | 5435 | 3003 |
| 4 | 5436 | 3004 |

## ensure-worktree.sh

Helper script that manages git worktrees:

- If the worktree directory already exists, it skips creation (just copies `.env` if missing).
- If the branch exists (local or remote), it checks it out into a new worktree.
- If the branch doesn't exist, it creates a new branch (optionally off a base branch) and worktree.
- With `--rebase`, it rebases existing worktrees onto the base branch, stashing dirty state first.

## Repos

| Repo | Main worktree | Description |
|------|---------------|-------------|
| bertie-desktop | `~/Documents/bertie/bertie-desktop/bdesk` | Frontend |
| bertie-backend | `~/Documents/bertie/bertie-backend/bb-master` | Backend |
| bertie-packages | `~/Documents/bertie/bertie-packages/bp-main` | Shared packages |
| bertie-auth | `~/Documents/bertie/bertie-auth/ba-stg` | Auth (fixed, no worktree) |
