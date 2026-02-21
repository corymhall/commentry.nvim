local Comments = require("commentry.comments")
local Config = require("commentry.config")
local Diffview = require("commentry.diffview")
local Util = require("commentry.util")

local M = {}
local initialized = false

local feature_modules = {
  "commentry.diffview",
  "commentry.comments",
}

---@alias commentry.command.Fn fun(args: vim.api.keyset.create_user_command.command_args, cmd_args: string)

---@type table<string, commentry.command.Fn>
M.commands = {}

---@param bufnr integer
---@return table
local function buffer_debug_info(bufnr)
  return {
    bufnr = bufnr,
    current = vim.api.nvim_get_current_buf(),
    name = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    buftype = vim.bo[bufnr].buftype,
    is_diff = vim.b[bufnr].commentry_diffview,
  }
end

---@param bufnr integer
local function maybe_attach_keymaps(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    Util.debug("Skipping keymap attach: invalid buffer", { bufnr = bufnr })
    return
  end
  local is_diff = vim.b[bufnr].commentry_diffview
  if is_diff == nil then
    local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, "commentry_diffview")
    if ok then
      is_diff = value
    end
  end
  if not is_diff then
    Util.debug("Skipping keymap attach: not a diffview buffer", buffer_debug_info(bufnr))
    return
  end
  if vim.b[bufnr].commentry_keymaps then
    Util.debug("Keymaps already attached", buffer_debug_info(bufnr))
    Comments.render_current_buffer()
    return
  end
  vim.b[bufnr].commentry_keymaps = true

  Util.debug("Attaching comment keymaps", buffer_debug_info(bufnr))

  vim.keymap.set("n", Config.keymaps.add_comment, function()
    Comments.add_comment()
  end, { buffer = bufnr, desc = "Commentry add comment" })

  local add_range_key = Config.keymaps.add_range_comment or Config.keymaps.add_comment
  vim.keymap.set("x", add_range_key, function()
    Comments.add_range_comment()
  end, { buffer = bufnr, desc = "Commentry add range comment" })

  vim.keymap.set("n", Config.keymaps.edit_comment, function()
    Comments.edit_comment()
  end, { buffer = bufnr, desc = "Commentry edit comment" })

  vim.keymap.set("n", Config.keymaps.delete_comment, function()
    Comments.delete_comment()
  end, { buffer = bufnr, desc = "Commentry delete comment" })

  vim.keymap.set("n", Config.keymaps.set_comment_type, function()
    Comments.set_comment_type()
  end, { buffer = bufnr, desc = "Commentry set comment type" })

  Comments.render_current_buffer()
end

function M.setup()
  if initialized then
    return
  end
  initialized = true

  M.register("open", function(_, cmd_args)
    if not Config.diffview.enabled then
      Util.warn("Diff view is disabled in config")
      return
    end
    local args = nil
    if type(cmd_args) == "string" and cmd_args ~= "" then
      args = vim.split(cmd_args, "%s+", { trimempty = true })
    end
    local ok, err = Diffview.open(args)
    if ok then
      return
    end
    if err == "no_changes" then
      Util.info("No local changes to review")
      return
    end
    if err == "not_git_repo" then
      Util.error("Current directory is not a git repository")
      return
    end
    if err == "git_status_failed" then
      Util.error("Failed to read git status")
      return
    end
    Util.error(err or "Failed to open diff view")
  end)

  M.register("list-comments", function()
    Comments.list_comments()
  end)

  M.register("add-range-comment", function()
    Comments.add_range_comment()
  end)

  M.register("set-comment-type", function()
    Comments.set_comment_type()
  end)

  for _, module_name in ipairs(feature_modules) do
    local ok, mod = pcall(require, module_name)
    if ok and type(mod.register_commands) == "function" then
      mod.register_commands(M.register)
    end
  end

  vim.api.nvim_create_user_command("CommentryDebugBuf", function()
    local bufnr = vim.api.nvim_get_current_buf()
    Util.info(vim.inspect(buffer_debug_info(bufnr)))
  end, { desc = "Commentry debug current buffer context" })

  vim.api.nvim_create_autocmd("User", {
    group = Config.augroup,
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.schedule(function()
        maybe_attach_keymaps(bufnr)
      end)
    end,
  })
end

---@param name string
---@param fn commentry.command.Fn
function M.register(name, fn)
  M.commands[name] = fn
end

---@param line string
function M.complete(line)
  M.setup()
  line = line:gsub("^%s*Commentry%s+", "")
  local prefix = line:match("^(%S*)") or ""
  local keys = vim.tbl_keys(M.commands)
  table.sort(keys)
  return vim.tbl_filter(function(key)
    return key:find(prefix, 1, true) == 1
  end, keys)
end

---@param line vim.api.keyset.create_user_command.command_args
function M.cmd(line)
  M.setup()
  local input = line.args or ""
  local parts = vim.split(input, "%s+", { trimempty = true })
  local name = parts[1] or ""
  local cmd = name ~= "" and M.commands[name] or nil
  if not cmd then
    if name == "" then
      Util.error("No command provided")
    else
      Util.error(("Unknown command: `%s`"):format(name))
    end
    return
  end
  local rest = table.concat(parts, " ", 2)
  cmd(line, rest)
end

return M
