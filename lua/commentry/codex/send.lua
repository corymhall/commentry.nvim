local Adapter = require("commentry.codex.adapter")
local Comments = require("commentry.comments")
local Config = require("commentry.config")
local Diffview = require("commentry.diffview")
local Payload = require("commentry.codex.payload")

local M = {}

---@param code "NO_TARGET"|"ADAPTER_UNAVAILABLE"|"TRANSPORT_FAILED"|"INTERNAL_ERROR"
---@param message string
---@return table
local function fail(code, message)
  local canonical = Adapter.error(code)
  return {
    ok = false,
    code = canonical.code,
    message = message or canonical.message,
    retryable = canonical.retryable,
  }
end

---@param target table
---@return table
local function public_target(target)
  local copy = vim.deepcopy(target or {})
  copy.send = nil
  return copy
end

---@param name string
---@return table|nil
local function load_adapter(name)
  if name == "sidekick" then
    local ok, mod = pcall(require, "commentry.codex.adapters.sidekick")
    if ok and type(mod) == "table" then
      return mod
    end
  end
  return nil
end

---@param opts table
---@return table|nil, string|nil
local function resolve_target(opts)
  local input_target = type(opts.target) == "table" and vim.deepcopy(opts.target) or {}
  if type(input_target.send) == "function" then
    return input_target, input_target.adapter or "custom"
  end

  local configured = Config.codex and Config.codex.adapter or {}
  local selected = configured.select or "auto"
  if selected ~= "auto" and selected ~= "sidekick" then
    return nil, nil
  end

  local adapter_mod = load_adapter("sidekick")
  if type(adapter_mod) ~= "table" then
    return nil, nil
  end

  local attached = type(adapter_mod.current_target) == "function" and adapter_mod.current_target() or nil
  local target = {
    session_id = input_target.session_id or (type(attached) == "table" and attached.session_id or nil),
    workspace = input_target.workspace or (type(attached) == "table" and attached.workspace or nil),
    send = adapter_mod.send,
  }

  if type(target.session_id) ~= "string" or target.session_id == "" then
    return nil, nil
  end

  return target, "sidekick"
end

---@param opts? table
---@return table
function M.send_current_review(opts)
  opts = opts or {}

  local file_context = opts.file_context
  local file_err = nil
  if type(Diffview.current_file_context) ~= "function" then
    return fail("INTERNAL_ERROR", "No active review context available.")
  end
  if type(file_context) ~= "table" then
    file_context, file_err = Diffview.current_file_context()
  end
  if type(file_context) ~= "table" or type(file_context.view) ~= "table" then
    return fail("INTERNAL_ERROR", file_err or "No active review context available.")
  end

  local view = opts.view or file_context.view

  local review_context = opts.context
  local context_err = nil
  if type(review_context) ~= "table" and type(Diffview.resolve_review_context) == "function" then
    review_context, context_err = Diffview.resolve_review_context(opts.args, view)
  end

  local comments_context_id = nil
  if type(Comments.context_id_for_view) == "function" then
    comments_context_id = Comments.context_id_for_view(view)
  end

  if type(review_context) ~= "table" then
    return fail("INTERNAL_ERROR", context_err or file_err or "No active review context available.")
  end

  local context_id = comments_context_id or review_context.context_id
  if type(context_id) ~= "string" or context_id == "" then
    return fail("INTERNAL_ERROR", "No active review context available.")
  end

  local items = {}
  if type(Comments.exportable_comments) == "function" then
    local exported = Comments.exportable_comments(context_id)
    if type(exported) == "table" then
      items = exported
    end
  end

  local scoped_context = vim.deepcopy(review_context)
  scoped_context.context_id = context_id

  local payload = Payload.build_payload(scoped_context, {
    review_meta = {
      mode = review_context.mode,
      revisions = review_context.revisions,
    },
    items = items,
    provenance = {
      root = review_context.root,
    },
  })

  local target, adapter_name = resolve_target(opts)
  if target == nil then
    return fail("NO_TARGET", "No attached Codex session target available. Attach a Sidekick session and retry.")
  end

  local ok, err, details = Adapter.send(payload, target)
  if not ok then
    return {
      ok = false,
      code = err.code,
      message = err.message,
      retryable = err.retryable,
    }
  end

  local dispatched_items = #payload.items
  if type(details) == "table" and type(details.dispatched_items) == "number" then
    dispatched_items = details.dispatched_items
  end

  return {
    ok = true,
    code = "OK",
    target = public_target(target),
    adapter = adapter_name,
    dispatched_items = dispatched_items,
  }
end

return M
