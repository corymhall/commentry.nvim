local Config = require("commentry.config")
local Diffview = require("commentry.diffview")
local Util = require("commentry.util")

local M = {}
local initialized = false

local feature_modules = {
  "commentry.diffview",
  "commentry.comments",
}

---@alias commentry.command.Fn fun(args: vim.api.keyset.create_user_command.command_args, cmd_args: string)

---@type table<string, commentry.command.Fn>
M.commands = {}

function M.setup()
  if initialized then
    return
  end
  initialized = true

  M.register("open", function(_, cmd_args)
    if not Config.diffview.enabled then
      Util.warn("Diff view is disabled in config")
      return
    end
    local args = nil
    if type(cmd_args) == "string" and cmd_args ~= "" then
      args = vim.split(cmd_args, "%s+", { trimempty = true })
    end
    local ok, err = Diffview.open(args)
    if ok then
      return
    end
    if err == "no_changes" then
      Util.info("No local changes to review")
      return
    end
    if err == "not_git_repo" then
      Util.error("Current directory is not a git repository")
      return
    end
    if err == "git_status_failed" then
      Util.error("Failed to read git status")
      return
    end
    Util.error(err or "Failed to open diff view")
  end)

  for _, module_name in ipairs(feature_modules) do
    local ok, mod = pcall(require, module_name)
    if ok and type(mod.register_commands) == "function" then
      mod.register_commands(M.register)
    end
  end
end

---@param name string
---@param fn commentry.command.Fn
function M.register(name, fn)
  M.commands[name] = fn
end

---@param line string
function M.complete(line)
  M.setup()
  line = line:gsub("^%s*Commentry%s+", "")
  local prefix = line:match("^(%S*)") or ""
  local keys = vim.tbl_keys(M.commands)
  table.sort(keys)
  return vim.tbl_filter(function(key)
    return key:find(prefix, 1, true) == 1
  end, keys)
end

---@param line vim.api.keyset.create_user_command.command_args
function M.cmd(line)
  M.setup()
  local input = line.args or ""
  local parts = vim.split(input, "%s+", { trimempty = true })
  local name = parts[1] or ""
  local cmd = name ~= "" and M.commands[name] or nil
  if not cmd then
    if name == "" then
      Util.error("No command provided")
    else
      Util.error(("Unknown command: `%s`"):format(name))
    end
    return
  end
  local rest = table.concat(parts, " ", 2)
  cmd(line, rest)
end

return M
