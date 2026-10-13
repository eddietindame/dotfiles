#!/usr/bin/env bash
# tmux-resurrect post-save-layout hook: drop OpenRig agent sessions from the
# save file. OpenRig names them <seat>@<rig>; restoring one gives an empty shell
# under the agent's name, which rig then mistakes for its live agent. Rig brings
# its own sessions back instead (rig up <rig> --existing).
#
# Save file lines are tab-separated with the session name in field 2 (pane,
# window, grouped_session). The state line is left alone: switching to a session
# that no longer exists just fails quietly on restore.

file="$1"
[ -f "$file" ] || exit 0

tmp="$file.tmp"
awk -F'\t' '
	($1 == "pane" || $1 == "window") && $2 ~ /@/ { next }
	$1 == "grouped_session" && ($2 ~ /@/ || $3 ~ /@/) { next }
	{ print }
' "$file" >"$tmp" && mv "$tmp" "$file"
