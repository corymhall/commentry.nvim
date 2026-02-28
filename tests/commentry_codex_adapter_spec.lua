---@module 'luassert'

local Adapter = require("commentry.codex.adapter")
local Orchestrator = require("commentry.codex.orchestrator")

local function failure_contract(ok, err)
  return {
    ok = ok,
    code = err.code,
    message = err.message,
    retryable = err.retryable,
  }
end

local function assert_failure_contract(ok, err, expected)
  assert.are.same({
    ok = false,
    code = expected.code,
    message = expected.message,
    retryable = expected.retryable,
  }, failure_contract(ok, err))
end

local function sorted_keys(value)
  local keys = vim.tbl_keys(value)
  table.sort(keys)
  return keys
end

describe("commentry.codex.adapter", function()
  it("returns NO_TARGET when target is missing", function()
    local ok, err = Adapter.send({ prompt = "ping" }, nil)
    assert_failure_contract(ok, err, {
      code = "NO_TARGET",
      message = "No target adapter configured.",
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
        message = "Target adapter is unavailable.",
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
      message = "Adapter transport failed.",
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
      message = "Internal adapter error.",
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
      message = "Internal adapter error.",
      retryable = false,
    })
  end)

  it("keeps failure return schema stable under mock failures", function()
    local failure_cases = {
      {
        name = "missing-target",
        invoke = function()
          return Adapter.send({ prompt = "ping" }, nil)
        end,
        expected = {
          code = "NO_TARGET",
          message = "No target adapter configured.",
          retryable = false,
        },
      },
      {
        name = "adapter-unavailable",
        invoke = function()
          return Adapter.send({ prompt = "ping" }, {})
        end,
        expected = {
          code = "ADAPTER_UNAVAILABLE",
          message = "Target adapter is unavailable.",
          retryable = true,
        },
      },
      {
        name = "malformed-adapter-response",
        invoke = function()
          return Adapter.send({ prompt = "ping" }, {
            send = function()
              return false, 42
            end,
          })
        end,
        expected = {
          code = "INTERNAL_ERROR",
          message = "Internal adapter error.",
          retryable = false,
        },
      },
    }

    for _, case in ipairs(failure_cases) do
      local ok, err = case.invoke()
      assert_failure_contract(ok, err, case.expected)
      assert.are.same({
        "code",
        "message",
        "ok",
        "retryable",
      }, sorted_keys(failure_contract(ok, err)))
    end
  end)

  it("maps thrown errors to INTERNAL_ERROR without leaking backend strings", function()
    local ok, err = Adapter.send({ prompt = "ping" }, {
      send = function()
        error("backend stack trace should not leak")
      end,
    })
    assert_failure_contract(ok, err, {
      code = "INTERNAL_ERROR",
      message = "Internal adapter error.",
      retryable = false,
    })
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

  it("preserves adapter failure schema exactly", function()
    local ok, err = Orchestrator.send({ prompt = "ping" }, {})
    assert_failure_contract(ok, err, {
      code = "ADAPTER_UNAVAILABLE",
      message = "Target adapter is unavailable.",
      retryable = true,
    })
    assert.are.same({
      "code",
      "message",
      "ok",
      "retryable",
    }, sorted_keys(failure_contract(ok, err)))
  end)
end)
