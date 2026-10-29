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

  it("accepts supported logging options", function()
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

  it("accepts partial keymap overrides without dropping other mappings", function()
    local Config = require("commentry.config")
    Config.setup({
      keymaps = {
        list_comments = "gce",
      },
    })

    assert.are.same("gce", Config.keymaps.list_comments)
    assert.is_string(Config.keymaps.add_comment)
  end)

  it("rejects malformed keymap configuration with an actionable warning", function()
    local warns = {}
    package.loaded["commentry.util"] = {
      warn = function(message)
        warns[#warns + 1] = message
      end,
    }
    local Config = require("commentry.config")
    Config.setup({ keymaps = "invalid" })
    assert.is_table(Config.keymaps)
    assert.are.same(1, #warns)
    assert.is_truthy(warns[1]:find("keymaps", 1, true))
    assert.is_truthy(warns[1]:find("invalid", 1, true))
  end)

  it("allows disabling each Diffview keymap", function()
    local Config = require("commentry.config")
    Config.setup({ keymaps = { add_comment = "", add_range_comment = "", list_comments = "" } })
    assert.are.same("", Config.keymaps.add_comment)
    assert.are.same("", Config.keymaps.add_range_comment)
    assert.are.same("", Config.keymaps.list_comments)
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
        list_comments = false,
        add_comment = {},
      },
    })

    assert.are.same("ml", Config.keymaps.list_comments)
    assert.are.same("mc", Config.keymaps.add_comment)
    local warning = table.concat(warns, "\n")
    assert.is_truthy(warning:find("keymaps.list_comments=false", 1, true))
    assert.is_truthy(warning:find("keymaps.add_comment", 1, true))
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
        add_range_comment = "   ",
      },
    })

    assert.are.same("mc", Config.keymaps.add_range_comment)
    assert.are.same(1, #warns)
    assert.is_truthy(warns[1]:find("keymaps.add_range_comment", 1, true))
    assert.is_truthy(warns[1]:find("string"))
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
        add_range_comment = "m\nc",
      },
    })

    assert.are.same("mc", Config.keymaps.add_range_comment)
    assert.are.same(1, #warns)
    assert.is_truthy(warns[1]:find("keymaps.add_range_comment", 1, true))
    assert.is_truthy(warns[1]:find("string"))
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
      diffview = {
        mystery = "value",
      },
    })

    assert.is_nil(Config.typo_option)
    assert.is_false(vim.tbl_contains(warns, ""))
    assert.is_truthy(vim.tbl_contains(warns, "commentry setup: unknown config key: typo_option"))
    assert.is_truthy(vim.tbl_contains(warns, "commentry setup: unknown config key: diffview.mystery"))
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
