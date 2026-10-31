#!/usr/bin/env bash
# here are flags :)
#
#   ./install.sh                   every step below except clips
#   ./install.sh dots notch        only the named steps
#   ./install.sh --with-clips      also build gpu-screen-recorder for the Clips module
#   ./install.sh --no-notch        leave the MacBook notch area hidden
#   ./install.sh --reset dots      swap your configs for the repo's instead of keeping them
#                                  (add asahi notch on a Mac, so its tweaks go back on too)
#   ./install.sh restore           put back the configs in a backup (--from=<folder> picks which)
#
# Running it again keeps your configs and settings: only the shell and Hyprland's core files get
# updated, and settings new to the repo get added to config.json. Anything replaced is moved to
# ~/.local/share/end4-pc-dotfiles/backup-<date>/ first
set -Eeuo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/end4-pc-dotfiles"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
VENV="$STATE/quickshell/.venv"
DATA="$HOME/.local/share/end4-pc-dotfiles"
BACKUP="$DATA/backup-$(date +%Y%m%d-%H%M%S)"
SETTINGS="$HOME/.config/illogical-impulse/config.json"

QUICKSHELL_REV=4f508be500dea6e5732cc3d50382a0048b17e7b1 # Quickshell 0.3.2
MATUGEN_VERSION=4.2.0
STARSHIP_VERSION=1.27.0
OBS_CMD_TAG=v1.0.2
DARKLY_TAG=v0.5.42

ALL_STEPS=(packages quickshell tools darkly python dots asahi notch firefox system login)
steps=()
with_clips=false
notch=true
reset=false
restore_from=""
for arg in "$@"; do
    case $arg in
        --with-clips) with_clips=true ;;
        --no-notch) notch=false ;;
        --reset) reset=true ;;
        --from=*) restore_from=${arg#--from=}; restore_from=${restore_from/#\~/$HOME} ;;
        -h | --help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) steps+=("$arg") ;;
    esac
done
# Steps asked for by name redo their tweaks; a full run only applies them to a fresh install
explicit=true
if [[ ${#steps[@]} -eq 0 ]]; then
    explicit=false
    steps=("${ALL_STEPS[@]}")
    if $with_clips; then steps+=(clips); fi
fi
first_install=true
if [[ -e $SETTINGS ]]; then first_install=false; fi

log() { printf '\e[1;34m::\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m!!\e[0m %s\n' "$*" >&2; }
die() { printf '\e[1;31mxx\e[0m %s\n' "$*" >&2; exit 1; }

list() { sed 's/#.*//; s/\*//g' "$REPO/packages/$1" | tr -s ' \n' '\n' | grep -v '^$'; }

is_apple() { grep -qs 'apple,' /proc/device-tree/compatible; }

# Files the repo's copy went into during this run, which the tweak steps are free to change
declare -A FRESH=()
kept=0

# Moves a path into this run's backup, or copies it there with --copy. The first copy of a path is the one kept
backup() {
    local path=$1 rel=${1#"$HOME"/}
    [[ -e $path || -L $path ]] || return 0
    if [[ -e $BACKUP/$rel || -L $BACKUP/$rel ]]; then
        if [[ ${2:-} != --copy ]]; then rm -rf "$path"; fi
        return 0
    fi
    mkdir -p "$BACKUP/$(dirname "$rel")"
    if [[ ${2:-} == --copy ]]; then cp -a "$path" "$BACKUP/$rel"; else mv "$path" "$BACKUP/$rel"; fi
}

deploy() {
    backup "$2"
    mkdir -p "$(dirname "$2")"
    cp -a "$1" "$2"
    FRESH[$2]=1
}

# For files the repo owns: brings them up to date, leaving them be if they already are
update() {
    if [[ -e $2 ]] && diff -rq -x __pycache__ "$1" "$2" &>/dev/null; then return 0; fi
    deploy "$1" "$2"
}

# For the user's configs: puts the repo's copy in only if there's nothing there yet (or with --reset)
offer() {
    if [[ -e $2 || -L $2 ]] && ! $reset; then
        kept=$((kept + 1))
    else
        update "$1" "$2"
    fi
}

# Hyprland's own files, which hyprland.lua says not to edit (your changes go in custom/). The shell's
# settings write shellOverrides/ and matugen writes colors.lua, so those are the user's
is_core() {
    case $1 in
        hypr/hyprland/shellOverrides/* | hypr/hyprland/colors.lua) return 1 ;;
        hypr/hyprland.lua | hypr/hyprland/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Whether a tweak step may change a file: the repo's copy went in during this run, or the step was
# asked for by name, in which case the user's copy is backed up first
may_edit() {
    [[ -e $1 ]] || return 1
    [[ -z ${FRESH[$1]:-} ]] || return 0
    $explicit || return 1
    backup "$1" --copy
}

# The repo's configs say @HOME@ where the home folder goes
fill_home() {
    local pictures
    pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
    sed -e "s|@HOME@/Pictures|$pictures|g" -e "s|@HOME@|$HOME|g"
}

# config.json keeps every value already in it and gains only the settings that are new in the repo's
merge_settings() {
    local src=$1 dest=$2 defaults merged
    if [[ ! -e $dest ]] || $reset; then
        update "$src" "$dest"
        return 0
    fi
    defaults=$(mktemp)
    merged=$(mktemp)
    fill_home <"$src" >"$defaults"
    if ! jq --indent 4 --slurpfile mine "$dest" '. * $mine[0]' "$defaults" >"$merged" 2>/dev/null; then
        warn "Couldn't read ${dest/#"$HOME"/\~}, left it as it is"
    elif ! jq -e --slurpfile mine "$dest" '. == $mine[0]' "$merged" >/dev/null; then
        backup "$dest" --copy
        cat "$merged" >"$dest"
        log "Added the settings that are new in this version to ${dest/#"$HOME"/\~}"
    fi
    rm -f "$defaults" "$merged"
}

jq_edit() {
    local file=$1 tmp
    shift
    tmp=$(mktemp)
    jq "$@" "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

fresh_clone() {
    local url=$1 dir=$2
    shift 2
    rm -rf "$dir"
    git clone "$@" "$url" "$dir"
}

step_packages() {
    log "Enabling COPR repos"
    sudo dnf install -y dnf5-plugins 2>/dev/null || sudo dnf install -y dnf-plugins-core
    local repo
    for repo in $(list copr.txt); do
        sudo dnf copr enable -y "$repo"
    done

    log "Installing packages"
    sudo dnf install -y $(list fedora.txt) $(list fedora-build.txt)
}

step_quickshell() {
    if qs --version 2>/dev/null | grep -q "$QUICKSHELL_REV"; then
        log "Quickshell is already at ${QUICKSHELL_REV:0:7}"
        return
    fi
    local pkg src="$CACHE/quickshell"
    for pkg in quickshell quickshell-git; do
        if rpm -q "$pkg" &>/dev/null; then sudo dnf remove -y "$pkg"; fi
    done

    log "Building Quickshell ${QUICKSHELL_REV:0:7}"
    fresh_clone https://git.outfoxxed.me/quickshell/quickshell.git "$src" --filter=blob:none ||
        fresh_clone https://github.com/quickshell-mirror/quickshell.git "$src" --filter=blob:none
    git -C "$src" checkout -q "$QUICKSHELL_REV"
    cmake -S "$src" -B "$src/build" -GNinja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DINSTALL_QML_PREFIX=lib64/qt6/qml \
        -DCRASH_HANDLER=OFF \
        -DDISTRIBUTOR="end4-pc-dotfiles (source build)" \
        -DGIT_REVISION="$QUICKSHELL_REV"
    cmake --build "$src/build"
    sudo cmake --install "$src/build"
}

step_tools() {
    local root="$CACHE/cargo"
    if [[ $(matugen --version 2>/dev/null) != "matugen $MATUGEN_VERSION" ]]; then
        log "Building matugen $MATUGEN_VERSION"
        cargo install --locked --root "$root" matugen --version "$MATUGEN_VERSION"
        sudo install -m755 "$root/bin/matugen" /usr/local/bin/matugen
    fi

    if ! command -v obs-cmd >/dev/null; then
        log "Building obs-cmd $OBS_CMD_TAG"
        cargo install --locked --root "$root" --git https://github.com/grigio/obs-cmd --tag "$OBS_CMD_TAG" obs-cmd
        sudo install -m755 "$root/bin/obs-cmd" /usr/local/bin/obs-cmd
    fi

    if [[ $(starship --version 2>/dev/null | head -n1) != "starship $STARSHIP_VERSION" ]]; then
        log "Installing starship $STARSHIP_VERSION"
        local dir="$CACHE/starship" tar=starship-aarch64-unknown-linux-musl.tar.gz
        local url="https://github.com/starship/starship/releases/download/v$STARSHIP_VERSION"
        rm -rf "$dir" && mkdir -p "$dir"
        curl -fsSL -o "$dir/$tar" "$url/$tar"
        echo "$(curl -fsSL "$url/$tar.sha256" | cut -d' ' -f1)  $dir/$tar" | sha256sum -c --quiet -
        tar -xzf "$dir/$tar" -C "$dir"
        sudo install -m755 "$dir/starship" /usr/local/bin/starship
    fi
}

step_darkly() {
    local src="$CACHE/darkly" stamp="$CACHE/darkly-$DARKLY_TAG.installed"
    if [[ -e $stamp ]]; then
        log "Darkly $DARKLY_TAG is already installed"
        return
    fi
    log "Building Darkly $DARKLY_TAG"
    if fresh_clone https://github.com/Bali10050/Darkly.git "$src" --depth 1 --branch "$DARKLY_TAG" &&
        cmake -S "$src" -B "$src/build" -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
            -DBUILD_QT5=OFF -DBUILD_QT6=ON -DWITH_DECORATIONS=OFF -DBUILD_TESTING=OFF &&
        cmake --build "$src/build" &&
        sudo cmake --install "$src/build"; then
        touch "$stamp"
    else
        warn "Darkly failed to build; Qt apps will use Breeze"
    fi
}

step_python() {
    log "Setting up the shell's Python venv"
    mkdir -p "$(dirname "$VENV")"
    UV_PYTHON_PREFERENCE=only-system uv venv --allow-existing --prompt .venv -p 3.12 "$VENV"
    uv pip install --python "$VENV/bin/python" -r "$REPO/packages/python-requirements.txt"
}

step_dots() {
    log "Updating the shell and Hyprland's core files"
    update "$REPO/config/quickshell/end4-pC" "$HOME/.config/quickshell/end4-pC"
    local file rel tmp
    while IFS= read -r -d '' file; do
        rel=${file#"$REPO"/config/}
        if [[ $rel == illogical-impulse/config.json ]]; then
            merge_settings "$file" "$SETTINGS"
        elif [[ $rel == hypr/monitors.lua ]] && is_apple; then
            offer "$REPO/asahi/hypr/monitors.lua" "$HOME/.config/$rel"
        elif is_core "$rel"; then
            update "$file" "$HOME/.config/$rel"
        else
            offer "$file" "$HOME/.config/$rel"
        fi
    done < <(find "$REPO/config" -path "$REPO/config/quickshell" -prune -o -type f -print0)
    while IFS= read -r -d '' file; do
        offer "$file" "$HOME/.${file#"$REPO"/}"
    done < <(find "$REPO/local" -type f -print0)
    if ((kept)); then
        log "Kept $kept configs you already had (./install.sh --reset dots swaps them for the repo's)"
    fi

    for file in "$SETTINGS" "$HOME/.config/hypr/hyprlock/colors.conf"; do
        if [[ -n ${FRESH[$file]:-} ]]; then
            tmp=$(mktemp)
            fill_home <"$file" >"$tmp"
            cat "$tmp" >"$file"
            rm -f "$tmp"
        fi
    done
    local pictures
    pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
    mkdir -p "$pictures/Wallpapers"
    cp --update=none "$REPO"/wallpapers/* "$pictures/Wallpapers/"
}

step_asahi() {
    if ! is_apple; then
        warn "Not Apple hardware, skipping the MacBook tweaks"
        return
    fi
    local monitors="$HOME/.config/hypr/monitors.lua" file changed=false
    if [[ ! -e $monitors ]] || may_edit "$monitors"; then
        cp "$REPO/asahi/hypr/monitors.lua" "$monitors"
        changed=true
    fi
    if may_edit "$SETTINGS"; then
        jq_edit "$SETTINGS" '.hyprland.input.touchpad.clickfingerBehavior = true'
        changed=true
    fi
    for file in "$HOME/.config/hypr/hyprland/shellOverrides/main.lua" "$HOME/.config/hypr/custom/general.lua"; do
        if may_edit "$file"; then
            sed -i -E 's/(clickfinger_behavior = )false/\1true/; s/(sensitivity = )-?[0-9.]+/\10/' "$file"
            changed=true
        fi
    done
    if $changed; then
        log "Applied the MacBook tweaks (internal display, trackpad)"
    else
        log "Keeping your display and trackpad settings (./install.sh asahi applies the MacBook ones again)"
    fi
}

notch_width() {
    local compat
    compat=" $(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null) "
    case $compat in
        *" apple,j314s "* | *" apple,j314c "* | *" apple,j316s "* | *" apple,j316c "* | \
            *" apple,j414s "* | *" apple,j414c "* | *" apple,j416s "* | *" apple,j416c "*)
            echo 400 ;;
        *" apple,j413 "* | *" apple,j415 "*)
            echo 360 ;;
        *)
            [[ -n $(find /proc/device-tree -name 'apple,notch-height' -print -quit 2>/dev/null) ]] || return 1
            echo 380 ;;
    esac
}

# Asahi merged the DCP driver into appledrm in 2025, which moved the flag from apple_dcp.show_notch
notch_param() {
    local module
    for module in appledrm apple_dcp; do
        if [[ -e /sys/module/$module/parameters/show_notch ]] || modinfo -p "$module" 2>/dev/null | grep '^show_notch:' >/dev/null; then
            echo "$module.show_notch=1"
            return
        fi
    done
    echo appledrm.show_notch=1
}

step_notch() {
    if ! $notch; then return; fi
    local width param
    if ! width=$(notch_width); then
        log "No notch on this machine"
        return
    fi
    param=$(notch_param)
    if [[ $param != apple_dcp.* ]] && sudo grubby --info=ALL 2>/dev/null | grep 'apple_dcp.show_notch' >/dev/null; then
        log "Removing the old apple_dcp.show_notch flag, current kernels ignore it"
        sudo grubby --update-kernel=ALL --remove-args=apple_dcp.show_notch
    fi
    if ! sudo grubby --info=ALL 2>/dev/null | grep "$param" >/dev/null; then
        log "Turning on the notch area ($param, takes effect after a reboot)"
        sudo grubby --update-kernel=ALL --args="$param"
    fi
    if may_edit "$SETTINGS"; then
        log "Splitting the top bar's center modules around the notch (${width}px)"
        jq_edit "$SETTINGS" --argjson width "$width" \
            '.bar.notch = {enable: true, screen: "eDP-1", width: $width, splitIndex: -1}'
    else
        log "Keeping your notch bar settings (./install.sh notch sets them again)"
    fi
}

step_firefox() {
    local generated="$STATE/quickshell/user/generated/firefox" profile found=false
    mkdir -p "$generated"
    for profile in "$HOME"/.mozilla/firefox/*.default-release "$HOME"/.config/mozilla/firefox/*.default-release; do
        [[ -d $profile ]] || continue
        found=true
        if [[ ! -L $profile/chrome ]]; then backup "$profile/chrome"; fi
        ln -sfn "$generated" "$profile/chrome"
        if ! grep -qs legacyUserProfileCustomizations "$profile/user.js"; then
            echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >>"$profile/user.js"
        fi
    done
    if ! $found; then
        warn "No Firefox profile yet: open Firefox once, then run ./install.sh firefox"
    fi
}

step_system() {
    log "Themes, groups and login shell"
    xdg-user-dirs-update || true
    sudo usermod -aG video,input "$USER"
    systemctl --user enable --now ydotool.service 2>/dev/null ||
        sudo systemctl enable --now ydotool.service 2>/dev/null ||
        warn "Couldn't enable ydotool's service; the on-screen keyboard won't type"

    local key value
    if $first_install || $explicit; then
        while read -r key value; do
            gsettings set org.gnome.desktop.interface "$key" "$value" || warn "gsettings: couldn't set $key"
        done <<'EOF'
gtk-theme adw-gtk3-dark
color-scheme prefer-dark
icon-theme breeze-plus-dark
cursor-theme Bibata-Modern-Classic
cursor-size 24
font-name Google Sans Flex Medium 11 @opsz=11,wght=500
EOF
        kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Darkly
        kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-plus-dark
    else
        log "Keeping your GTK/Qt theme, icons, cursor and font (./install.sh system sets them again)"
    fi
    fc-cache -f >/dev/null

    local fish
    fish=$(command -v fish)
    if [[ $(getent passwd "$USER" | cut -d: -f7) != "$fish" ]]; then
        read -rp "Make fish your login shell? [Y/n] " answer
        if [[ ! $answer =~ ^[Nn] ]]; then sudo usermod --shell "$fish" "$USER"; fi
    fi
}

# Minimal installs have no login manager; anything already set up (sddm, gdm...) is left alone
step_login() {
    local current=/etc/systemd/system/display-manager.service
    if [[ -e $current ]]; then
        log "Login manager already set up ($(basename "$(readlink -f "$current")" .service)), leaving it alone"
        return
    fi
    log "Setting up greetd + tuigreet as the login screen"
    sudo dnf install -y greetd tuigreet
    [[ -e /etc/greetd/config.toml.orig ]] || sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.orig
    sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --asterisks --cmd start-hyprland"
user = "greetd"
EOF
    sudo systemctl enable greetd.service
    sudo systemctl set-default graphical.target
}

step_clips() {
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        log "Enabling RPM Fusion (free) for ffmpeg with libx264"
        sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    fi
    if rpm -q ffmpeg-free &>/dev/null; then sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing; fi
    sudo dnf install -y $(list fedora-clips.txt)

    log "Building gpu-screen-recorder"
    local src="$CACHE/gpu-screen-recorder"
    fresh_clone https://repo.dec05eba.com/gpu-screen-recorder "$src" --depth 1
    meson setup "$src/build" "$src" --buildtype=release --prefix=/usr -Dnvidia_suspend_fix=false
    meson compile -C "$src/build"
    sudo meson install -C "$src/build"
}

# Puts back the configs in a backup, by default the newest one holding a config.json (from the run that
# replaced them). The shell and Hyprland's core files stay at this version
step_restore() {
    local from=$restore_from dir file rel dest answer count=0
    if [[ -z $from ]]; then
        for dir in "$DATA"/backup-*/; do
            if [[ $dir != *-before-restore/ && -e ${dir}.config/illogical-impulse/config.json ]]; then
                from=${dir%/}
            fi
        done
    fi
    [[ -n $from && -d $from ]] ||
        die "Found no backup with your settings in ${DATA/#"$HOME"/\~}; pick one with --from=<folder>"
    from=${from%/}
    read -rp "Put back the configs from ${from/#"$HOME"/\~}? [Y/n] " answer || answer=""
    if [[ $answer =~ ^[Nn] ]]; then
        log "Pick another with --from=<folder>:"
        printf '   %s\n' "$DATA"/backup-*/
        return
    fi

    BACKUP="$BACKUP-before-restore" # Never picked by a later restore
    while IFS= read -r -d '' file; do
        rel=${file#"$from"/}
        case $rel in
            .config/quickshell/* | .config/mozilla/*) continue ;;
            .config/* | .local/*) ;;
            *) continue ;;
        esac
        if is_core "${rel#.config/}"; then continue; fi
        dest="$HOME/$rel"
        if [[ -e $dest ]] && cmp -s "$file" "$dest"; then continue; fi
        backup "$dest"
        mkdir -p "$(dirname "$dest")"
        cp -a "$file" "$dest"
        count=$((count + 1))
    done < <(find "$from" \( -type f -o -type l \) -print0)
    log "Put back $count files. Log out and back in so everything picks them up"
}

[[ $EUID -ne 0 ]] || die "Run this as your user; it uses sudo where it needs to"
command -v dnf >/dev/null || die "This installer is for Fedora (Asahi Remix)"
[[ $(uname -m) == aarch64 ]] || warn "This isn't aarch64; the package choices were checked for Apple Silicon"
is_apple || warn "This doesn't look like a Mac; the MacBook steps will be skipped"

for step in "${steps[@]}"; do
    declare -F "step_$step" >/dev/null || die "Unknown step: $step"
done
mkdir -p "$CACHE"
sudo -v
for step in "${steps[@]}"; do
    "step_$step"
done

log "Done."
[[ -d $BACKUP ]] && log "Your previous configs are in ${BACKUP/#"$HOME"/\~}"
if $first_install; then
    log "Reboot and log in to Hyprland. The welcome window lets you choose a wallpaper,"
    log "which generates the colors for everything else."
fi
