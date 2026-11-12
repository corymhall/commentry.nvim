---@module 'luassert'

describe("commentry.health", function()
  local original_health
  local original_diffview
  local original_snacks
  local original_config
  local original_fn_has
  local original_fn_exists
  local original_fn_isdirectory
  local original_io_open

  before_each(function()
    original_health = vim.health
    original_diffview = package.loaded["diffview"]
    original_snacks = package.loaded["snacks"]
    original_config = package.loaded["commentry.config"]
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
    vim.fn.has = original_fn_has
    vim.fn.exists = original_fn_exists
    vim.fn.isdirectory = original_fn_isdirectory
    io.open = original_io_open
    package.loaded["commentry.health"] = nil
  end)

  local function contains_message(messages, fragment)
    for _, message in ipairs(messages) do
      if message:find(fragment, 1, true) then
        return true
      end
    end
    return false
  end

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
    package.loaded["commentry.config"] = config or {}
  end

  it("reports core and picker readiness", function()
    local seen = capture_health()
    healthy_dependencies()

    require("commentry.health").check()

    assert.is_true(contains_message(seen.ok, "Neovim"))
    assert.is_true(contains_message(seen.ok, ":Commentry"))
    assert.is_true(contains_message(seen.ok, "commentry.config"))
    assert.is_true(contains_message(seen.ok, "diffview.nvim"))
    assert.are.same(0, #seen.warn)
  end)

  it("does not require Diffview or a picker for the inbox", function()
    local seen = capture_health()
    package.loaded["diffview"] = nil
    package.loaded["snacks"] = nil
    package.loaded["commentry.config"] = {}
    require("commentry.health").check()
    assert.are.same(0, #seen.error)
    assert.are.same(0, #seen.warn)
  end)

  it("reports an actionable error when NUI is missing", function()
    local seen = capture_health()
    healthy_dependencies()
    local original_popup = package.loaded["nui.popup"]
    local original_preload = package.preload["nui.popup"]
    package.loaded["nui.popup"] = nil
    package.preload["nui.popup"] = function()
      error("NUI deliberately absent")
    end
    local success, err = pcall(function()
      require("commentry.health").check()
    end)
    package.loaded["nui.popup"] = original_popup
    package.preload["nui.popup"] = original_preload
    assert.is_true(success, tostring(err))
    assert.is_true(contains_message(seen.error, "add MunifTanjim/nui.nvim"))
  end)

  it("warns when logger config values are invalid", function()
    local seen = capture_health()
    healthy_dependencies({
      log = { level = "trace", sink = "stdout" },
    })

    require("commentry.health").check()

    assert.is_true(contains_message(seen.warn, 'log.level="trace" is invalid; expected one of error|warn|info|debug'))
    assert.is_true(contains_message(seen.warn, 'log.sink="stdout" is invalid; expected one of notify|echo|file'))
  end)

  it("warns when file sink path is not writable", function()
    local seen = capture_health()
    io.open = function()
      return nil
    end
    healthy_dependencies({
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
end)
