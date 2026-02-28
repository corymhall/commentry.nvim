local Comments = require("commentry.comments")
local Config = require("commentry.config")
local Diffview = require("commentry.diffview")
local Util = require("commentry.util")

local M = {}
local initialized = false

local fallback_keymap_defaults = {
  add_comment = "mc",
  add_range_comment = "mc",
  edit_comment = "me",
  delete_comment = "md",
  set_comment_type = "mt",
  toggle_file_reviewed = "mr",
  next_unreviewed_file = "]r",
  send_to_codex = "ms",
  list_comments = "ml",
}

local keymap_defaults = vim.deepcopy(Config.default_keymaps or fallback_keymap_defaults)

local keymap_empty_disable_allowed = {
  toggle_file_reviewed = true,
  next_unreviewed_file = true,
}

local feature_modules = {
  "commentry.diffview",
  "commentry.comments",
}

---@alias commentry.command.Fn fun(args: vim.api.keyset.create_user_command.command_args, cmd_args: string)

---@type table<string, commentry.command.Fn>
M.commands = {}

---@param result table
local function report_send_failure(result)
  local code = type(result.code) == "string" and result.code or "UNKNOWN"
  local message = type(result.message) == "string" and result.message or "Failed to send current review."
  local base = ("Codex send failed (%s): %s"):format(code, message)
  if code == "NO_TARGET" then
    Util.error({
      base,
      "Attach a Sidekick session, then retry: :Commentry send-to-codex",
    })
    return
  end
  if code == "ADAPTER_UNAVAILABLE" then
    Util.error({
      base,
      "Ensure the configured adapter is installed and available, then retry the command.",
    })
    return
  end
  if code == "TRANSPORT_FAILED" then
    local retry_hint = result.retryable and "This failure is retryable; try the command again." or "Review adapter logs before retrying."
    Util.error({ base, retry_hint })
    return
  end
  if code == "INTERNAL_ERROR" then
    Util.error({
      base,
      "Confirm an active review context exists and run the command again.",
    })
    return
  end
  Util.error(base)
end

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

---@param value unknown
---@return string|nil
local function non_empty_keymap(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

---@param keymaps unknown
---@param action string
---@return string|nil
local function resolve_keymap(keymaps, action)
  local configured = type(keymaps) == "table" and keymaps[action] or nil
  if configured == "" and keymap_empty_disable_allowed[action] then
    return nil
  end
  local resolved = non_empty_keymap(configured)

  if action == "add_range_comment" and not resolved then
    local add_comment = type(keymaps) == "table" and keymaps.add_comment or nil
    resolved = non_empty_keymap(add_comment)
  end

  return resolved or keymap_defaults[action]
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
  if not is_diff and type(Diffview.current_file_context) == "function" then
    local context = Diffview.current_file_context()
    if type(context) == "table" and context.bufnr == bufnr then
      is_diff = true
      pcall(vim.api.nvim_buf_set_var, bufnr, "commentry_diffview", true)
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

  local function send_to_codex_keymap()
    local send_cmd = M.commands["send-to-codex"]
    if type(send_cmd) ~= "function" then
      Util.error("Codex send command is unavailable.")
      return
    end
    send_cmd({}, "")
  end

  local keymap_specs = {
    { action = "add_comment", mode = "n", desc = "Commentry add comment", handler = Comments.add_comment },
    { action = "add_range_comment", mode = "x", desc = "Commentry add range comment", handler = Comments.add_range_comment },
    { action = "edit_comment", mode = "n", desc = "Commentry edit comment", handler = Comments.edit_comment },
    { action = "delete_comment", mode = "n", desc = "Commentry delete comment", handler = Comments.delete_comment },
    { action = "set_comment_type", mode = "n", desc = "Commentry set comment type", handler = Comments.set_comment_type },
    {
      action = "toggle_file_reviewed",
      mode = "n",
      desc = "Commentry toggle file reviewed",
      handler = Comments.toggle_file_reviewed,
    },
    {
      action = "next_unreviewed_file",
      mode = "n",
      desc = "Commentry jump next unreviewed file",
      handler = Comments.next_unreviewed_file,
    },
    {
      action = "send_to_codex",
      mode = "n",
      desc = "Commentry send to codex",
      handler = send_to_codex_keymap,
    },
    {
      action = "list_comments",
      mode = "n",
      desc = "Commentry list comments",
      handler = Comments.list_comments,
    },
  }

  for _, spec in ipairs(keymap_specs) do
    local key = resolve_keymap(Config.keymaps, spec.action)
    if key then
      local handler = spec.handler
      vim.keymap.set(spec.mode, key, function()
        handler()
      end, { buffer = bufnr, desc = spec.desc })
    end
  end

  Comments.render_current_buffer()
end

--- setup.
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
    local review_context = nil
    if type(Diffview.resolve_review_context) == "function" then
      review_context = Diffview.resolve_review_context(args)
    end
    local ok, err = Diffview.open(args, review_context)
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

  M.register("toggle-file-reviewed", function()
    Comments.toggle_file_reviewed()
  end)

  M.register("next-unreviewed", function()
    Comments.next_unreviewed_file()
  end)

  M.register("export", function(_, cmd_args)
    Comments.export_comments(cmd_args)
  end)

  M.register("debug-store", function()
    -- Keep this as a user-visible command so persistence/debug context can be
    -- inspected without requiring `debug = true` or custom instrumentation.
    if type(Comments.debug_store_context) ~= "function" then
      Util.error("Store debug helper unavailable.")
      return
    end
    local info, err = Comments.debug_store_context()
    if not info then
      Util.error(err or "Unable to resolve store context.")
      return
    end
    Util.info(vim.inspect(info))
  end)

  M.register("send-to-codex", function(_, _cmd_args)
    if not (Config.codex and Config.codex.enabled) then
      Util.error({
        "Codex integration is disabled.",
        "Enable `codex.enabled = true` and retry :Commentry send-to-codex.",
      })
      return
    end

    local ok_orchestrator, orchestrator = pcall(require, "commentry.codex.orchestrator")
    if not ok_orchestrator then
      Util.error({
        "Codex orchestrator is unavailable.",
        "Check plugin installation/runtimepath and retry :Commentry send-to-codex.",
      })
      return
    end

    local function handle_result(result)
      if type(result) ~= "table" then
        Util.error("Codex send failed: invalid orchestrator response.")
        return
      end
      if not result.ok then
        report_send_failure(result)
        return
      end

      local adapter = type(result.adapter) == "string" and result.adapter or "unknown"
      local dispatched_items = type(result.dispatched_items) == "number" and result.dispatched_items or 0
      Util.info(("Sent %d review item(s) to Codex via %s."):format(dispatched_items, adapter))
    end

    if type(orchestrator.send_current_review_async) == "function" then
      orchestrator.send_current_review_async({}, handle_result)
      return
    end
    if type(orchestrator.send_current_review) ~= "function" then
      Util.error({
        "Codex orchestrator is unavailable.",
        "Check plugin installation/runtimepath and retry :Commentry send-to-codex.",
      })
      return
    end

    handle_result(orchestrator.send_current_review({}))
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
    desc = "Commentry attach diffview-local keymaps",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if type(Diffview.mark_current_buffer) == "function" then
        Diffview.mark_current_buffer()
      end
      maybe_attach_keymaps(bufnr)
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
