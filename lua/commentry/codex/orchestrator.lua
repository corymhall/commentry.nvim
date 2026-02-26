local Adapter = require("commentry.codex.adapter")

local M = {}

---@param payload any
---@param target? table
---@return boolean ok, commentry.CodexError? err, table? details
function M.send(payload, target)
  return Adapter.send(payload, target)
end

return M
