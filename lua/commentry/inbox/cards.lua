-- Diffview cards are presentation of shared inbox threads. They never own or
-- persist a second comment model.
local Config = require("commentry.config")
local M = {}

local function wrap(line, width)
  local rows, row, size = {}, "", 0
  for _, char in ipairs(vim.fn.split(line, "\\zs")) do
    local cells = vim.fn.strdisplaywidth(char)
    if size + cells > width and row ~= "" then
      rows[#rows + 1], row, size = row, "", 0
    end
    row, size = row .. char, size + cells
  end
  rows[#rows + 1] = row
  return rows
end

local function card(item, cfg)
  local thread = item.thread
  local message = thread.messages[#thread.messages]
  local review = #thread.messages == 1 and thread.review
  local author = review and review.author or message.author
  local body = review and review.summary or message.body
  local range = "L" .. item.first .. (item.last > item.first and "-L" .. item.last or "")
  local header = author .. " · " .. range
  local rows = { { { "  ┌ ", "CommentryInboxCardBorder" }, { header, "CommentryInboxAccent" } } }
  local lines = {}
  for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
    vim.list_extend(lines, wrap(line, math.max(12, cfg.max_width - 10)))
  end
  for index = 1, math.min(#lines, cfg.max_body_lines) do
    rows[#rows + 1] = { { "  ┆ ", "CommentryInboxCardBorder" }, { lines[index], "CommentryInboxCardBody" } }
  end
  if #lines > cfg.max_body_lines then
    rows[#rows + 1] = { { "  ┆ ", "CommentryInboxCardBorder" }, { "…  gC open thread", "CommentryInboxMuted" } }
  end
  rows[#rows + 1] = {
    {
      "  └" .. string.rep("─", math.max(8, math.min(cfg.max_width - 2, vim.fn.strdisplaywidth(header) + 2))),
      "CommentryInboxCardBorder",
    },
  }
  return rows
end

function M.draw(buf, ns, items)
  for name, link in pairs({ CardBorder = "Comment", CardBody = "Comment", CardRange = "CursorLine" }) do
    vim.api.nvim_set_hl(0, "CommentryInbox" .. name, { default = true, link = link })
  end
  local config = Config.diffview
  local cfg = {
    max_width = math.max(24, math.floor(config.comment_cards.max_width)),
    max_body_lines = math.max(1, math.floor(config.comment_cards.max_body_lines)),
  }
  table.sort(items, function(a, b)
    if a.first ~= b.first then
      return a.first < b.first
    end
    if a.thread.created_at ~= b.thread.created_at then
      return a.thread.created_at < b.thread.created_at
    end
    return a.thread.id < b.thread.id
  end)
  local groups, decorated = {}, {}
  for _, item in ipairs(items) do
    local row = item.first - 1
    groups[row] = groups[row] or {}
    if #groups[row] > 0 then
      groups[row][#groups[row] + 1] = { { " ", "CommentryInboxCardBody" } }
    end
    vim.list_extend(groups[row], card(item, cfg))
    if config.comment_ranges.enabled then
      for line = item.first, item.last do
        if not decorated[line] then
          local sign = item.first == item.last and "•"
            or line == item.first and "╭"
            or line == item.last and "╰"
            or "┆"
          vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
            sign_text = sign,
            sign_hl_group = "CommentryInboxCardBorder",
            line_hl_group = config.comment_ranges.line_highlight and "CommentryInboxCardRange" or nil,
            priority = 90,
          })
          decorated[line] = true
        end
      end
    end
  end
  for row, lines in pairs(groups) do
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
      virt_lines = lines,
      virt_lines_above = false,
      hl_mode = "combine",
      virt_text = config.comment_cards.show_markers and { { "[comment]", "CommentryInboxMuted" } } or nil,
      virt_text_pos = "eol",
    })
  end
end

return M
