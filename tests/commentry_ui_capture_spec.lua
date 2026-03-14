---@module 'luassert'

describe("commentry.dev.ui_capture", function()
  it("renders key UI affordances into the SVG snapshot", function()
    local capture = require("commentry.dev.ui_capture")
    local svg = capture.render_svg({
      name = "comment-popup",
      cwd = "/tmp/commentry-demo",
      columns = 120,
      lines = 40,
      windows = {
        {
          id = 1,
          row = 0,
          col = 0,
          width = 60,
          height = 15,
          relative = "editor",
          title = "demo.lua",
          winbar = "",
          buffer = {
            name = "demo.lua",
            filetype = "lua",
            buftype = "",
          },
          cursor = { 2, 0 },
          rows = {
            {
              kind = "buffer",
              line_number = 2,
              text = 'local name = "commentry"',
              labels = {
                { text = "[suggestion]", color = "#0f766e" },
              },
              signs = {
                { text = "╭", color = "#d94841" },
              },
              line_hl = "#d94841",
            },
            {
              kind = "overlay",
              text = "  ╭─ [SUGGESTION] L2",
              color = "#0f766e",
            },
          },
        },
        {
          id = 2,
          row = 6,
          col = 20,
          width = 48,
          height = 12,
          relative = "editor+float",
          title = " Commentry Comment ",
          winbar = "Add line comment [note]  Enter:newline  C-s:save  q/Esc:cancel  Tab:type",
          buffer = {
            name = "",
            filetype = "markdown",
            buftype = "nofile",
          },
          cursor = { 1, 0 },
          rows = {
            {
              kind = "buffer",
              line_number = 1,
              text = "Consider renaming this variable.",
              labels = {},
              signs = {},
            },
          },
        },
      },
    })

    assert.is_truthy(svg:find("Commentry Comment", 1, true) ~= nil)
    assert.is_truthy(svg:find("Add line comment", 1, true) ~= nil)
    assert.is_truthy(svg:find("%[suggestion%]") ~= nil)
    assert.is_truthy(svg:find("╭─ %[%SUGGESTION%] L2") ~= nil)
  end)
end)
