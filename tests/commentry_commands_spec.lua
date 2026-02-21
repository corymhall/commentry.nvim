---@module 'luassert'

describe("commentry lifecycle hooks", function()
  local original_diffview
  local original_diffview_lib
  local original_comments
  local original_config
  local original_create_autocmd
  local original_schedule

  before_each(function()
    original_diffview = package.loaded["commentry.diffview"]
    original_diffview_lib = package.loaded["diffview.lib"]
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_create_autocmd = vim.api.nvim_create_autocmd
    original_schedule = vim.schedule
  end)

  after_each(function()
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["diffview.lib"] = original_diffview_lib
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    vim.api.nvim_create_autocmd = original_create_autocmd
    vim.schedule = original_schedule
  end)

  it("loads persisted comments when diffview auto-attach events fire", function()
    local autocmds = {}
    local calls = { load = 0, render = 0 }

    vim.api.nvim_create_autocmd = function(_, opts)
      autocmds[#autocmds + 1] = opts
    end
    vim.schedule = function(cb)
      cb()
    end

    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { auto_attach = true },
    }
    package.loaded["commentry.comments"] = {
      load_current_view = function()
        calls.load = calls.load + 1
        return true
      end,
      render_current_buffer = function()
        calls.render = calls.render + 1
      end,
    }
    package.loaded["diffview.lib"] = {
      get_current_view = function()
        return nil
      end,
    }

    package.loaded["commentry.diffview"] = nil
    local Diffview = require("commentry.diffview")
    Diffview.setup()

    assert.are.same(2, #autocmds)
    autocmds[1].callback()
    autocmds[2].callback()

    assert.are.same(2, calls.load)
    assert.are.same(2, calls.render)
  end)
end)

describe("commentry command routing", function()
  local original_comments
  local original_config
  local original_diffview
  local original_commands
  local original_create_autocmd

  before_each(function()
    original_comments = package.loaded["commentry.comments"]
    original_config = package.loaded["commentry.config"]
    original_diffview = package.loaded["commentry.diffview"]
    original_commands = package.loaded["commentry.commands"]
    original_create_autocmd = vim.api.nvim_create_autocmd
  end)

  after_each(function()
    package.loaded["commentry.comments"] = original_comments
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.diffview"] = original_diffview
    package.loaded["commentry.commands"] = original_commands
    vim.api.nvim_create_autocmd = original_create_autocmd
  end)

  it("routes :Commentry list-comments to comments.list_comments", function()
    local called = 0
    vim.api.nvim_create_autocmd = function()
      return 1
    end

    package.loaded["commentry.comments"] = {
      list_comments = function()
        called = called + 1
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    Commands.cmd({ args = "list-comments" })

    assert.are.same(1, called)
  end)

  it("includes list-comments in command completion", function()
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    package.loaded["commentry.comments"] = {
      list_comments = function()
        return
      end,
      render_current_buffer = function()
        return
      end,
    }
    package.loaded["commentry.config"] = {
      augroup = 1,
      diffview = { enabled = true },
      keymaps = { add_comment = "mc", edit_comment = "me", delete_comment = "md" },
    }
    package.loaded["commentry.diffview"] = {
      open = function()
        return true
      end,
    }

    package.loaded["commentry.commands"] = nil
    local Commands = require("commentry.commands")
    local matches = Commands.complete("Commentry list")

    assert.is_true(vim.tbl_contains(matches, "list-comments"))
  end)
end)
