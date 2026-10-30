#!/usr/bin/env bash
# Opens the Clips app (clips.qml), or brings the open one forward.
# Usage: clips-app.sh [clip id]   open it, showing that clip if one is given
#        clips-app.sh --toggle    close it if it's open, open it otherwise

APP="$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../clips.qml")"

if [[ "$1" == "--toggle" ]]; then
    qs ipc -p "$APP" call clipviewer close >/dev/null 2>&1 && exit 0
    shift
fi

if [[ -n "$1" ]]; then
    qs ipc -p "$APP" call clipviewer open "$1" >/dev/null 2>&1
else
    qs ipc -p "$APP" call clipviewer show >/dev/null 2>&1
fi
if [[ $? -eq 0 ]]; then
    hyprctl dispatch 'hl.dsp.focus({ window = "class:^(qs-clips)$" })' >/dev/null 2>&1
    exit 0
fi

QS_CLIPS_OPEN="$1" exec qs -n -d -p "$APP"
