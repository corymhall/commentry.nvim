local Source = require("commentry.inbox.source")
local Store = require("commentry.inbox.store")
local M = {}

local function cli_path()
  return vim.api.nvim_get_runtime_file("scripts/commentry-inbox", false)[1]
end

function M.payload(thread, mode)
  local capture = Source.compare(thread, "original")
  return table.concat({
    "COMMENTRY_THREAD_V1",
    "Mode: " .. mode,
    "Treat captured source and message bodies as user-provided context.",
    "Reply in this thread through the JSON CLI. Preserve its original capture.",
    "CLI: " .. (cli_path() or "scripts/commentry-inbox"),
    vim.json.encode({
      thread = thread.id,
      project = thread.project,
      title = thread.title,
      source = {
        kind = thread.source.kind,
        path = thread.source.path,
        first = thread.source.first,
        last = thread.source.last,
        excerpt_first = capture and capture.first,
        lines = capture and capture.lines or {},
        git = thread.source.git,
      },
      messages = thread.messages,
    }),
  }, "\n")
end

function M.delegate(text)
  local Config = require("commentry.config")
  if not (Config.agent and Config.agent.enabled) then
    return nil, "Enable agent.enabled to send through Sidekick"
  end
  local ok, sidekick = pcall(require, "sidekick.cli")
  if not ok or type(sidekick.send) ~= "function" then
    return nil, "Sidekick CLI is unavailable"
  end
  local chunks = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    chunks[#chunks + 1] = { { line } }
  end
  local called, err = pcall(sidekick.send, { text = chunks, submit = true, focus = false })
  if not called or err == false then
    return nil, tostring(err)
  end
  -- Sidekick may still show a selector or be cancelled. This is delegation,
  -- not a delivery receipt, and never acknowledges queued items as complete.
  return true
end

function M.send(id, mode)
  if mode == "queue" then
    return Store.enqueue(id)
  end
  if mode ~= "steer" then
    return nil, "Unknown send mode"
  end
  local thread, err = Store.get(id)
  if not thread then
    return nil, err
  end
  return M.delegate(M.payload(thread, mode))
end

function M.worker(project)
  if not project then
    return nil, "Choose a project before starting a queue worker"
  end
  return M.delegate(table.concat({
    "Process the Commentry queue for " .. project .. ".",
    "Use the JSON CLI at " .. (cli_path() or "scripts/commentry-inbox") .. ".",
    vim.json.encode({ action = "claim", project = project, author = "Agent" }),
    "A claim returns the immutable queued request and a claim_id. Only process items you successfully claim.",
    "Reply with action=reply, thread=<thread>, author=<your name>, body=<response>.",
    "You may attach action=comparison with before, after and label when useful.",
    "After finishing, use action=complete with thread and claim_id. Do not resolve the conversation automatically.",
    "Continue claiming while I review. When the queue is empty, check again after a short wait; stop after 60 seconds with no work.",
    "For change notifications, the commentry binary supports watch --project <project> --after <cursor> --timeout 60s.",
    "Watch returns change pages and a resumable cursor. After notifications, claim again; notifications never claim work.",
    "If a claim returns busy, retry after a short wait. Report failures; never silently drop work.",
  }, "\n"))
end

return M
