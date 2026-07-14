local Adapter = require("commentry.agent.adapter")
local Comments = require("commentry.comments")
local Diffview = require("commentry.diffview")
local Payload = require("commentry.agent.payload")
local Sidekick = require("commentry.agent.adapters.sidekick")

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

---@param payload table
---@param target table
---@param details? table
---@return table
local function success(payload, target, details)
  local dispatched_items = #payload.items
  if type(details) == "table" and type(details.dispatched_items) == "number" then
    dispatched_items = details.dispatched_items
  end

  return {
    ok = true,
    code = "OK",
    target = public_target(target),
    adapter = "sidekick",
    delegated = type(details) == "table" and details.delegated == true,
    dispatched_items = dispatched_items,
  }
end

---@return table|nil
local function resolve_target()
  if type(Sidekick) ~= "table" or type(Sidekick.send) ~= "function" then
    return nil
  end
  return { send = Sidekick.send }
end

---@param opts table
---@return table|nil, table
local function build_send_context(opts)
  local file_context = opts.file_context
  local file_err = nil
  if type(Diffview.current_file_context) ~= "function" then
    return nil, fail("INTERNAL_ERROR", "No active review context available.")
  end
  if type(file_context) ~= "table" then
    file_context, file_err = Diffview.current_file_context()
  end
  if type(file_context) ~= "table" or type(file_context.view) ~= "table" then
    return nil, fail("INTERNAL_ERROR", file_err or "No active review context available.")
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
    return nil, fail("INTERNAL_ERROR", context_err or file_err or "No active review context available.")
  end

  local context_id = comments_context_id or review_context.context_id
  if type(context_id) ~= "string" or context_id == "" then
    return nil, fail("INTERNAL_ERROR", "No active review context available.")
  end

  local items = {}
  if type(Comments.reconcile_review) == "function" then
    Comments.reconcile_review(view)
  end
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
      revision_anchors = review_context.revision_anchors,
    },
    items = items,
    provenance = {
      root = review_context.root,
    },
  })

  return {
    payload = payload,
  }, nil
end

---@param opts? table
---@return table
function M.send_current_review(opts)
  opts = opts or {}
  local prepared, prep_err = build_send_context(opts)
  if not prepared then
    return prep_err
  end

  local target = resolve_target()
  if not target then
    return fail("ADAPTER_UNAVAILABLE", "Sidekick adapter is unavailable. Ensure Sidekick is installed and loaded.")
  end

  local ok, err, details = Adapter.send(prepared.payload, target)
  if not ok then
    return {
      ok = false,
      code = err.code,
      message = err.message,
      retryable = err.retryable,
    }
  end

  return success(prepared.payload, target, details)
end

---@param opts? table
---@param cb? fun(result: table)
function M.send_current_review_async(opts, cb)
  cb = type(cb) == "function" and cb or function() end
  cb(M.send_current_review(opts))
end

return M
