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

---@class commentry.Config
---@field debug boolean
---@field keymaps commentry.Keymaps
---@field comment_types string[]
---@field default_comment_type string
---@field store commentry.StoreConfig
---@field diffview commentry.DiffviewConfig
---@field codex commentry.CodexConfig
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
      max_width = 88,
      max_body_lines = 8,
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
}

local keymap_empty_allowed = {
  toggle_file_reviewed = true,
  next_unreviewed_file = true,
}

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
      if type(value) ~= "string" then
        warn_keymap_validation(key, value, expected_shape)
      elseif value == "" and not allow_empty then
        warn_keymap_validation(key, value, expected_shape)
      elseif value ~= "" and not is_valid_keymap_format(value) then
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
M.augroup = vim.api.nvim_create_augroup("commentry", { clear = true })

---@param name string
function M.state(name)
  return state_dir .. "/" .. name
end

---@param opts? commentry.Config
function M.setup(opts)
  config = vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), opts or {})
  config.keymaps = normalize_keymaps(config.keymaps)

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
