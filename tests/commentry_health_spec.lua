---@module 'luassert'

describe("commentry.health", function()
  local original_health
  local original_diffview
  local original_snacks
  local original_config
  local original_sidekick

  before_each(function()
    original_health = vim.health
    original_diffview = package.loaded["diffview"]
    original_snacks = package.loaded["snacks"]
    original_config = package.loaded["commentry.config"]
    original_sidekick = package.loaded["commentry.codex.adapters.sidekick"]
  end)

  after_each(function()
    vim.health = original_health
    package.loaded["diffview"] = original_diffview
    package.loaded["snacks"] = original_snacks
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.codex.adapters.sidekick"] = original_sidekick
    package.loaded["commentry.health"] = nil
  end)

  it("reports snacks readiness and codex disabled mode as healthy", function()
    local seen = { ok = {}, warn = {} }
    vim.health = {
      start = function() end,
      ok = function(msg)
        seen.ok[#seen.ok + 1] = msg
      end,
      warn = function(msg)
        seen.warn[#seen.warn + 1] = msg
      end,
      error = function() end,
    }

    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = { select = function() end } }
    package.loaded["commentry.config"] = {
      codex = {
        enabled = false,
        adapter = { select = "auto" },
      },
    }

    local health = require("commentry.health")
    health.check()

    assert.is_true(vim.tbl_contains(seen.ok, "diffview.nvim is installed"))
    assert.is_true(vim.tbl_contains(seen.ok, "snacks.nvim picker.select is available for :Commentry list-comments"))
    assert.is_true(vim.tbl_contains(seen.ok, "codex integration disabled: :Commentry send-to-codex is inactive"))
    assert.are.same(0, #seen.warn)
  end)

  it("warns when snacks is unavailable", function()
    local seen_warn = nil
    vim.health = {
      start = function() end,
      ok = function() end,
      warn = function(msg)
        seen_warn = msg
      end,
      error = function() end,
    }

    package.loaded["diffview"] = {}
    package.loaded["snacks"] = nil
    package.loaded["commentry.config"] = {
      codex = {
        enabled = false,
        adapter = { select = "auto" },
      },
    }

    local health = require("commentry.health")
    health.check()

    assert.are.same("snacks.nvim not installed: :Commentry list-comments is unavailable", seen_warn)
  end)

  it("warns when snacks picker.select is unavailable", function()
    local seen_warn = nil
    vim.health = {
      start = function() end,
      ok = function() end,
      warn = function(msg)
        seen_warn = msg
      end,
      error = function() end,
    }

    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = {} }
    package.loaded["commentry.config"] = {
      codex = {
        enabled = false,
        adapter = { select = "auto" },
      },
    }

    local health = require("commentry.health")
    health.check()

    assert.are.same("snacks.nvim installed but picker.select is unavailable", seen_warn)
  end)

  it("warns when codex is enabled and sidekick adapter is unavailable", function()
    local seen = { ok = {}, warn = {} }
    vim.health = {
      start = function() end,
      ok = function(msg)
        seen.ok[#seen.ok + 1] = msg
      end,
      warn = function(msg)
        seen.warn[#seen.warn + 1] = msg
      end,
      error = function() end,
    }

    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = { select = function() end } }
    package.loaded["commentry.config"] = {
      codex = {
        enabled = true,
        adapter = { select = "sidekick" },
      },
    }
    package.loaded["commentry.codex.adapters.sidekick"] = {}

    local health = require("commentry.health")
    health.check()

    assert.is_true(vim.tbl_contains(seen.warn, "codex enabled but sidekick adapter is unavailable; install sidekick integration or set codex.enabled=false"))
  end)

  it("warns when codex is enabled but sidekick runtime is unavailable", function()
    local seen = { ok = {}, warn = {} }
    vim.health = {
      start = function() end,
      ok = function(msg)
        seen.ok[#seen.ok + 1] = msg
      end,
      warn = function(msg)
        seen.warn[#seen.warn + 1] = msg
      end,
      error = function() end,
    }

    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = { select = function() end } }
    package.loaded["commentry.config"] = {
      codex = {
        enabled = true,
        adapter = { select = "sidekick" },
      },
    }
    package.loaded["commentry.codex.adapters.sidekick"] = {
      send = function()
        return true, nil, { dispatched_items = 1 }
      end,
      available = function()
        return false
      end,
    }

    local health = require("commentry.health")
    health.check()

    assert.is_true(vim.tbl_contains(seen.warn, "codex enabled but sidekick adapter runtime is unavailable; check sidekick install and active target session"))
  end)

  it("reports codex adapter readiness when enabled and available", function()
    local seen = { ok = {}, warn = {} }
    vim.health = {
      start = function() end,
      ok = function(msg)
        seen.ok[#seen.ok + 1] = msg
      end,
      warn = function(msg)
        seen.warn[#seen.warn + 1] = msg
      end,
      error = function() end,
    }

    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = { select = function() end } }
    package.loaded["commentry.config"] = {
      codex = {
        enabled = true,
        adapter = { select = "sidekick" },
      },
    }
    package.loaded["commentry.codex.adapters.sidekick"] = {
      send = function()
        return true, nil, {}
      end,
      available = function()
        return true
      end,
    }

    local health = require("commentry.health")
    health.check()

    assert.is_true(vim.tbl_contains(seen.ok, "codex adapter ready (sidekick transport available); :Commentry send-to-codex uses attached session target"))
    assert.are.same(0, #seen.warn)
  end)
end)
