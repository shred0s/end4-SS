-- MacBook (Asahi). Installed over the desktop's monitors.lua by install.sh.
-- With appledrm.show_notch=1 the panel reports its full height, including the strip on either
-- side of the notch, and the top bar sits there (see bar.notch in the shell config).
-- Scale 2 matches macOS's default "looks like" size on the 14"/16" Pro; try 1.6 on the 13" Air.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })

-- Anything plugged in: preferred mode, placed automatically
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
