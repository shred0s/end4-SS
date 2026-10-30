#!/usr/bin/env bash
# here are flags :)
#
#   ./install.sh                   every step below except clips
#   ./install.sh dots notch        only the named steps
#   ./install.sh --with-clips      also build gpu-screen-recorder for the Clips module
#   ./install.sh --no-notch        leave the MacBook notch area hidden
#
# configs that already exist are moved to ~/.local/share/end4-pc-dotfiles/backup-<date>/ first
set -Eeuo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/end4-pc-dotfiles"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
VENV="$STATE/quickshell/.venv"
BACKUP="$HOME/.local/share/end4-pc-dotfiles/backup-$(date +%Y%m%d-%H%M%S)"

QUICKSHELL_REV=4f508be500dea6e5732cc3d50382a0048b17e7b1 # Quickshell 0.3.2
MATUGEN_VERSION=4.2.0
STARSHIP_VERSION=1.27.0
OBS_CMD_TAG=v1.0.2
DARKLY_TAG=v0.5.42

ALL_STEPS=(packages quickshell tools darkly python dots asahi notch firefox system login)
steps=()
with_clips=false
notch=true
for arg in "$@"; do
    case $arg in
        --with-clips) with_clips=true ;;
        --no-notch) notch=false ;;
        -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) steps+=("$arg") ;;
    esac
done
if [[ ${#steps[@]} -eq 0 ]]; then
    steps=("${ALL_STEPS[@]}")
    if $with_clips; then steps+=(clips); fi
fi

log() { printf '\e[1;34m::\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m!!\e[0m %s\n' "$*" >&2; }
die() { printf '\e[1;31mxx\e[0m %s\n' "$*" >&2; exit 1; }

list() { sed 's/#.*//; s/\*//g' "$REPO/packages/$1" | tr -s ' \n' '\n' | grep -v '^$'; }

is_apple() { grep -qs 'apple,' /proc/device-tree/compatible; }

backup() {
    local path=$1 rel=${1#"$HOME"/}
    [[ -e $path || -L $path ]] || return 0
    mkdir -p "$BACKUP/$(dirname "$rel")"
    mv "$path" "$BACKUP/$rel"
}

deploy() {
    backup "$2"
    mkdir -p "$(dirname "$2")"
    cp -a "$1" "$2"
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
    log "Copying configs (existing ones are moved to ${BACKUP/#"$HOME"/\~})"
    local item name file
    for item in "$REPO"/config/*; do
        name=$(basename "$item")
        if [[ $name == quickshell ]]; then
            deploy "$item/end4-pC" "$HOME/.config/quickshell/end4-pC"
        else
            deploy "$item" "$HOME/.config/$name"
        fi
    done
    while IFS= read -r -d '' file; do
        deploy "$file" "$HOME/.${file#"$REPO"/}"
    done < <(find "$REPO/local" -type f -print0)

    local pictures
    pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
    mkdir -p "$pictures/Wallpapers"
    cp --update=none "$REPO"/wallpapers/* "$pictures/Wallpapers/"
    sed -i -e "s|@HOME@/Pictures|$pictures|g" -e "s|@HOME@|$HOME|g" \
        "$HOME/.config/illogical-impulse/config.json" "$HOME/.config/hypr/hyprlock/colors.conf"
}

step_asahi() {
    if ! is_apple; then
        warn "Not Apple hardware, skipping the MacBook tweaks"
        return
    fi
    log "Applying MacBook tweaks (internal display, trackpad)"
    cp "$REPO/asahi/hypr/monitors.lua" "$HOME/.config/hypr/monitors.lua"
    jq_edit "$HOME/.config/illogical-impulse/config.json" '.hyprland.input.touchpad.clickfingerBehavior = true'
    sed -i -E 's/(clickfinger_behavior = )false/\1true/; s/(sensitivity = )-?[0-9.]+/\10/' \
        "$HOME/.config/hypr/hyprland/shellOverrides/main.lua" "$HOME/.config/hypr/custom/general.lua"
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
    log "Splitting the top bar's center modules around the notch (${width}px)"
    jq_edit "$HOME/.config/illogical-impulse/config.json" --argjson width "$width" \
        '.bar.notch = {enable: true, screen: "eDP-1", width: $width, splitIndex: -1}'
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
log "Reboot and log in to Hyprland. The welcome window lets you choose a wallpaper,"
log "which generates the colors for everything else."
