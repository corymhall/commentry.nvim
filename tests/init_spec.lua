---@module 'luassert'

describe("commentry.setup", function()
  it("does not error", function()
    local ok = pcall(require("commentry").setup, {})
    assert.is_true(ok)
  end)
end)
