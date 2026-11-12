---@module 'luassert'
describe("inbox animation lifecycle", function()
  it("cancels a fade on redraw and ignores its already scheduled frames", function()
    local original = package.loaded.snacks
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
    local callbacks = {}
    local stopped = {}
    local animate = setmetatable({
      enabled = function()
        return true
      end,
      del = function(id)
        stopped[id] = true
      end,
    }, {
      __call = function(_, _, _, callback)
        callbacks[#callbacks + 1] = callback
      end,
    })
    package.loaded.snacks = { animate = animate }
    vim.api.nvim_set_hl(0, "Normal", { bg = 0x101010 })
    vim.api.nvim_set_hl(0, "Visual", { bg = 0x505050 })
    local buf = vim.api.nvim_create_buf(false, true)
    local Flash = require("commentry.inbox.animate")
    local ok, err = pcall(function()
      local Render = require("commentry.inbox.render")
      Render.write(buf, { "First conversation", "First answer" }, "markdown")
      Flash.flash(buf, 2, 2)
      local ns = vim.api.nvim_get_namespaces()["commentry.inbox.animate"]
      local function marks()
        return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      end
      assert.are.same(1, #marks())
      Render.write(buf, { "Another conversation", "Another answer" }, "markdown")
      assert.are.same(0, #marks())
      assert.is_true(stopped["commentry-flash:" .. buf])
      Flash.flash(buf, 2, 2)
      local current = marks()
      callbacks[1](100, { done = true })
      assert.are.same(current, marks())
      callbacks[2](100, { done = true })
      assert.are.same(0, #marks())
      assert.are.same({ "Another conversation", "Another answer" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
    Flash.clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    package.loaded.snacks = original
    vim.api.nvim_set_hl(0, "Normal", normal)
    vim.api.nvim_set_hl(0, "Visual", visual)
    assert.is_true(ok, tostring(err))
  end)
end)
