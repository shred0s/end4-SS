#!/usr/bin/env bash
# Writes the Clips hotkeys into Hyprland's config (custom/clips.lua, loaded from custom/keybinds.lua)
# and reloads Hyprland. The Clips app runs this when a shortcut is changed in its settings.
# Usage: clip_keybinds.sh [save saveBuffer toggle openApp]
#   Each is a Hyprland key combo like "ALT + F10", or "" for none. Without arguments they're read from
#   the shell config.

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
OUT="$HOME/.config/hypr/custom/clips.lua"

shortcut() { # shortcut <name> <default>; an empty string (cleared on purpose) is kept
    jq -r --arg default "$2" ".clips.shortcuts.$1 // \$default" "$CONFIG_FILE" 2>/dev/null || echo "$2"
}

if [[ $# -eq 4 ]]; then
    save=$1 save_buffer=$2 toggle=$3 open_app=$4
else
    save=$(shortcut save "ALT + F10")
    save_buffer=$(shortcut saveBuffer "SHIFT + ALT + F10")
    toggle=$(shortcut toggle "CTRL + ALT + F10")
    open_app=$(shortcut openApp "")
fi

bind() { # bind <combo> <quickshell global shortcut> <description>
    [[ -z "$1" ]] && return
    if [[ ! "$1" =~ ^[A-Za-z0-9_:+\ ]+$ ]]; then
        echo "Skipping odd shortcut: $1" >&2
        return
    fi
    printf 'hl.bind("%s", hl.dsp.global("quickshell:%s"), { description = "%s" })\n' "$1" "$2" "$3"
}

{
    echo "-- Written by the Clips app (Settings → Shortcuts & sound). Changes made here get overwritten."
    bind "$save" clipSave "Clips: Save a clip of the last few seconds"
    bind "$save_buffer" clipSaveBuffer "Clips: Save the whole replay buffer"
    bind "$toggle" clipToggle "Clips: Start or stop clipping"
    bind "$open_app" clipViewerToggle "Clips: Open or close the Clips app"
} > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

hyprctl reload >/dev/null
