local Adapter = require("commentry.codex.adapter")
local Payload = require("commentry.codex.payload")

local M = {}

-- Compatibility strategy:
-- 1) Prefer explicit codex-oriented entrypoints when available.
-- 2) Fallback to sidekick CLI state/session APIs used by current upstream sidekick.nvim.
-- This keeps send semantics stable across sidekick runtime variants.
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

---@param payload any
---@return string|nil
local function compact_payload(payload)
  local text = Payload.render_compact(payload)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  return text
end

---@return table|nil, table|nil
local function codex_session_states()
  local ok_state, state = pcall(require, "sidekick.cli.state")
  if not ok_state or type(state) ~= "table" or type(state.get) ~= "function" then
    return nil, nil
  end

  local listed = state.get({ name = "codex" })
  if type(listed) ~= "table" then
    return nil, state
  end

  local sessions = {}
  for _, item in ipairs(listed) do
    local session = type(item) == "table" and item.session or nil
    if type(session) == "table" and type(session.id) == "string" and session.id ~= "" then
      sessions[#sessions + 1] = item
    end
  end

  return sessions, state
end

---@param state_item table
---@return table|nil
local function target_from_state_item(state_item)
  if type(state_item) ~= "table" then
    return nil
  end
  return normalize_target({
    session_id = state_item and state_item.session and state_item.session.id or nil,
    workspace = state_item and state_item.session and state_item.session.cwd or nil,
  })
end

---@param state_mod table
---@param state_item table
---@return table|nil, string|nil
local function attach_state_target(state_mod, state_item)
  if type(state_item) ~= "table" then
    return nil, "invalid session selection"
  end

  local attached_state = state_item
  if type(state_mod) == "table" and type(state_mod.attach) == "function" then
    local called, next_state = pcall(state_mod.attach, state_item, { show = false, focus = false })
    if not called or type(next_state) ~= "table" then
      return nil, "unable to attach selected Codex session target"
    end
    attached_state = next_state
  end

  local target = target_from_state_item(attached_state)
  if target then
    return target, nil
  end

  return nil, "selected Codex session is invalid"
end

---@return fun(payload:any, target:table):boolean,table?,table? | nil
local function resolve_sender()
  -- Prefer direct attached-session transport to guarantee "send this to attached
  -- session" semantics independent of sidekick higher-level context validation.
  local ok_state, state = pcall(require, "sidekick.cli.state")
  if ok_state and type(state) == "table" and type(state.get) == "function" then
    return function(payload, target)
      local encoded = compact_payload(payload)
      if type(encoded) ~= "string" then
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

      return true,
        {
          dispatched_items = type(payload) == "table" and type(payload.items) == "table" and #payload.items or nil,
        }
    end
  end

  for _, module_name in ipairs(ENTRYPOINT_MODULES) do
    local ok, mod = pcall(require, module_name)
    if ok and type(mod) == "table" then
      for _, entrypoint in ipairs(ENTRYPOINTS) do
        if type(mod[entrypoint]) == "function" then
          return function(payload, target)
            local encoded = compact_payload(payload)
            if type(encoded) ~= "string" then
              return false, Adapter.error("INTERNAL_ERROR")
            end
            return mod[entrypoint](encoded, target)
          end
        end
      end
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

  -- sidekick.nvim mainline fallback target discovery.
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

---@param state_item table
---@return string
local function format_state_item(state_item)
  local session_id = state_item and state_item.session and state_item.session.id or "unknown"
  local cwd = state_item and state_item.session and state_item.session.cwd or nil
  if type(cwd) == "string" and cwd ~= "" then
    return ("%s (%s)"):format(session_id, cwd)
  end
  return session_id
end

---@return string
local function current_cwd()
  local cwd = vim.fn.getcwd()
  if type(cwd) ~= "string" or cwd == "" then
    return ""
  end
  return vim.fs.normalize(cwd)
end

---@param value any
---@return string
local function normalize_path(value)
  if type(value) ~= "string" or value == "" then
    return ""
  end
  return vim.fs.normalize(value)
end

---@param states table[]
---@return table[]
local function cwd_matching_states(states)
  local matches = {}
  local cwd = current_cwd()
  if cwd == "" then
    return matches
  end
  for _, state_item in ipairs(states or {}) do
    local session_cwd = normalize_path(state_item and state_item.session and state_item.session.cwd or nil)
    if session_cwd ~= "" and session_cwd == cwd then
      matches[#matches + 1] = state_item
    end
  end
  return matches
end

---@param cb fun(choice:table|nil)
local function select_with_sidekick_picker(cb)
  local ok_picker, picker = pcall(require, "sidekick.cli.ui.select")
  if not ok_picker or type(picker) ~= "table" or type(picker.select) ~= "function" then
    cb(nil)
    return false
  end

  picker.select({
    auto = false,
    filter = { name = "codex", started = true },
    cb = function(choice)
      cb(choice)
    end,
  })
  return true
end

---@param cb fun(target:table|nil, err_code:string|nil, err_message:string|nil)
function M.resolve_target_async(cb)
  cb = type(cb) == "function" and cb or function() end

  local states, state_mod = codex_session_states()
  if type(states) ~= "table" or #states == 0 then
    cb(nil, "NO_TARGET", "No attached Codex session target available. Attach a Sidekick session and retry.")
    return
  end

  local function resolve_selected(state_item)
    local target, attach_err = attach_state_target(state_mod, state_item)
    if not target then
      cb(nil, "ADAPTER_UNAVAILABLE", attach_err or "Unable to attach selected Codex session target.")
      return
    end
    cb(target, nil, nil)
  end

  if #states == 1 then
    resolve_selected(states[1])
    return
  end

  local cwd_matches = cwd_matching_states(states)
  if #cwd_matches == 1 then
    resolve_selected(cwd_matches[1])
    return
  end

  local used_sidekick_picker = select_with_sidekick_picker(function(choice)
    if not choice then
      cb(nil, "NO_TARGET", "No Codex session selected.")
      return
    end
    resolve_selected(choice)
  end)
  if used_sidekick_picker then
    return
  end

  vim.ui.select(states, {
    prompt = "Select Codex session target:",
    format_item = format_state_item,
  }, function(choice)
    if not choice then
      cb(nil, "NO_TARGET", "No Codex session selected.")
      return
    end
    resolve_selected(choice)
  end)
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
