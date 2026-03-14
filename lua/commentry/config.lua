---@class commentry.config: commentry.Config
local M = {}
local Util = require("commentry.util")

M.ns = vim.api.nvim_create_namespace("commentry")

---@class commentry.Keymaps
---@field add_comment string
---@field add_range_comment string
---@field edit_comment string
---@field delete_comment string
---@field set_comment_type string
---@field toggle_file_reviewed string
---@field next_unreviewed_file string
---@field send_to_codex string
---@field list_comments string

---@class commentry.StoreConfig
---@field filename string

---@class commentry.DiffviewConfig
---@field enabled boolean
---@field prefer string
---@field auto_attach boolean
---@field comment_cards commentry.DiffviewCommentCardsConfig
---@field comment_ranges commentry.DiffviewCommentRangesConfig

---@class commentry.DiffviewCommentCardsConfig
---@field max_width integer
---@field max_body_lines integer
---@field show_markers boolean

---@class commentry.DiffviewCommentRangesConfig
---@field enabled boolean
---@field line_highlight boolean

---@class commentry.CodexAdapterConfig
---@field select string
---@field fallback string|nil

---@class commentry.CodexBehaviorConfig
---@field open string

---@class commentry.CodexConfig
---@field enabled boolean
---@field adapter commentry.CodexAdapterConfig
---@field behavior commentry.CodexBehaviorConfig

---@class commentry.LogConfig
---@field level "error"|"warn"|"info"|"debug"
---@field sink "notify"|"echo"|"file"
---@field file string|nil

---@class commentry.DiagnosticsConfig
---@field open_style "split"|"vsplit"|"float"

---@class commentry.Config
---@field debug boolean
---@field keymaps commentry.Keymaps
---@field comment_types string[]
---@field default_comment_type string
---@field store commentry.StoreConfig
---@field diffview commentry.DiffviewConfig
---@field codex commentry.CodexConfig
---@field log commentry.LogConfig
---@field diagnostics commentry.DiagnosticsConfig
local defaults = {
  debug = false,
  keymaps = {
    add_comment = "mc",
    add_range_comment = "mc",
    edit_comment = "me",
    delete_comment = "md",
    set_comment_type = "mt",
    toggle_file_reviewed = "mr",
    next_unreviewed_file = "]r",
    send_to_codex = "ms",
    list_comments = "ml",
  },
  comment_types = { "note", "suggestion", "issue", "praise" },
  default_comment_type = "note",
  store = {
    filename = "commentry.json",
  },
  diffview = {
    enabled = true,
    prefer = "diffview.nvim",
    auto_attach = true,
    comment_cards = {
      max_width = 76,
      max_body_lines = 6,
      show_markers = true,
    },
    comment_ranges = {
      enabled = true,
      line_highlight = true,
    },
  },
  codex = {
    enabled = false,
    adapter = {
      select = "auto",
      fallback = nil,
    },
    behavior = {
      open = "reuse",
    },
  },
  log = {
    level = "warn",
    sink = "notify",
    file = nil,
  },
  diagnostics = {
    open_style = "split",
  },
}

-- Canonical defaults shared across setup normalization and runtime fallback.
M.default_keymaps = vim.deepcopy(defaults.keymaps)

local keymap_keys = {
  "add_comment",
  "add_range_comment",
  "edit_comment",
  "delete_comment",
  "set_comment_type",
  "toggle_file_reviewed",
  "next_unreviewed_file",
  "send_to_codex",
  "list_comments",
}

local keymap_empty_allowed = {
  toggle_file_reviewed = true,
  next_unreviewed_file = true,
}

local log_levels = {
  error = true,
  warn = true,
  info = true,
  debug = true,
}

local log_sinks = {
  notify = true,
  echo = true,
  file = true,
}

local diagnostics_open_styles = {
  split = true,
  vsplit = true,
  float = true,
}

local known_nullable_keys = {
  ["codex.adapter.fallback"] = true,
  ["log.file"] = true,
}

---@param tbl table
---@return boolean
local function is_list_table(tbl)
  if vim.islist then
    return vim.islist(tbl)
  end
  if vim.tbl_islist then
    return vim.tbl_islist(tbl)
  end
  local max = 0
  for key, _ in pairs(tbl) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    if key > max then
      max = key
    end
  end
  return max == #tbl
end

---@param defaults_table table
---@param key any
---@param prefix string
---@return boolean
local function has_declared_key(defaults_table, key, prefix)
  if defaults_table[key] ~= nil then
    return true
  end
  return known_nullable_keys[("%s%s"):format(prefix, tostring(key))] == true
end

---@param path string
---@param value any
---@param expected string
local function warn_invalid_type(path, value, expected)
  Util.warn(("commentry setup: %s=%s is invalid; expected %s"):format(path, vim.inspect(value), expected))
end

---@param provided table
---@param defaults_table table
---@param prefix string
local function warn_unknown_keys(provided, defaults_table, prefix)
  if type(provided) ~= "table" then
    return
  end
  for key, value in pairs(provided) do
    if not has_declared_key(defaults_table, key, prefix) then
      Util.warn(("commentry setup: unknown config key: %s%s"):format(prefix, tostring(key)))
    else
      local default_value = defaults_table[key]
      if type(default_value) == "table" and type(value) == "table" and not is_list_table(default_value) then
        warn_unknown_keys(value, default_value, ("%s%s."):format(prefix, tostring(key)))
      end
    end
  end
end

---@param provided table
---@param defaults_table table
---@param prefix string
---@return table
local function sanitize_known_keys(provided, defaults_table, prefix)
  local sanitized = {}
  if type(provided) ~= "table" then
    return sanitized
  end
  for key, default_value in pairs(defaults_table) do
    local value = provided[key]
    if value ~= nil then
      if type(default_value) == "table" and not is_list_table(default_value) then
        if type(value) ~= "table" then
          warn_invalid_type(("%s%s"):format(prefix, key), value, "table")
        else
          sanitized[key] = sanitize_known_keys(value, default_value, ("%s%s."):format(prefix, key))
        end
      else
        sanitized[key] = value
      end
    end
  end
  for full_path, _ in pairs(known_nullable_keys) do
    -- Match nullable keys whose full path starts with the current prefix.
    if vim.startswith(full_path, prefix) then
      local leaf = full_path:sub(#prefix + 1)
      -- Only apply at the correct nesting level (leaf has no dots).
      if not leaf:find(".", 1, true) and provided[leaf] ~= nil then
        sanitized[leaf] = provided[leaf]
      end
    end
  end
  return sanitized
end

---@param value any
---@param expected string
---@param fallback any
---@param path string
---@return any
local function normalize_scalar(value, expected, fallback, path)
  if type(value) == expected then
    return value
  end
  warn_invalid_type(path, value, expected)
  return fallback
end

---@param current commentry.Config
---@return commentry.Config
local function normalize_config(current)
  current.debug = normalize_scalar(current.debug, "boolean", defaults.debug, "debug")
  current.default_comment_type =
    normalize_scalar(current.default_comment_type, "string", defaults.default_comment_type, "default_comment_type")

  if type(current.comment_types) ~= "table" then
    warn_invalid_type("comment_types", current.comment_types, "table")
    current.comment_types = vim.deepcopy(defaults.comment_types)
  end

  local valid_comment_types = {}
  for _, value in ipairs(current.comment_types) do
    if type(value) == "string" and value ~= "" then
      valid_comment_types[#valid_comment_types + 1] = value
    else
      warn_invalid_type("comment_types[]", value, "non-empty string")
    end
  end
  if #valid_comment_types == 0 then
    Util.warn("commentry setup: comment_types must include at least one non-empty string; using defaults")
    valid_comment_types = vim.deepcopy(defaults.comment_types)
  end
  current.comment_types = valid_comment_types
  if not vim.tbl_contains(current.comment_types, current.default_comment_type) then
    Util.warn(
      ("commentry setup: default_comment_type=%s is not present in comment_types; using %q"):format(
        vim.inspect(current.default_comment_type),
        current.comment_types[1]
      )
    )
    current.default_comment_type = current.comment_types[1]
  end

  current.store.filename = normalize_scalar(current.store.filename, "string", defaults.store.filename, "store.filename")
  current.diffview.enabled =
    normalize_scalar(current.diffview.enabled, "boolean", defaults.diffview.enabled, "diffview.enabled")
  current.diffview.prefer =
    normalize_scalar(current.diffview.prefer, "string", defaults.diffview.prefer, "diffview.prefer")
  current.diffview.auto_attach =
    normalize_scalar(current.diffview.auto_attach, "boolean", defaults.diffview.auto_attach, "diffview.auto_attach")
  current.diffview.comment_cards.max_width = normalize_scalar(
    current.diffview.comment_cards.max_width,
    "number",
    defaults.diffview.comment_cards.max_width,
    "diffview.comment_cards.max_width"
  )
  current.diffview.comment_cards.max_body_lines = normalize_scalar(
    current.diffview.comment_cards.max_body_lines,
    "number",
    defaults.diffview.comment_cards.max_body_lines,
    "diffview.comment_cards.max_body_lines"
  )
  current.diffview.comment_cards.show_markers = normalize_scalar(
    current.diffview.comment_cards.show_markers,
    "boolean",
    defaults.diffview.comment_cards.show_markers,
    "diffview.comment_cards.show_markers"
  )
  current.diffview.comment_ranges.enabled = normalize_scalar(
    current.diffview.comment_ranges.enabled,
    "boolean",
    defaults.diffview.comment_ranges.enabled,
    "diffview.comment_ranges.enabled"
  )
  current.diffview.comment_ranges.line_highlight = normalize_scalar(
    current.diffview.comment_ranges.line_highlight,
    "boolean",
    defaults.diffview.comment_ranges.line_highlight,
    "diffview.comment_ranges.line_highlight"
  )
  current.codex.enabled = normalize_scalar(current.codex.enabled, "boolean", defaults.codex.enabled, "codex.enabled")
  current.codex.adapter.select =
    normalize_scalar(current.codex.adapter.select, "string", defaults.codex.adapter.select, "codex.adapter.select")
  if current.codex.adapter.fallback ~= nil and type(current.codex.adapter.fallback) ~= "string" then
    warn_invalid_type("codex.adapter.fallback", current.codex.adapter.fallback, "string|nil")
    current.codex.adapter.fallback = defaults.codex.adapter.fallback
  end
  current.codex.behavior.open =
    normalize_scalar(current.codex.behavior.open, "string", defaults.codex.behavior.open, "codex.behavior.open")
  current.log.level = normalize_scalar(current.log.level, "string", defaults.log.level, "log.level")
  current.log.sink = normalize_scalar(current.log.sink, "string", defaults.log.sink, "log.sink")
  if not log_levels[current.log.level] then
    Util.warn(
      ("commentry setup: log.level=%s is invalid; expected one of error|warn|info|debug"):format(
        vim.inspect(current.log.level)
      )
    )
    current.log.level = defaults.log.level
  end
  if not log_sinks[current.log.sink] then
    Util.warn(
      ("commentry setup: log.sink=%s is invalid; expected one of notify|echo|file"):format(
        vim.inspect(current.log.sink)
      )
    )
    current.log.sink = defaults.log.sink
  end
  if current.log.file ~= nil and type(current.log.file) ~= "string" then
    warn_invalid_type("log.file", current.log.file, "string|nil")
    current.log.file = defaults.log.file
  end
  current.diagnostics.open_style = normalize_scalar(
    current.diagnostics.open_style,
    "string",
    defaults.diagnostics.open_style,
    "diagnostics.open_style"
  )
  if not diagnostics_open_styles[current.diagnostics.open_style] then
    Util.warn(
      ("commentry setup: diagnostics.open_style=%s is invalid; expected one of split|vsplit|float"):format(
        vim.inspect(current.diagnostics.open_style)
      )
    )
    current.diagnostics.open_style = defaults.diagnostics.open_style
  end

  return current
end

---@param value string
---@return boolean
local function is_valid_keymap_format(value)
  if value:match("^%s*$") then
    return false
  end
  if value:find("[\n\r]") then
    return false
  end
  return true
end

---@param action string
---@param provided unknown
---@param expected string
local function warn_keymap_validation(action, provided, expected)
  Util.warn(("commentry setup: keymaps.%s=%s is invalid; expected %s"):format(action, vim.inspect(provided), expected))
end

---@param keymaps unknown
---@return commentry.Keymaps
local function normalize_keymaps(keymaps)
  local normalized = vim.deepcopy(defaults.keymaps)
  if type(keymaps) ~= "table" then
    return normalized
  end

  for _, key in ipairs(keymap_keys) do
    local value = keymaps[key]
    if value ~= nil then
      local allow_empty = keymap_empty_allowed[key] == true
      local expected_shape = allow_empty and 'string (use "" to disable)' or "non-empty string"
      local valid = type(value) == "string"
      if valid then
        if value == "" then
          valid = allow_empty
        else
          valid = is_valid_keymap_format(value)
        end
      end

      if not valid then
        warn_keymap_validation(key, value, expected_shape)
      else
        normalized[key] = value
      end
    end
  end

  return normalized
end

local state_dir = vim.fn.stdpath("state") .. "/commentry"
local config = vim.deepcopy(defaults) --[[@as commentry.Config]]
-- Create the augroup once. Subsequent require() calls reuse the existing group
-- without clearing autocmds that setup() registered.
M.augroup = M.augroup or vim.api.nvim_create_augroup("commentry", { clear = true })

---@param name string
function M.state(name)
  return state_dir .. "/" .. name
end

---@param opts? commentry.Config
function M.setup(opts)
  local provided = opts or {}
  warn_unknown_keys(provided, defaults, "")
  local sanitized = sanitize_known_keys(provided, defaults, "")
  config = vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), sanitized)
  config = normalize_config(config)
  config.keymaps = normalize_keymaps(config.keymaps)

  -- Register the command if the plugin/ entrypoint hasn't already done so.
  if vim.fn.exists(":Commentry") ~= 2 then
    vim.api.nvim_create_user_command("Commentry", function(args)
      require("commentry.commands").cmd(args)
    end, {
      range = true,
      nargs = "?",
      desc = "Commentry",
      complete = function(_, line)
        return require("commentry.commands").complete(line)
      end,
    })
  end

  vim.schedule(function()
    vim.fn.mkdir(state_dir, "p")
  end)
end

setmetatable(M, {
  __index = function(_, key)
    return config[key]
  end,
})

return M
