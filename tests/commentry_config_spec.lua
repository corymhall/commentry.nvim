---@module 'luassert'

describe("commentry config", function()
  local original_config
  local original_create_user_command
  local original_schedule

  before_each(function()
    original_config = package.loaded["commentry.config"]
    original_create_user_command = vim.api.nvim_create_user_command
    original_schedule = vim.schedule
    vim.api.nvim_create_user_command = function()
      return
    end
    vim.schedule = function(cb)
      cb()
    end
    package.loaded["commentry.config"] = nil
  end)

  after_each(function()
    package.loaded["commentry.config"] = original_config
    vim.api.nvim_create_user_command = original_create_user_command
    vim.schedule = original_schedule
  end)

  it("defines codex defaults with explicit disabled mode", function()
    local Config = require("commentry.config")

    assert.are.same(false, Config.codex.enabled)
    assert.are.same("auto", Config.codex.adapter.select)
    assert.is_nil(Config.codex.adapter.fallback)
    assert.are.same("reuse", Config.codex.behavior.open)
    assert.are.same(88, Config.diffview.comment_cards.max_width)
    assert.are.same(8, Config.diffview.comment_cards.max_body_lines)
    assert.are.same(true, Config.diffview.comment_cards.show_markers)
    assert.are.same(true, Config.diffview.comment_ranges.enabled)
    assert.are.same(true, Config.diffview.comment_ranges.line_highlight)
  end)

  it("deep-merges codex config deterministically", function()
    local Config = require("commentry.config")
    Config.setup({
      codex = {
        enabled = true,
        adapter = {
          select = "snacks",
        },
      },
    })

    assert.are.same(true, Config.codex.enabled)
    assert.are.same("snacks", Config.codex.adapter.select)
    assert.is_nil(Config.codex.adapter.fallback)
    assert.are.same("reuse", Config.codex.behavior.open)
  end)

  it("defines explicit defaults for all supported keymap actions", function()
    local Config = require("commentry.config")

    assert.are.same({
      add_comment = "mc",
      add_range_comment = "mc",
      edit_comment = "me",
      delete_comment = "md",
      set_comment_type = "mt",
      toggle_file_reviewed = "mr",
      next_unreviewed_file = "]r",
    }, Config.keymaps)
  end)

  it("preserves unrelated keymap defaults on partial override", function()
    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        edit_comment = "gce",
      },
    })

    assert.are.same("mc", Config.keymaps.add_comment)
    assert.are.same("mc", Config.keymaps.add_range_comment)
    assert.are.same("gce", Config.keymaps.edit_comment)
    assert.are.same("md", Config.keymaps.delete_comment)
    assert.are.same("mt", Config.keymaps.set_comment_type)
    assert.are.same("mr", Config.keymaps.toggle_file_reviewed)
    assert.are.same("]r", Config.keymaps.next_unreviewed_file)
  end)

  it("normalizes malformed keymaps overrides back to defaults", function()
    local Config = require("commentry.config")
    Config.setup({
      keymaps = "invalid",
    })

    assert.are.same({
      add_comment = "mc",
      add_range_comment = "mc",
      edit_comment = "me",
      delete_comment = "md",
      set_comment_type = "mt",
      toggle_file_reviewed = "mr",
      next_unreviewed_file = "]r",
    }, Config.keymaps)
  end)

  it("is idempotent across repeated setup calls", function()
    local Config = require("commentry.config")
    local opts = {
      codex = {
        enabled = true,
        adapter = {
          select = "snacks",
          fallback = "none",
        },
        behavior = {
          open = "split",
        },
      },
    }

    Config.setup(opts)
    local first = vim.deepcopy(Config.codex)
    Config.setup(opts)
    local second = vim.deepcopy(Config.codex)

    assert.are.same(first, second)
  end)
end)
