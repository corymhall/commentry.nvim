local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error
local uv = vim.uv or vim.loop

---@return table
local function agent_config()
  local loaded, config = pcall(require, "commentry.config")
  if not loaded or type(config) ~= "table" or type(config.agent) ~= "table" then
    return { enabled = false }
  end
  return config.agent
end

---@param agent table
local function agent_health(agent)
  if not agent.enabled then
    return
  end

  local sidekick_ok, sidekick = pcall(require, "commentry.agent.adapters.sidekick")
  if not sidekick_ok or type(sidekick) ~= "table" or type(sidekick.send) ~= "function" then
    warn("agent enabled but sidekick adapter is unavailable; install sidekick integration or set agent.enabled=false")
    return
  end

  local available = type(sidekick.available) ~= "function" or sidekick.available() == true
  if not available then
    warn("agent enabled but sidekick CLI send API is unavailable; check the Sidekick installation")
    return
  end

  ok("agent adapter ready; Sidekick resolves the :Commentry send-to-agent target")
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

local function store_writable_health()
  local home = (uv and uv.os_homedir and uv.os_homedir()) or vim.env.HOME
  if type(home) ~= "string" or home == "" then
    warn("comment store health skipped: home directory unavailable")
    return
  end
  local base = vim.fs.joinpath(vim.fs.normalize(home), ".commentry")
  if vim.fn.isdirectory(base) ~= 1 then
    ok(("comment store directory does not exist yet (created on first write): %s"):format(base))
    return
  end
  local probe = vim.fs.joinpath(base, ".health-write-test")
  local wrote, result = pcall(vim.fn.writefile, { "ok" }, probe)
  if not wrote or result ~= 0 then
    warn(("comment store directory is not writable: %s"):format(base))
    return
  end
  pcall(vim.fn.delete, probe)
  ok(("comment store directory is writable: %s"):format(base))
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

  store_writable_health()
  log_health(log_config())
  agent_health(agent_config())
end

return M
