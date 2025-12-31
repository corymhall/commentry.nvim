---@class commentry.config: commentry.Config
local M = {}

M.ns = vim.api.nvim_create_namespace("commentry")

---@class commentry.Keymaps
---@field add_comment string
---@field edit_comment string
---@field delete_comment string

---@class commentry.StoreConfig
---@field filename string

---@class commentry.DiffviewConfig
---@field enabled boolean
---@field prefer string

---@class commentry.Config
---@field debug boolean
---@field keymaps commentry.Keymaps
---@field store commentry.StoreConfig
---@field diffview commentry.DiffviewConfig
local defaults = {
  debug = false,
  keymaps = {
    add_comment = "gc",
    edit_comment = "ge",
    delete_comment = "gd",
  },
  store = {
    filename = "commentry.json",
  },
  diffview = {
    enabled = true,
    prefer = "diffview.nvim",
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
