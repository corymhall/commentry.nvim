---@module 'luassert'

local Adapter = require("commentry.codex.adapter")
local Orchestrator = require("commentry.codex.orchestrator")

describe("commentry.codex.adapter", function()
  it("returns NO_TARGET when target is missing", function()
    local ok, err = Adapter.send({ prompt = "ping" }, nil)
    assert.is_false(ok)
    assert.are.same({
      code = "NO_TARGET",
      message = "No target adapter configured.",
      retryable = false,
    }, err)
  end)

  it("returns ADAPTER_UNAVAILABLE when target has no send function", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {})
    assert.is_false(ok)
    assert.are.same({
      code = "ADAPTER_UNAVAILABLE",
      message = "Target adapter is unavailable.",
      retryable = true,
    }, err)
  end)

  it("passes through success details", function()
    local ok, err, details = Adapter.send({ prompt = "ping" }, {
      send = function()
        return true, { request_id = "abc123" }
      end,
    })
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.same({ request_id = "abc123" }, details)
  end)

  it("normalizes explicit transport failures", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        return false, {
          code = "TRANSPORT_FAILED",
          message = "ECONNRESET backend detail",
          retryable = false,
        }
      end,
    })
    assert.is_false(ok)
    assert.are.same({
      code = "TRANSPORT_FAILED",
      message = "Adapter transport failed.",
      retryable = true,
    }, err)
  end)

  it("maps unknown backend error objects to INTERNAL_ERROR", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        return false, {
          code = "UNMAPPED",
          message = "provider said this should leak",
          retryable = false,
        }
      end,
    })
    assert.is_false(ok)
    assert.are.same({
      code = "INTERNAL_ERROR",
      message = "Internal adapter error.",
      retryable = false,
    }, err)
  end)

  it("maps thrown errors to INTERNAL_ERROR without leaking backend strings", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        error("backend stack trace should not leak")
      end,
    })
    assert.is_false(ok)
    assert.are.same({
      code = "INTERNAL_ERROR",
      message = "Internal adapter error.",
      retryable = false,
    }, err)
    assert.is_nil(err.message:find("backend", 1, true))
  end)
end)

describe("commentry.codex.orchestrator", function()
  it("imports and delegates to adapter contract", function()
    local ok, err, details = Orchestrator.send({ prompt = "ping" }, {
      send = function()
        return true, { source = "test" }
      end,
    })

    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.same({ source = "test" }, details)
  end)
end)
