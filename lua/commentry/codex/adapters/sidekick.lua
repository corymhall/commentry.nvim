local Adapter = require("commentry.codex.adapter")

local M = {}

local ENTRYPOINT_MODULES = {
  "sidekick.codex",
  "sidekick.integration.codex",
  "sidekick",
}

local ENTRYPOINTS = {
  "send_to_session",
  "send",
}

---@param target any
---@return boolean
local function valid_target(target)
  return type(target) == "table" and type(target.session_id) == "string" and target.session_id ~= ""
end

---@return fun(payload:any, target:table):boolean,table?,table? | nil
local function resolve_sender()
  for _, module_name in ipairs(ENTRYPOINT_MODULES) do
    local ok, mod = pcall(require, module_name)
    if ok and type(mod) == "table" then
      for _, entrypoint in ipairs(ENTRYPOINTS) do
        if type(mod[entrypoint]) == "function" then
          return function(payload, target)
            return mod[entrypoint](payload, target)
          end
        end
      end
    end
  end
end

---@param target? table
---@return boolean
function M.available(target)
  return valid_target(target) and resolve_sender() ~= nil
end

---@param payload any
---@param target? { session_id:string, workspace:string|nil }
---@return boolean ok, commentry.CodexError? err, table? details
function M.send(payload, target)
  if not valid_target(target) then
    return false, Adapter.error("ADAPTER_UNAVAILABLE")
  end

  local sender = resolve_sender()
  if sender == nil then
    return false, Adapter.error("ADAPTER_UNAVAILABLE")
  end

  local dispatch_target = {
    session_id = target.session_id,
    workspace = target.workspace,
  }

  local called, ok, err, details = pcall(sender, payload, dispatch_target)
  if not called then
    return false, Adapter.error("INTERNAL_ERROR")
  end

  if ok then
    local success_details = details
    if success_details == nil and type(err) == "table" then
      success_details = err
    end
    return true, nil, success_details
  end

  return false, Adapter.normalize_error(err, "TRANSPORT_FAILED")
end

return M
