local M = {}

local Config = require("commentry.config")
local hover_ns = vim.api.nvim_create_namespace("commentry-hover-preview")
local hover_attached = {}

local function mark_buffer(bufnr)
  if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_set_var, bufnr, "commentry_diffview", true)
  end
end

---@return string|nil
local function git_root()
  local output = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local root = output[1]
  if type(root) ~= "string" or root == "" then
    return nil
  end
  return root
end

---@param root string
---@return boolean|nil, string|nil
local function has_local_changes(root)
  local output = vim.fn.systemlist({ "git", "-C", root, "status", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    return nil, "git_status_failed"
  end
  return #output > 0, nil
end

---@param args? string[]|string
---@return boolean
local function is_empty_args(args)
  if args == nil then
    return true
  end
  if type(args) == "string" then
    return args == ""
  end
  if type(args) == "table" then
    return #args == 0
  end
  return true
end

local function mark_view_buffers()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return
  end
  local view = lib.get_current_view()
  if type(view) ~= "table" then
    return
  end
  local entry = view.cur_entry
  if type(entry) ~= "table" or type(entry.layout) ~= "table" then
    return
  end
  for _, slot in pairs(entry.layout) do
    local file = slot and slot.file or nil
    local bufnr = file and file.bufnr or nil
    mark_buffer(bufnr)
  end
end

local function sync_comments_for_view()
  local ok, comments = pcall(require, "commentry.comments")
  if not ok then
    return
  end
  if type(comments.load_current_view) == "function" then
    comments.load_current_view()
  end
  if type(comments.render_current_buffer) == "function" then
    comments.render_current_buffer()
  end
  if type(comments.refresh_hover_preview) == "function" then
    comments.refresh_hover_preview()
  end
end

---@param bufnr integer
local function is_diff_buffer(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local is_diff = vim.b[bufnr].commentry_diffview
  if is_diff == nil then
    local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, "commentry_diffview")
    if ok then
      is_diff = value
    end
  end
  return is_diff == true
end

local function refresh_hover_for_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_diff_buffer(bufnr) then
    M.clear_hover_preview(bufnr)
    return
  end
  local ok, comments = pcall(require, "commentry.comments")
  if not ok or type(comments.refresh_hover_preview) ~= "function" then
    M.clear_hover_preview(bufnr)
    return
  end
  comments.refresh_hover_preview()
end

---@param bufnr integer
local function ensure_hover_autocmd(bufnr)
  if type(bufnr) ~= "number" or hover_attached[bufnr] then
    return
  end
  hover_attached[bufnr] = true
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold" }, {
    group = Config.augroup,
    buffer = bufnr,
    callback = function()
      refresh_hover_for_current_buffer()
    end,
  })
end

---@return boolean
function M.is_available()
  return pcall(require, "diffview")
end

---@param args? string[]|string
---@return boolean, string|nil
function M.open(args)
  local ok, diffview = pcall(require, "diffview")
  if not ok then
    return false, "diffview.nvim is required"
  end
  if is_empty_args(args) then
    local root = git_root()
    if not root then
      return false, "not_git_repo"
    end
    local changed, err = has_local_changes(root)
    if changed == nil then
      return false, err
    end
    if not changed then
      return false, "no_changes"
    end
  end
  if type(args) == "string" then
    args = { args }
  end
  diffview.open(args or {})
  vim.schedule(function()
    mark_view_buffers()
    sync_comments_for_view()
  end)
  return true, nil
end

---@return boolean
function M.mark_current_buffer()
  local context = M.current_file_context()
  if not context then
    return false
  end
  mark_buffer(context.bufnr)
  ensure_hover_autocmd(context.bufnr)
  return true
end

function M.setup()
  if not Config.diffview.auto_attach then
    return
  end
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewViewPostLayout",
    callback = function()
      mark_view_buffers()
      vim.schedule(sync_comments_for_view)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
      M.mark_current_buffer()
      vim.schedule(sync_comments_for_view)
    end,
  })
end

---@return any|nil, string|nil
function M.get_current_view()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return nil, "diffview.nvim is required"
  end
  return lib.get_current_view(), nil
end

---@return table|nil, string|nil
function M.current_file_context()
  local view, err = M.get_current_view()
  if not view then
    return nil, err
  end

  local entry = view.cur_entry
  if type(entry) ~= "table" or type(entry.layout) ~= "table" then
    return nil, "diffview has no active file entry"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local side = nil
  for _, key in ipairs({ "a", "b", "c", "d" }) do
    local slot = entry.layout[key]
    if slot and slot.file and slot.file.bufnr == bufnr then
      side = key
      break
    end
  end

  if not side then
    return nil, "current buffer is not a diffview file buffer"
  end

  local line_side = side == "a" and "base" or side == "b" and "head" or nil
  if not line_side then
    return nil, ("unsupported diffview side: %s"):format(side)
  end

  return {
    file_path = entry.path,
    line_number = vim.api.nvim_win_get_cursor(0)[1],
    line_side = line_side,
    bufnr = bufnr,
    view = view,
  },
    nil
end

---@param bufnr integer
---@param comments commentry.DraftComment[]
function M.render_comment_markers(bufnr, comments)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, Config.ns, 0, -1)

  if type(comments) ~= "table" then
    return
  end

  local counts = {}
  for _, comment in ipairs(comments) do
    if type(comment) == "table" and type(comment.line_number) == "number" then
      counts[comment.line_number] = (counts[comment.line_number] or 0) + 1
    end
  end

  for line_number, count in pairs(counts) do
    local label = count == 1 and "[c]" or ("[c:%d]"):format(count)
    local line = math.max(line_number - 1, 0)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, Config.ns, line, 0, {
      virt_text = { { label, "Comment" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
end

---@param bufnr integer
function M.clear_hover_preview(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, hover_ns, 0, -1)
end

---@param bufnr integer
---@param line_number integer
---@param comments commentry.DraftComment[]
function M.render_hover_preview(bufnr, line_number, comments)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.clear_hover_preview(bufnr)
  if type(line_number) ~= "number" or line_number < 1 then
    return
  end
  if type(comments) ~= "table" or #comments == 0 then
    return
  end

  local virt_lines = {}
  for _, comment in ipairs(comments) do
    if type(comment) == "table" and type(comment.body) == "string" and comment.body ~= "" then
      local body = comment.body:gsub("\n", " ")
      virt_lines[#virt_lines + 1] = { { ("[comment] %s"):format(body), "Comment" } }
    end
  end
  if #virt_lines == 0 then
    return
  end

  local line = math.max(line_number - 1, 0)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, hover_ns, line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    hl_mode = "combine",
  })
end

return M
