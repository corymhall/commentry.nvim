local M = {}
local ns = vim.api.nvim_create_namespace("commentry.inbox.ui")

function M.highlights()
  for name, target in pairs({
    Title = "Title",
    Muted = "Comment",
    Accent = "Special",
    Selection = "Visual",
    Warning = "DiagnosticWarn",
    Added = "DiffAdd",
    Removed = "DiffDelete",
    Hunk = "DiffChange",
  }) do
    vim.api.nvim_set_hl(0, "CommentryInbox" .. name, { default = true, link = target })
  end
end

function M.clip(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local out = ""
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if vim.fn.strdisplaywidth(out .. char) > math.max(0, width - 3) then
      break
    end
    out = out .. char
  end
  return out .. "..."
end

function M.write(buf, contents, filetype)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, #contents > 0 and contents or { "" })
  vim.bo[buf].filetype = filetype
  vim.bo[buf].modifiable = false
end

function M.mark(buf, row, group, opts)
  local mark = vim.tbl_extend("force", { end_row = row + 1, hl_group = "CommentryInbox" .. group }, opts or {})
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, mark)
end

function M.list(view)
  local width = vim.api.nvim_win_get_width(view.list_win) - 3
  local rows = {}
  for _, thread in ipairs(view.threads) do
    rows[#rows + 1] = (thread.unread and " * " or "   ") .. M.clip(thread.title, width - 1)
  end
  M.write(view.list_buf, #rows > 0 and rows or { "  Your inbox is empty" }, "text")
  for index, thread in ipairs(view.threads) do
    local status = thread.resolved and "Resolved" or "Open"
    if view.outdated[thread.id] then
      status = status .. " / Outdated"
    end
    for _, item in ipairs(thread.queue) do
      if item.status == "failed" then
        status = status .. " / Failed"
        break
      end
      if item.status == "pending" or item.status == "claimed" then
        status = status .. " / " .. (item.status == "pending" and "Pending" or "Sent")
        break
      end
    end
    local location = thread.source.kind == "file" and vim.fs.basename(thread.source.path) .. ":" .. thread.source.first
      or thread.source.origin == "general" and "Project thread"
      or "Copied text"
    local metadata = "  " .. M.clip(status .. " / " .. location, width)
    local highlight = view.outdated[thread.id] and "CommentryInboxWarning" or "CommentryInboxMuted"
    vim.api.nvim_buf_set_extmark(view.list_buf, ns, index - 1, 0, {
      virt_lines = { { { metadata, highlight } }, { { "", "CommentryInboxMuted" } } },
    })
  end
end

function M.selection(view, row)
  if view.selection_mark then
    pcall(vim.api.nvim_buf_del_extmark, view.list_buf, ns, view.selection_mark)
  end
  view.selection_mark = vim.api.nvim_buf_set_extmark(view.list_buf, ns, row - 1, 0, {
    line_hl_group = "CommentryInboxSelection",
    virt_text = { { ">", "CommentryInboxAccent" } },
    virt_text_pos = "overlay",
    priority = 150,
  })
end

function M.source(view, thread, comparison)
  local source = thread.source
  local general = source.kind == "text" and source.origin == "general"
  local title = view.mode == "agent" and "Attached comparisons"
    or general and "Project conversation"
    or source.kind == "file" and source.path .. ":" .. source.first .. "-" .. source.last
    or "Captured text"
  local label = view.mode == "agent" and comparison.label
    or view.mode == "original" and "Original capture"
    or comparison.unavailable and "Outdated / file unavailable / original capture"
    or comparison.outdated and "Outdated / approximate comparison"
    or general and "No file or excerpt attached"
    or source.kind ~= "file" and "Original capture / no file anchor"
    or "Since comment / captured -> current"
  local rows = { " " .. title, " " .. label, "" }
  local old, new = comparison.first or 1, comparison.current_first or 1
  local marks, numbers = {}, {}
  for index, line in ipairs(comparison.lines) do
    local row = #rows
    if comparison.headings and comparison.headings[index] then
      marks[#marks + 1] = { row, "Title" }
    elseif comparison.filetype == "diff" and (not comparison.diff_rows or comparison.diff_rows[index]) then
      local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      if old_start then
        old = tonumber(old_start) + (comparison.first or 1) - 1
        new = tonumber(new_start) + (comparison.current_first or 1) - 1
        line = ("@@ -%d%s +%d%s @@"):format(
          old,
          old_count ~= "" and "," .. old_count or "",
          new,
          new_count ~= "" and "," .. new_count or ""
        )
        marks[#marks + 1] = { row, "Hunk" }
      elseif line:sub(1, 1) == "+" then
        numbers[#numbers + 1] = { row, ("     %4d "):format(new) }
        new = new + 1
        marks[#marks + 1] = { row, "Added" }
      elseif line:sub(1, 1) == "-" then
        numbers[#numbers + 1] = { row, ("%4d      "):format(old) }
        old = old + 1
        marks[#marks + 1] = { row, "Removed" }
      elseif line:sub(1, 1) == " " then
        numbers[#numbers + 1] = { row, ("%4d %4d "):format(old, new) }
        old, new = old + 1, new + 1
      end
    elseif source.kind == "file" and view.mode ~= "agent" then
      numbers[#numbers + 1] = { row, ("%4d  "):format(old) }
      if old >= source.first and old <= source.last then
        marks[#marks + 1] = { row, "Selection" }
      end
      old = old + 1
    end
    rows[#rows + 1] = line
  end
  M.write(view.source_buf, rows, comparison.filetype)
  M.mark(view.source_buf, 0, "Title")
  M.mark(view.source_buf, 1, comparison.outdated and "Warning" or "Muted")
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(view.source_buf, ns, mark[1], 0, { line_hl_group = "CommentryInbox" .. mark[2] })
  end
  for _, number in ipairs(numbers) do
    vim.api.nvim_buf_set_extmark(view.source_buf, ns, number[1], 0, {
      virt_text = { { number[2], "CommentryInboxMuted" } },
      virt_text_pos = "inline",
    })
  end
end

function M.conversation(view, thread)
  local status = thread.resolved and "Resolved" or "Open"
  if view.outdated[thread.id] then
    status = status .. " / Outdated"
  end
  local rows =
    { thread.title, status .. " / " .. (thread.unread and "Unread / " or "") .. #thread.messages .. " messages", "" }
  for _, item in ipairs(thread.queue) do
    if item.status == "failed" then
      vim.list_extend(rows, vim.split("Request failed: " .. (item.error or "Delivery failed"), "\n", { plain = true }))
      vim.list_extend(rows, { "Inspect partial work, then press t to retry.", "" })
    end
  end
  if #(thread.attachments or {}) > 0 then
    rows[#rows + 1] = #thread.attachments .. " code locations / gl choose / gf go to code"
    for _, attachment in ipairs(thread.attachments) do
      rows[#rows + 1] = attachment.label .. " / " .. attachment.source.path .. ":" .. attachment.source.first
    end
    rows[#rows + 1] = ""
  end
  local comparison = thread.comparisons[#thread.comparisons]
  if comparison then
    vim.list_extend(rows, {
      "Comparisons attached: " .. #thread.comparisons,
      comparison.label .. " / " .. comparison.author,
      "Press c and choose agent to view all.",
      "",
    })
  end
  local authors = {}
  for _, message in ipairs(thread.messages) do
    local at = message.at:match("T(%d%d:%d%d)") or message.at
    if message.at:sub(1, 10) ~= os.date("!%Y-%m-%d") then
      at = message.at:sub(1, 10) .. " " .. at
    end
    authors[#authors + 1] = { row = #rows, length = #message.author }
    rows[#rows + 1] = message.author .. "  " .. at
    vim.list_extend(rows, vim.split(message.body, "\n", { plain = true }))
    vim.list_extend(rows, { "", "" })
  end
  M.write(view.thread_buf, rows, "markdown")
  M.mark(view.thread_buf, 0, "Title")
  M.mark(view.thread_buf, 1, view.outdated[thread.id] and "Warning" or "Muted")
  for _, author in ipairs(authors) do
    M.mark(view.thread_buf, author.row, "Muted")
    M.mark(view.thread_buf, author.row, "Accent", { end_row = author.row, end_col = author.length, priority = 110 })
  end
end

return M
