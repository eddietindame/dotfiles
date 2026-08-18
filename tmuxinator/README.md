# Tmuxinator Dev Config

Spins up a full Bertie development environment using git worktrees, with separate tmux windows for each repo.

## Quick start

```sh
scripts/start-dev.sh <branch> [options]   # tmux + a herdr space for the agents
# or, tmux only
tmuxinator start dev <branch> [options]
```

`start-dev.sh` runs `tmuxinator start dev` exactly as before, then builds a
[herdr](https://herdr.dev) space holding **only** the agent windows (`bb`, `bd`,
`bp`), each running claude as a tracked agent, and finally attaches you to tmux.
Run tmux and herdr in separate Ghostty windows.

## Options

| Flag | Long | Description |
|------|------|-------------|
| (positional) | | Branch name (required). Used for frontend, backend, and packages by default. |
| `-be` | `--backend` | Backend branch, if different from frontend. |
| `-w` | `--web` | Include the `bertie-web` repo (off unless passed). Branch is optional — defaults to the frontend branch. |
| `-d` | `--docker` | Docker instance number. Offsets postgres port (5432+n) and backend port (3000+n). Auto-detected if omitted: loops from 1 and picks the first n where both ports are free. |
| `-b` | `--base` | Base branch to branch off for both repos. Only applies when creating new worktrees. |
| `-bfe` | `--base-fe` | Base branch for frontend only. Overrides `-b`. |
| `-bbe` | `--base-be` | Base branch for backend only. Overrides `-b`. |
| `-r` | `--rebase` | Rebase existing worktrees onto their base branch instead of creating new ones. Requires `-b`, `-bfe`, or `-bbe`. |
| `-l` | `--desktop-local` | Run the Electron app over ssh on the machine you're sitting at, instead of here — macOS can't forward a window, so an app started here is only visible here. Needs an ssh target in `~/.config/tmuxinator/desktop-host` (one line, untracked), these dotfiles, and a base clone of `bertie-desktop` on that machine. `scripts/desktop-dev.sh` creates the worktree and installs deps there, honouring `-bfe` and `-r`. |
| `-l` | `--desktop-local` | Run the Electron app over ssh on the machine you're sitting at, instead of here — macOS can't forward a window, so an app started here is only visible here. Needs an ssh target in `~/.config/tmuxinator/desktop-host` (one line, untracked), plus a checkout with `node_modules` on that machine. |
| `-c` | `--claude` | Add the claude pane back to the `bb`, `bd`, and `bp` windows. Off by default — claude normally runs in herdr instead. |

### start-dev.sh only

| Flag | Description |
|------|-------------|
| `--no-herdr` | Skip the herdr space entirely; behaves like a plain `tmuxinator start`. |
| `--herdr-only` | Build only the herdr space (worktrees must already exist). Doesn't touch tmux. |

The two halves are independent — `-c` controls tmux's claude panes, `--no-herdr`
/ `--herdr-only` control the herdr space:

```sh
scripts/start-dev.sh feat/x                # claude in herdr only (default)
scripts/start-dev.sh feat/x -c             # claude in both
scripts/start-dev.sh feat/x -c --no-herdr  # claude in tmux only (original setup)
scripts/start-dev.sh feat/x --no-herdr     # no claude anywhere
scripts/start-dev.sh --herdr-only feat/x   # rebuild just the herdr space
```

## Examples

```sh
# Basic - same branch for all repos, docker instance auto-detected
tmuxinator start dev feat/my-feature

# Separate backend branch
tmuxinator start dev feat/fe-branch -be feat/be-branch

# Include bertie-web on the same branch as the frontend
tmuxinator start dev feat/my-feature -w

# Include bertie-web on its own branch
tmuxinator start dev feat/my-feature -w feat/web-branch

# Force docker instance 2 (postgres on 5434, backend on 3002)
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

1. Creates git worktrees for **frontend** (`bertie-desktop`), **backend** (`bertie-backend`), and **packages** (`bertie-packages`) using `ensure-worktree.sh`. Also **web** (`bertie-web`) if `-w` was passed.
2. Generates `tmp/.env` in the backend worktree with connection details:
   ```
   POSTGRES_PORT=5433
   BACKEND_PORT=3001
   DOCKER_INSTANCE=1
   FRONTEND_ROOT=~/Documents/bertie/bertie-desktop/feat-my-feature
   BACKEND_ROOT=~/Documents/bertie/bertie-backend/feat-my-feature
   PACKAGES_ROOT=~/Documents/bertie/bertie-packages/feat-my-feature
   WEB_ROOT=~/Documents/bertie/bertie-web/feat-my-feature   # only with -w
   ```
3. With `-w`, also generates `tmp/.env` in the web worktree (`BACKEND_URL`, `AUTH_URL`) and sets `BERTIE_BACKEND_PROXY_URL` in the web worktree's `.env` to point at this session's backend port, adding the line if it isn't already there.
4. Generates `tmp/repos.txt` in every worktree with labelled paths to each repo (for AI agent discovery).

### Windows

| Window | Repo | Panes |
|--------|------|-------|
| `bbs` | backend | Backend docker compose (postgres on the offset port), auth docker compose (postgres on 5432), `pnpm i` + db setup + backend dev server, auth `npm i` + auth dev server |
| `bb` | backend | nvim (+ claude with `-c`) |
| `bd` | frontend | nvim (+ claude with `-c`) |
| `bds` | frontend | `npm i`, sqlitbd |
| `sqlbb` | backend | sqlitbb (connects to offset postgres port) |
| `bp` | packages | nvim, `npm i` (+ `&& claude` with `-c`) |
| `bw` | web | nvim, `npm i` (+ claude with `-c`) — only with `-w` |

### herdr space (`start-dev.sh`)

One space labelled with the frontend branch, with a tab per agent window:

| Tab | Repo | Agent name |
|-----|------|------------|
| `bb` | backend | `bb-<slug>` |
| `bd` | frontend | `bd-<slug>` |
| `bp` | packages | `bp-<slug>` |

Agents are started with `herdr agent start --kind claude`, so herdr tracks their
idle/working/blocked state and `prefix+J` / `prefix+K` cycles between them. If a
space with that label already exists, the script leaves it alone rather than
adding a second set of agents.

### Worktree paths

Branch slashes are replaced with dashes in directory names:
- `feat/my-feature` -> `~/Documents/bertie/bertie-desktop/feat-my-feature`

The actual git branch name is preserved (with slashes). The tmux session name also uses the original branch name. Packages always follows the frontend branch.

### Port offsets

The `-d` flag offsets ports to allow multiple instances to run simultaneously. If omitted, the lowest free instance is auto-detected by scanning `netstat` output for listening TCP ports and picking the first candidate pair that isn't in use.

Detection starts at instance **1**. Instance 0 is not usable: the auth stack is pinned to port 3000 and its postgres to 5432, so instance 0 would collide with it — and because the auth stack is started by this same config, those ports look free at launch time and only conflict once the panes come up.

| Instance (`-d`) | Postgres port | Backend port | |
|-----------------|---------------|--------------|---|
| 0 | 5432 | 3000 | Reserved by the auth stack — don't use |
| 1 | 5433 | 3001 | |
| 2 | 5434 | 3002 | |
| 3 | 5435 | 3003 | |
| 4 | 5436 | 3004 | |

The instance is chosen when tmuxinator renders the config, but the ports aren't bound until the panes actually start. Launching two sessions within a few seconds of each other can hand both the same instance — pass `-d` explicitly if you're starting several at once.

## ensure-worktree.sh

Helper script that manages git worktrees:

- If a directory exists at the target path but isn't a git worktree, it's removed and recreated.
- If the worktree already exists, it skips creation (just copies `.env` from the main worktree if missing).
- If the branch exists (local or remote), it checks it out into a new worktree. Any base branch argument is ignored in this case.
- If the branch doesn't exist, it creates a new branch (optionally off `origin/<base>`) and worktree.
- With `--rebase`, it rebases existing worktrees onto the base branch, stashing dirty state (including untracked files) first and popping it afterwards.

Note that `git worktree add` fails if the branch is already checked out in another worktree — including a repo's main worktree.

## Repos

| Repo | Main worktree | Description |
|------|---------------|-------------|
| bertie-desktop | `~/Documents/bertie/bertie-desktop/bdesk` | Frontend |
| bertie-backend | `~/Documents/bertie/bertie-backend/bb-master` | Backend |
| bertie-packages | `~/Documents/bertie/bertie-packages/bp-main` | Shared packages |
| bertie-web | `~/Documents/bertie/bertie-web/bw-staging` | Web (opt-in via `-w`) |
| bertie-auth | `~/Documents/bertie/bertie-auth/ba-stg` | Auth (fixed, no worktree) |
