---@module 'luassert'

describe("commentry.codex.adapters.sidekick", function()
  local original_module
  local original_adapter
  local original_sidekick
  local original_sidekick_codex
  local original_sidekick_integration
  local original_sidekick_cli_state
  local original_sidekick_preload
  local original_sidekick_codex_preload
  local original_sidekick_integration_preload
  local original_sidekick_cli_state_preload
  local original_sidekick_cli_ui_select
  local original_sidekick_cli_ui_select_preload
  local original_ui_select
  local original_getcwd

  before_each(function()
    original_module = package.loaded["commentry.codex.adapters.sidekick"]
    original_adapter = package.loaded["commentry.codex.adapter"]
    original_sidekick = package.loaded["sidekick"]
    original_sidekick_codex = package.loaded["sidekick.codex"]
    original_sidekick_integration = package.loaded["sidekick.integration.codex"]
    original_sidekick_cli_state = package.loaded["sidekick.cli.state"]
    original_sidekick_preload = package.preload["sidekick"]
    original_sidekick_codex_preload = package.preload["sidekick.codex"]
    original_sidekick_integration_preload = package.preload["sidekick.integration.codex"]
    original_sidekick_cli_state_preload = package.preload["sidekick.cli.state"]
    original_sidekick_cli_ui_select = package.loaded["sidekick.cli.ui.select"]
    original_sidekick_cli_ui_select_preload = package.preload["sidekick.cli.ui.select"]
    original_ui_select = vim.ui.select
    original_getcwd = vim.fn.getcwd
  end)

  after_each(function()
    package.loaded["commentry.codex.adapters.sidekick"] = original_module
    package.loaded["commentry.codex.adapter"] = original_adapter
    package.loaded["sidekick"] = original_sidekick
    package.loaded["sidekick.codex"] = original_sidekick_codex
    package.loaded["sidekick.integration.codex"] = original_sidekick_integration
    package.loaded["sidekick.cli.state"] = original_sidekick_cli_state
    package.preload["sidekick"] = original_sidekick_preload
    package.preload["sidekick.codex"] = original_sidekick_codex_preload
    package.preload["sidekick.integration.codex"] = original_sidekick_integration_preload
    package.preload["sidekick.cli.state"] = original_sidekick_cli_state_preload
    package.loaded["sidekick.cli.ui.select"] = original_sidekick_cli_ui_select
    package.preload["sidekick.cli.ui.select"] = original_sidekick_cli_ui_select_preload
    vim.ui.select = original_ui_select
    vim.fn.getcwd = original_getcwd
  end)

  it("returns ADAPTER_UNAVAILABLE for invalid targets", function()
    package.loaded["commentry.codex.adapters.sidekick"] = nil
    local sidekick = require("commentry.codex.adapters.sidekick")
    local ok, err = sidekick.send({ prompt = "ping" }, {})
    assert.is_false(ok)
    assert.are.same("ADAPTER_UNAVAILABLE", err.code)
    assert.are.same("Target adapter is unavailable.", err.message)
  end)

  it("resolves sender via module fallback order", function()
    local calls = {}
    package.loaded["sidekick.codex"] = {}
    package.loaded["sidekick.integration.codex"] = {
      send_to_session = function(payload, target)
        calls[#calls + 1] = { payload = payload, target = target }
        return true, { dispatched_items = 7 }
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    local ok, err, details = sidekick.send({ prompt = "ping" }, {
      session_id = "session-42",
      workspace = "/tmp/repo",
      extra = "ignored",
    })

    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.same({ dispatched_items = 7 }, details)
    assert.are.same(1, #calls)
    assert.are.same("session-42", calls[1].target.session_id)
    assert.are.same("/tmp/repo", calls[1].target.workspace)
    assert.is_nil(calls[1].target.extra)
  end)

  it("discovers the attached target from sidekick runtime", function()
    package.loaded["sidekick.codex"] = {
      current_session = function()
        return {
          id = "session-attached",
          workspace = "/tmp/repo",
        }
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    assert.are.same({
      session_id = "session-attached",
      workspace = "/tmp/repo",
    }, sidekick.current_target())
  end)

  it("normalizes provider failures to TRANSPORT_FAILED", function()
    package.loaded["sidekick.codex"] = {
      send = function()
        return false, { code = "RANDOM_PROVIDER_FAILURE", message = "provider-specific" }
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    local ok, err = sidekick.send({ prompt = "ping" }, { session_id = "session-55" })
    assert.is_false(ok)
    assert.are.same("TRANSPORT_FAILED", err.code)
    assert.are.same("Adapter transport failed.", err.message)
    assert.is_true(err.retryable)
  end)

  it("uses attached sidekick.cli.state session fallback when codex modules are unavailable", function()
    local sent = nil
    package.loaded["sidekick.codex"] = nil
    package.loaded["sidekick.integration.codex"] = nil
    package.loaded["sidekick"] = nil
    package.loaded["sidekick.cli.state"] = {
      get = function(filter)
        if filter and filter.attached and filter.session == "session-cli" then
          return {
            {
              session = {
                id = "session-cli",
                cwd = "/tmp/repo",
                send = function(_, msg)
                  sent = msg
                end,
              },
            },
          }
        end
        return {}
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    local ok, err, details = sidekick.send({ items = { { id = "c1" }, { id = "c2" } } }, { session_id = "session-cli" })

    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.same(2, details.dispatched_items)
    assert.are.same("string", type(sent))
    assert.is_truthy(sent:sub(-1) == "\n")
    assert.is_truthy(sent:find("COMMENTRY_REVIEW_V1", 1, true))
    assert.is_truthy(sent:find("items: 2", 1, true))
  end)

  it("discovers current target via sidekick.cli.state fallback", function()
    package.loaded["sidekick.codex"] = nil
    package.loaded["sidekick.integration.codex"] = nil
    package.loaded["sidekick"] = nil
    package.loaded["sidekick.cli.state"] = {
      get = function(filter)
        if filter and filter.name == "codex" then
          return {
            {
              session = {
                id = "session-from-state",
                cwd = "/tmp/state-cwd",
              },
            },
          }
        end
        return {}
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    assert.are.same({
      session_id = "session-from-state",
      workspace = "/tmp/state-cwd",
    }, sidekick.current_target())
  end)

  it("auto-attaches the only existing codex session target", function()
    local attach_calls = 0
    package.loaded["sidekick.codex"] = nil
    package.loaded["sidekick.integration.codex"] = nil
    package.loaded["sidekick"] = nil
    package.loaded["sidekick.cli.state"] = {
      get = function(filter)
        if filter and filter.name == "codex" then
          return {
            {
              session = {
                id = "session-single",
                cwd = "/tmp/one",
              },
            },
          }
        end
        return {}
      end,
      attach = function(state)
        attach_calls = attach_calls + 1
        return state, true
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    local seen = nil
    sidekick.resolve_target_async(function(target, err_code, err_message)
      seen = { target = target, err_code = err_code, err_message = err_message }
    end)

    assert.are.same(1, attach_calls)
    assert.are.same(nil, seen.err_code)
    assert.are.same({
      session_id = "session-single",
      workspace = "/tmp/one",
    }, seen.target)
  end)

  it("prompts to choose codex session when multiple existing sessions are available", function()
    local attach_calls = 0
    local prompted = false
    vim.ui.select = function(items, _, cb)
      prompted = true
      cb(items[2])
    end
    package.loaded["sidekick.codex"] = nil
    package.loaded["sidekick.integration.codex"] = nil
    package.loaded["sidekick"] = nil
    package.loaded["sidekick.cli.state"] = {
      get = function(filter)
        if filter and filter.name == "codex" then
          return {
            { session = { id = "session-a", cwd = "/tmp/a" } },
            { session = { id = "session-b", cwd = "/tmp/b" } },
          }
        end
        return {}
      end,
      attach = function(state)
        attach_calls = attach_calls + 1
        return state, true
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    local seen = nil
    sidekick.resolve_target_async(function(target, err_code, err_message)
      seen = { target = target, err_code = err_code, err_message = err_message }
    end)

    assert.is_true(prompted)
    assert.are.same(1, attach_calls)
    assert.are.same(nil, seen.err_code)
    assert.are.same({
      session_id = "session-b",
      workspace = "/tmp/b",
    }, seen.target)
  end)

  it("auto-selects the single codex session matching current cwd", function()
    local attach_calls = 0
    local prompted = false
    vim.ui.select = function(_, _, _)
      prompted = true
    end
    vim.fn.getcwd = function()
      return "/tmp/b"
    end
    package.loaded["sidekick.codex"] = nil
    package.loaded["sidekick.integration.codex"] = nil
    package.loaded["sidekick"] = nil
    package.loaded["sidekick.cli.ui.select"] = nil
    package.preload["sidekick.cli.ui.select"] = function()
      return {
        select = function()
          prompted = true
        end,
      }
    end
    package.loaded["sidekick.cli.state"] = {
      get = function(filter)
        if filter and filter.name == "codex" then
          return {
            { session = { id = "session-a", cwd = "/tmp/a" } },
            { session = { id = "session-b", cwd = "/tmp/b" } },
            { session = { id = "session-c", cwd = "/tmp/c" } },
          }
        end
        return {}
      end,
      attach = function(state)
        attach_calls = attach_calls + 1
        return state, true
      end,
    }
    package.loaded["commentry.codex.adapters.sidekick"] = nil

    local sidekick = require("commentry.codex.adapters.sidekick")
    local seen = nil
    sidekick.resolve_target_async(function(target, err_code, err_message)
      seen = { target = target, err_code = err_code, err_message = err_message }
    end)

    assert.are.same(1, attach_calls)
    assert.is_false(prompted)
    assert.are.same(nil, seen.err_code)
    assert.are.same("session-b", seen.target.session_id)
  end)
end)
