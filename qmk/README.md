## QMK Firmware

Custom firmware for Charybdis 4x6 (Splinktegrated/RP2040).

Source files are copies from:
```
~/qmk_firmware/keyboards/bastardkb/charybdis/4x6/keymaps/eddie/
```

### Compile

```bash
cd ~/.config/qmk && make
```

### Flash

```bash
cd ~/.config/qmk && make flash
```

Enter bootloader (QK_BOOT key on Media layer, or double-tap hardware reset), then drag `.uf2` to the drive that appears.

### Firmware Mods

#### `config.h`

| Define | Value | Description |
|--------|-------|-------------|
| `DYNAMIC_KEYMAP_LAYER_COUNT` | `7` | Enables 7 layers for VIA (default is 4) |
| `TAPPING_TERM` | `200` | ms window to decide tap vs hold for dual-function keys |
| `PERMISSIVE_HOLD` | — | Registers hold when another key is pressed and released within tapping term. Helps home row mods trigger reliably during fast combos. |
| `HOLD_ON_OTHER_KEY_PRESS_PER_KEY` | — | Enables per-key override of `HOLD_ON_OTHER_KEY_PRESS` via callback function in `keymap.c` |

#### `keymap.c`

| Mod | Description |
|-----|-------------|
| `get_hold_on_other_key_press()` | Returns `true` for layer-tap (thumb keys) and mod-tap (home row mods) keys. Makes all dual-function keys register hold instantly when any other key is pressed, without waiting for tapping term. Regular keys are unaffected. |

### Files

| File | Description |
|------|-------------|
| `config.h` | QMK config overrides |
| `keymap.c` | Default keymap + per-key hold callback |
| `bastardkb_charybdis_4x6_eddie.uf2` | Compiled firmware |
| `Makefile` | Build automation (sync, compile, flash) |
