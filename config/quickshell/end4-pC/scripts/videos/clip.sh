#!/usr/bin/env bash
# Instant-replay clipping with gpu-screen-recorder.
# Usage: clip.sh start|stop|toggle|restart|status|save [seconds]
# Saved clips go into <savePath> as <uuid>.mp4, named "Untitled" in the library database (clips_db.py),
# with the game taken from the window focused at save time.

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
SOCK="${XDG_RUNTIME_DIR:-/tmp}/qs-clips.sock"
LOG="${XDG_RUNTIME_DIR:-/tmp}/qs-clips.log"

cfg() {
    local value
    # Not `// empty`: that would also drop an explicit false
    value=$(jq -r "$1 | if . == null then empty else . end" "$CONFIG_FILE" 2>/dev/null)
    echo "${value:-$2}"
}

CLIPS_DIR="$(cfg .clips.savePath "$HOME/Videos/clips")"
CLIPS_DIR="${CLIPS_DIR/#\~/$HOME}"
INCOMING_DIR="$CLIPS_DIR/.incoming" # Replays land here first, out of the library's sight until they're added
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
DB_SCRIPT="$SCRIPT_DIR/clips_db.py"
BUFFER_SECONDS="$(cfg .clips.bufferSeconds 60)"
FPS="$(cfg .clips.fps 60)"
QUALITY="$(cfg .clips.quality very_high)"
RESOLUTION="$(cfg .clips.resolution 0x0)"
MONITOR="$(cfg .clips.monitor "")"
SYSTEM_AUDIO="$(cfg .clips.systemAudio true)"
MICROPHONE="$(cfg .clips.microphone false)"
SAVE_SOUND_ENABLED="$(cfg .clips.saveSoundEnabled true)"
SAVE_SOUND="$(cfg .clips.saveSound "")"
SAVE_SOUND="${SAVE_SOUND/#\~/$HOME}"

is_running() {
    gsr-cli -ipc "$SOCK" status >/dev/null 2>&1
}

focused_monitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

sanitize() {
    # Strip trademark symbols and characters that are awkward in folder names
    sed -E 's/[™®©]//g; s#[/\\:*?"<>|]#_#g; s/[[:space:]]+/ /g; s/^[ .]+//; s/[ .]+$//' <<< "$1" | cut -c1-64
}

steam_game_name() {
    local appid=$1 lib manifest
    local libraries=("$HOME/.local/share/Steam")
    while IFS= read -r lib; do
        libraries+=("$lib")
    done < <(grep -oP '"path"\s+"\K[^"]+' "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" 2>/dev/null)
    for lib in "${libraries[@]}"; do
        manifest="$lib/steamapps/appmanifest_${appid}.acf"
        if [[ -f "$manifest" ]]; then
            grep -oP '^\s*"name"\s+"\K[^"]+' "$manifest" | head -1
            return
        fi
    done
}

desktop_entry_name() {
    local class=$1 dir file
    local dirs=("$HOME/.local/share/applications" /usr/share/applications
        /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications")
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        file=$(grep -rilE "^StartupWMClass=${class}$" "$dir" --include='*.desktop' 2>/dev/null | head -1)
        [[ -z "$file" ]] && file=$(find "$dir" -maxdepth 1 -iname "${class}.desktop" 2>/dev/null | head -1)
        if [[ -n "$file" ]]; then
            grep -m1 '^Name=' "$file" | cut -d= -f2-
            return
        fi
    done
}

# Prints "<game name>|<steam appid>|<window class>" for a window (hyprctl JSON)
game_info() {
    local win=$1 class title fullscreen name="" appid=""
    class=$(jq -r '.class // empty' <<< "$win")
    title=$(jq -r '.title // empty' <<< "$win")
    fullscreen=$(jq -r '.fullscreen // 0' <<< "$win")

    if [[ -z "$class" ]]; then
        name="Desktop"
    elif [[ "$class" =~ ^steam_app_([0-9]+)$ ]]; then
        appid="${BASH_REMATCH[1]}"
        name="$(steam_game_name "$appid")"
        [[ -z "$name" ]] && name="$title"
    elif [[ "${class,,}" == *.exe ]]; then
        name="${title:-${class%.*}}"
    else
        name="$(desktop_entry_name "$class")"
        if [[ -z "$name" ]]; then
            if [[ "$fullscreen" != "0" && -n "$title" ]]; then
                name="$title"
            else
                name="$class"
            fi
        fi
    fi

    name="$(sanitize "$name")"
    # "|" can't appear in sanitized names, and unlike a tab it keeps empty fields when read back
    printf '%s|%s|%s\n' "${name:-Unknown}" "$appid" "$class"
}

detect_game() {
    game_info "$(hyprctl activewindow -j 2>/dev/null)"
}

# Whether a window belongs to a game: Proton/gamescope/Wine classes, or a process
# launched by Steam (native games too), Lutris, Heroic or umu
is_game() {
    local class=$1 pid=$2
    case "${class,,}" in
        ""|steam|steamwebhelper) return 1 ;;
        steam_app_*|gamescope|*.exe) return 0 ;;
    esac
    [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/environ" ]] || return 1
    tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
        | grep -qE '^(SteamGameId=[1-9]|SteamAppId=[1-9]|LUTRIS_GAME_UUID=.|HEROIC_APP_NAME=.|UMU_ID=.)'
}

# Prints "<game name>|<steam appid>|<window class>|<monitor>" for a running game, focused one first
active_game() {
    local clients focused address class pid monitor_id win monitor
    clients=$(hyprctl clients -j 2>/dev/null) || return 1
    focused=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
    while IFS=$'\x1f' read -r address class pid monitor_id; do
        is_game "$class" "$pid" || continue
        win=$(jq -c --arg a "$address" '.[] | select(.address == $a)' <<< "$clients")
        monitor=$(hyprctl monitors -j | jq -r --argjson id "$monitor_id" '.[] | select(.id == $id) | .name')
        printf '%s|%s\n' "$(game_info "$win")" "$monitor"
        return 0
    done < <(jq -r --arg f "$focused" 'sort_by(.address != $f) | .[]
        | [.address, .class, (.pid | tostring), (.monitor | tostring)] | join("\u001f")' <<< "$clients")
    return 1
}

# start [monitor]: the configured monitor wins, then the given one, then the focused one
start() {
    if is_running; then
        return 0
    fi
    if ! command -v gpu-screen-recorder >/dev/null; then
        notify-send "Clipping unavailable" "gpu-screen-recorder is not installed" -a 'Clips' & disown
        return 1
    fi

    local monitor="${MONITOR:-${1:-$(focused_monitor)}}"
    local audio=()
    if [[ "$SYSTEM_AUDIO" == "true" && "$MICROPHONE" == "true" ]]; then
        audio=(-a "default_output|default_input")
    elif [[ "$SYSTEM_AUDIO" == "true" ]]; then
        audio=(-a default_output)
    elif [[ "$MICROPHONE" == "true" ]]; then
        audio=(-a default_input)
    fi

    # Apple Silicon (Asahi) has no VA-API encoder, so encode on the CPU there
    local encoder=()
    if grep -qs 'apple,' /proc/device-tree/compatible; then
        encoder=(-encoder cpu)
    fi

    mkdir -p "$INCOMING_DIR"
    rm -f "$SOCK"
    setsid -f gpu-screen-recorder -v no \
        -w "$monitor" -s "$RESOLUTION" -f "$FPS" -q "$QUALITY" \
        -c mp4 -k auto "${encoder[@]}" -ac aac "${audio[@]}" \
        -r "$BUFFER_SECONDS" -replay-storage ram \
        -o "$INCOMING_DIR" -ipc "$SOCK" > "$LOG" 2>&1

    # The socket shows up before capture has started; wait for it to answer
    for _ in $(seq 1 30); do
        is_running && return 0
        sleep 0.1
    done
    notify-send "Clipping failed to start" "$(tail -n 3 "$LOG")" -a 'Clips' -u critical & disown
    return 1
}

stop() {
    is_running || return 0
    gsr-cli -ipc "$SOCK" stop >/dev/null 2>&1 || pkill -SIGINT -f "^gpu-screen-recorder .*-ipc $SOCK"
}

play_save_sound() {
    [[ "$SAVE_SOUND_ENABLED" == "true" && -f "$SAVE_SOUND" ]] || return 0
    setsid -f ffplay -nodisp -autoexit -loglevel quiet "$SAVE_SOUND" >/dev/null 2>&1
}

# "Clip saved" with a frame of the clip; its Open button shows the clip in the Clips app
notify_saved() {
    local dest=$1 body=$2 id thumb args choice
    id="$(basename "${dest%.*}")"
    thumb="${XDG_RUNTIME_DIR:-/tmp}/qs-clips-notify-$id.jpg"
    ffmpeg -v error -y -ss 0.5 -i "$dest" -frames:v 1 -vf scale=480:-2 -q:v 5 "$thumb" >/dev/null 2>&1
    args=(-a 'Clips' -i qs-clips -A "open=Open")
    [[ -s "$thumb" ]] && args+=(-h "string:image-path:$thumb")
    choice=$(notify-send "${args[@]}" "Clip saved" "$body")
    [[ "$choice" == "open" ]] && "$SCRIPT_DIR/clips-app.sh" "$id"
}

save() {
    local seconds=$1 game appid class path dest length
    if ! is_running; then
        notify-send "Clipping is off" "Start clipping before saving a clip" -a 'Clips' & disown
        return 1
    fi

    IFS='|' read -r game appid class < <(detect_game)

    if [[ -n "$seconds" && "$seconds" != "0" ]]; then
        path=$(gsr-cli -ipc "$SOCK" save-replay "$seconds" 2>&1)
    else
        path=$(gsr-cli -ipc "$SOCK" save-replay 2>&1)
    fi
    if [[ $? -ne 0 || ! -f "$path" ]]; then
        notify-send "Clip failed" "$path" -a 'Clips' -u critical & disown
        return 1
    fi
    play_save_sound

    if ! dest=$(python3 -I "$DB_SCRIPT" --library "$CLIPS_DIR" add "$path" \
            --game="$game" --appid="$appid" --class="$class"); then
        # Leave it loose in the clips folder; the library adopts it the next time it's indexed
        dest="$CLIPS_DIR/$(basename "$path")"
        [[ "$path" != "$dest" ]] && mv -n "$path" "$dest"
    fi

    length="last ${seconds}s"
    [[ -z "$seconds" || "$seconds" == "0" ]] && length="whole buffer"
    notify_saved "$dest" "$game · $length" >/dev/null 2>&1 & disown
    echo "$dest"
}

case "$1" in
    start) start "$2" ;;
    stop) stop ;;
    restart) stop; sleep 0.5; start "$2" ;;
    toggle) if is_running; then stop; else start; fi ;;
    status) if is_running; then echo running; else echo stopped; exit 1; fi ;;
    save) save "$2" ;;
    game) detect_game ;;
    active-game) active_game ;;
    *) echo "Usage: $0 start [monitor]|stop|toggle|restart [monitor]|status|save [seconds]|game|active-game" >&2; exit 2 ;;
esac
