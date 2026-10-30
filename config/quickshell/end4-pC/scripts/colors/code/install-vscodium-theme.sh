#!/usr/bin/env bash
# Installs the end4-pC color theme into VSCodium.
#
# The theme file inside the extension is a symlink to the theme that
# generate-vscodium-theme.py renders on every wallpaper change. The theme is
# contributed with "_watch": true, which makes VSCodium reload it live whenever
# that file changes.
#
# Both "end4-pC Dark" and "end4-pC Light" read the same file (it always holds
# the current mode's colors); they only differ in the base theme VSCodium uses
# for anything the file doesn't set.
set -euo pipefail

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_SRC="$SCRIPT_DIR/vscodium-theme"
THEME_FILE="$XDG_STATE_HOME/quickshell/user/generated/vscodium-theme.json"
EXTENSIONS_DIR="$HOME/.vscode-oss/extensions"

publisher=$(jq -r .publisher "$EXT_SRC/package.json")
name=$(jq -r .name "$EXT_SRC/package.json")
version=$(jq -r .version "$EXT_SRC/package.json")
ext_dir="$EXTENSIONS_DIR/$publisher.$name-$version"

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/extension"
cp "$EXT_SRC/package.json" "$build_dir/extension/"
(cd "$build_dir" && zip -qr theme.vsix extension)

codium --install-extension "$build_dir/theme.vsix" --force

"$SCRIPT_DIR/generate-vscodium-theme.py"
mkdir -p "$ext_dir/themes"
ln -sfn "$THEME_FILE" "$ext_dir/themes/end4-pc-theme.json"
echo "Linked $ext_dir/themes/end4-pc-theme.json -> $THEME_FILE"
