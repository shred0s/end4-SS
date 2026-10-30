#!/usr/bin/env -S\_/bin/sh\_-c\_"source\_\$(eval\_echo\_\$ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate&&exec\_python\_-E\_"\$0"\_"\$@""
# Renders the VSCodium theme from the Material colors matugen generated for the
# current wallpaper. Syntax, git and terminal hues are fixed base colors
# harmonized towards primary rather than matugen custom colors, because those
# follow the scheme type: expressive rotates their hue and neutral grays them out.
import json
import os
import re
from pathlib import Path

from materialyoucolor.blend import Blend
from materialyoucolor.hct import Hct

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "quickshell/user/generated"
COLORS_PATH = STATE_DIR / "colors.json"
OUTPUT_PATH = STATE_DIR / "vscodium-theme.json"
TEMPLATE_PATH = Path(__file__).resolve().parent / "vscodium-theme.template.json"

BASE_COLORS = {
    "red": "#f44336",
    "yellow": "#ffb300",
    "green": "#4caf50",
    "cyan": "#00bcd4",
    "blue": "#2196f3",
    "magenta": "#e040fb",
}
MAX_CHROMA = 40

hex_to_argb = lambda hex_code: 0xFF000000 | int(hex_code.lstrip("#"), 16)
argb_to_hex = lambda argb: "#{:06x}".format(argb & 0xFFFFFF)

colors = json.loads(COLORS_PATH.read_text())
darkmode = Hct.from_int(hex_to_argb(colors["background"])).tone < 50
primary = hex_to_argb(colors["primary"])

# Same tones Material uses for custom colors: color, container, on-container
tones = (80, 30, 90) if darkmode else (40, 90, 10)
for name, base in BASE_COLORS.items():
    hct = Hct.from_int(Blend.harmonize(hex_to_argb(base), primary))
    chroma = min(hct.chroma, MAX_CHROMA)
    for key, tone in zip((name, f"{name}_container", f"on_{name}_container"), tones):
        colors[key] = argb_to_hex(Hct.from_hct(hct.hue, chroma, tone).to_int())

theme = re.sub(r"\{\{(\w+)\}\}", lambda m: colors[m.group(1)], TEMPLATE_PATH.read_text())

# Replace atomically so VSCodium's file watcher never reloads a half-written theme
tmp_path = OUTPUT_PATH.with_suffix(".tmp")
tmp_path.write_text(theme)
tmp_path.replace(OUTPUT_PATH)
