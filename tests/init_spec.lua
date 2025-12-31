local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

T["setup"] = function()
  local ok = pcall(require("commentry").setup, {})
  expect.equality(ok, true)
end

return T
