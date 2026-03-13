---
name: edit-keymap
description: >
  Edit a Charybdis keyboard layout JSON file (charybdis.layout.json or
  charybdis-3x5.layout.json). Use when the user wants to change key
  mappings, add/modify layers, or rearrange their keyboard layout.
  After editing, update the matching layout diagram in README.md.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Write, Glob, Grep
---

# Edit Charybdis Keymap

When editing a Charybdis keyboard layout:

1. Determine which keymap file to edit (`charybdis.layout.json` for 4x6, `charybdis-3x5.layout.json` for 3x5).
2. Read the keymap JSON file.
3. Make the requested changes to the JSON.
4. Read `README.md` and check if the edited file is referenced there.
5. If it is, regenerate the layout diagram section for that file to match the new JSON.
6. Show the user the updated layout diagram for confirmation.

## JSON key position mapping

- Left side keys are stored left-to-right (outer to inner) in the JSON.
- Right side keys are stored right-to-left (outer to inner) in the JSON — reverse them for the diagram.

### 4x6 layout (charybdis.layout.json)

60 keys per layer:
- Indices 0–5: Left Row 0 (number row, 6 keys)
- Indices 6–11: Left Row 1 (6 keys)
- Indices 12–17: Left Row 2 (home row, 6 keys)
- Indices 18–23: Left Row 3 (6 keys)
- Indices 24–29: Left Thumb (6 keys)
- Indices 30–35: Right Row 0 (number row, 6 keys, stored outer→inner)
- Indices 36–41: Right Row 1 (6 keys, stored outer→inner)
- Indices 42–47: Right Row 2 (home row, 6 keys, stored outer→inner)
- Indices 48–53: Right Row 3 (6 keys, stored outer→inner)
- Indices 54–59: Right Thumb (6 keys)

### 3x5 layout (charybdis-3x5.layout.json)

60 keys per layer (same indices, but row 0 and outer columns are KC_NO):
- Active left keys: indices 7–11 (row 1), 13–17 (row 2), 19–23 (row 3)
- Active left thumb: indices 25, 27, 28 (3 keys)
- Active right keys: indices 37–41 (row 1), 43–47 (row 2), 49–53 (row 3)
- Active right thumb: indices 55, 57 (2 keys)

## Layout diagram format

Use box-drawing characters in fenced code blocks. 5-char wide cells. Abbreviate key names to fit (e.g. CTL_A, SFT_J, L1_EN, HOLD, trns, CUS0).
