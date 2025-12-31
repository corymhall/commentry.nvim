local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local error = vim.health.error or vim.health.report_error

function M.check()
  start("commentry")
  if pcall(require, "diffview") then
    ok("diffview.nvim is installed")
  else
    error("diffview.nvim is required for Commentry")
  end
end

return M
