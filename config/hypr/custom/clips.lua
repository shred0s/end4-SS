-- Written by the Clips app (Settings → Shortcuts & sound). Changes made here get overwritten.
hl.bind("F8", hl.dsp.global("quickshell:clipSave"), { description = "Clips: Save a clip of the last few seconds" })
hl.bind("SHIFT + ALT + F10", hl.dsp.global("quickshell:clipSaveBuffer"), { description = "Clips: Save the whole replay buffer" })
hl.bind("CTRL + ALT + F10", hl.dsp.global("quickshell:clipToggle"), { description = "Clips: Start or stop clipping" })
