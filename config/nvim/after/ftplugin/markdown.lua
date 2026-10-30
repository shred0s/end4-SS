local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node

-- This helper forces snippets to trigger instantly without pressing enter/tab
local s_auto = function(triggers, nodes)
  return s({ trig = triggers, snippetType = "autosnippet" }, nodes)
end

ls.add_snippets("markdown", {
  -- 1. Inline Math Blocks: type 'mk' -> expands to $ $
  s_auto("mk", {
    t("$"),
    i(1),
    t("$"),
  }),

  -- 2. Display Math Blocks: type 'dm' -> expands to $$ $$ on new lines
  s_auto("dm", {
    t({ "$$", "" }),
    t("  "),
    i(1),
    t({ "", "$$" }),
  }),

  -- 3. Fractions: type 'ff' -> expands to \frac{numerator}{denominator}
  s_auto("ff", {
    t("\\frac{"),
    i(1),
    t("}{"),
    i(2),
    t("}"),
  }),

  -- 4. Superscript (Powers): type 'sr' -> expands to ^{}
  s_auto("sr", {
    t("^{"),
    i(1),
    t("}"),
  }),

  -- 5. Subscript: type 'cb' -> expands to _{}
  s_auto("cb", {
    t("_{"),
    i(1),
    t("}"),
  }),

  -- 6. Common Summation: type 'sum' -> builds a beautifully bounded sum
  s({ trig = "sum" }, {
    t("\\sum_{i="),
    i(1, "1"),
    t("}^{"),
    i(2, "n"),
    t("} "),
    i(3),
  }),
})
