-- Standalone UI, embedded in the Go CLI so installed captures need no plugin path.
local options = vim.json.decode(table.concat(vim.fn.readfile(vim.env.COMMENTRY_CAPTURE_CONFIG), "\n"))
vim.cmd("silent! tabonly | silent! only | enew")
vim.o.laststatus = 2
vim.o.showmode = false
vim.o.ruler = false
vim.o.showcmd = false
vim.opt.fillchars:append({ eob = " " })
local body = vim.api.nvim_get_current_buf()
local body_win = vim.api.nvim_get_current_win()
vim.bo[body].buftype = "nofile"
vim.bo[body].bufhidden = "hide"
vim.bo[body].swapfile = false
vim.bo[body].filetype = "markdown"
vim.api.nvim_buf_set_name(body, "Commentry comment")
vim.wo[body_win].wrap = true
vim.wo[body_win].number = false
vim.wo[body_win].relativenumber = false
vim.wo[body_win].list = false
local preview, preview_win
local thread
local queued
local function header()
  vim.wo[body_win].winbar = " Comment / " .. vim.fn.fnamemodify(options.project, ":t"):gsub("%%", "%%%%")
  vim.wo[body_win].statusline = " Ctrl-s Save  Ctrl-d Save + queue  Ctrl-p Project  :q Cancel"
end
header()
if options.text ~= nil then
  vim.cmd("aboveleft split")
  preview, preview_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  -- A split initially shares its buffer with the body. Give it a fresh buffer.
  preview = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(preview_win, preview)
  vim.api.nvim_buf_set_lines(preview, 0, -1, false, vim.split(options.text, "\n", { plain = true }))
  vim.bo[preview].modifiable = false
  vim.bo[preview].bufhidden = "wipe"
  vim.wo[preview_win].winbar = " Captured text"
  vim.wo[preview_win].statusline = " Clipboard snapshot"
  vim.wo[preview_win].wrap = false
  vim.wo[preview_win].number = false
  vim.wo[preview_win].relativenumber = false
  vim.wo[preview_win].list = false
  vim.api.nvim_win_set_height(preview_win, math.max(2, math.min(8, math.floor(vim.o.lines / 3))))
  vim.api.nvim_set_current_win(body_win)
end
local function request(input)
  local result = vim
    .system({ options.executable, "--directory", options.directory, "rpc" }, {
      text = true,
      stdin = vim.json.encode(input),
    })
    :wait(15000)
  local ok, value = pcall(vim.json.decode, result.stdout or "")
  if result.code ~= 0 or not ok or type(value) ~= "table" or not value.ok then
    vim.notify(
      (ok and type(value) == "table" and value.error) or (result.stderr or "Unable to save comment"),
      vim.log.levels.ERROR
    )
    return nil
  end
  return value.result
end
local function save(queue)
  if not thread then
    local text = table.concat(vim.api.nvim_buf_get_lines(body, 0, -1, false), "\n")
    thread = request({ action = "create", project = options.project, body = text, text = options.text })
    if not thread then
      return
    end
    -- A queue failure must not create another thread when the user retries.
    vim.bo[body].modifiable = false
  end
  if queue then
    -- Retain the receipt so another Ctrl-d cannot replay uncertain delivery.
    queued = queued or request({ action = "queue", thread = thread })
    if not queued then
      return
    end
    if queued.delivery_error then
      vim.wo[body_win].statusline = " Saved / delivery failed. Inspect inbox. Ctrl-s Close"
      vim.notify(
        "Comment saved. " .. queued.delivery_error .. " Open the inbox to inspect delivery before retrying.",
        vim.log.levels.WARN
      )
      return
    end
  end
  vim.cmd("qa!")
end
for key, action in pairs({
  ["<C-s>"] = function()
    save(false)
  end,
  ["<C-d>"] = function()
    save(true)
  end,
  ["<C-p>"] = function()
    if thread then
      return
    end
    vim.ui.input({ prompt = "Project directory: ", default = options.project, completion = "dir" }, function(value)
      if value and value ~= "" then
        local path = vim.fn.fnamemodify(value, ":p")
        if vim.fn.isdirectory(path) == 0 then
          vim.notify("Choose an existing project directory", vim.log.levels.ERROR)
          return
        end
        options.project = path
        header()
      end
    end)
  end,
}) do
  vim.keymap.set({ "n", "i" }, key, action, { buffer = body })
end
vim.keymap.set("n", "q", function()
  vim.cmd("qa!")
end, { buffer = body, desc = "Cancel capture" })
vim.api.nvim_create_autocmd("QuitPre", {
  callback = function()
    vim.cmd("qa!")
  end,
  once = true,
})
vim.cmd("startinsert")

-- This editor process exists only for the capture. Keep its action hints
-- visible when a user's statusline plugin finishes loading after startup.
local function chrome()
  local ok, lualine = pcall(require, "lualine")
  if ok and type(lualine.hide) == "function" then
    lualine.hide({ place = { "statusline", "winbar" } })
  end
  vim.o.laststatus = 2
  header()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.wo[preview_win].winbar = " Captured text"
    vim.wo[preview_win].statusline = " Clipboard snapshot"
  end
end
vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", once = true, callback = chrome })
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(chrome)
  end,
})
chrome()
