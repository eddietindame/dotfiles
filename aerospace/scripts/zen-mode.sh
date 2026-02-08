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
#         /tmp/aerospace-zen-top-gap (saved outer.top value for restore)
#
# NOTE: AeroSpace has no CLI command to change gaps at runtime, so this script
# modifies aerospace.toml directly (outer.left, outer.right, and outer.top)
# via sed, then runs `aerospace reload-config` to apply. The values are always
# restored to their original state when zen mode is toggled off.
#
# How it works:
#   1. Reads margin-percent, monitor target, and wallpaper settings from zen-mode.conf
#   2. On toggle ON:
#      - Resolves the target monitor name and gets its pixel width via NSScreen
#      - Calculates margin = width * margin-percent / 100
#      - Edits aerospace.toml outer.left/outer.right with per-monitor array syntax:
#        e.g. outer.left = [{ monitor."S34CG50" = 688 }, 10]
#      - Hides sketchybar on the target monitor (keeps it on other displays)
#        and reduces outer.top to reclaim bar space
#      - Runs `aerospace reload-config` and switches to accordion layout
#      - Swaps the target monitor's wallpaper (to a colour or image)
#      - Notifies sketchybar (MODE=zen)
#   3. On toggle OFF:
#      - Restores outer.left, outer.right, and outer.top in aerospace.toml
#      - Restores sketchybar to all displays and runs `aerospace reload-config`
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
HIDE_SKETCHYBAR=$(read_config_str hide-sketchybar)
HIDE_SKETCHYBAR=${HIDE_SKETCHYBAR:-true}

# Detect number of connected displays via NSScreen
DISPLAY_COUNT=$(osascript -e 'use framework "AppKit"' -e 'count of (current application'\''s NSScreen'\''s screens())')

# Apply single-display overrides when only one monitor is connected
if [[ "$DISPLAY_COUNT" -le 1 ]]; then
    SD_PERCENT=$(read_config single-display-margin-percent)
    [[ -n "$SD_PERCENT" ]] && ZEN_PERCENT="$SD_PERCENT"
    SD_DIM=$(read_config_str single-display-dim-wallpaper)
    [[ -n "$SD_DIM" ]] && DIM_WALLPAPER="$SD_DIM"
    SD_DIM_PATH=$(read_config_str single-display-dim-wallpaper-path)
    [[ -n "$SD_DIM_PATH" ]] && DIM_WALLPAPER_PATH="$SD_DIM_PATH"
    SD_SKETCHYBAR=$(read_config_str single-display-hide-sketchybar)
    [[ -n "$SD_SKETCHYBAR" ]] && HIDE_SKETCHYBAR="$SD_SKETCHYBAR"
fi

STATE_FILE="/tmp/aerospace-zen-mode"
SETTINGS_STATE="/tmp/aerospace-zen-settings"
WALLPAPER_STATE="/tmp/aerospace-zen-wallpaper"
TOP_GAP_STATE="/tmp/aerospace-zen-top-gap"
LEFT_GAP_STATE="/tmp/aerospace-zen-left-gap"
RIGHT_GAP_STATE="/tmp/aerospace-zen-right-gap"
# Generate a small solid-colour PNG from a hex value (e.g. "#1a1a2e").
# Uses python3 to write a 16x16 RGB PNG with no external dependencies.
# The filename includes the hex value so macOS doesn't serve a cached image.
generate_color_png() {
    local hex="${1#\#}"
    local out="/tmp/aerospace-zen-color-${hex}.png"
    python3 -c "
import struct, zlib
r,g,b = int('$hex'[0:2],16), int('$hex'[2:4],16), int('$hex'[4:6],16)
raw = (b'\x00' + bytes([r,g,b]) * 16) * 16
c = zlib.compress(raw)
def chunk(t, d):
    x = t + d
    return struct.pack('>I', len(d)) + x + struct.pack('>I', zlib.crc32(x) & 0xffffffff)
import sys; sys.stdout.buffer.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',16,16,8,2,0,0,0)) + chunk(b'IDAT', c) + chunk(b'IEND', b''))
" > "$out"
    echo "$out"
}

# Resolve dim-wallpaper-path: if it starts with #, generate a PNG from the colour
resolve_dim_wallpaper() {
    if [[ "$DIM_WALLPAPER_PATH" == \#* ]]; then
        generate_color_png "$DIM_WALLPAPER_PATH"
    else
        echo "$DIM_WALLPAPER_PATH"
    fi
}

if [[ -f "$STATE_FILE" ]]; then
    # --- Zen mode OFF ---

    # Restore the settings that were active when zen mode was toggled ON.
    # This handles the case where display count changed between on/off (e.g. undocking).
    if [[ -f "$SETTINGS_STATE" ]]; then
        # shellcheck disable=SC1090
        source "$SETTINGS_STATE"
        rm "$SETTINGS_STATE"
    fi

    rm "$STATE_FILE"
    # Restore original outer.left/right values (may contain per-monitor syntax)
    if [[ -f "$LEFT_GAP_STATE" && -f "$RIGHT_GAP_STATE" ]]; then
        SAVED_LEFT=$(cat "$LEFT_GAP_STATE")
        SAVED_RIGHT=$(cat "$RIGHT_GAP_STATE")
        rm "$LEFT_GAP_STATE" "$RIGHT_GAP_STATE"
        SAVED_LEFT="$SAVED_LEFT" perl -i -pe 's/^(\s+outer\.left\s*=\s*).+/${1}$ENV{SAVED_LEFT}/' "$CONFIG"
        SAVED_RIGHT="$SAVED_RIGHT" perl -i -pe 's/^(\s+outer\.right\s*=\s*).+/${1}$ENV{SAVED_RIGHT}/' "$CONFIG"
    else
        sed -i '' "s/outer\.left =.*/outer.left =       $NORMAL_MARGIN/" "$CONFIG"
        sed -i '' "s/outer\.right =.*/outer.right =      $NORMAL_MARGIN/" "$CONFIG"
    fi

    # Restore sketchybar and the original outer.top gap value
    if [[ "$HIDE_SKETCHYBAR" == "true" ]]; then
        sketchybar --bar hidden=false display=all
        if [[ -f "$TOP_GAP_STATE" ]]; then
            SAVED_TOP=$(cat "$TOP_GAP_STATE")
            rm "$TOP_GAP_STATE"
            # Use perl for restore — the saved value contains special chars like [{
            SAVED_TOP="$SAVED_TOP" perl -i -pe 's/^(\s+outer\.top\s*=\s*).+/${1}$ENV{SAVED_TOP}/' "$CONFIG"
        fi
    fi

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

    # Resolve the System Events display name for wallpaper operations.
    # NSScreen and System Events use different names for the built-in display
    # (e.g. "Built-in Retina Display" vs "Colour LCD"), so we can't reuse
    # MONITOR_NAME directly. On single display we just use the only desktop.
    if [[ "$DISPLAY_COUNT" -le 1 ]]; then
        SE_DISPLAY_NAME=$(osascript -e 'tell application "System Events" to return display name of first desktop')
    else
        SE_DISPLAY_NAME="$MONITOR_NAME"
    fi

    touch "$STATE_FILE"
    # Persist the active settings so toggle OFF uses the correct values,
    # even if the display count changes between on and off (e.g. undocking).
    cat > "$SETTINGS_STATE" <<SETTINGS
HIDE_SKETCHYBAR=$HIDE_SKETCHYBAR
DIM_WALLPAPER=$DIM_WALLPAPER
SETTINGS
    # Save original outer.left/right values before modifying
    perl -ne 'if (/^\s+outer\.left\s*=\s*(.+)/) { print "$1\n"; exit }' "$CONFIG" > "$LEFT_GAP_STATE"
    perl -ne 'if (/^\s+outer\.right\s*=\s*(.+)/) { print "$1\n"; exit }' "$CONFIG" > "$RIGHT_GAP_STATE"
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
    # Hide sketchybar and adjust outer.top to reclaim the bar's space.
    # Saves the original outer.top value for restore.
    if [[ "$HIDE_SKETCHYBAR" == "true" ]]; then
        if [[ "$DISPLAY_COUNT" -le 1 ]]; then
            # Single display — hide sketchybar entirely
            sketchybar --bar hidden=true
        else
            # Multi-display — restrict sketchybar to the other display.
            # NOTE: sketchybar display numbering is reversed from aerospace's, so we use
            # the target monitor's aerospace ID (which maps to the other display in sketchybar).
            SKETCHYBAR_DISPLAY=$(aerospace list-monitors | grep "$MONITOR_NAME" | sed 's/ |.*//' | tr -d ' ')
            if [[ -n "$SKETCHYBAR_DISPLAY" ]]; then
                sketchybar --bar display="$SKETCHYBAR_DISPLAY"
            else
                sketchybar --bar hidden=true
            fi
        fi
        # Save original outer.top value (match indented config line, not comments)
        perl -ne 'if (/^\s+outer\.top\s*=\s*(.+)/) { print "$1\n"; exit }' "$CONFIG" > "$TOP_GAP_STATE"
        # Replace only the indented config line, not comments containing outer.top
        perl -i -pe 's/^(\s+outer\.top\s*=\s*).+/${1}'"$NORMAL_MARGIN"'/' "$CONFIG"
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
        if display name of d is "$SE_DISPLAY_NAME" then
            set currentPic to picture of d
            do shell script "echo '$SE_DISPLAY_NAME':" & quoted form of currentPic & " > $WALLPAPER_STATE"
            set picture of d to "$RESOLVED_WALLPAPER"
        end if
    end repeat
end tell
APPLESCRIPT
    fi

    sketchybar --trigger aerospace_mode_changed MODE=zen
fi
