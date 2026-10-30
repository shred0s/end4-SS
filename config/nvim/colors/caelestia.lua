-- Material You-driven colorscheme.
-- Palette read from the shell's generated colors (end-4 writes material_colors.scss on every
-- wallpaper change), else caelestia's scheme.json; live-reloads when either changes.

local SCSS_PATH = vim.fn.expand("~/.local/state/quickshell/user/generated/material_colors.scss")
local SCHEME_PATH = vim.fn.expand("~/.local/state/caelestia/scheme.json")

local fallback = {
  bg = "#1e1e2e", fg = "#cdd6f4",
  colors = {
    "#1e1e2e","#f38ba8","#a6e3a1","#f9e2af","#89b4fa",
    "#cba6f7","#94e2d5","#cdd6f4","#585b70","#f38ba8",
    "#a6e3a1","#f9e2af","#89b4fa","#cba6f7","#94e2d5","#cdd6f4",
  },
}

-- end-4's palette: lines like `$term0: #1A1B1A;`, stored without the "#" like caelestia's
local function read_scss()
  local ok, lines = pcall(vim.fn.readfile, SCSS_PATH)
  if not ok or not lines then return nil end
  local cl = {}
  for _, line in ipairs(lines) do
    local name, value = line:match("^%$([%w_]+):%s*#(%x+);")
    if name then cl[name] = value end
  end
  return next(cl) and cl or nil
end

local function read_scheme_json()
  local ok, lines = pcall(vim.fn.readfile, SCHEME_PATH)
  if not ok or not lines or #lines == 0 then return nil end
  local ok2, parsed = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok2 or type(parsed) ~= "table" or type(parsed.colours) ~= "table" then return nil end
  return parsed.colours
end

local function read_palette()
  local cl = read_scss() or read_scheme_json()
  if not cl then return fallback end
  local hex = function(k) return cl[k] and ("#" .. cl[k]) or nil end
  local term = {}
  for i = 0, 15 do
    term[i + 1] = hex("term" .. i) or fallback.colors[i + 1]
  end
  return {
    bg = hex("background") or fallback.bg,
    fg = hex("onBackground") or hex("text") or fallback.fg,
    colors = term,
  }
end

local function apply()
  local p = read_palette()
  local c, bg, fg = p.colors, p.bg, p.fg

  vim.o.termguicolors = true
  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") then vim.cmd("syntax reset") end
  vim.g.colors_name = "caelestia"

  local set = function(g, o) vim.api.nvim_set_hl(0, g, o) end

  set("Normal",       { fg = fg,   bg = "NONE" })
  set("NormalNC",     { fg = fg,   bg = "NONE" })
  set("NormalFloat",  { fg = fg,   bg = "NONE" })
  set("FloatBorder",  { fg = c[6], bg = "NONE" })
  set("SignColumn",   { bg = "NONE" })
  set("EndOfBuffer",  { bg = "NONE" })
  set("LineNr",       { fg = c[9], bg = "NONE" })
  set("CursorLineNr", { fg = c[6], bold = true })
  set("CursorLine",   { bg = c[1] })
  set("Visual",       { bg = c[9] })
  set("StatusLine",   { fg = fg,   bg = "NONE" })
  set("VertSplit",    { fg = c[9], bg = "NONE" })
  set("WinSeparator", { fg = c[9], bg = "NONE" })
  set("Pmenu",        { fg = fg,   bg = c[1] })
  set("PmenuSel",     { fg = bg,   bg = c[6], bold = true })
  set("Search",       { fg = bg,   bg = c[4] })
  set("IncSearch",    { fg = bg,   bg = c[3] })
  set("MatchParen",   { fg = c[2], bold = true })
  set("Comment",      { fg = c[9], italic = true })

  set("Constant",   { fg = c[2] })
  set("String",     { fg = c[3] })
  set("Identifier", { fg = c[5] })
  set("Function",   { fg = c[6] })
  set("Statement",  { fg = c[4], bold = true })
  set("Keyword",    { fg = c[6], italic = true })
  set("Type",       { fg = c[5] })
  set("Special",    { fg = c[7] })
  set("PreProc",    { fg = c[6] })
  set("Number",     { fg = c[4] })
  set("Boolean",    { fg = c[4], bold = true })
  set("Error",      { fg = c[2] })

  set("@variable",        { fg = fg })
  set("@variable.builtin",{ fg = c[2] })
  set("@function",        { fg = c[6] })
  set("@function.call",   { fg = c[6] })
  set("@keyword",         { fg = c[6], italic = true })
  set("@string",          { fg = c[3] })
  set("@number",          { fg = c[4] })
  set("@type",            { fg = c[5] })
  set("@constant",        { fg = c[2] })
  set("@comment",         { fg = c[9], italic = true })

  set("DiagnosticError", { fg = c[2] })
  set("DiagnosticWarn",  { fg = c[4] })
  set("DiagnosticInfo",  { fg = c[5] })
  set("DiagnosticHint",  { fg = c[7] })

  set("DiffAdd",    { fg = c[3] })
  set("DiffChange", { fg = c[4] })
  set("DiffDelete", { fg = c[2] })

  set("TelescopeBorder",       { fg = c[6], bg = "NONE" })
  set("TelescopePromptBorder", { fg = c[6], bg = "NONE" })
  set("TelescopeNormal",       { fg = fg,   bg = "NONE" })
  set("TelescopePromptNormal", { fg = fg,   bg = "NONE" })
  set("TelescopeMatching",     { fg = c[4], bold = true })
  set("NotifyBackground",      { bg = c[1] })
end

apply()

-- Live reload: watch each palette file's directory (atomic rewrites change inode).
if not _G.__caelestia_scheme_watchers then
  _G.__caelestia_scheme_watchers = {}
  for _, path in ipairs({ SCSS_PATH, SCHEME_PATH }) do
    local dir = vim.fn.fnamemodify(path, ":h")
    local fname = vim.fn.fnamemodify(path, ":t")
    local w = vim.fn.isdirectory(dir) == 1 and vim.uv.new_fs_event() or nil
    if w then
      w:start(dir, {}, vim.schedule_wrap(function(err, changed)
        if not err and (changed == nil or changed == fname) then
          pcall(vim.cmd.colorscheme, "caelestia")
        end
      end))
      table.insert(_G.__caelestia_scheme_watchers, w)
    end
  end
end
