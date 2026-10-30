-- Blur translucent terminals (end4 disables blur for every window by default)
hl.window_rule({match = {class = "^(foot|kitty)$" }, no_blur = false })

-- Keep these apps fully opaque when unfocused (overrides decoration.inactive_opacity)
-- Add window classes here; find one with `hyprctl clients` or `hyprctl activewindow`.
local opaque_apps = { "firefox", "vesktop", "swiftify" }
hl.window_rule({match = {class = "^(" .. table.concat(opaque_apps, "|") .. ")$" }, opacity = "1.0 override 1.0 override" })

-- Quickshell Launchpad (dock's left button) runs its own zoom animation
hl.layer_rule({ match = { namespace = "quickshell:launchpad" }, no_anim = true })
-- Quickshell start menu runs its own slide animation
hl.layer_rule({ match = { namespace = "quickshell:startMenu" }, no_anim = true })
-- Quickshell dock: blur behind it even when it's see-through (glass style / low opacity)
hl.layer_rule({ match = { namespace = "quickshell:dock" }, ignore_alpha = 0.2 })
