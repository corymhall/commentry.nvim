local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

function M.check()
  start("commentry")
  if pcall(require, "diffview") then
    ok("diffview.nvim is installed")
  else
    error("diffview.nvim is required for Commentry")
  end

  local snacks_ok, snacks = pcall(require, "snacks")
  if not snacks_ok then
    warn("snacks.nvim not installed: :Commentry list-comments is unavailable")
    return
  end

  if type(snacks.picker) ~= "table" or type(snacks.picker.select) ~= "function" then
    warn("snacks.nvim installed but picker.select is unavailable")
    return
  end

  ok("snacks.nvim picker.select is available for :Commentry list-comments")
end

return M
