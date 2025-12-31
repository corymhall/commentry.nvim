local M = {}

---@param msg string|string[]
---@param level? vim.log.levels
function M.notify(msg, level)
  msg = type(msg) == "table" and table.concat(msg, "\n") or msg
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Commentry" })
  end)
end

---@param msg string|string[]
function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

---@param msg string|string[]
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

---@param msg string|string[]
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---@param msg string|string[]
---@param what? any
function M.debug(msg, what)
  if require("commentry.config").debug then
    if what ~= nil then
      msg = type(msg) == "table" and msg or { msg } ---@type string[]
      msg[#msg + 1] = "```lua"
      msg[#msg + 1] = vim.inspect(what)
      msg[#msg + 1] = "```"
    end
    M.warn(msg)
  end
end

return M
