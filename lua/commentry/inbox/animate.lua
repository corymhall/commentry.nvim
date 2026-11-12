local M = {}
local ns = vim.api.nvim_create_namespace("commentry.inbox.animate")
local active = {}

-- A redraw can replace the conversation while a fade is still running.
function M.clear(buf)
  if active[buf] then
    active[buf]()
  end
end

-- Optional decoration only. Never move text, focus, or the reply boundary.
function M.flash(buf, first, last)
  M.clear(buf)
  local ok, snacks = pcall(require, "snacks")
  if not ok or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local animate = snacks.animate
  if not animate or not animate.enabled({ buf = buf }) then
    return
  end
  local id = "commentry-flash:" .. buf
  local group = "CommentryInboxFlash" .. buf
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local accent = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
  local from, to = accent.bg or normal.fg, normal.bg
  if not from or not to then
    return
  end
  local mark = vim.api.nvim_buf_set_extmark(buf, ns, first - 1, 0, {
    end_row = math.min(last, vim.api.nvim_buf_line_count(buf)),
    hl_group = group,
    hl_eol = true,
    priority = 130,
  })
  local function cleanup()
    animate.del(id)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_del_extmark(buf, ns, mark)
    end
    active[buf] = nil
    vim.api.nvim_set_hl(0, group, {})
  end
  active[buf] = cleanup
  vim.api.nvim_set_hl(0, group, { bg = from })
  local function blend(progress)
    local color = 0
    for _, shift in ipairs({ 16, 8, 0 }) do
      local a = math.floor(from / 2 ^ shift) % 256
      local b = math.floor(to / 2 ^ shift) % 256
      color = color + math.floor(a + (b - a) * progress) * 2 ^ shift
    end
    return color
  end
  animate(0, 100, function(value, ctx)
    -- Snacks may already have scheduled a frame when a redraw cancels it.
    if active[buf] ~= cleanup then
      return
    end
    if ctx.done or not vim.api.nvim_buf_is_valid(buf) then
      cleanup()
      return
    end
    vim.api.nvim_set_hl(0, group, { bg = blend(value / 100) })
  end, { id = id, buf = buf, duration = { total = 650 } })
end

return M
