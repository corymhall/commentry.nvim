local Adapter = require("commentry.agent.adapter")
local Send = require("commentry.agent.send")

local M = {}

---@param payload any
---@param target? table
---@return boolean ok, commentry.AgentError? err, table? details
function M.send(payload, target)
  return Adapter.send(payload, target)
end

---@param opts? table
---@return table
function M.send_current_review(opts)
  return Send.send_current_review(opts)
end

---@param opts? table
---@param cb? fun(result: table)
function M.send_current_review_async(opts, cb)
  return Send.send_current_review_async(opts, cb)
end

return M
