hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
-- OBS clipping hotkey (saves replay buffer over obs-websocket)
hl.bind("CTRL+SHIFT + R", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/custom/scripts/obs-replay-save.fish"), {description = "Save OBS replay"})
-- GPU Screen Recorder clipping (quickshell Clips service). Its hotkeys are set in the Clips app
-- (Settings → Shortcuts & sound), which writes them to clips.lua.
if is_file_exists(HOME .. "/.config/hypr/custom/clips.lua") then
	require("custom.clips")
end
