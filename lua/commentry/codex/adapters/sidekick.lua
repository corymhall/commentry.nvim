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

local TARGET_ENTRYPOINTS = {
  "current_target",
  "current_session",
  "get_current_session",
  "attached_session",
  "get_attached_session",
}

---@param target any
---@return boolean
local function valid_target(target)
  return type(target) == "table" and type(target.session_id) == "string" and target.session_id ~= ""
end

---@param raw any
---@return table|nil
local function normalize_target(raw)
  if type(raw) == "string" and raw ~= "" then
    return { session_id = raw }
  end
  if type(raw) ~= "table" then
    return nil
  end

  local session_id = raw.session_id or raw.id
  if type(raw.session) == "table" then
    session_id = session_id or raw.session.session_id or raw.session.id
  end
  if type(session_id) ~= "string" or session_id == "" then
    return nil
  end

  local workspace = raw.workspace
  if type(raw.session) == "table" and workspace == nil then
    workspace = raw.session.workspace
  end
  if type(workspace) ~= "string" or workspace == "" then
    workspace = nil
  end

  return {
    session_id = session_id,
    workspace = workspace,
  }
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

  local ok_state, state = pcall(require, "sidekick.cli.state")
  if ok_state and type(state) == "table" and type(state.get) == "function" then
    return function(payload, target)
      local encoded = vim.json and vim.json.encode(payload) or nil
      if type(encoded) ~= "string" or encoded == "" then
        return false, Adapter.error("INTERNAL_ERROR")
      end

      local attached = state.get({
        attached = true,
        name = "codex",
        session = target and target.session_id or nil,
      })
      if type(attached) ~= "table" or #attached == 0 then
        attached = state.get({
          attached = true,
          session = target and target.session_id or nil,
        })
      end
      local current = type(attached) == "table" and attached[1] or nil
      local session = current and current.session or nil
      if type(session) ~= "table" or type(session.send) ~= "function" then
        return false, Adapter.error("ADAPTER_UNAVAILABLE")
      end

      local wrote = pcall(function()
        session:send(encoded .. "\n")
      end)
      if not wrote then
        return false, Adapter.error("TRANSPORT_FAILED")
      end

      return true, {
        dispatched_items = type(payload) == "table" and type(payload.items) == "table" and #payload.items or nil,
      }
    end
  end
end

---@return table|nil
local function resolve_current_target()
  for _, module_name in ipairs(ENTRYPOINT_MODULES) do
    local ok, mod = pcall(require, module_name)
    if ok and type(mod) == "table" then
      for _, entrypoint in ipairs(TARGET_ENTRYPOINTS) do
        if type(mod[entrypoint]) == "function" then
          local called, value = pcall(mod[entrypoint])
          if called then
            local target = normalize_target(value)
            if target then
              return target
            end
          end
        end
      end
    end
  end

  local ok_state, state = pcall(require, "sidekick.cli.state")
  if ok_state and type(state) == "table" and type(state.get) == "function" then
    local attached = state.get({ attached = true, name = "codex" })
    if type(attached) == "table" and #attached == 0 then
      attached = state.get({ attached = true })
    end
    if type(attached) == "table" then
      for _, item in ipairs(attached) do
        local target = normalize_target({
          session_id = item and item.session and item.session.id or nil,
          workspace = item and item.session and item.session.cwd or nil,
        })
        if target then
          return target
        end
      end
    end
  end
end

---@param target? table
---@return boolean
function M.available(target)
  if resolve_sender() == nil then
    return false
  end
  if target == nil then
    return resolve_current_target() ~= nil
  end
  return valid_target(target)
end

---@return table|nil
function M.current_target()
  return resolve_current_target()
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
