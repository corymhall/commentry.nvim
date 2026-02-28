local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

---@return table
local function codex_config()
  local loaded, config = pcall(require, "commentry.config")
  if not loaded or type(config) ~= "table" or type(config.codex) ~= "table" then
    return { enabled = false, adapter = { select = "auto" } }
  end
  return config.codex
end

---@param codex table
local function codex_health(codex)
  if not codex.enabled then
    ok("codex integration disabled: :Commentry send-to-codex is inactive")
    return
  end

  local adapter = type(codex.adapter) == "table" and codex.adapter or {}
  local selected = adapter.select or "auto"
  if selected ~= "auto" and selected ~= "sidekick" then
    warn(("codex enabled with unsupported adapter.select=%q; configure \"auto\"/\"sidekick\" or disable codex"):format(selected))
    return
  end

  local sidekick_ok, sidekick = pcall(require, "commentry.codex.adapters.sidekick")
  if not sidekick_ok or type(sidekick) ~= "table" or type(sidekick.send) ~= "function" then
    warn("codex enabled but sidekick adapter is unavailable; install sidekick integration or set codex.enabled=false")
    return
  end

  local available = true
  if type(sidekick.available) == "function" then
    available = sidekick.available() == true
  end

  if not available then
    warn("codex enabled but sidekick adapter runtime is unavailable; check sidekick install and active target session")
    return
  end

  ok("codex adapter ready (sidekick transport available); :Commentry send-to-codex uses attached session target")
end

local function version_health()
  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim version is supported (>= 0.10)")
  else
    error("Neovim >= 0.10 is required by commentry.nvim")
  end
end

local function setup_health()
  if vim.fn.exists(":Commentry") == 2 then
    ok(":Commentry command is registered")
  else
    warn(":Commentry command is not registered; run require('commentry').setup()")
  end

  if package.loaded["commentry.config"] then
    ok("commentry.config is loaded")
  else
    warn("commentry.config is not loaded; setup may not have run in this session")
  end
end

--- check.
function M.check()
  start("commentry")
  version_health()
  setup_health()
  if pcall(require, "diffview") then
    ok("diffview.nvim is installed")
  else
    error("diffview.nvim is required for Commentry")
  end

  local snacks_ok, snacks = pcall(require, "snacks")
  if not snacks_ok then
    warn("snacks.nvim not installed: :Commentry list-comments is unavailable")
  elseif type(snacks.picker) ~= "table" or type(snacks.picker.select) ~= "function" then
    warn("snacks.nvim installed but picker.select is unavailable")
  else
    ok("snacks.nvim picker.select is available for :Commentry list-comments")
  end

  codex_health(codex_config())
end

return M
