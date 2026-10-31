local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

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

---@return table
local function log_config()
  local loaded, config = pcall(require, "commentry.config")
  if not loaded or type(config) ~= "table" or type(config.log) ~= "table" then
    return { level = "warn", sink = "notify", file = nil }
  end
  return config.log
end

---@param cfg table
local function log_health(cfg)
  local levels = { error = true, warn = true, info = true, debug = true }
  local sinks = { notify = true, echo = true, file = true }
  if not levels[cfg.level] then
    warn(("log.level=%q is invalid; expected one of error|warn|info|debug"):format(tostring(cfg.level)))
  else
    ok(("log level configured: %s"):format(cfg.level))
  end
  if not sinks[cfg.sink] then
    warn(("log.sink=%q is invalid; expected one of notify|echo|file"):format(tostring(cfg.sink)))
    return
  end
  if cfg.sink ~= "file" then
    ok(("log sink configured: %s"):format(cfg.sink))
    return
  end
  if type(cfg.file) ~= "string" or cfg.file == "" then
    warn("log sink is 'file' but log.file is empty")
    return
  end
  local parent = vim.fn.fnamemodify(cfg.file, ":h")
  if type(parent) == "string" and parent ~= "" and parent ~= "." then
    local mkdir_ok = pcall(vim.fn.mkdir, parent, "p")
    if not mkdir_ok then
      warn(("log file sink is not writable: %s"):format(cfg.file))
      return
    end
  end
  local fd = io.open(cfg.file, "a")
  if not fd then
    warn(("log file sink is not writable: %s"):format(cfg.file))
    return
  end
  fd:close()
  ok(("log file sink writable: %s"):format(cfg.file))
end

--- check.
function M.check()
  start("commentry")
  version_health()
  setup_health()
  if pcall(require, "diffview") then
    ok("diffview.nvim available for diff capture")
  else
    ok("diffview.nvim not installed; optional diff capture is unavailable")
  end
  local backend = require("commentry.inbox.store").executable()
  if backend and backend ~= "" and vim.fn.executable(backend) == 1 then
    ok("inbox Go backend available: " .. backend)
  else
    warn("inbox requires commentry on PATH; install it, or run mise run build and add bin/ to PATH")
  end
  log_health(log_config())
end

return M
