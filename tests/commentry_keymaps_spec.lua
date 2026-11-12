describe("Commentry global keymaps", function()
  local Keymaps = require("commentry.keymaps")
  local original_commands, original_leader, original_util
  local calls, warnings

  before_each(function()
    Keymaps.setup({})
    original_commands = package.loaded["commentry.commands"]
    original_util = package.loaded["commentry.util"]
    original_leader = vim.g.mapleader
    vim.g.mapleader = ","
    calls, warnings = {}, {}
    package.loaded["commentry.commands"] = {
      cmd = function(args)
        calls[#calls + 1] = args
      end,
    }
    package.loaded["commentry.util"] = {
      warn = function(message)
        warnings[#warnings + 1] = message
      end,
    }
  end)

  after_each(function()
    vim.cmd.normal({ args = { "\27" }, bang = true })
    Keymaps.setup({})
    pcall(vim.keymap.del, "n", ",cc")
    package.loaded["commentry.commands"] = original_commands
    package.loaded["commentry.util"] = original_util
    vim.g.mapleader = original_leader
  end)

  it("routes the global shortcuts without requiring a Diffview buffer", function()
    local Config = require("commentry.config")
    Config.setup()
    Keymaps.setup(Config.global_keymaps)
    local expected = {
      cc = "comment",
      ce = "edit",
      cn = "new-thread",
      ci = "inbox",
      cu = "inbox unread",
      ca = "inbox all",
      cp = "capture-text +",
      cd = "open",
    }
    for suffix, command in pairs(expected) do
      local mapping = vim.fn.maparg("," .. suffix, "n", false, true)
      assert.is_truthy(mapping.desc:find("Commentry", 1, true))
      mapping.callback()
      assert.are.same(command, calls[#calls].args)
      assert.are.same(0, calls[#calls].range)
    end
  end)

  it("captures a backwards visual range before leaving Visual mode", function()
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
    Keymaps.setup({ add_range_comment = "<leader>cc" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd.normal({ args = { "v" }, bang = true })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.fn.maparg(",cc", "x", false, true).callback()
    assert.are.same({ args = "comment", range = 2, line1 = 2, line2 = 4 }, calls[1])
    assert.are.same("n", vim.fn.mode())
    vim.bo.modified = false
  end)

  it("preserves existing and subsequently replaced user mappings", function()
    local user = function() end
    vim.keymap.set("n", ",cc", user)
    Keymaps.setup({ add_comment = "<leader>cc" })
    assert.are.same(user, vim.fn.maparg(",cc", "n", false, true).callback)
    assert.are.same(1, #warnings)
    vim.keymap.del("n", ",cc")
    Keymaps.setup({ add_comment = "<leader>cc" })
    vim.keymap.set("n", ",cc", user)
    Keymaps.setup({})
    assert.are.same(user, vim.fn.maparg(",cc", "n", false, true).callback)
  end)

  it("removes stale owned mappings after remapping, disabling or changing leader", function()
    Keymaps.setup({ add_comment = "<leader>cc" })
    Keymaps.setup({ add_comment = "<leader>cc" })
    assert.are.same(0, #warnings)
    vim.g.mapleader = ";"
    Keymaps.setup({ add_comment = "<leader>cn" })
    assert.are.same("", vim.fn.maparg(",cc", "n"))
    assert.is_function(vim.fn.maparg(";cn", "n", false, true).callback)
    Keymaps.setup({ add_comment = "" })
    assert.are.same("", vim.fn.maparg(";cn", "n"))
  end)
end)
