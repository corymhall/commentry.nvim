local M = {}

---@param opts? commentry.Config
function M.setup(opts)
  require("commentry.config").setup(opts)
  require("commentry.commands").setup()
  require("commentry.diffview").setup()
end

return M
