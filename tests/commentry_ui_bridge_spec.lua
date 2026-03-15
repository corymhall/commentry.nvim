---@module 'luassert'

describe("commentry.dev.ui_bridge", function()
  it("applies multigrid redraw events into positioned snapshot windows", function()
    local bridge = require("commentry.dev.ui_bridge")
    local screen = bridge.new_screen_state(80, 24)

    screen:apply_batch({
      { "default_colors_set", { 0xdddddd, 0x111111, 0x000000, 0, 0 } },
      { "hl_attr_define", { 1, { foreground = 0x88c0d0, background = 0x1b242b, bold = true }, {}, {} } },
      { "mode_info_set", { true, { { cursor_shape = "vertical", cell_percentage = 25, attr_id = 1 } } } },
      { "mode_change", { "insert", 0 } },
      { "grid_resize", { 2, 12, 4 } },
      { "win_pos", { 2, 1001, 1, 10, 12, 4 } },
      { "grid_line", { 2, 0, 0, { { "Commentry", 1 }, { " ", 1, 3 } }, false } },
      { "grid_line", { 2, 1, 0, { { "Popup", 1 } }, false } },
      { "grid_cursor_goto", { 2, 1, 3 } },
      { "flush", {} },
    })

    local snapshot = screen:snapshot("bridge-test")
    local popup = nil
    for _, window in ipairs(snapshot.windows) do
      if window.grid == 2 then
        popup = window
        break
      end
    end

    assert.is_truthy(popup ~= nil)
    assert.are.same(1, popup.row)
    assert.are.same(10, popup.col)
    assert.are.same("Commentry", popup.rows[1][1].text:sub(1, 9))
    assert.are.same(2, snapshot.cursor.grid)
    assert.are.same("vertical", snapshot.cursor_style.shape)
    assert.are.same(25, snapshot.cursor_style.cell_percentage)

    snapshot.highlight_resolver = function(hl_id)
      return screen:highlight(hl_id)
    end
    local svg = bridge.render_svg(snapshot)
    assert.is_truthy(svg:find("Commentry", 1, true) ~= nil)
    assert.is_truthy(svg:find("Popup", 1, true) ~= nil)
    assert.is_truthy(svg:find('width="2" height="16" rx="1" fill="#88c0d0"', 1, true) ~= nil)
  end)
end)
