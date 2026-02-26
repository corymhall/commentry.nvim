local Adapter = require("commentry.codex.adapter")
local Send = require("commentry.codex.send")

local M = {}

---@param payload any
---@param target? table
---@return boolean ok, commentry.CodexError? err, table? details
function M.send(payload, target)
  return Adapter.send(payload, target)
end

---@param opts? table
---@return table
function M.send_current_review(opts)
  return Send.send_current_review(opts)
end

return M
