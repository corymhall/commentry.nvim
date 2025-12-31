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
