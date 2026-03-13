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

When the user changes firmware config or asks to recompile:

1. Run:
   ```bash
   cd ~/.config/qmk && make
   ```
   This syncs local files to the QMK tree, compiles, and copies the output back.
2. Update `~/.config/qmk/README.md` if any defines in `config.h` or functions in `keymap.c` have changed. The README documents all firmware mods in tables — keep them in sync with the actual code.
3. Remind the user to flash both halves of the keyboard.
