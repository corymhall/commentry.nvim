local M = {}

local Config = require("commentry.config")

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
  vim.schedule(mark_view_buffers)
  return true, nil
end

---@return boolean
function M.mark_current_buffer()
  local context = M.current_file_context()
  if not context then
    return false
  end
  mark_buffer(context.bufnr)
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
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
      M.mark_current_buffer()
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
  }, nil
end

return M
