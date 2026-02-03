#!/usr/bin/env bash
#
# Zen Mode for AeroSpace
#
# Toggles a focused, distraction-free layout by adding large left/right
# margins on a target monitor and switching to accordion layout.
# Other monitors are unaffected (uses AeroSpace per-monitor gap syntax).
#
# Usage: Bound to alt-z in aerospace.toml
# Config: ~/.config/aerospace/zen-mode.conf
# State:  /tmp/aerospace-zen-mode (presence = zen mode is active)
#         /tmp/aerospace-zen-wallpaper (saved wallpaper path for restore)
#
# NOTE: AeroSpace has no CLI command to change gaps at runtime, so this script
# modifies aerospace.toml directly (the outer.left and outer.right gap values)
# via sed, then runs `aerospace reload-config` to apply. The values are always
# restored to their normal state (10) when zen mode is toggled off.
#
# How it works:
#   1. Reads margin-percent, monitor target, and wallpaper settings from zen-mode.conf
#   2. On toggle ON:
#      - Resolves the target monitor name and gets its pixel width via NSScreen
#      - Calculates margin = width * margin-percent / 100
#      - Edits aerospace.toml outer.left/outer.right with per-monitor array syntax:
#        e.g. outer.left = [{ monitor."S34CG50" = 688 }, 10]
#      - Runs `aerospace reload-config` and switches to accordion layout
#      - Swaps the target monitor's wallpaper (to a colour or image)
#      - Notifies sketchybar (MODE=zen)
#   3. On toggle OFF:
#      - Restores outer.left and outer.right in aerospace.toml to 10
#      - Runs `aerospace reload-config`
#      - Restores the original wallpaper on the target monitor
#      - Notifies sketchybar (MODE=main)
#

CONFIG="$HOME/.config/aerospace/aerospace.toml"
ZEN_CONF="$HOME/.config/aerospace/zen-mode.conf"

# Read a numeric value from zen-mode.conf by key name
read_config() {
    awk -v key="$1" '$0 ~ "^"key{gsub(/[^0-9]/,"",$NF); print $NF; exit}' "$ZEN_CONF"
}

# Read a string value from zen-mode.conf by key name
read_config_str() {
    awk -v key="$1" '$0 ~ "^"key{split($0,a,"= "); gsub(/^[ \t]+|[ \t]+$/,"",a[2]); print a[2]; exit}' "$ZEN_CONF"
}

ZEN_PERCENT=$(read_config margin-percent)
ZEN_PERCENT=${ZEN_PERCENT:-20}
TARGET_MONITOR=$(read_config_str monitor)
NORMAL_MARGIN=10
DIM_WALLPAPER=$(read_config_str dim-wallpaper)
DIM_WALLPAPER=${DIM_WALLPAPER:-true}
DIM_WALLPAPER_PATH=$(read_config_str dim-wallpaper-path)
DIM_WALLPAPER_PATH=${DIM_WALLPAPER_PATH:-#000000}
STATE_FILE="/tmp/aerospace-zen-mode"
WALLPAPER_STATE="/tmp/aerospace-zen-wallpaper"
COLOR_WALLPAPER="/tmp/aerospace-zen-color.png"

# Generate a small solid-colour PNG from a hex value (e.g. "#1a1a2e").
# Uses python3 to write a 16x16 RGB PNG with no external dependencies.
generate_color_png() {
    local hex="${1#\#}"
    python3 -c "
import struct, zlib
r,g,b = int('$hex'[0:2],16), int('$hex'[2:4],16), int('$hex'[4:6],16)
raw = (b'\x00' + bytes([r,g,b]) * 16) * 16
c = zlib.compress(raw)
def chunk(t, d):
    x = t + d
    return struct.pack('>I', len(d)) + x + struct.pack('>I', zlib.crc32(x) & 0xffffffff)
import sys; sys.stdout.buffer.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',16,16,8,2,0,0,0)) + chunk(b'IDAT', c) + chunk(b'IEND', b''))
" > "$COLOR_WALLPAPER"
}

# Resolve dim-wallpaper-path: if it starts with #, generate a PNG from the colour
resolve_dim_wallpaper() {
    if [[ "$DIM_WALLPAPER_PATH" == \#* ]]; then
        generate_color_png "$DIM_WALLPAPER_PATH"
        echo "$COLOR_WALLPAPER"
    else
        echo "$DIM_WALLPAPER_PATH"
    fi
}

if [[ -f "$STATE_FILE" ]]; then
    # --- Zen mode OFF ---
    rm "$STATE_FILE"
    sed -i '' "s/outer\.left =.*/outer.left =       $NORMAL_MARGIN/" "$CONFIG"
    sed -i '' "s/outer\.right =.*/outer.right =      $NORMAL_MARGIN/" "$CONFIG"
    aerospace reload-config

    # Restore the original wallpaper on the target monitor.
    # The state file stores "monitor_name:wallpaper_path".
    if [[ "$DIM_WALLPAPER" == "true" && -f "$WALLPAPER_STATE" ]]; then
        SAVED_LINE=$(cat "$WALLPAPER_STATE")
        SAVED_MONITOR="${SAVED_LINE%%:*}"
        SAVED_WALLPAPER="${SAVED_LINE#*:}"
        rm "$WALLPAPER_STATE"
        osascript <<APPLESCRIPT
tell application "System Events"
    repeat with d in every desktop
        if display name of d is "$SAVED_MONITOR" then
            set picture of d to "$SAVED_WALLPAPER"
        end if
    end repeat
end tell
APPLESCRIPT
    fi

    sketchybar --trigger aerospace_mode_changed MODE=main
else
    # --- Zen mode ON ---

    # Resolve the monitor target to an actual monitor name and pixel width.
    # Uses macOS NSScreen API:
    #   - "external": picks the first monitor that isn't "Built-in Retina Display"
    #   - "<name>":   matches a specific monitor by name (from `aerospace list-monitors`)
    #   - empty:      falls back to the currently focused monitor
    # Returns "name:width" (e.g. "S34CG50:3440")
    MONITOR_TARGET="${TARGET_MONITOR:-}"
    RESULT=$(osascript <<APPLESCRIPT
use framework "AppKit"
set target to "$MONITOR_TARGET"
set screens to current application's NSScreen's screens()
set s to missing value
if target is "external" then
    repeat with scr in screens
        if (scr's localizedName() as text) is not "Built-in Retina Display" then
            set s to scr
            exit repeat
        end if
    end repeat
else if target is not "" then
    repeat with scr in screens
        if (scr's localizedName() as text) is target then
            set s to scr
            exit repeat
        end if
    end repeat
end if
if s is missing value then
    set s to current application's NSScreen's mainScreen()
end if
set n to s's localizedName() as text
set f to s's frame()
set w to (item 1 of item 2 of f) as integer
return n & ":" & w
APPLESCRIPT
    )

    # Parse "name:width" result
    MONITOR_NAME="${RESULT%%:*}"
    WIDTH="${RESULT##*:}"
    ZEN_MARGIN=$(( WIDTH * ZEN_PERCENT / 100 ))

    touch "$STATE_FILE"
    if [[ -n "$MONITOR_NAME" ]]; then
        # Use per-monitor gap syntax so only the target monitor is affected.
        # Other monitors (e.g. laptop) keep the normal margin.
        sed -i '' "s/outer\.left =.*/outer.left =       [{ monitor.\"$MONITOR_NAME\" = $ZEN_MARGIN }, $NORMAL_MARGIN]/" "$CONFIG"
        sed -i '' "s/outer\.right =.*/outer.right =      [{ monitor.\"$MONITOR_NAME\" = $ZEN_MARGIN }, $NORMAL_MARGIN]/" "$CONFIG"
    else
        # No monitor resolved — apply margins globally as a fallback
        sed -i '' "s/outer\.left =.*/outer.left =       $ZEN_MARGIN/" "$CONFIG"
        sed -i '' "s/outer\.right =.*/outer.right =      $ZEN_MARGIN/" "$CONFIG"
    fi
    aerospace reload-config
    aerospace layout accordion

    # Swap the target monitor's wallpaper.
    # Resolves dim-wallpaper-path: hex colours (e.g. #1a1a2e) are converted to a
    # generated PNG, file paths are used directly.
    # Saves "monitor_name:wallpaper_path" so it can be restored on toggle off.
    if [[ "$DIM_WALLPAPER" == "true" ]]; then
        RESOLVED_WALLPAPER=$(resolve_dim_wallpaper)
        osascript <<APPLESCRIPT
tell application "System Events"
    repeat with d in every desktop
        if display name of d is "$MONITOR_NAME" then
            set currentPic to picture of d
            do shell script "echo '$MONITOR_NAME':" & quoted form of currentPic & " > $WALLPAPER_STATE"
            set picture of d to "$RESOLVED_WALLPAPER"
        end if
    end repeat
end tell
APPLESCRIPT
    fi

    sketchybar --trigger aerospace_mode_changed MODE=zen
fi
