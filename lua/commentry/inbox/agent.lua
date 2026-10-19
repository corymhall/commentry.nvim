local Store = require("commentry.inbox.store")
local Util = require("commentry.util")
local M = {}

local function delivery_message(sent)
  if sent == 0 then
    return "Nothing new to send. There are no pending requests."
  end
  return "Sent " .. sent .. " request(s)."
end

function M.send(id, mode)
  local result, err
  if mode == "queue" then
    result, err = Store.enqueue(id)
  elseif mode == "steer" then
    local thread
    thread, err = Store.get(id)
    if not thread then
      return nil, err
    end
    result, err = Store.command({ "agent", "--project", thread.project, "steer", id })
  else
    return nil, "Unknown send mode"
  end
  if result and result.delivery_error then
    Util.warn("Request saved. " .. result.delivery_error)
  end
  return result, err
end

-- Compare human message IDs with immutable delivery snapshots. Agent replies
-- alone must not start another round of work when sending a project's inbox.
local function needs_delivery(thread)
  if thread.resolved then
    return false
  end
  local latest
  for _, message in ipairs(thread.messages) do
    if message.author == "You" then
      latest = message.id
    end
  end
  if not latest then
    return false
  end
  for _, request in ipairs(thread.queue) do
    local encoded = request.message:match("\n({.*})$")
    local ok, payload = pcall(vim.json.decode, encoded or "")
    if ok and type(payload) == "table" and type(payload.messages) == "table" then
      for _, message in ipairs(payload.messages) do
        if
          message.id == latest
          and (request.status == "claimed" or request.status == "complete" or request.status == "failed")
        then
          return false
        end
      end
    end
  end
  return true
end

function M.send_all(project)
  if not project or project == "" then
    return nil, "Send all requires a project"
  end
  local threads, err = Store.list(project)
  if not threads then
    return nil, err
  end
  local result = { sent = 0, queued = 0, skipped = 0, failed = 0, errors = {} }
  local ids = {}
  for _, thread in ipairs(threads) do
    if needs_delivery(thread) then
      local request, send_err = Store.enqueue(thread.id, nil, { defer_delivery = true })
      if not request or request.delivery_error then
        result.failed = result.failed + 1
        result.errors[#result.errors + 1] = thread.title
          .. ": "
          .. (send_err or (request and request.delivery_error) or "Send failed")
      elseif request.status == "pending" then
        result.queued = result.queued + 1
        ids[#ids + 1] = request.id
      elseif request.skipped then
        result.skipped = result.skipped + 1
      else
        result.sent = result.sent + 1
      end
    else
      result.skipped = result.skipped + 1
    end
  end
  if #ids > 0 then
    local args = { "agent", "--project", project, "dispatch-batch" }
    for _, id in ipairs(ids) do
      vim.list_extend(args, { "--queue-id", id })
    end
    local receipt, dispatch_err = Store.command(args)
    if receipt then
      result.sent = result.sent + receipt.sent
      result.queued = result.queued - receipt.sent
    end
    if not receipt or receipt.delivery_error then
      result.failed = result.failed + result.queued
      result.queued = 0
      result.errors[#result.errors + 1] = dispatch_err
        or (receipt and receipt.delivery_error)
        or "Batch delivery failed"
    end
  end
  return result
end

function M.status(project)
  return Store.command({ "agent", "--project", project, "status" })
end

function M.choose(project)
  local discovery, err = Store.command({ "agent", "--project", project, "list" })
  if not discovery then
    Util.error(err)
    return
  end
  if #discovery.sessions == 0 then
    Util.warn(
      "No running agents found in this project. Load integrations/rex/agents.lua in Rex. "
        .. table.concat(discovery.errors, " ")
    )
    return
  end
  vim.ui.select(discovery.sessions, {
    prompt = "Attach existing agent",
    format_item = function(item)
      return item.harness .. " / " .. (item.name or item.rex_block) .. " / " .. item.rex_block:sub(-8)
    end,
  }, function(choice)
    if not choice then
      return
    end
    local result, attach_err = Store.command({ "agent", "--project", project, "attach", choice.id })
    if not result then
      Util.error(attach_err)
    elseif result.delivery_error then
      Util.warn("Session selected. " .. result.delivery_error)
    else
      Util.info(
        delivery_message(result.sent) .. " Attached to " .. choice.harness .. " / " .. (choice.name or choice.rex_block)
      )
    end
  end)
end

function M.controls(project)
  local status, err = M.status(project)
  if not status then
    Util.error(err)
    return
  end
  if status.state == "detached" then
    M.choose(project)
    return
  end
  vim.ui.select({ "Focus existing terminal", "Deliver pending requests", "Choose another session", "Detach" }, {
    prompt = (status.agent.name or status.agent.rex_block) .. " / " .. status.state,
  }, function(choice)
    if not choice then
      return
    end
    if choice == "Choose another session" then
      M.choose(project)
      return
    end
    local action = choice == "Detach" and "detach" or (choice == "Deliver pending requests" and "dispatch" or "focus")
    local result, control_err = Store.command({ "agent", "--project", project, action })
    if not result then
      Util.error(control_err)
    elseif action == "dispatch" then
      Util.info(delivery_message(result.sent))
    end
  end)
end

return M
