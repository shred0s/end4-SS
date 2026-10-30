#!/usr/bin/env fish
# Save the OBS replay buffer via obs-websocket (works while OBS is unfocused)
set -l pw (jq -r .server_password ~/.config/obs-studio/plugin_config/obs-websocket/config.json)
if obs-cmd -w "obsws://localhost:4455/$pw" replay save >/dev/null 2>&1
    notify-send -a OBS -t 2000 "Clip saved"
else
    notify-send -a OBS -u critical "Clip failed" "Is OBS running with the replay buffer started?"
end
