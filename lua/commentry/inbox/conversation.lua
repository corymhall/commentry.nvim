local M = {}
local ns = vim.api.nvim_create_namespace("commentry.inbox.conversation")
local generated_highlights = {}

local function highlight(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

-- Derive chrome from the active theme, while retaining explicit user overrides.
function M.highlights()
  local normal, menu = highlight("Normal"), highlight("Pmenu")
  local background = menu.bg or highlight("CursorLine").bg or highlight("NormalFloat").bg or normal.bg
  local foreground = normal.fg or menu.fg
  local groups = {
    MessageHeader = { fg = foreground, bg = background, bold = true, italic = false },
    MessageHuman = {
      fg = highlight("CommentryInboxHuman").fg or foreground,
      bg = background,
      bold = true,
      italic = false,
    },
    MessageAgent = {
      fg = highlight("DiagnosticInfo").fg or highlight("CommentryInboxAgent").fg or foreground,
      bg = background,
      bold = true,
      italic = false,
    },
    MessageTime = { fg = foreground, bg = background, bold = false, italic = false },
    MessageFoldText = { fg = foreground, bg = highlight("Folded").bg or normal.bg, bold = false, italic = false },
  }
  for suffix, value in pairs(groups) do
    -- Folded may be italic in the theme. Replace its attributes for our chunks.
    value.nocombine = true
    local name = "CommentryInbox" .. suffix
    local current = vim.api.nvim_get_hl(0, { name = name, link = true })
    if next(current) == nil or vim.deep_equal(current, generated_highlights[name]) then
      vim.api.nvim_set_hl(0, name, value)
      generated_highlights[name] = vim.api.nvim_get_hl(0, { name = name, link = true })
    end
  end
end

local function header_parts(message, line)
  return vim.fn.toupper(line:sub(1, message.label_length)), vim.trim(line:sub(message.label_length + 1))
end

-- Remember departures from the automatic fold policy, rather than every fold
-- state. A previous latest message can then fold when a newer reply arrives.
function M.remember(view)
  local presentation = view.message_presentation
  if not presentation or not vim.api.nvim_win_is_valid(view.thread_win) then
    return
  end
  view.message_folds = view.message_folds or {}
  local choices = view.message_folds[presentation.thread_id] or {}
  vim.api.nvim_win_call(view.thread_win, function()
    for _, message in ipairs(presentation.messages) do
      local closed = vim.fn.foldclosed(message.first) == message.first
      if closed ~= message.default_closed then
        choices[message.id] = closed
      else
        choices[message.id] = nil
      end
    end
  end)
  view.message_folds[presentation.thread_id] = choices
end

function M.decorate(view, presentation)
  local buf = view.thread_buf
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not presentation then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local function mark(row, group, opts)
    if row < count then
      vim.api.nvim_buf_set_extmark(
        buf,
        ns,
        row,
        0,
        vim.tbl_extend("force", {
          end_row = row + 1,
          hl_group = "CommentryInbox" .. group,
          priority = 100,
        }, opts or {})
      )
    end
  end
  mark(0, "Title")
  mark(1, presentation.status_group)
  mark(presentation.reply_row, "Accent")
  for _, row in ipairs(presentation.headings) do
    mark(row, "Title")
  end
  local width = vim.api.nvim_win_get_width(view.thread_win)
  local spacious = vim.api.nvim_win_get_height(view.thread_win) >= 22
  local closed = vim.api.nvim_win_call(view.thread_win, function()
    local folds = {}
    for _, message in ipairs(presentation.messages) do
      folds[message.first] = vim.fn.foldclosed(message.first) == message.first
    end
    return folds
  end)
  for index, message in ipairs(presentation.messages) do
    local row = message.first - 1
    if row < count and not closed[message.first] then
      local previous = presentation.messages[index - 1]
      if previous and closed[previous.first] then
        -- Separate a compact folded run from the next expanded message.
        -- Keep this visual only so saved history and reply boundaries do not move.
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
          virt_lines = { { { string.rep(" ", width), "Normal" } } },
          virt_lines_above = true,
        })
      end
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      local label, time = header_parts(message, line)
      local role = message.human and "CommentryInboxMessageHuman" or "CommentryInboxMessageAgent"
      local heading = "  " .. label .. "  "
      local padding = string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(heading .. time)))
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        line_hl_group = "CommentryInboxMessageHeader",
        virt_text = {
          { heading, role },
          { time, "CommentryInboxMessageTime" },
          { padding, "CommentryInboxMessageHeader" },
        },
        virt_text_pos = "overlay",
        hl_mode = "replace",
        priority = 120,
      })
      if spacious and message.first < count then
        -- Anchor padding inside the body so it disappears with a closed fold.
        vim.api.nvim_buf_set_extmark(buf, ns, message.first, 0, {
          virt_lines = { { { string.rep(" ", width), "CommentryInboxMessageHeader" } } },
          virt_lines_above = true,
        })
      end
    end
  end
end

function M.apply(view, presentation)
  if vim.api.nvim_win_is_valid(view.thread_win) then
    vim.api.nvim_win_call(view.thread_win, function()
      vim.wo.foldmethod, vim.wo.foldenable, vim.wo.foldcolumn = "manual", true, "0"
      vim.wo.foldminlines = 0
      vim.wo.foldtext = "get(b:commentry_message_summaries, string(v:foldstart), getline(v:foldstart))"
      vim.cmd("normal! zE")
      local summaries = {}
      local choices = presentation and view.message_folds and view.message_folds[presentation.thread_id] or {}
      for _, message in ipairs(presentation and presentation.messages or {}) do
        local label, time = header_parts(message, message.header)
        summaries[tostring(message.first)] = {
          { " + ", "CommentryInboxMessageFoldText" },
          { " " .. label .. " ", message.human and "CommentryInboxMessageHuman" or "CommentryInboxMessageAgent" },
          { " " .. time .. " / " .. message.summary, "CommentryInboxMessageFoldText" },
        }
        if message.last > message.first then
          vim.cmd(message.first .. "," .. message.last .. "fold")
          local closed = choices[message.id]
          if closed == nil then
            closed = message.default_closed
          end
          if not closed then
            vim.cmd(message.first .. "foldopen")
          end
        end
      end
      vim.b[view.thread_buf].commentry_message_summaries = summaries
    end)
  end
  view.message_presentation = presentation
  M.decorate(view, presentation)
end

return M
