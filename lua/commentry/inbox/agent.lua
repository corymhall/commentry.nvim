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
