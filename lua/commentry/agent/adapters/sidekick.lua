local Adapter = require("commentry.agent.adapter")
local Payload = require("commentry.agent.payload")

local M = {}

---@return table|nil
local function cli()
  local ok, loaded = pcall(require, "sidekick.cli")
  if not ok or type(loaded) ~= "table" or type(loaded.send) ~= "function" then
    return nil
  end
  return loaded
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

---@return boolean
function M.available()
  return cli() ~= nil
end

---@param payload any
---@return boolean ok, commentry.AgentError? err, table? details
function M.send(payload)
  local sidekick = cli()
  if not sidekick then
    return false, Adapter.error("ADAPTER_UNAVAILABLE")
  end

  local encoded = compact_payload(payload)
  if not encoded then
    return false, Adapter.error("INTERNAL_ERROR")
  end

  local text = {}
  for _, line in ipairs(vim.split(encoded, "\n", { plain = true })) do
    text[#text + 1] = { { line } }
  end

  local opts = {
    text = text,
    submit = true,
  }
  local called = pcall(sidekick.send, opts)
  if not called then
    return false, Adapter.error("TRANSPORT_FAILED")
  end

  return true,
    nil,
    {
      delegated = true,
      dispatched_items = type(payload) == "table" and type(payload.items) == "table" and #payload.items or nil,
    }
end

return M
