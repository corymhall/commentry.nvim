local Render = require("commentry.inbox.render")
local M = {}

-- Search is navigation only. Previewing or cancelling must never acknowledge
-- human activity, resolve a thread, or submit work.
function M.open(threads, choose)
  if #threads == 0 then
    require("commentry.util").info("No conversations in this scope")
    return
  end
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.ui.select(threads, {
      prompt = "Find conversation",
      format_item = function(thread)
        return thread.title .. " / " .. Render.status(thread)
      end,
    }, function(thread)
      if thread then
        choose(thread.id)
      end
    end)
    return
  end
  local items = {}
  for _, thread in ipairs(threads) do
    local status = Render.status(thread)
    local rows = { "# " .. thread.title, "", status, "" }
    if thread.review then
      vim.list_extend(rows, vim.split(thread.review.summary, "\n", { plain = true }))
      rows[#rows + 1] = ""
    end
    for _, message in ipairs(thread.messages) do
      rows[#rows + 1] = "## " .. message.author
      vim.list_extend(rows, vim.split(message.body, "\n", { plain = true }))
      rows[#rows + 1] = ""
    end
    items[#items + 1] = {
      text = thread.title .. " " .. status .. " " .. (thread.source.path or "") .. " " .. table.concat(rows, " "),
      title = thread.title,
      thread_id = thread.id,
      status = status,
      unread = thread.unread,
      preview = { text = table.concat(rows, "\n"), ft = "markdown", loc = false },
    }
  end
  snacks.picker({
    title = "Commentry conversations",
    items = items,
    preview = "preview",
    format = function(item)
      return {
        { item.unread and "* " or "  ", "Special" },
        { item.title, "Title" },
        { "  " .. item.status, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        choose(item.thread_id)
      end
    end,
  })
end

return M
