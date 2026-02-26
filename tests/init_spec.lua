---@module 'luassert'

describe("commentry.setup", function()
  local original_codex
  local original_codex_preload

  before_each(function()
    original_codex = package.loaded["commentry.codex"]
    original_codex_preload = package.preload["commentry.codex"]
  end)

  after_each(function()
    package.loaded["commentry.codex"] = original_codex
    package.preload["commentry.codex"] = original_codex_preload
  end)

  it("does not error", function()
    local ok = pcall(require("commentry").setup, {})
    assert.is_true(ok)
  end)

  it("does not load codex namespace when codex is disabled", function()
    package.loaded["commentry.codex"] = nil
    package.preload["commentry.codex"] = function()
      error("codex namespace should not load when disabled")
    end

    local ok = pcall(require("commentry").setup, {
      codex = {
        enabled = false,
      },
    })
    assert.is_true(ok)
  end)

  it("does not error when codex is enabled but codex namespace is unavailable", function()
    package.loaded["commentry.codex"] = nil
    package.preload["commentry.codex"] = function()
      error("codex namespace unavailable")
    end

    local ok = pcall(require("commentry").setup, {
      codex = {
        enabled = true,
      },
    })
    assert.is_true(ok)
  end)
end)
