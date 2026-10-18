---@module 'luassert'

local Adapter = require("commentry.agent.adapter")

local function failure_contract(ok, err)
  return {
    ok = ok,
    code = err.code,
    retryable = err.retryable,
  }
end

local function assert_failure_contract(ok, err, expected)
  assert.are.same({
    ok = false,
    code = expected.code,
    retryable = expected.retryable,
  }, failure_contract(ok, err))
end

describe("commentry.agent.adapter", function()
  it("returns NO_TARGET when target is missing", function()
    local ok, err = Adapter.send({ prompt = "ping" }, nil)
    assert_failure_contract(ok, err, {
      code = "NO_TARGET",
      retryable = false,
    })
  end)

  it("returns deterministic ADAPTER_UNAVAILABLE for unavailable adapter targets", function()
    local cases = {
      "not-a-table",
      {},
      { send = true },
    }

    for _, target in ipairs(cases) do
      local ok, err = Adapter.send({ prompt = "ping" }, target)
      assert_failure_contract(ok, err, {
        code = "ADAPTER_UNAVAILABLE",
        retryable = true,
      })
    end
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

  it("normalizes timeout-like transport failures to canonical TRANSPORT_FAILED", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        return false,
          {
            code = "TRANSPORT_FAILED",
            message = "timeout after 30s",
            retryable = false,
          }
      end,
    })
    assert_failure_contract(ok, err, {
      code = "TRANSPORT_FAILED",
      retryable = true,
    })
  end)

  it("normalizes malformed adapter responses to INTERNAL_ERROR", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        return false, "totally malformed error payload"
      end,
    })
    assert_failure_contract(ok, err, {
      code = "INTERNAL_ERROR",
      retryable = false,
    })
  end)

  it("maps unknown backend error objects to INTERNAL_ERROR", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        return false,
          {
            code = "UNMAPPED",
            message = "provider said this should leak",
            retryable = false,
          }
      end,
    })
    assert_failure_contract(ok, err, {
      code = "INTERNAL_ERROR",
      retryable = false,
    })
  end)

  it("maps thrown errors to INTERNAL_ERROR without leaking backend strings", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        error("backend stack trace should not leak")
      end,
    })
    assert_failure_contract(ok, err, {
      code = "INTERNAL_ERROR",
      retryable = false,
    })
    assert.is_nil(err.message:find("backend", 1, true))
  end)
end)
