---@module 'luassert'

describe("commentry config", function()
  local original_config
  local original_util
  local original_create_user_command
  local original_schedule

  before_each(function()
    original_config = package.loaded["commentry.config"]
    original_util = package.loaded["commentry.util"]
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
    package.loaded["commentry.util"] = original_util
    vim.api.nvim_create_user_command = original_create_user_command
    vim.schedule = original_schedule
  end)

  it("defines codex defaults with explicit disabled mode", function()
    local Config = require("commentry.config")

    assert.are.same(false, Config.codex.enabled)
    assert.are.same("auto", Config.codex.adapter.select)
    assert.is_nil(Config.codex.adapter.fallback)
    assert.are.same("reuse", Config.codex.behavior.open)
    assert.are.same(76, Config.diffview.comment_cards.max_width)
    assert.are.same(6, Config.diffview.comment_cards.max_body_lines)
    assert.are.same(true, Config.diffview.comment_cards.show_markers)
    assert.are.same(true, Config.diffview.comment_ranges.enabled)
    assert.are.same(true, Config.diffview.comment_ranges.line_highlight)
    assert.are.same("warn", Config.log.level)
    assert.are.same("notify", Config.log.sink)
    assert.is_nil(Config.log.file)
    assert.are.same("split", Config.diagnostics.open_style)
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

  it("deep-merges log config deterministically", function()
    local Config = require("commentry.config")
    Config.setup({
      log = {
        level = "debug",
        sink = "echo",
      },
    })

    assert.are.same("debug", Config.log.level)
    assert.are.same("echo", Config.log.sink)
    assert.is_nil(Config.log.file)
  end)

  it("defines explicit defaults for all supported keymap actions after setup({})", function()
    local Config = require("commentry.config")
    Config.setup({})

    local expected = {
      add_comment = "mc",
      add_range_comment = "mc",
      edit_comment = "me",
      delete_comment = "md",
      set_comment_type = "mt",
      toggle_file_reviewed = "mr",
      next_unreviewed_file = "]r",
      send_to_codex = "ms",
      list_comments = "ml",
    }

    for key, value in pairs(expected) do
      assert.is_not_nil(Config.keymaps[key])
      assert.are.same(value, Config.keymaps[key])
    end
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
    assert.are.same("ms", Config.keymaps.send_to_codex)
    assert.are.same("ml", Config.keymaps.list_comments)
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
      send_to_codex = "ms",
      list_comments = "ml",
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

  it("warns and restores default when non-empty-required keymap is set to empty string", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        add_comment = "",
      },
    })

    assert.are.same("mc", Config.keymaps.add_comment)
    assert.are.same(1, #warns)
    assert.is_truthy(warns[1]:find("keymaps.add_comment", 1, true))
    assert.is_truthy(warns[1]:find('""', 1, true))
    assert.is_truthy(warns[1]:find("expected non%-empty string"))
    assert.is_truthy(warns[1]:find("non%-empty string"))
  end)

  it("allows empty-string disables only on remap-only actions without warning", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        toggle_file_reviewed = "",
        next_unreviewed_file = "",
      },
    })

    assert.are.same("", Config.keymaps.toggle_file_reviewed)
    assert.are.same("", Config.keymaps.next_unreviewed_file)
    assert.are.same(0, #warns)
  end)

  it("warns and restores defaults when keymap overrides have invalid types", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        edit_comment = false,
        delete_comment = {},
      },
    })

    assert.are.same("me", Config.keymaps.edit_comment)
    assert.are.same("md", Config.keymaps.delete_comment)
    assert.are.same(2, #warns)
    assert.is_truthy(warns[1]:find("keymaps.edit_comment", 1, true))
    assert.is_truthy(warns[1]:find("false", 1, true))
    assert.is_truthy(warns[1]:find("expected non%-empty string"))
    assert.is_truthy(warns[2]:find("keymaps.delete_comment", 1, true))
    assert.is_truthy(warns[2]:find("{}", 1, true))
    assert.is_truthy(warns[2]:find("expected non%-empty string"))
  end)

  it("warns and restores default when keymap string format is unsupported", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        set_comment_type = "   ",
      },
    })

    assert.are.same("mt", Config.keymaps.set_comment_type)
    assert.are.same(1, #warns)
    assert.is_truthy(warns[1]:find("keymaps.set_comment_type", 1, true))
    assert.is_truthy(warns[1]:find("non%-empty string"))
  end)

  it("warns and restores default when keymap contains newline characters", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        set_comment_type = "m\nc",
      },
    })

    assert.are.same("mt", Config.keymaps.set_comment_type)
    assert.are.same(1, #warns)
    assert.is_truthy(warns[1]:find("keymaps.set_comment_type", 1, true))
    assert.is_truthy(warns[1]:find("non%-empty string"))
  end)

  it("warns on unknown config keys and ignores them", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      typo_option = true,
      codex = {
        mystery = "value",
      },
    })

    assert.is_nil(Config.typo_option)
    assert.is_false(vim.tbl_contains(warns, ""))
    assert.is_truthy(vim.tbl_contains(warns, "commentry setup: unknown config key: typo_option"))
    assert.is_truthy(vim.tbl_contains(warns, "commentry setup: unknown config key: codex.mystery"))
  end)

  it("warns and restores defaults for invalid log config values", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      log = {
        level = "trace",
        sink = "stdout",
        file = false,
      },
    })

    assert.are.same("warn", Config.log.level)
    assert.are.same("notify", Config.log.sink)
    assert.is_nil(Config.log.file)
    assert.is_true(
      vim.tbl_contains(warns, 'commentry setup: log.level="trace" is invalid; expected one of error|warn|info|debug')
    )
    assert.is_true(
      vim.tbl_contains(warns, 'commentry setup: log.sink="stdout" is invalid; expected one of notify|echo|file')
    )
    assert.is_true(vim.tbl_contains(warns, "commentry setup: log.file=false is invalid; expected string|nil"))
  end)

  it("warns and restores default for invalid diagnostics open style", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(msg)
        warns[#warns + 1] = msg
      end,
    }

    local Config = require("commentry.config")
    Config.setup({
      diagnostics = {
        open_style = "tab",
      },
    })

    assert.are.same("split", Config.diagnostics.open_style)
    assert.is_true(
      vim.tbl_contains(
        warns,
        'commentry setup: diagnostics.open_style="tab" is invalid; expected one of split|vsplit|float'
      )
    )
  end)
end)
