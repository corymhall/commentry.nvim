local M = {}
local Reply = require("commentry.inbox.reply")
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
    local status = thread.pending and "Pending review" or thread.resolved and "Resolved" or "Open"
    if view.outdated[thread.id] then
      status = status .. " / Outdated"
    end
    for _, item in ipairs(thread.queue) do
      if item.status == "failed" then
        status = status .. " / Failed"
        break
      end
      if item.status == "pending" or item.status == "claimed" then
        status = status
          .. " / "
          .. (
            item.status == "pending" and "Queued"
            or item.acknowledged_at and "Fetched / Awaiting answer"
            or "Submitted / Not acknowledged"
          )
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

function M.remember_source(view)
  if
    not view.source_sections
    or not view.source_win
    or view.source_fold_win ~= view.source_win
    or not vim.api.nvim_win_is_valid(view.source_win)
  then
    return
  end
  view.source_folds = view.source_folds or {}
  local folds = view.source_folds[view.source_thread] or {}
  vim.api.nvim_win_call(view.source_win, function()
    for _, section in ipairs(view.source_sections) do
      folds[section.id] = vim.fn.foldclosed(section.first) == section.first
    end
  end)
  view.source_folds[view.source_thread] = folds
end

function M.source_section(view, row)
  for _, section in ipairs(view.source_sections or {}) do
    if row >= section.first and row <= section.last then
      return section
    end
  end
end

-- Separate file snippets can have different languages. Native syntax regions
-- preserve their highlighting without making section headings part of a file.
local function source_syntax(buf, sections)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("syntax clear")
    local included = {}
    for index, section in ipairs(sections) do
      local filetype = section.comparison.filetype
      if filetype ~= "text" and filetype ~= "diff" and filetype:match("^[%w_]+$") then
        local cluster = "CommentrySource_" .. filetype
        if included[filetype] == nil then
          vim.b.current_syntax = nil
          included[filetype] = pcall(vim.cmd, "syntax include @" .. cluster .. " syntax/" .. filetype .. ".vim")
        end
        if included[filetype] and section.last >= section.first + 3 then
          vim.cmd(
            ("syntax region CommentrySource%d start=/\\%%%dl/ end=/\\%%%dl/ keepend contains=@%s"):format(
              index,
              section.first + 3,
              section.last + 1,
              cluster
            )
          )
        end
      end
    end
    vim.b.current_syntax = "commentry_inbox_source"
  end)
end

function M.source(view, thread, sections)
  M.remember_source(view)
  local same = view.source_thread == thread.id
  local changed_primary = same and view.source_primary ~= (sections[1] and sections[1].id)
  local rows, marks, numbers = {}, {}, {}
  for _, section in ipairs(sections) do
    local comparison, source = section.comparison, section.source
    section.first = #rows + 1
    marks[#marks + 1] = { #rows, "Title" }
    rows[#rows + 1] = section.title
    marks[#marks + 1] = { #rows, comparison.unavailable and "Warning" or "Muted" }
    rows[#rows + 1] = section.detail
    rows[#rows + 1] = ""
    local old, new = comparison.first or 1, comparison.current_first or 1
    for _, line in ipairs(comparison.lines) do
      local row = #rows
      if comparison.filetype == "diff" then
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
      elseif source and source.kind == "file" then
        numbers[#numbers + 1] = { row, ("%4d  "):format(old) }
        if old >= source.first and old <= source.last then
          marks[#marks + 1] = { row, "Selection" }
        end
        old = old + 1
      end
      rows[#rows + 1] = line
    end
    section.last = #rows
    rows[#rows + 1] = ""
  end
  M.write(view.source_buf, rows, "text")
  source_syntax(view.source_buf, sections)
  for _, mark in ipairs(marks) do
    M.mark(view.source_buf, mark[1], mark[2])
    vim.api.nvim_buf_set_extmark(view.source_buf, ns, mark[1], 0, { line_hl_group = "CommentryInbox" .. mark[2] })
  end
  for _, number in ipairs(numbers) do
    vim.api.nvim_buf_set_extmark(view.source_buf, ns, number[1], 0, {
      virt_text = { { number[2], "CommentryInboxMuted" } },
      virt_text_pos = "inline",
    })
  end
  if view.source_win and vim.api.nvim_win_is_valid(view.source_win) then
    vim.api.nvim_win_call(view.source_win, function()
      vim.wo.foldmethod, vim.wo.foldenable, vim.wo.foldcolumn = "manual", true, "1"
      vim.wo.foldtext = "getline(v:foldstart) . '  [' . (v:foldend - v:foldstart) . ' lines]'"
      vim.cmd("normal! zE")
      local folds = view.source_folds and view.source_folds[thread.id] or {}
      for _, section in ipairs(sections) do
        if section.last > section.first then
          vim.cmd(section.first .. "," .. section.last .. "fold")
          local closed = folds[section.id]
          if changed_primary then
            if section == sections[1] then
              closed = false
            elseif section.id == view.source_primary then
              closed = true
            end
          end
          if closed == nil then
            closed = section.collapsed
          end
          if not closed then
            vim.cmd(section.first .. "foldopen")
          end
        end
      end
      if not same then
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
      end
    end)
  end
  view.source_sections, view.source_thread = sections, thread.id
  view.source_primary = sections[1] and sections[1].id
  view.source_fold_win = view.source_win
end

function M.conversation(view, thread)
  if view.reply and view.reply.id == thread.id and vim.bo[view.thread_buf].modified then
    return
  end
  local status = thread.pending and "Pending review" or thread.resolved and "Resolved" or "Open"
  if view.outdated[thread.id] then
    status = status .. " / Outdated"
  end
  local rows =
    { thread.title, status .. " / " .. (thread.unread and "Unread / " or "") .. #thread.messages .. " messages", "" }
  for _, item in ipairs(thread.queue) do
    if item.status == "claimed" then
      vim.list_extend(rows, {
        item.acknowledged_at and "Fetched by agent / Awaiting answer"
          or "Submitted / Agent has not acknowledged receipt",
        "Press gn to notify again or explicitly hand off.",
        "",
      })
    end
    if item.status == "failed" then
      vim.list_extend(rows, vim.split("Request failed: " .. (item.error or "Delivery failed"), "\n", { plain = true }))
      vim.list_extend(rows, { "Inspect partial work, then press t to retry.", "" })
    end
  end
  local review = thread.review
  if review then
    rows[#rows + 1] = "Current review / " .. review.author
    vim.list_extend(rows, vim.split(review.summary, "\n", { plain = true }))
    vim.list_extend(rows, { "", "Discussion", "" })
  end
  local authors = {}
  local original_fold
  for index, message in ipairs(thread.messages) do
    local at = message.at:match("T(%d%d:%d%d)") or message.at
    if message.at:sub(1, 10) ~= os.date("!%Y-%m-%d") then
      at = message.at:sub(1, 10) .. " " .. at
    end
    authors[#authors + 1] = { row = #rows, length = #message.author }
    rows[#rows + 1] = (review and index == 1 and message.author == review.author and "Original finding / " or "")
      .. message.author
      .. "  "
      .. at
    local first = #rows
    vim.list_extend(rows, vim.split(message.body, "\n", { plain = true }))
    if review and index == 1 and message.author == review.author then
      original_fold = { first, #rows }
    end
    vim.list_extend(rows, { "", "" })
  end
  local dirty
  rows, dirty = Reply.prepare(view, thread, rows)
  M.write(view.thread_buf, rows, "markdown")
  vim.bo[view.thread_buf].modifiable = not thread.pending
  vim.bo[view.thread_buf].modified = dirty
  if dirty then
    -- Restored drafts retain their displayed history. Folds from the previous
    -- thread must not hide a reply or unrelated messages in that frozen text.
    if view.thread_win and vim.api.nvim_win_is_valid(view.thread_win) then
      vim.api.nvim_win_call(view.thread_win, function()
        vim.cmd("normal! zE")
      end)
    end
    return
  end
  if view.thread_win and vim.api.nvim_win_is_valid(view.thread_win) then
    vim.api.nvim_win_call(view.thread_win, function()
      local same = view.review_thread == thread.id
      local closed = not same or vim.fn.foldclosed(view.review_original_first or 1) ~= -1
      vim.wo.foldmethod, vim.wo.foldenable = "manual", true
      vim.wo.foldtext = "getline(v:foldstart) . ' / za expand'"
      vim.cmd("normal! zE")
      if original_fold and original_fold[2] > original_fold[1] then
        vim.cmd(original_fold[1] .. "," .. original_fold[2] .. "fold")
        if not closed then
          vim.cmd(original_fold[1] .. "foldopen")
        end
      end
      view.review_original_first = original_fold and original_fold[1]
      view.review_thread = thread.id
    end)
  end
  M.mark(view.thread_buf, #view.reply.prefix - 2, "Accent")
  M.mark(view.thread_buf, 0, "Title")
  M.mark(view.thread_buf, 1, view.outdated[thread.id] and "Warning" or "Muted")
  for _, author in ipairs(authors) do
    M.mark(view.thread_buf, author.row, "Muted")
    M.mark(view.thread_buf, author.row, "Accent", { end_row = author.row, end_col = author.length, priority = 110 })
  end
end

return M
