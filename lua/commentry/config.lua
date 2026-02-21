---@class commentry.config: commentry.Config
local M = {}

M.ns = vim.api.nvim_create_namespace("commentry")

---@class commentry.Keymaps
---@field add_comment string
---@field edit_comment string
---@field delete_comment string
---@field set_comment_type string
---@field toggle_file_reviewed string
---@field next_unreviewed_file string

---@class commentry.StoreConfig
---@field filename string

---@class commentry.DiffviewConfig
---@field enabled boolean
---@field prefer string
---@field auto_attach boolean

---@class commentry.Config
---@field debug boolean
---@field keymaps commentry.Keymaps
---@field comment_types string[]
---@field default_comment_type string
---@field store commentry.StoreConfig
---@field diffview commentry.DiffviewConfig
local defaults = {
  debug = false,
  keymaps = {
    add_comment = "mc",
    edit_comment = "me",
    delete_comment = "md",
    set_comment_type = "mt",
    toggle_file_reviewed = "mr",
    next_unreviewed_file = "m]",
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
  },
}

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
