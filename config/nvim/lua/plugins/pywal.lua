-- LazyVim plugin spec: point LazyVim at the caelestia colorscheme
-- (defined in ~/.config/nvim/colors/caelestia.lua, palette from the shell's generated colors).

return {
  { "folke/tokyonight.nvim", enabled = false },
  { "catppuccin/nvim",       enabled = false },

  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "caelestia" },
  },
}
