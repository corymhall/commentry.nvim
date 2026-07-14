---@module 'luassert'

describe("commentry.agent.adapters.sidekick", function()
  local original_module
  local original_cli
  local original_cli_preload

  before_each(function()
    original_module = package.loaded["commentry.agent.adapters.sidekick"]
    original_cli = package.loaded["sidekick.cli"]
    original_cli_preload = package.preload["sidekick.cli"]
  end)

  after_each(function()
    package.loaded["commentry.agent.adapters.sidekick"] = original_module
    package.loaded["sidekick.cli"] = original_cli
    package.preload["sidekick.cli"] = original_cli_preload
  end)

  local function load_with_cli(cli)
    package.loaded["sidekick.cli"] = cli
    package.preload["sidekick.cli"] = function()
      return cli
    end
    package.loaded["commentry.agent.adapters.sidekick"] = nil
    return require("commentry.agent.adapters.sidekick")
  end

  it("reports unavailable when the Sidekick CLI send API cannot load", function()
    package.loaded["sidekick.cli"] = nil
    package.preload["sidekick.cli"] = function()
      error("unavailable")
    end
    package.loaded["commentry.agent.adapters.sidekick"] = nil

    local sidekick = require("commentry.agent.adapters.sidekick")
    assert.is_false(sidekick.available())

    local ok, err = sidekick.send({ items = {} }, {})
    assert.is_false(ok)
    assert.are.same("ADAPTER_UNAVAILABLE", err.code)
  end)

  it("delegates generic sends without a tool filter", function()
    local seen = nil
    local sidekick = load_with_cli({
      send = function(opts)
        seen = opts
      end,
    })

    local ok, err, details = sidekick.send({ items = { { id = "c1", body = "{file}" }, { id = "c2" } } }, {})

    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_true(details.delegated)
    assert.are.same(2, details.dispatched_items)
    assert.is_nil(seen.name)
    assert.is_nil(seen.msg)
    assert.is_true(seen.submit)
    local rendered = table.concat(
      vim.tbl_map(function(line)
        return line[1][1]
      end, seen.text),
      "\n"
    )
    assert.is_truthy(rendered:find("COMMENTRY_REVIEW_V1", 1, true))
    assert.is_truthy(rendered:find("items: 2", 1, true))
    assert.is_truthy(rendered:find("body: {file}", 1, true))
  end)

  it("normalizes Sidekick send failures", function()
    local sidekick = load_with_cli({
      send = function()
        error("send failed")
      end,
    })

    local ok, err = sidekick.send({ items = {} }, {})

    assert.is_false(ok)
    assert.are.same("TRANSPORT_FAILED", err.code)
    assert.is_true(err.retryable)
  end)
end)
