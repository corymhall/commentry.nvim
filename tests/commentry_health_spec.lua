---@module 'luassert'

describe("commentry.health", function()
  local original_health
  local original_diffview
  local original_snacks
  local original_config
  local original_sidekick
  local original_fn_has
  local original_fn_exists
  local original_fn_isdirectory
  local original_io_open

  before_each(function()
    original_health = vim.health
    original_diffview = package.loaded["diffview"]
    original_snacks = package.loaded["snacks"]
    original_config = package.loaded["commentry.config"]
    original_sidekick = package.loaded["commentry.agent.adapters.sidekick"]
    original_fn_has = vim.fn.has
    original_fn_exists = vim.fn.exists
    original_fn_isdirectory = vim.fn.isdirectory
    original_io_open = io.open
    vim.fn.has = function(feature)
      if feature == "nvim-0.10" then
        return 1
      end
      return original_fn_has(feature)
    end
    vim.fn.exists = function(expr)
      if expr == ":Commentry" then
        return 2
      end
      return original_fn_exists(expr)
    end
  end)

  after_each(function()
    vim.health = original_health
    package.loaded["diffview"] = original_diffview
    package.loaded["snacks"] = original_snacks
    package.loaded["commentry.config"] = original_config
    package.loaded["commentry.agent.adapters.sidekick"] = original_sidekick
    vim.fn.has = original_fn_has
    vim.fn.exists = original_fn_exists
    vim.fn.isdirectory = original_fn_isdirectory
    io.open = original_io_open
    package.loaded["commentry.health"] = nil
  end)

  local function capture_health()
    local seen = { ok = {}, warn = {}, error = {} }
    vim.health = {
      start = function() end,
      ok = function(msg)
        seen.ok[#seen.ok + 1] = msg
      end,
      warn = function(msg)
        seen.warn[#seen.warn + 1] = msg
      end,
      error = function(msg)
        seen.error[#seen.error + 1] = msg
      end,
    }
    return seen
  end

  local function healthy_dependencies(config)
    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = { select = function() end } }
    package.loaded["commentry.config"] = config or { agent = { enabled = false } }
  end

  it("reports core and picker readiness", function()
    local seen = capture_health()
    healthy_dependencies()

    require("commentry.health").check()

    assert.is_true(vim.tbl_contains(seen.ok, "Neovim version is supported (>= 0.10)"))
    assert.is_true(vim.tbl_contains(seen.ok, ":Commentry command is registered"))
    assert.is_true(vim.tbl_contains(seen.ok, "commentry.config is loaded"))
    assert.is_true(vim.tbl_contains(seen.ok, "diffview.nvim is installed"))
    assert.is_true(vim.tbl_contains(seen.ok, "snacks.nvim picker.select is available for :Commentry list-comments"))
    assert.are.same(0, #seen.warn)
  end)

  it("warns when snacks is unavailable", function()
    local seen = capture_health()
    package.loaded["diffview"] = {}
    package.loaded["snacks"] = nil
    package.loaded["commentry.config"] = { agent = { enabled = false } }

    require("commentry.health").check()

    assert.is_true(vim.tbl_contains(seen.warn, "snacks.nvim not installed: :Commentry list-comments is unavailable"))
  end)

  it("warns when snacks picker.select is unavailable", function()
    local seen = capture_health()
    package.loaded["diffview"] = {}
    package.loaded["snacks"] = { picker = {} }
    package.loaded["commentry.config"] = { agent = { enabled = false } }

    require("commentry.health").check()

    assert.is_true(vim.tbl_contains(seen.warn, "snacks.nvim installed but picker.select is unavailable"))
  end)

  it("warns when agent delegation is enabled and the adapter is unavailable", function()
    local seen = capture_health()
    healthy_dependencies({ agent = { enabled = true } })
    package.loaded["commentry.agent.adapters.sidekick"] = {}

    require("commentry.health").check()

    assert.is_true(
      vim.tbl_contains(
        seen.warn,
        "agent enabled but sidekick adapter is unavailable; install sidekick integration or set agent.enabled=false"
      )
    )
  end)

  it("warns when the Sidekick CLI send API is unavailable", function()
    local seen = capture_health()
    healthy_dependencies({ agent = { enabled = true } })
    package.loaded["commentry.agent.adapters.sidekick"] = {
      send = function() end,
      available = function()
        return false
      end,
    }

    require("commentry.health").check()

    assert.is_true(
      vim.tbl_contains(
        seen.warn,
        "agent enabled but sidekick CLI send API is unavailable; check the Sidekick installation"
      )
    )
  end)

  it("reports agent delegation readiness", function()
    local seen = capture_health()
    healthy_dependencies({ agent = { enabled = true } })
    package.loaded["commentry.agent.adapters.sidekick"] = {
      send = function() end,
      available = function()
        return true
      end,
    }

    require("commentry.health").check()

    assert.is_true(
      vim.tbl_contains(seen.ok, "agent adapter ready; Sidekick resolves the :Commentry send-to-agent target")
    )
    assert.are.same(0, #seen.warn)
  end)

  it("warns when logger config values are invalid", function()
    local seen = capture_health()
    healthy_dependencies({
      agent = { enabled = false },
      log = { level = "trace", sink = "stdout" },
    })

    require("commentry.health").check()

    assert.is_true(vim.tbl_contains(seen.warn, 'log.level="trace" is invalid; expected one of error|warn|info|debug'))
    assert.is_true(vim.tbl_contains(seen.warn, 'log.sink="stdout" is invalid; expected one of notify|echo|file'))
  end)

  it("warns when file sink path is not writable", function()
    local seen = capture_health()
    io.open = function()
      return nil
    end
    healthy_dependencies({
      agent = { enabled = false },
      log = {
        level = "info",
        sink = "file",
        file = vim.fn.tempname() .. "/commentry.log",
      },
    })

    require("commentry.health").check()

    local found = false
    for _, message in ipairs(seen.warn) do
      if message:find("log file sink is not writable:", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("does not create store directory during health checks", function()
    local seen = capture_health()
    vim.fn.isdirectory = function(path)
      if type(path) == "string" and path:find(".commentry", 1, true) then
        return 0
      end
      return original_fn_isdirectory(path)
    end
    healthy_dependencies()

    require("commentry.health").check()

    local found = false
    for _, message in ipairs(seen.ok) do
      if message:find("comment store directory does not exist yet", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)
end)
