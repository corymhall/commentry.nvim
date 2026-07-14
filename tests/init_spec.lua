---@module 'luassert'

describe("commentry.setup", function()
  local original_orchestrator
  local original_orchestrator_preload

  before_each(function()
    original_orchestrator = package.loaded["commentry.agent.orchestrator"]
    original_orchestrator_preload = package.preload["commentry.agent.orchestrator"]
  end)

  after_each(function()
    package.loaded["commentry.agent.orchestrator"] = original_orchestrator
    package.preload["commentry.agent.orchestrator"] = original_orchestrator_preload
  end)

  it("does not error", function()
    local ok = pcall(require("commentry").setup, {})
    assert.is_true(ok)
  end)

  it("loads agent delegation lazily even when enabled", function()
    package.loaded["commentry.agent.orchestrator"] = nil
    package.preload["commentry.agent.orchestrator"] = function()
      error("agent orchestrator should load only when sending")
    end

    local ok = pcall(require("commentry").setup, {
      agent = {
        enabled = true,
      },
    })
    assert.is_true(ok)
  end)
end)
