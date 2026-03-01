---@module 'luassert'

describe("commentry.log", function()
  local original_log
  local original_notify
  local original_echo
  local original_schedule

  before_each(function()
    original_log = package.loaded["commentry.log"]
    original_notify = vim.notify
    original_echo = vim.api.nvim_echo
    original_schedule = vim.schedule
    package.loaded["commentry.log"] = nil
  end)

  after_each(function()
    package.loaded["commentry.log"] = original_log
    vim.notify = original_notify
    vim.api.nvim_echo = original_echo
    vim.schedule = original_schedule
  end)

  it("honors log level filtering for debug/info", function()
    local seen = {}
    vim.schedule = function(cb)
      cb()
    end
    vim.notify = function(msg)
      seen[#seen + 1] = msg
    end

    local Log = require("commentry.log")
    Log.setup({ level = "warn", sink = "notify" })
    Log.debug("debug_event", { a = 1 })
    Log.info("info_event", { b = 2 })
    Log.warn("warn_event", { c = 3 })

    assert.are.same(1, #seen)
    assert.is_truthy(seen[1]:find("warn_event", 1, true))
  end)

  it("emits structured entries with stable key ordering", function()
    local seen = {}
    vim.api.nvim_echo = function(chunks)
      seen[#seen + 1] = chunks[1][1]
    end

    local Log = require("commentry.log")
    Log.setup({ level = "debug", sink = "echo" })
    Log.info("event_name", { z = "last", a = "first" })

    assert.are.same(1, #seen)
    assert.are.same("[commentry] event_name a=first z=last", seen[1])
  end)

  it("creates parent directories for file sink and writes entries", function()
    local base = vim.fn.tempname()
    local file = base .. "/nested/commentry.log"
    local Log = require("commentry.log")
    Log.setup({ level = "info", sink = "file", file = file })
    Log.info("file_event", { ok = true })

    local lines = vim.fn.readfile(file)
    assert.is_true(#lines >= 1)
    assert.is_truthy(lines[#lines]:find("file_event", 1, true))
    pcall(vim.fn.delete, base, "rf")
  end)
end)
