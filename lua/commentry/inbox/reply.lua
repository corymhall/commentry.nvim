local Store = require("commentry.inbox.store")
local Util = require("commentry.util")
local M = {}

-- Session-local drafts survive thread switches and closing/reopening the inbox.
-- Keep the displayed history with a dirty draft so refreshes cannot replace
-- edits or move its save boundary while the user is writing.
local drafts = {}

function M.remember(view)
  local reply = view.reply
  if reply and vim.api.nvim_buf_is_valid(view.thread_buf) then
    if vim.bo[view.thread_buf].modified then
      reply.lines = vim.api.nvim_buf_get_lines(view.thread_buf, 0, -1, false)
      drafts[reply.id] = reply
    else
      drafts[reply.id] = nil
    end
  end
end

function M.prepare(view, thread, history)
  M.remember(view)
  local reply = drafts[thread.id]
  if not reply then
    local prompt = thread.inbox and "Reply / :write save"
      or thread.pending and "Pending review / ge edit / gd discard / s send"
      or "Reply / :write save / s send"
    local prefix = vim.list_extend(vim.deepcopy(history), { prompt, "" })
    reply = {
      id = thread.id,
      project = thread.project,
      inbox = thread.inbox,
      incoming = thread.incoming,
      prefix = prefix,
      lines = vim.deepcopy(prefix),
    }
    reply.lines[#reply.lines + 1] = ""
  end
  view.reply = reply
  return reply.lines, drafts[thread.id] ~= nil
end

function M.unsaved(view, project, id)
  M.remember(view)
  for _, reply in pairs(drafts) do
    if (not project or reply.project == project) and (not id or reply.id == id) then
      Util.warn("Save the reply with :write before sending")
      return true
    end
  end
  return false
end

local function history_unchanged(view)
  return view.reply
    and vim.deep_equal(vim.api.nvim_buf_get_lines(view.thread_buf, 0, #view.reply.prefix, false), view.reply.prefix)
end

function M.focus(view, quote)
  vim.api.nvim_set_current_win(view.thread_win)
  if not history_unchanged(view) then
    Util.warn("Conversation history cannot be edited. Undo those changes before replying.")
    return
  end
  if quote then
    local tail = vim.api.nvim_buf_get_lines(view.thread_buf, #view.reply.prefix, -1, false)
    local lines = {}
    if table.concat(tail, ""):find("%S") then
      lines[1] = ""
    else
      vim.api.nvim_buf_set_lines(view.thread_buf, #view.reply.prefix, -1, false, {})
    end
    for _, line in ipairs(quote) do
      lines[#lines + 1] = "> " .. line
    end
    vim.list_extend(lines, { "", "" })
    vim.api.nvim_buf_set_lines(view.thread_buf, -1, -1, false, lines)
  end
  local last = vim.api.nvim_buf_line_count(view.thread_buf)
  vim.api.nvim_win_set_cursor(
    view.thread_win,
    { last, #vim.api.nvim_buf_get_lines(view.thread_buf, last - 1, last, false)[1] }
  )
  vim.cmd("normal! zb")
  vim.cmd.startinsert({ bang = true })
end

function M.save(view)
  if not history_unchanged(view) then
    Util.warn("Conversation history cannot be edited. Undo those changes, then :write the reply below it.")
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(view.thread_buf, #view.reply.prefix, -1, false)
  while #lines > 0 and not lines[#lines]:find("%S") do
    table.remove(lines)
  end
  while #lines > 0 and not lines[1]:find("%S") do
    table.remove(lines, 1)
  end
  local body = table.concat(lines, "\n")
  if body ~= "" then
    local event, err = Store.update(view.reply.id, { kind = "reply", body = body })
    if not event then
      Util.error(err or "Reply could not be saved")
      return false
    end
    Util.info(view.reply.inbox and "Reply saved to shared inbox." or "Reply saved. Press s to send.")
  end
  drafts[view.reply.id] = nil
  vim.bo[view.thread_buf].modified = false
  view.reply = nil
  return true
end

return M
