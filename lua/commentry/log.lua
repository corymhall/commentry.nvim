local M = {}

M.levels = {
  error = 1,
  warn = 2,
  info = 3,
  debug = 4,
}

M._level = M.levels.warn
M._sink = "notify"
M._file = nil

---@param value string|nil
---@return boolean
local function valid_sink(value)
  return value == "notify" or value == "echo" or value == "file"
end

---@param value string|nil
---@return boolean
local function valid_level(value)
  return type(value) == "string" and M.levels[value] ~= nil
end

---@param opts? commentry.LogConfig
function M.setup(opts)
  opts = opts or {}
  if valid_level(opts.level) then
    M._level = M.levels[opts.level]
  end
  if valid_sink(opts.sink) then
    M._sink = opts.sink
  end
  if type(opts.file) == "string" and opts.file ~= "" then
    M._file = opts.file
  elseif opts.file == nil then
    M._file = nil
  end
end

---@param value any
---@return string
local function scalar_string(value)
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then
    return tostring(value)
  end
  if value == nil then
    return "nil"
  end
  return vim.inspect(value)
end

---@param kv table|nil
---@return string
local function encode_kv(kv)
  if type(kv) ~= "table" then
    return ""
  end
  local parts = {}
  for key, value in pairs(kv) do
    parts[#parts + 1] = ("%s=%s"):format(tostring(key), scalar_string(value))
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

---@param msg string
---@param level integer
local function emit(msg, level)
  if M._sink == "notify" then
    vim.schedule(function()
      vim.notify(msg, level, { title = "Commentry" })
    end)
    return
  end
  if M._sink == "echo" then
    vim.api.nvim_echo({ { msg, "None" } }, true, {})
    return
  end
  if M._sink == "file" and type(M._file) == "string" and M._file ~= "" then
    local parent = vim.fn.fnamemodify(M._file, ":h")
    if type(parent) == "string" and parent ~= "" and parent ~= "." then
      pcall(vim.fn.mkdir, parent, "p")
    end
    local fd = io.open(M._file, "a")
    if fd then
      fd:write(msg .. "\n")
      fd:close()
    end
  end
end

---@param level "error"|"warn"|"info"|"debug"
---@return boolean
local function should_log(level)
  return M.levels[level] and M.levels[level] <= M._level
end

---@param event string
---@param kv table|nil
---@return string
local function format_event(event, kv)
  local suffix = encode_kv(kv)
  if suffix == "" then
    return ("[commentry] %s"):format(event)
  end
  return ("[commentry] %s %s"):format(event, suffix)
end

---@param event string
---@param kv? table
function M.debug(event, kv)
  if not should_log("debug") then
    return
  end
  emit(format_event(event, kv), vim.log.levels.DEBUG)
end

---@param event string
---@param kv? table
function M.info(event, kv)
  if not should_log("info") then
    return
  end
  emit(format_event(event, kv), vim.log.levels.INFO)
end

---@param event string
---@param kv? table
function M.warn(event, kv)
  if not should_log("warn") then
    return
  end
  emit(format_event(event, kv), vim.log.levels.WARN)
end

---@param event string
---@param kv? table
function M.error(event, kv)
  emit(format_event(event, kv), vim.log.levels.ERROR)
end

---@param msg string|string[]
---@param level integer
function M.notify_message(msg, level)
  local payload = type(msg) == "table" and table.concat(msg, "\n") or tostring(msg)
  emit(payload, level)
end

return M
