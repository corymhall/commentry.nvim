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
