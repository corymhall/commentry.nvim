local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok

function M.check()
  start("commentry")
  ok("Health checks not configured yet")
end

return M
