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
#
# How it works:
#   1. Reads margin-percent and monitor target from zen-mode.conf
#   2. On toggle ON:
#      - Resolves the target monitor name and gets its pixel width via NSScreen
#      - Calculates margin = width * margin-percent / 100
#      - Edits aerospace.toml gaps using per-monitor array syntax:
#        outer.left = [{ monitor."<name>" = <margin> }, 10]
#      - Reloads aerospace config and switches to accordion layout
#      - Notifies sketchybar (MODE=zen)
#   3. On toggle OFF:
#      - Restores outer.left and outer.right to the normal value (10)
#      - Reloads aerospace config
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
STATE_FILE="/tmp/aerospace-zen-mode"

if [[ -f "$STATE_FILE" ]]; then
    # --- Zen mode OFF ---
    rm "$STATE_FILE"
    sed -i '' "s/outer\.left =.*/outer.left =       $NORMAL_MARGIN/" "$CONFIG"
    sed -i '' "s/outer\.right =.*/outer.right =      $NORMAL_MARGIN/" "$CONFIG"
    aerospace reload-config
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
    sketchybar --trigger aerospace_mode_changed MODE=zen
fi
