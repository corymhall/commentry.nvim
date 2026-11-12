local M = {}

-- Keep sizing, chrome and lifecycle in one place. The body is always a real
-- buffer, including the multiline Markdown composer.
function M.popup(opts)
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    require("commentry.util").error("Commentry requires nui.nvim. Add MunifTanjim/nui.nvim to your dependencies.")
    return
  end
  local Render = require("commentry.inbox.render")
  Render.highlights()
  local function dimensions()
    return {
      width = math.max(1, math.min(opts.width or 88, vim.o.columns - 8)),
      height = math.max(1, math.min(opts.height or 12, vim.o.lines - 6)),
    }
  end
  local size = dimensions()
  local function label(text)
    return " " .. Render.clip(text, math.max(1, size.width - 4)) .. " "
  end
  local popup = Popup({
    enter = true,
    relative = "editor",
    position = "50%",
    size = size,
    border = {
      style = "rounded",
      padding = { 0, 1 },
      text = {
        top = label(opts.title or "Commentry"),
        top_align = "left",
        bottom = label(opts.footer or "q close"),
        bottom_align = "right",
      },
    },
    buf_options = { buftype = "nofile", swapfile = false, filetype = opts.filetype or "text" },
    win_options = {
      wrap = true,
      linebreak = true,
      breakindent = true,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      spell = false,
      winbar = "",
      scrolloff = 2,
      winhighlight = "Normal:NormalFloat,FloatBorder:CommentryInboxBorder,FloatTitle:CommentryInboxAccent",
    },
  })
  popup:mount()
  -- NUI owns cleanup, including its separate padding/border window.
  local group = vim.api.nvim_create_augroup("CommentryPopup" .. popup.bufnr, { clear = true })
  local function cleanup()
    popup:unmount()
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(popup.winid),
    once = true,
    desc = "Dispose of Commentry popup chrome when its window closes",
    callback = function()
      vim.schedule(cleanup)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = popup.bufnr,
    once = true,
    desc = "Remove Commentry popup resize handlers",
    callback = function()
      vim.schedule(cleanup)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    desc = "Keep Commentry popup on screen",
    callback = function()
      if not popup.winid or not vim.api.nvim_win_is_valid(popup.winid) then
        return
      end
      size = dimensions()
      popup.border:set_text("top", label(opts.title or "Commentry"), "left")
      popup.border:set_text("bottom", label(opts.footer or "q close"), "right")
      popup:update_layout({ size = size, position = "50%" })
    end,
  })
  return popup
end

-- Statuslines and winbars interpret %, unlike ordinary buffer text.
local function escape(text)
  return text:gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end

function M.headers(view)
  if not vim.api.nvim_win_is_valid(view.list_win) then
    return
  end
  local Render = require("commentry.inbox.render")
  local unread = 0
  for _, thread in ipairs(view.threads) do
    unread = unread + (thread.unread and 1 or 0)
  end
  local scope = view.project and vim.fs.basename(view.project) or "All projects"
  local width = vim.api.nvim_win_get_width(view.list_win)
  vim.wo[view.list_win].winbar = "%#CommentryInboxTitle# Inbox %*%=%#CommentryInboxMuted#"
    .. #view.threads
    .. " / "
    .. unread
    .. " new "
  vim.wo[view.list_win].statusline = " " .. escape(Render.clip(scope .. " / " .. view.filter, math.max(1, width - 2)))
  if vim.api.nvim_win_is_valid(view.source_win) then
    vim.wo[view.source_win].winbar = "%#CommentryInboxTitle# Source and changes"
    vim.wo[view.source_win].statusline = " %#CommentryInboxMuted#za fold  gl sections  gf code%=%* %l/%L "
  end
  vim.wo[view.thread_win].winbar = "%#CommentryInboxTitle# Conversation %*%=%#CommentryInboxMuted#"
    .. view.delivery_mode
    .. " "
  vim.wo[view.thread_win].statusline = " %#CommentryInboxMuted#r reply  s send  za fold  ? help%=%*%m %l/%L "
end

return M
