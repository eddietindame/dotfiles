---
name: offload-builder
description: Use when you lead a rig on the Mac mini and need another builder but the mini is short of memory, or a slice will run heavy checks (full test suites, browser tests, builds). Starts a builder on the laptop (64 GB) over ssh, assigns it work, fetches its branch back and removes it when done.
---

# Offloading a builder to the laptop

The mini has 16 GB shared by every rig on it. When it runs out, macOS kills
processes and has taken the whole machine down. The laptop has 64 GB and runs
its own OpenRig daemon, so a slice can be built there instead. Everything goes
through `~/.config/openrig/scripts/offload.sh` (call it `offload.sh` below).

## When to offload

- Before giving a builder a slice, check memory: `memory_pressure | tail -1`.
  Below about 30% free, or with several heavy checks already running on the
  mini, offload the slice instead of starting it here.
- Slices whose checks are heavy anyway: full test suites, Storybook or browser
  tests, Electron or Next builds.
- Not for a slice that needs your local dev server or the human's eyes on the
  mini, and not for one that edits lead-only files.

## Start one

```
offload.sh start <rig> [repos...]
```

Run it from your own shell. The default is every repo in your folder; name only
the ones the slice touches, since each one is cloned and installed on the laptop.
It takes a few minutes and prints the new seat, e.g. `dev-x1@<rig>-x1` on host
`laptop`, on branch `<your branch>-x1`. The laptop seat starts from your culture
file, plus a note on how it differs there, and copies of your `BRIEF.md` and
`PROGRESS.md`.

## Work with it

It's a builder like the others, addressed with `--host laptop`:

```
offload.sh sync <rig> x1                        # first, if BRIEF.md / PROGRESS.md changed
rig queue create --host laptop --destination dev-x1@<rig>-x1 --summary "..." --body-file slice.md
rig send dev-x1@<rig>-x1 --host laptop "..."
rig capture dev-x1@<rig>-x1 --host laptop       # read its screen
offload.sh status <rig>
```

It reports to you with `rig send ... --host mini`, starting its messages with
its seat name. A watcher on the mini also messages you if the laptop seat needs
attention, stops running, or the laptop is unreachable for five minutes.

## When it hands a slice back

The laptop builder hands finished slices to you, not to the reviewer:

1. `offload.sh fetch <rig> x1` brings `<branch>-x1` into your repos and says
   how many commits it is ahead.
2. Hand it to the reviewer like any builder's branch: the commit range
   `<branch>..<branch>-x1` per repo.
3. Send the reviewer's findings to the laptop builder, then fetch again.
4. Merge it as usual, then tell the laptop builder to rebase before its next
   slice. Its `origin` is your repos on the mini, so it picks up your merges
   with `git fetch origin && git rebase origin/<branch>`; its culture note
   already says so.

Its work counts as done only once you've fetched it to the mini. Until then
it exists only on the laptop.

## Finish

```
offload.sh done <rig> x1
```

This fetches the branch one last time, stops the laptop rig and removes its
folder. The branch stays in your repos. Do this as soon as the builder has
nothing left, so it doesn't use the laptop or its Claude usage for nothing.

## If something is wrong

- `can't reach the laptop`: it is asleep, off or off Tailscale. Its work is
  safe there; tell the human, and carry on with local builders meanwhile.
- `rig ps --host laptop` fails: the laptop's daemon is down. `offload.sh start`
  starts it; for an existing seat, ask the human.
- Never delete the laptop's folders by hand: use `offload.sh done`.
