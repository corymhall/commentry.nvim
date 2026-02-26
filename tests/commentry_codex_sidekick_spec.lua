---@module 'luassert'

describe("commentry.codex.adapters.sidekick", function()
  local original_module
  local original_adapter
  local original_sidekick
  local original_sidekick_codex
  local original_sidekick_integration
  local original_sidekick_preload
  local original_sidekick_codex_preload
  local original_sidekick_integration_preload

  before_each(function()
    original_module = package.loaded["commentry.codex.adapters.sidekick"]
    original_adapter = package.loaded["commentry.codex.adapter"]
    original_sidekick = package.loaded["sidekick"]
    original_sidekick_codex = package.loaded["sidekick.codex"]
    original_sidekick_integration = package.loaded["sidekick.integration.codex"]
    original_sidekick_preload = package.preload["sidekick"]
    original_sidekick_codex_preload = package.preload["sidekick.codex"]
    original_sidekick_integration_preload = package.preload["sidekick.integration.codex"]
  end)

  after_each(function()
    package.loaded["commentry.codex.adapters.sidekick"] = original_module
    package.loaded["commentry.codex.adapter"] = original_adapter
    package.loaded["sidekick"] = original_sidekick
    package.loaded["sidekick.codex"] = original_sidekick_codex
    package.loaded["sidekick.integration.codex"] = original_sidekick_integration
    package.preload["sidekick"] = original_sidekick_preload
    package.preload["sidekick.codex"] = original_sidekick_codex_preload
    package.preload["sidekick.integration.codex"] = original_sidekick_integration_preload
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
end)
