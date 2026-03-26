---
name: compile-firmware
description: >
  Compile the Charybdis QMK firmware and copy the output to ~/.config/qmk/.
  Use when the user changes config.h, keymap.c, or asks to rebuild/recompile
  the keyboard firmware.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# Compile Charybdis Firmware

## Source of truth

Firmware configs live in `~/.config/qmk/profiles/<name>/`, each containing `config.h` and `keymap.c`. The active profile is tracked in `profiles/.active`. There are no loose config files in the qmk root.

## Compiling

```bash
cd ~/.config/qmk && make compile
```

This copies the active profile to the QMK tree and compiles.

## Profile management

- `make profiles` — list available profiles and show which is active
- `make use P=name` — switch to a profile and compile
- `make save P=name` — snapshot the current QMK tree config as a new profile
- `make active` — show the active profile and its config

## When the user changes firmware config

1. Edit files in the active profile directory: `~/.config/qmk/profiles/<active>/config.h` or `keymap.c`.
2. Run `cd ~/.config/qmk && make compile`.
3. Update `~/.config/qmk/README.md` if any defines or functions have changed. The README documents all firmware mods in tables — keep them in sync with the active profile.
4. Remind the user to flash both halves of the keyboard.

## When the user wants to try a new config

1. Edit the active profile or create a new one with `make save P=new-name`.
2. Switch with `make use P=name` (this compiles automatically).
