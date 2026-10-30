-- Monitors (carried over from the caelestia config)
-- Layout: 4K (HDMI-A-1) on the left, 240Hz FHD (DP-2) on the right.
-- 4K at scale 1.666667 is 2304x1296 logical, so DP-2 starts at x=2304,
-- and y=216 (1296 - 1080) lines up the bottom edges.
hl.monitor({
    output = "HDMI-A-1",
    mode = "3840x2160@60",
    position = "0x0",
    scale = 1.666667,
})
hl.monitor({
    output = "DP-2",
    mode = "1920x1080@239.76",
    position = "2304x216",
    scale = 1,
})

-- Workspace -> monitor binding
-- 1-10 live on the main 240Hz display (DP-2), 11+ on the 4K (HDMI-A-1).
-- The SUPER+N binds use workspace_in_group(), so they stay within each monitor's group of 10.
for i = 1, 10 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "DP-2", default = (i == 1) })
end
for i = 11, 100 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "HDMI-A-1", default = (i == 11) })
end
