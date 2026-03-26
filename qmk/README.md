## QMK Firmware

Custom firmware for Charybdis 4x6 (Splinktegrated/RP2040).

### Usage

```bash
cd ~/.config/qmk
make profiles        # list profiles
make use P=name      # switch profile and compile
make save P=name     # save current QMK tree config as profile
make active          # show active profile
make flash           # compile and print flash instructions
```

### Flash

Enter bootloader (QK_BOOT key on Media layer, or double-tap hardware reset), then drag `.uf2` to the drive that appears.

### Profiles

Firmware configs live in `profiles/<name>/`, each with `config.h` and optionally `keymap.c`. The active profile is compiled into the QMK tree at `~/qmk_firmware/keyboards/bastardkb/charybdis/4x6/keymaps/eddie/`.

#### `permissive-hold` (active)

| Define | Value | Description |
|--------|-------|-------------|
| `DYNAMIC_KEYMAP_LAYER_COUNT` | `7` | Enables 7 layers for VIA (default is 4) |
| `TAPPING_TERM` | `175` | ms window to decide tap vs hold for dual-function keys |
| `PERMISSIVE_HOLD` | — | Registers hold when another key is pressed and released within tapping term |

#### `hold-on-other`

| Define | Value | Description |
|--------|-------|-------------|
| `DYNAMIC_KEYMAP_LAYER_COUNT` | `7` | Enables 7 layers for VIA (default is 4) |
| `TAPPING_TERM` | `200` | ms window to decide tap vs hold for dual-function keys |
| `PERMISSIVE_HOLD` | — | Registers hold when another key is pressed and released within tapping term |
| `HOLD_ON_OTHER_KEY_PRESS` | — | Registers hold instantly when any other key is pressed down |

Also includes `get_hold_on_other_key_press()` in `keymap.c` returning `true` for LT and MT keys.

### Files

| File | Description |
|------|-------------|
| `Makefile` | Build automation and profile management |
| `profiles/` | Firmware config profiles (`config.h` + `keymap.c`) |
| `bastardkb_charybdis_4x6_eddie.uf2` | Compiled firmware |
