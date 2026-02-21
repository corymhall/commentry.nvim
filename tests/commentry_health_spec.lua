---@module 'luassert'

describe("commentry.health", function()
  local original_health
  local original_diffview
  local original_snacks

  before_each(function()
    original_health = vim.health
    original_diffview = package.loaded["diffview"]
    original_snacks = package.loaded["snacks"]
  end)

  after_each(function()
    vim.health = original_health
    package.loaded["diffview"] = original_diffview
    package.loaded["snacks"] = original_snacks
    package.loaded["commentry.health"] = nil
  end)

  it("reports snacks readiness when picker.select is available", function()
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

    local health = require("commentry.health")
    health.check()

    assert.is_true(vim.tbl_contains(seen.ok, "diffview.nvim is installed"))
    assert.is_true(vim.tbl_contains(seen.ok, "snacks.nvim picker.select is available for :Commentry list-comments"))
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

    local health = require("commentry.health")
    health.check()

    assert.are.same("snacks.nvim not installed: :Commentry list-comments is unavailable", seen_warn)
  end)
end)
